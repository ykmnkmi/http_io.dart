// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:isolate';

import 'package:http_io/http_io.dart';

import 'expect.dart';

class TestServerMain {
  TestServerMain();

  void setServerStartedHandler(void Function(int port) startedCallback) {
    _startedCallback = startedCallback;
  }

  void start([bool chunkedEncoding = false]) {
    ReceivePort receivePort = ReceivePort();
    Isolate.spawn(startTestServer, receivePort.sendPort);
    receivePort.first.then((Object? port) {
      _serverPort = port as SendPort;

      if (chunkedEncoding) {
        // Send chunked encoding message to the server.
        port.send([TestServerCommand.chunkedEncoding(), _statusPort.sendPort]);
      }

      // Send server start message to the server.
      var command = TestServerCommand.start();
      port.send([command, _statusPort.sendPort]);
    });

    // Handle status messages from the server.
    _statusPort.listen((Object? status) {
      status as TestServerStatus;

      if (status.isStarted) {
        _startedCallback(status.port);
      }
    });
  }

  void close() {
    // Send server stop message to the server.
    _serverPort.send([TestServerCommand.stop(), _statusPort.sendPort]);
    _statusPort.close();
  }

  final _statusPort =
      ReceivePort(); // Port for receiving messages from the server.
  late SendPort _serverPort; // Port for sending messages to the server.
  late void Function(int port) _startedCallback;
}

class TestServerCommand {
  static const _start = 0;
  static const _stop = 1;
  static const _chunkedEncoding = 2;

  TestServerCommand.start() : _command = _start;
  TestServerCommand.stop() : _command = _stop;
  TestServerCommand.chunkedEncoding() : _command = _chunkedEncoding;

  bool get isStart => _command == _start;
  bool get isStop => _command == _stop;
  bool get isChunkedEncoding => _command == _chunkedEncoding;

  final int _command;
}

class TestServerStatus {
  static const _started = 0;
  static const _stopped = 1;
  static const _error = 2;

  TestServerStatus.started(this._port) : _state = _started;
  TestServerStatus.stopped() : _state = _stopped;
  TestServerStatus.error() : _state = _error;

  bool get isStarted => _state == _started;
  bool get isStopped => _state == _stopped;
  bool get isError => _state == _error;

  int get port => _port;

  final int _state;
  int _port = 0;
}

void startTestServer(Object replyToObj) {
  var replyTo = replyToObj as SendPort;
  var server = TestServer();
  server.init();
  replyTo.send(server.dispatchSendPort);
}

class TestServer {
  // Echo the request content back to the response.
  void _echoHandler(HttpRequest request) {
    var response = request.response;
    Expect.equals('POST', request.method);
    response.contentLength = request.contentLength;
    request.cast<List<int>>().pipe(response);
  }

  // Echo the request content back to the response.
  void _zeroToTenHandler(HttpRequest request) {
    var response = request.response;
    Expect.equals('GET', request.method);
    request.listen((_) {}, onDone: () {
      response.write('01234567890');
      response.close();
    });
  }

  // Return a 404.
  void _notFoundHandler(HttpRequest request) {
    var response = request.response;
    response.statusCode = HttpStatus.notFound;
    response.headers.set('Content-Type', 'text/html; charset=UTF-8');
    response.write('Page not found');
    response.close();
  }

  // Return a 301 with a custom reason phrase.
  void _reasonForMovingHandler(HttpRequest request) {
    var response = request.response;
    response.statusCode = HttpStatus.movedPermanently;
    response.reasonPhrase = "Don't come looking here any more";
    response.close();
  }

  // Check the "Host" header.
  void _hostHandler(HttpRequest request) {
    var response = request.response;
    Expect.equals(1, request.headers['Host']?.length);
    Expect.equals('www.dartlang.org:1234', request.headers['Host']![0]);
    Expect.equals('www.dartlang.org', request.headers.host);
    Expect.equals(1234, request.headers.port);
    response.statusCode = HttpStatus.ok;
    response.close();
  }

  void init() {
    // Setup request handlers.
    _requestHandlers['/echo'] = _echoHandler;
    _requestHandlers['/0123456789'] = _zeroToTenHandler;
    _requestHandlers['/reasonformoving'] = _reasonForMovingHandler;
    _requestHandlers['/host'] = _hostHandler;
    _dispatchPort.listen(dispatch);
  }

  SendPort get dispatchSendPort => _dispatchPort.sendPort;

