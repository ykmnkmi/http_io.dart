// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:http_io/http_io.dart';

import 'async_helper.dart';
import 'expect.dart';

void testGetEmptyRequest() {
  HttpServer.bind('127.0.0.1', 0).then((server) {
    server.listen((request) {
      request.cast<List<int>>().pipe(request.response);
    });

    var client = HttpClient();
    client
        .get('127.0.0.1', server.port, '/')
        .then((request) => request.close())
        .then((response) {
      response.listen((data) {}, onDone: server.close);
    });
  });
}

void testGetDataRequest() {
  HttpServer.bind('127.0.0.1', 0).then((server) {
    var data = 'lalala'.codeUnits;
    server.listen((request) {
      request.response.add(data);
      request.cast<List<int>>().pipe(request.response);
    });

    var client = HttpClient();
    client
        .get('127.0.0.1', server.port, '/')
        .then((request) => request.close())
        .then((response) {
      int count = 0;
      response.listen((data) => count += data.length, onDone: () {
        server.close();
        Expect.equals(data.length, count);
      });
    });
  });
}

void testGetInvalidHost() {
  asyncStart();
  var client = HttpClient();
  Future<HttpClientRequest?>.value(
          client.get('__SOMETHING_INVALID__', 8888, '/'))
      .catchError((error) {
    client.close();
    asyncEnd();
    return null;
  });
}

void testGetServerClose() {
  asyncStart();
  HttpServer.bind('127.0.0.1', 0).then((server) {
    server.listen((request) {
      server.close();
      Timer(const Duration(milliseconds: 100), () {
        request.response.close();
      });
    });

    var client = HttpClient();
    client
        .get('127.0.0.1', server.port, '/')
        .then((request) => request.close())
        .then((response) => response.drain<void>())
        .then((_) => asyncEnd());
  });
}

void testGetServerCloseNoKeepAlive() {
  asyncStart();
  var client = HttpClient();
  HttpServer.bind('127.0.0.1', 0).then((server) {
    int port = server.port;
    server.first.then((request) => request.response.close());

    client
        .get('127.0.0.1', port, '/')
        .then((request) => request.close())
        .then((response) => response.drain<void>())
        .then((_) => client.get('127.0.0.1', port, '/'))
        .then((request) => request.close())
        .then((_) => Expect.fail('should not succeed'), onError: (_) {})
        .then((_) => asyncEnd());
  });
}

void testGetServerForceClose() {
  asyncStart();
  HttpServer.bind('127.0.0.1', 0).then((server) {
    server.listen((request) {
      server.close(force: true);
    });

    var client = HttpClient();
    client
        .get('127.0.0.1', server.port, '/')
        .then((request) => request.close())
        .then((response) {
      Expect.fail('Request not expected');
    }).catchError((Object error) {
      asyncEnd();
    }, test: (error) => error is HttpException);
  });
}

void testGetDataServerForceClose() {
  asyncStart();
  var completer = Completer<void>();
  HttpServer.bind('127.0.0.1', 0).then((server) {
    server.listen((request) {
      request.response.bufferOutput = false;
      request.response.contentLength = 100;
      request.response.write('data');
      request.response.write('more data');
      completer.future.then((_) => server.close(force: true));
    });

    var client = HttpClient();
    client
        .get('127.0.0.1', server.port, '/')
        .then((request) => request.close())
        .then((response) {
      // Close the (incomplete) response, now that we have seen
      // the response object.
      completer.complete(null);
      int errors = 0;
      response.listen((data) {},
          onError: (error) => errors++,
          onDone: () {
            Expect.equals(1, errors);
            asyncEnd();
          });
    });
  });
}

typedef Callback1 = Future<HttpClientRequest> Function(
    String a1, int a2, String a3);
