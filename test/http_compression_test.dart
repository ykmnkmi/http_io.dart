// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:http_io/http_io.dart';

import 'expect.dart';

Future<void> testServerCompress({bool clientAutoUncompress = true}) async {
  Future<void> test(List<int> data) async {
    var server = await HttpServer.bind('127.0.0.1', 0);
    server.autoCompress = true;
    server.listen((request) {
      request.response.add(data);
      request.response.close();
    });
    var client = HttpClient();
    client.autoUncompress = clientAutoUncompress;
    var request = await client.get('127.0.0.1', server.port, '/');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip,deflate');
    var response = await request.close();
    Expect.equals(
        'gzip', response.headers.value(HttpHeaders.contentEncodingHeader));
    var list =
        await response.fold<List<int>>(<int>[], (list, b) => list..addAll(b));
    if (clientAutoUncompress) {
      Expect.listEquals(data, list);
    } else {
      Expect.listEquals(data, gzip.decode(list));
    }
    server.close();
    client.close();
  }

  await test('My raw server provided data'.codeUnits);
  var longBuffer = Uint8List(1024 * 1024);
  for (int i = 0; i < longBuffer.length; i++) {
    longBuffer[i] = i & 0xFF;
  }
  await test(longBuffer);
}

Future<void> testAcceptEncodingHeader() async {
  Future<void> test(String encoding, bool valid) async {
    var server = await HttpServer.bind('127.0.0.1', 0);
    server.autoCompress = true;
    server.listen((request) {
      request.response.write('data');
      request.response.close();
    });
    var client = HttpClient();
    var request = await client.get('127.0.0.1', server.port, '/');
    request.headers.set(HttpHeaders.acceptEncodingHeader, encoding);
    var response = await request.close();
    Expect.equals(valid,
        'gzip' == response.headers.value(HttpHeaders.contentEncodingHeader));
    await response.listen((_) {}).asFuture<void>();
    server.close();
    client.close();
  }

  await test('gzip', true);
  await test('deflate', false);
  await test('gzip, deflate', true);
  await test('gzip ,deflate', true);
  await test('gzip  ,  deflate', true);
  await test('deflate,gzip', true);
  await test('deflate, gzip', true);
  await test('deflate ,gzip', true);
  await test('deflate  ,  gzip', true);
  await test('abc,deflate  ,  gzip,def,,,ghi  ,jkl', true);
  await test('xgzip', false);
  await test('gzipx;', false);
}

Future<void> testDisableCompressTest() async {
  var server = await HttpServer.bind('127.0.0.1', 0);
  Expect.equals(false, server.autoCompress);
  server.listen((request) {
    Expect.equals(
        'gzip', request.headers.value(HttpHeaders.acceptEncodingHeader));
    request.response.write('data');
    request.response.close();
  });
  var client = HttpClient();
  var request = await client.get('127.0.0.1', server.port, '/');
  var response = await request.close();
  Expect.equals(
      null, response.headers.value(HttpHeaders.contentEncodingHeader));
  await response.listen((_) {}).asFuture<void>();
  server.close();
  client.close();
}

void main() async {
  await testServerCompress();
  await testServerCompress(clientAutoUncompress: false);
  await testAcceptEncodingHeader();
  await testDisableCompressTest();
}