  void dispatch(Object? message) {
    message as List;

    TestServerCommand command = message[0] as TestServerCommand;
    SendPort replyTo = message[1] as SendPort;
    if (command.isStart) {
      try {
        HttpServer.bind('127.0.0.1', 0).then((server) {
          _server = server;
          _server.listen(_requestReceivedHandler);
          replyTo.send(TestServerStatus.started(_server.port));
        });
      } catch (e) {
        replyTo.send(TestServerStatus.error());
      }
    } else if (command.isStop) {
      _server.close();
      _dispatchPort.close();
      replyTo.send(TestServerStatus.stopped());
    } else if (command.isChunkedEncoding) {}
  }

  void _requestReceivedHandler(HttpRequest request) {
    var requestHandler = _requestHandlers[request.uri.path];
    if (requestHandler != null) {
      requestHandler(request);
    } else {
      _notFoundHandler(request);
    }
  }

  late HttpServer _server; // HTTP server instance.
  final ReceivePort _dispatchPort = ReceivePort();
  final _requestHandlers = <String, void Function(HttpRequest)>{};
}

void testStartStop() {
  TestServerMain testServerMain = TestServerMain();
  testServerMain.setServerStartedHandler((int port) {
    testServerMain.close();
  });
  testServerMain.start();
}

void testGET() {
  TestServerMain testServerMain = TestServerMain();
  testServerMain.setServerStartedHandler((int port) {
    HttpClient httpClient = HttpClient();
    httpClient
        .get('127.0.0.1', port, '/0123456789')
        .then((request) => request.close())
        .then((response) {
      Expect.equals(HttpStatus.ok, response.statusCode);
      StringBuffer body = StringBuffer();
      response.listen((data) => body.write(String.fromCharCodes(data)),
          onDone: () {
        Expect.equals('01234567890', body.toString());
        httpClient.close();
        testServerMain.close();
      });
    });
  });
  testServerMain.start();
}

void testPOST(bool chunkedEncoding) {
  String data = 'ABCDEFGHIJKLMONPQRSTUVWXYZ';
  int kMessageCount = 10;

  TestServerMain testServerMain = TestServerMain();

  void runTest(int port) {
    int count = 0;
    HttpClient httpClient = HttpClient();
    void sendRequest() {
      httpClient.post('127.0.0.1', port, '/echo').then((request) {
        if (chunkedEncoding) {
          request.write(data.substring(0, 10));
          request.write(data.substring(10, data.length));
        } else {
          request.contentLength = data.length;
          request.write(data);
        }
        return request.close();
      }).then((response) {
        Expect.equals(HttpStatus.ok, response.statusCode);
        StringBuffer body = StringBuffer();
        response.listen((data) => body.write(String.fromCharCodes(data)),
            onDone: () {
          Expect.equals(data, body.toString());
          count++;
          if (count < kMessageCount) {
            sendRequest();
          } else {
            httpClient.close();
            testServerMain.close();
          }
        });
      });
    }

    sendRequest();
  }

  testServerMain.setServerStartedHandler(runTest);
  testServerMain.start(chunkedEncoding);
}

void test404() {
  TestServerMain testServerMain = TestServerMain();
  testServerMain.setServerStartedHandler((int port) {
    HttpClient httpClient = HttpClient();
    httpClient
        .get('127.0.0.1', port, '/thisisnotfound')
        .then((request) => request.close())
        .then((response) {
      Expect.equals(HttpStatus.notFound, response.statusCode);
      var body = StringBuffer();
      response.listen((data) => body.write(String.fromCharCodes(data)),
          onDone: () {
        Expect.equals('Page not found', body.toString());
        httpClient.close();
        testServerMain.close();
      });
    });
  });
  testServerMain.start();
}

void testReasonPhrase() {
  TestServerMain testServerMain = TestServerMain();
  testServerMain.setServerStartedHandler((int port) {
    HttpClient httpClient = HttpClient();
    httpClient.get('127.0.0.1', port, '/reasonformoving').then((request) {
      request.followRedirects = false;
      return request.close();
    }).then((response) {
      Expect.equals(HttpStatus.movedPermanently, response.statusCode);
      Expect.equals("Don't come looking here any more", response.reasonPhrase);
      response.listen((data) => Expect.fail('No data expected'), onDone: () {
        httpClient.close();
        testServerMain.close();
      });
    });
  });
  testServerMain.start();
}

void main() {
  testStartStop();
  testGET();
  testPOST(true);
  testPOST(false);
  test404();
  testReasonPhrase();
}
