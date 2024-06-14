// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:typed_data';

import 'package:http_io/http_io.dart';

import "expect.dart";

void testChunkedBufferSizeMsg() {
  // Buffer of same size as our internal buffer, minus 4. Makes us hit the
  // boundary.
  var sendData = Uint8List(8 * 1024 - 4);
  for (int i = 0; i < sendData.length; i++) sendData[i] = i % 256;

  HttpServer.bind('127.0.0.1', 0).then((server) {
    server.listen((request) {
      // Chunked is on by default. Be sure no data is lost when sending several
      // chunks of data.
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.close();
    });
    var client = HttpClient();
    client.get('127.0.0.1', server.port, '/').then((request) {
      request.headers.set(HttpHeaders.acceptEncodingHeader, "");
      return request.close();
    }).then((response) {
      var buffer = [];
      response.listen((data) => buffer.addAll(data), onDone: () {
        Expect.equals(sendData.length * 8, buffer.length);
        for (int i = 0; i < buffer.length; i++) {
          Expect.equals(sendData[i % sendData.length], buffer[i]);
        }
        server.close();
      });
    });
  });
}

void main() {
  testChunkedBufferSizeMsg();
}
