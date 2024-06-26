// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:isolate';

import 'package:http_io/http_io.dart';

import 'expect.dart';

class IsolatedHttpServer {
  IsolatedHttpServer();

  void setServerStartedHandler(void Function(int port) startedCallback) {
    _startedCallback = startedCallback;
  }

  void start([bool chunkedEncoding = false]) {
    ReceivePort receivePort = ReceivePort();
    Isolate.spawn(startIsolatedHttpServer, receivePort.sendPort);
    receivePort.first.then((Object? port) {
      _serverPort = port as SendPort;

      if (chunkedEncoding) {
        // Send chunked encoding message to the server.
        port.send([
          IsolatedHttpServerCommand.chunkedEncoding(),
          _statusPort.sendPort
        ]);
      }

      // Send server start message to the server.
      var command = IsolatedHttpServerCommand.start();
      port.send([command, _statusPort.sendPort]);
    });

    // Handle status messages from the server.
    _statusPort.listen((var status) {
      status as IsolatedHttpServerStatus;

      if (status.isStarted) {
        _startedCallback(status.port);
      }
    });
  }

  void shutdown() {
    // Send server stop message to the server.
    _serverPort.send([IsolatedHttpServerCommand.stop(), _statusPort.sendPort]);
    _statusPort.close();
  }

  final _statusPort =
      ReceivePort(); // Port for receiving messages from the server.
  late SendPort _serverPort; // Port for sending messages to the server.
  late void Function(int port) _startedCallback;
}

class IsolatedHttpServerCommand {
  static const _start = 0;
  static const _stop = 1;
  static const _chunkedEncoding = 2;

  IsolatedHttpServerCommand.start() : _command = _start;
  IsolatedHttpServerCommand.stop() : _command = _stop;
  IsolatedHttpServerCommand.chunkedEncoding() : _command = _chunkedEncoding;

  bool get isStart => _command == _start;
  bool get isStop => _command == _stop;
  bool get isChunkedEncoding => _command == _chunkedEncoding;

  final int _command;
}

class IsolatedHttpServerStatus {
  static const _started = 0;
  static const _stopped = 1;
  static const _error = 2;

  IsolatedHttpServerStatus.started(this._port) : _state = _started;
  IsolatedHttpServerStatus.stopped() : _state = _stopped;
  IsolatedHttpServerStatus.error() : _state = _error;

  bool get isStarted => _state == _started;
  bool get isStopped => _state == _stopped;
  bool get isError => _state == _error;

  int get port => _port;

  final int _state;
  int _port = 0;
}

void startIsolatedHttpServer(Object replyToObj) {
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

  // Return a 404.
  void _notFoundHandler(HttpRequest request) {
    var response = request.response;
    response.statusCode = HttpStatus.notFound;
    response.headers.set('Content-Type', 'text/html; charset=UTF-8');
    response.write('Page not found');
    response.close();
  }

  void init() {
    // Setup request handlers.
    _requestHandlers['/echo'] = _echoHandler;
    _dispatchPort.listen(dispatch);
  }

  SendPort get dispatchSendPort => _dispatchPort.sendPort;

  void dispatch(Object? message) {
    message as List;

    IsolatedHttpServerCommand command = message[0] as IsolatedHttpServerCommand;
    SendPort replyTo = message[1] as SendPort;
    if (command.isStart) {
      try {
        HttpServer.bind('127.0.0.1', 0).then((server) {
          _server = server;
          _server.listen(_requestReceivedHandler);
          replyTo.send(IsolatedHttpServerStatus.started(_server.port));
        });
      } catch (e) {
        replyTo.send(IsolatedHttpServerStatus.error());
      }
    } else if (command.isStop) {
      _server.close();
      _dispatchPort.close();
      replyTo.send(IsolatedHttpServerStatus.stopped());
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
  final _dispatchPort = ReceivePort();
  final _requestHandlers = <String, void Function(HttpRequest)>{};
}

void testRead(bool chunkedEncoding) {
  String data = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  int kMessageCount = 10;

  IsolatedHttpServer server = IsolatedHttpServer();

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
          request.add(data.codeUnits);
        }
        return request.close();
      }).then((response) {
        Expect.equals(HttpStatus.ok, response.statusCode);
        List<int> body = <int>[];
        response.listen(body.addAll, onDone: () {
          Expect.equals(data, String.fromCharCodes(body));
          count++;
          if (count < kMessageCount) {
            sendRequest();
          } else {
            httpClient.close();
            server.shutdown();
          }
        });
      });
    }

    sendRequest();
  }

  server.setServerStartedHandler(runTest);
  server.start(chunkedEncoding);
}

void main() {
  testRead(true);
  testRead(false);
}
