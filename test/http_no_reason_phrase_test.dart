// (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:http_io/http_io.dart';

import 'expect.dart';

// Test that a response line without any reason phrase is handled.
void missingReasonPhrase(int statusCode, bool includeSpace) {
  var client = HttpClient();
  ServerSocket.bind('127.0.0.1', 0).then((server) {
    server.listen((client) {
      client.listen(null);
      if (includeSpace) {
        client.write('HTTP/1.1 $statusCode \r\n\r\n');
      } else {
        client.write('HTTP/1.1 $statusCode\r\n\r\n');
      }
      client.close();
    });
    client
        .getUrl(Uri.parse('http://127.0.0.1:${server.port}/'))
        .then((request) => request.close())
        .then((response) {
      Expect.equals(statusCode, response.statusCode);
      Expect.equals('', response.reasonPhrase);
      return response.drain<void>();
    }).whenComplete(() => server.close());
  });
}

void main() {
  missingReasonPhrase(HttpStatus.ok, true);
  missingReasonPhrase(HttpStatus.internalServerError, true);
  missingReasonPhrase(HttpStatus.ok, false);
  missingReasonPhrase(HttpStatus.internalServerError, false);
}
