// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:async';

import 'package:http_io/http_io.dart';

import 'async_helper.dart';
import 'expect.dart';

void main() {
  // A virtual tun/tap interface should be created with following instructions:
  // Create an interface with name [tap0],
  //    sudo ip tuntap add name [tap0] mode tap
  // Assign an ipv6 address [fe80:1::1],
  //    sudo ip -6 addr add dev [tap0] [fe80:1::1] scope link nodad
  // Check for virtual interface with ipv6 set,
  //    ip address show
  asyncStart();
  try {
    // Make sure the address here is the same as what it shows in
    // "ip address show"
    var ipv6 = 'fe80:1::1%tap0';

    // Parses a Link-local address on Linux and Windows will throw an exception.
    InternetAddress(ipv6);

    HttpServer.bind(ipv6, 0).then((server) {
      server.listen((request) {
        var timer = Timer.periodic(const Duration(milliseconds: 0), (_) {
          request.response.write(
            'data:${DateTime.now().millisecondsSinceEpoch}\n\n',
          );
        });
        request.response.done
            .whenComplete(() {
              timer.cancel();
            })
            .catchError((_) {});
      });

      var client = HttpClient();
      client
          .getUrl(Uri.parse('http://[$ipv6]:${server.port}'))
          .then((request) => request.close())
          .then((response) {
            print(
              'response: status code: ${response.statusCode}, reason: ${response.reasonPhrase}',
            );
            int bytes = 0;
            response.listen(
              (data) {
                bytes += data.length;
                if (bytes > 100) {
                  client.close(force: true);
                }
              },
              onError: (error) {
                server.close();
              },
            );
          });
      asyncEnd();
    });
  } catch (e) {
    Expect.fail('SocketException: $e');
    asyncEnd();
  }
}
