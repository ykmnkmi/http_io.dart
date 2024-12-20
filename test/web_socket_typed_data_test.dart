// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// VMOptions=
// VMOptions=--short_socket_read
// VMOptions=--short_socket_write
// VMOptions=--short_socket_read --short_socket_write

import 'dart:async';
import 'dart:typed_data';

import 'package:http_io/http_io.dart';

import 'expect.dart';

Future<HttpServer> createServer() => HttpServer.bind('127.0.0.1', 0);

Future<WebSocket> createClient(int port, bool compression) => compression
    ? WebSocket.connect('ws://127.0.0.1:$port/')
    : WebSocket.connect('ws://127.0.0.1:$port/',
        compression: CompressionOptions.compressionOff);

void test(List<int> expected, List<List<int>> testData, bool compression) {
  createServer().then((server) {
    var messageCount = 0;
    var transformer = compression
        ? WebSocketTransformer()
        : WebSocketTransformer(compression: CompressionOptions.compressionOff);
    server.transform(transformer).listen((webSocket) {
      webSocket.listen((message) {
        Expect.listEquals(expected, message as List);
        webSocket.add(testData[messageCount]);
        messageCount++;
      }, onDone: () => Expect.equals(testData.length, messageCount));
    });

    createClient(server.port, compression).then((webSocket) {
      var messageCount = 0;
      webSocket.listen((message) {
        Expect.listEquals(expected, message as List);
        messageCount++;
        if (messageCount == testData.length) {
          webSocket.close();
        }
      }, onDone: server.close);
      testData.forEach(webSocket.add);
    });
  });
}

void testUintLists({bool compression = false}) {
  var fillData = List.generate(256, (index) => index);
  var testData = [
    Uint8List(256),
    Uint8ClampedList(256),
    Uint16List(256),
    Uint32List(256),
    Uint64List(256),
  ];
  for (var list in testData) {
    list.setAll(0, fillData);
  }
  test(fillData, testData, compression);
}

void testIntLists({bool compression = false}) {
  var fillData = List.generate(128, (index) => index);
  var testData = [
    Int8List(128),
    Int16List(128),
    Int32List(128),
    Int64List(128),
  ];
  for (var list in testData) {
    list.setAll(0, fillData);
  }
  test(fillData, testData, compression);
}

void testOutOfRangeClient({bool compression = false}) {
  createServer().then((server) {
    var transformer = compression
        ? WebSocketTransformer()
        : WebSocketTransformer(compression: CompressionOptions.compressionOff);
    server.transform(transformer).listen((webSocket) {
      webSocket.listen((message) => Expect.fail('No message expected'));
    });

    Future<void> clientError(List<int> data) {
      return createClient(server.port, compression).then((webSocket) {
        webSocket.listen((message) => Expect.fail('No message expected'));
        webSocket.add(data);
        webSocket.close();
        return webSocket.done;
      });
    }

    Future<bool> expectError(List<int> data) {
      var completer = Completer<bool>();
      clientError(data)
          .then((_) => completer.completeError('Message $data did not fail'))
          .catchError((e) => completer.complete(true));
      return completer.future;
    }

    var futures = <Future<bool>>[];
    List<int> data;
    data = Uint16List(1);
    data[0] = 256;
    futures.add(expectError(data));
    data = Uint32List(1);
    data[0] = 256;
    futures.add(expectError(data));
    data = Uint64List(1);
    data[0] = 256;
    futures.add(expectError(data));
    data = Int16List(1);
    data[0] = 256;
    futures.add(expectError(data));
    data[0] = -1;
    futures.add(expectError(data));
    data = Int32List(1);
    data[0] = 256;
    futures.add(expectError(data));
    data[0] = -1;
    futures.add(expectError(data));
    data = Int64List(1);
    data[0] = 256;
    futures.add(expectError(data));
    data[0] = -1;
    futures.add(expectError(data));
    futures.add(expectError([-1]));
    futures.add(expectError([256]));

    Future.wait(futures).then((_) => server.close());
  });
}

void testOutOfRangeServer({bool compression = false}) {
  var futures = <Future<bool>>[];
  var testData = <List<int>>[];
  List<int> data;
  data = Uint16List(1);
  data[0] = 256;
  testData.add(data);
  data = Uint32List(1);
  data[0] = 256;
  testData.add(data);
  data = Uint64List(1);
  data[0] = 256;
  testData.add(data);
  data = Int16List(1);
  data[0] = 256;
  testData.add(data);
  data = Int16List(1);
  data[0] = -1;
  testData.add(data);
  data = Int32List(1);
  data[0] = 256;
  testData.add(data);
  data = Int32List(1);
  data[0] = -1;
  testData.add(data);
  data = Int64List(1);
  data[0] = 256;
  testData.add(data);
  data = Int64List(1);
  data[0] = -1;
  testData.add(data);
  testData.add([-1]);
  testData.add([256]);

  var allDone = Completer<bool>();

  Future<bool> expectError(Future<void> future) {
    var completer = Completer<bool>();
    future
        .then((_) => completer.completeError('Message $data did not fail'))
        .catchError((e) => completer.complete(true));
    return completer.future;
  }

  createServer().then((server) {
    var messageCount = 0;
    var transformer = compression
        ? WebSocketTransformer()
        : WebSocketTransformer(compression: CompressionOptions.compressionOff);
    server.transform(transformer).listen((webSocket) {
      webSocket.listen((message) {
        messageCount++;
        webSocket.add(testData[(message as List<int>)[0]]);
        webSocket.close();
        futures.add(expectError(webSocket.done));
        if (messageCount == testData.length) {
          allDone.complete(true);
        }
      });
    });

    Future<bool> x(int i) {
      var completer = Completer<bool>();
      createClient(server.port, compression).then((webSocket) {
        webSocket.listen((message) => Expect.fail('No message expected'),
            onDone: () => completer.complete(true),
            onError: (Object e) => completer.completeError(e));
        webSocket.add([i]);
      });
      return completer.future;
    }

    for (int i = 0; i < testData.length; i++) {
      futures.add(x(i));
    }
    allDone.future
        .then((_) => Future.wait(futures).then((_) => server.close()));
  });
}

void main() {
  testUintLists();
  testUintLists(compression: true);
  testIntLists();
  testIntLists(compression: true);
  testOutOfRangeClient();
  testOutOfRangeClient(compression: true);
  // testOutOfRangeServer();
  // testOutOfRangeServer(compression: true);
}
