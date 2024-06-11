// (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import "dart:async";
import "dart:isolate";
import "dart:typed_data";

import "package:http_io/http_io.dart";
import "package:test/test.dart";

// Client makes a HTTP 1.0 request without connection keep alive. The
// server sets a content length but still needs to close the
// connection as there is no keep alive.
Future<void> testHttp10NoKeepAlive() async {
  Completer<void> completer = Completer<void>();

  HttpServer server = await HttpServer.bind("127.0.0.1", 0);

  server.listen((HttpRequest request) {
    expect(request.headers.value('content-length'), isNull);
    expect(-1, equals(request.contentLength));

    HttpResponse response = request.response;
    response.contentLength = 1;
    expect("1.0", equals(request.protocolVersion));

    Future(() async {
      try {
        await response.done;
        fail("Unexpected response completion");
      } catch (error) {
        expect(error, isA<HttpException>());
      }
    });

    response.write("Z");
    response.write("Z");
    response.close();
    expect(() => response.write("x"), throwsA(isA<StateError>()));
  }, onError: (error, stackTrace) {
    String message = "Unexpected error $error";

    if (stackTrace != null) {
      message += "\nStackTrace: $stackTrace";
    }

    fail(message);
  });

  int count = 0;

  Future<void> makeRequest() async {
    Socket socket = await Socket.connect("127.0.0.1", server.port);
    socket.write("GET / HTTP/1.0\r\n\r\n");

    List<int> response = <int>[];

    socket.listen(response.addAll, onDone: () {
      count++;
      socket.destroy();

      String value = String.fromCharCodes(response).toLowerCase();
      expect(-1, equals(value.indexOf("keep-alive")));

      if (count < 10) {
        makeRequest();
      } else {
        server.close();
        completer.complete();
      }
    });
  }

  makeRequest();
  await completer.future;
}

// Client makes a HTTP 1.0 request and the server does not set a
// content length so it has to close the connection to mark the end of
// the response.
Future<void> testHttp10ServerClose() async {
  Completer<void> completer = Completer<void>();

  HttpServer server = await HttpServer.bind("127.0.0.1", 0);

  server.listen((HttpRequest request) {
    expect(request.headers.value('content-length'), isNull);
    expect(-1, equals(request.contentLength));
    request.listen(null, onDone: () {
      HttpResponse response = request.response;
      expect("1.0", equals(request.protocolVersion));
      response.write("Z");
      response.close();
    });
  }, onError: (error, stackTrace) {
    String message = "Unexpected error $error";

    if (stackTrace != null) {
      message += "\nStackTrace: $stackTrace";
    }

    fail(message);
  });

  int count = 0;

  Future<void> makeRequest() async {
    Socket socket = await Socket.connect("127.0.0.1", server.port);
    socket.write("GET / HTTP/1.0\r\n");
    socket.write("Connection: Keep-Alive\r\n\r\n");

    List<int> response = <int>[];
    socket.listen(response.addAll, onDone: () {
      socket.destroy();
      count++;

      String value = String.fromCharCodes(response).toLowerCase();
      expect("z", equals(value[value.length - 1]));
      expect(-1, equals(value.indexOf("content-length:")));
      expect(-1, equals(value.indexOf("keep-alive")));

      if (count < 10) {
        makeRequest();
      } else {
        server.close();
        completer.complete();
      }
    }, onError: print);
  }

  makeRequest();
  await completer.future;
}

// Client makes a HTTP 1.0 request with connection keep alive. The
// server sets a content length so the persistent connection can be
// used.
Future<void> testHttp10KeepAlive() async {
  Completer<void> completer = Completer<void>();

  HttpServer server = await HttpServer.bind("127.0.0.1", 0);

  server.listen((HttpRequest request) {
    expect(request.headers.value('content-length'), isNull);
    expect(-1, equals(request.contentLength));

    HttpResponse response = request.response;
    response.contentLength = 1;
    response.persistentConnection = true;
    expect("1.0", equals(request.protocolVersion));
    response.write("Z");
    response.close();
  }, onError: (error, stackTrace) {
    String message = 'Unexpected error $error';

    if (stackTrace != null) {
      message += '\nStackTrace: $stackTrace';
    }

    fail(message);
  });

  Socket socket = await Socket.connect("127.0.0.1", server.port);

  void sendRequest() {
    socket.write("GET / HTTP/1.0\r\n");
    socket.write("Connection: Keep-Alive\r\n\r\n");
  }

  List<int> response = <int>[];
  int count = 0;

  socket.listen((Uint8List data) {
    response.addAll(data);

    if (response[response.length - 1] == "Z".codeUnitAt(0)) {
      String value = String.fromCharCodes(response).toLowerCase();
      expect(value.indexOf("\r\nconnection: keep-alive\r\n") > 0, isTrue);
      expect(value.indexOf("\r\ncontent-length: 1\r\n") > 0, isTrue);
      count++;

      if (count < 10) {
        response = <int>[];
        sendRequest();
      } else {
        socket.close();
      }
    }
  }, onDone: () {
    socket.destroy();
    server.close();
    completer.complete();
  });

  sendRequest();
  await completer.future;
}

// Client makes a HTTP 1.0 request with connection keep alive. The
// server does not set a content length so it cannot honor connection
// keep alive.
Future<void> testHttp10KeepAliveServerCloses() async {
  Completer<void> completer = Completer();

  HttpServer server = await HttpServer.bind("127.0.0.1", 0);

  server.listen((HttpRequest request) {
    expect(request.headers.value('content-length'), isNull);
    expect(-1, equals(request.contentLength));

    HttpResponse response = request.response;
    expect("1.0", equals(request.protocolVersion));
    response.write("Z");
    response.close();
  }, onError: (error, stackTrace) {
    String message = "Unexpected error $error";

    if (stackTrace != null) {
      message += "\nStackTrace: $stackTrace";
    }

    fail(message);
  });

  int count = 0;

  Future<void> makeRequest() async {
    Socket socket = await Socket.connect("127.0.0.1", server.port);
    socket.write("GET / HTTP/1.0\r\n");
    socket.write("Connection: Keep-Alive\r\n\r\n");

    List<int> response = <int>[];

    socket.listen(response.addAll, onDone: () {
      socket.destroy();
      count++;

      String value = String.fromCharCodes(response).toLowerCase();
      expect("z", equals(value[value.length - 1]));
      expect(-1, equals(value.indexOf("content-length")));
      expect(-1, equals(value.indexOf("connection")));

      if (count < 10) {
        makeRequest();
      } else {
        server.close();
        completer.complete();
      }
    });
  }

  makeRequest();
  await completer.future;
}

void main() {
  test("Http10NoKeepAlive", testHttp10NoKeepAlive);

  test("Http10ServerClose", testHttp10ServerClose);

  test("Http10KeepAlive", testHttp10KeepAlive);

  test("Http10KeepAliveServerCloses", testHttp10KeepAliveServerCloses);
}
