// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test that closing a large amount of servers will not lead to a stack
// overflow.

import 'package:http_io/http_io.dart';

Future<void> main() async {
  var max = 10000;
  var servers = <ServerSocket>[];
  for (var i = 0; i < max; i++) {
    var server = await ServerSocket.bind('localhost', 0);
    server.listen((Socket socket) {});
    servers.add(server);
  }
  var client = HttpClient();
  var got = 0;
  for (var i = 0; i < max; i++) {
    Future(() async {
      try {
        var request = await client
            .getUrl(Uri.parse('http://localhost:${servers[i].port}/'));
        got++;
        if (got == max) {
          // Test that no stack overflow happens.
          client.close(force: true);
          for (var server in servers) {
            server.close();
          }
        }
        var response = await request.close();
        response.drain<void>();
      } on HttpException catch (_) {}
    });
  }
}