void testOpenEmptyRequest() {
  var client = HttpClient();
  var methods = [
    [client.get, 'GET'],
    [client.post, 'POST'],
    [client.put, 'PUT'],
    [client.delete, 'DELETE'],
    [client.patch, 'PATCH'],
    [client.head, 'HEAD']
  ];

  for (var method in methods) {
    HttpServer.bind('127.0.0.1', 0).then((server) {
      server.listen((request) {
        Expect.equals(method[1], request.method);
        request.cast<List<int>>().pipe(request.response);
      });

      Callback1 cb = method[0] as Callback1;
      cb('127.0.0.1', server.port, '/')
          .then((request) => request.close())
          .then((response) {
        response.listen((data) {}, onDone: server.close);
      });
    });
  }
}

typedef Callback2 = Future<HttpClientRequest> Function(Uri a1);
void testOpenUrlEmptyRequest() {
  var client = HttpClient();
  var methods = [
    [client.getUrl, 'GET'],
    [client.postUrl, 'POST'],
    [client.putUrl, 'PUT'],
    [client.deleteUrl, 'DELETE'],
    [client.patchUrl, 'PATCH'],
    [client.headUrl, 'HEAD']
  ];

  for (var method in methods) {
    HttpServer.bind('127.0.0.1', 0).then((server) {
      server.listen((request) {
        Expect.equals(method[1], request.method);
        request.cast<List<int>>().pipe(request.response);
      });

      Callback2 cb = method[0] as Callback2;
      cb(Uri.parse('http://127.0.0.1:${server.port}/'))
          .then((request) => request.close())
          .then((response) {
        response.listen((data) {}, onDone: server.close);
      });
    });
  }
}

void testNoBuffer() {
  asyncStart();
  HttpServer.bind('127.0.0.1', 0).then((server) {
    late HttpResponse response;
    server.listen((request) {
      response = request.response;
      response.bufferOutput = false;
      response.writeln('init');
    });

    var client = HttpClient();
    client
        .get('127.0.0.1', server.port, '/')
        .then((request) => request.close())
        .then((clientResponse) {
      var iterator = StreamIterator(clientResponse
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(LineSplitter()));
      iterator.moveNext().then((hasValue) {
        Expect.isTrue(hasValue);
        Expect.equals('init', iterator.current);
        int count = 0;
        void run() {
          if (count == 10) {
            response.close();
            iterator.moveNext().then((hasValue) {
              Expect.isFalse(hasValue);
              server.close();
              asyncEnd();
            });
          } else {
            response.writeln('output$count');
            iterator.moveNext().then((hasValue) {
              Expect.isTrue(hasValue);
              Expect.equals('output$count', iterator.current);
              count++;
              run();
            });
          }
        }

        run();
      });
    });
  });
}

void testMaxConnectionsPerHost(int connectionCap, int connections) {
  asyncStart();
  HttpServer.bind('127.0.0.1', 0).then((server) {
    int handled = 0;
    server.listen((request) {
      Expect.isTrue(
          server.connectionsInfo().total <= connectionCap,
          '${server.connectionsInfo().total} <= $connectionCap '
          '(connections: $connections)');
      request.response.close();
      handled++;
      if (handled == connections) {
        asyncEnd();
        server.close();
      }
    });

    var client = HttpClient();
    client.maxConnectionsPerHost = connectionCap;
    for (int i = 0; i < connections; i++) {
      asyncStart();
      client
          .get('127.0.0.1', server.port, '/')
          .then((request) => request.close())
          .then((response) {
        response.listen(null, onDone: asyncEnd);
      });
    }
  });
}

Future<void> testMaxConnectionsWithFailure() async {
  // When DNS lookup failed, counter for connecting doesn't decrement which
  // prevents the following connections.
  asyncStart();
  var client = HttpClient();
  client.maxConnectionsPerHost = 1;
  try {
    await client.getUrl(Uri.parse('http://domain.invalid'));
  } catch (e) {
    if (e is! SocketException) {
      Expect.fail('Unexpected exception $e is thrown');
    }
  }
  try {
    await client.getUrl(Uri.parse('http://domain.invalid'));
    Expect.fail("Calls exceed client's maxConnectionsPerHost should throw "
        'exceptions as well');
  } catch (e) {
    if (e is! SocketException) {
      Expect.fail('Unexpected exception $e is thrown');
    }
  }
  asyncEnd();
}

