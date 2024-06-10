// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import 'dart:convert';
import "dart:typed_data";

import "package:http_io/http_io.dart";
import "package:test/test.dart";

Future<Null> doTest(responseBytes, bodyLength) async {
  bool fullRequest(List<int> bytes) {
    int length = bytes.length;
    return length > 4 &&
        bytes[length - 4] == 13 &&
        bytes[length - 3] == 10 &&
        bytes[length - 2] == 13 &&
        bytes[length - 1] == 10;
  }

  Future<void> handleSocket(Socket socket) async {
    List<int> bytes = <int>[];

    await for (Uint8List data in socket) {
      bytes.addAll(data);

      if (fullRequest(bytes)) {
        socket.add(responseBytes);
        socket.close();
      }
    }
  }

  ServerSocket server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen(handleSocket);

  HttpClient client = HttpClient();
  Uri url = Uri.parse('http://127.0.0.1:${server.port}/');
  HttpClientRequest request = await client.getUrl(url);
  HttpClientResponse response = await request.close();
  expect(response.statusCode, equals(200));

  List<int> bytes = <int>[];
  await response.forEach(bytes.addAll);
  expect(bodyLength, equals(bytes.length));
  await server.close();
}

void main() {
  String r1 = '''
HTTP/1.1 100 Continue\r
\r
HTTP/1.1 200 OK\r
\r
''';

  String r2 = '''
HTTP/1.1 100 Continue\r
My-Header-1: hello\r
My-Header-2: world\r
\r
HTTP/1.1 200 OK\r
\r
''';

  String r3 = '''
HTTP/1.1 100 Continue\r
\r
HTTP/1.1 200 OK\r
Content-Length: 2\r
\r
AB''';

  group('CRLF', () {
    test("Continue OK", () async {
      await doTest(ascii.encode(r1), 0);
    });

    test("Continue hello world OK", () async {
      await doTest(ascii.encode(r2), 0);
    });

    test("Continue OK length AB", () async {
      await doTest(ascii.encode(r3), 2);
    });
  });

  group('LF', () {
    test("Continue OK", () async {
      await doTest(ascii.encode(r1.replaceAll('\r\n', '\n')), 0);
    });

    test("Continue hello world OK", () async {
      await doTest(ascii.encode(r2.replaceAll('\r\n', '\n')), 0);
    });

    test("Continue OK length AB", () async {
      await doTest(ascii.encode(r3.replaceAll('\r\n', '\n')), 2);
    });
  });
}