Future<void> testHttpAbort() async {
  // Test that abort() is called after request is sent.
  asyncStart();
  var completer = Completer<void>();
  var server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((request) {
    completer.complete();
    request.response.close();
  });

  var request = await HttpClient().get('127.0.0.1', server.port, '/');
  request.headers.add(HttpHeaders.contentLengthHeader, '8');
  request.write('somedata');
  completer.future.then((_) {
    request.abort();
    asyncStart();
    Future.delayed(Duration(milliseconds: 500), () {
      server.close();
      asyncEnd();
    });
  });
  request.close().then((response) {
    Expect.fail('abort() prevents a response being returned');
  }, onError: (Object e) {
    Expect.type<HttpException>(e);
    Expect.isTrue(e.toString().contains('abort'));
    asyncEnd();
  });
}

Future<void> testHttpAbortBeforeWrite() async {
  // Test that abort() is called before write(). No message should be sent from
  // HttpClientRequest.
  asyncStart();
  var completer = Completer<Socket>();
  var server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen((s) async {
    s.listen((data) {
      Expect.fail('No message should be received');
    });
    await Future<void>.delayed(Duration(milliseconds: 500));
    completer.complete(s);
  });

  var request = await HttpClient().get('127.0.0.1', server.port, '/');
  request.headers.add(HttpHeaders.contentLengthHeader, '8');
  // This HttpException will go to onError callback.
  request.abort(HttpException('Error'));
  asyncStart();
  request.write('somedata');
  completer.future.then((socket) {
    socket.destroy();
    server.close();
    asyncEnd();
  });
  request.close().then((response) {
    Expect.fail('abort() prevents a response being returned');
  }, onError: (Object e) {
    Expect.type<HttpException>(e);
    asyncEnd();
  });
}

Future<void> testHttpAbortBeforeClose() async {
  // Test that abort() is called after write(). Some messages added prior to
  // abort() are sent.
  var completer = Completer<void>();
  asyncStart();
  var server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen((s) {
    StringBuffer buffer = StringBuffer();
    s.listen((data) {
      buffer.write(utf8.decode(data));
      if (buffer.toString().contains('content-length: 8')) {
        completer.complete();
        s.destroy();
        server.close();
      }
    });
  });

  var request = await HttpClient().get('127.0.0.1', server.port, '/');
  // Add an additional header field for server to verify.
  request.headers.add(HttpHeaders.contentLengthHeader, '8');
  request.write('somedata');
  await completer.future;
  var string = 'abort message';
  request.abort(string);
  request.close().then((response) {
    Expect.fail('abort() prevents a response being returned');
  }, onError: (Object e) {
    Expect.type<String>(e);
    Expect.equals(string, e);
    asyncEnd();
  });
}

Future<void> testHttpAbortAfterClose() async {
  // Test that abort() is called after response is received. It should not
  // affect HttpClientResponse.
  asyncStart();
  var value = 'someRandomData';
  var server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((request) {
    request.response.write(value);
    request.response.close();
  });

  var request = await HttpClient().get('127.0.0.1', server.port, '/');
  var response = await request.close();
  request.abort();
  var data = await response.transform(utf8.decoder).join();
  Expect.equals(value, data);
  asyncEnd();
  server.close();
}

void main() async {
  asyncStart();
  testGetEmptyRequest();
  testGetDataRequest();
  testGetInvalidHost();
  testGetServerClose();
  testGetServerCloseNoKeepAlive();
  testGetServerForceClose();
  testGetDataServerForceClose();
  testOpenEmptyRequest();
  testOpenUrlEmptyRequest();
  testNoBuffer();
  testMaxConnectionsPerHost(1, 1);
  testMaxConnectionsPerHost(1, 10);
  testMaxConnectionsPerHost(5, 10);
  testMaxConnectionsPerHost(10, 50);
  await testMaxConnectionsWithFailure();
  await testHttpAbort();
  await testHttpAbortBeforeWrite();
  await testHttpAbortBeforeClose();
  await testHttpAbortAfterClose();
  asyncEnd();
}
