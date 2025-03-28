// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:http_io/http_io.dart' show exit;

import 'package:http_io/http_io.dart';

void main(List<String> arguments) {
  int port = int.parse(arguments.first);
  const max = 64;
  int count = 0;
  void run() {
    if (count++ == max) {
      exit(0);
    }
    Socket.connect('127.0.0.1', port).then((socket) {
      socket.write('POST / HTTP/1.1\r\n');
      socket.write('Content-Length: 10\r\n');
      socket.write('\r\n');
      socket.write('LALALA');
      socket.destroy();
      socket.listen(null, onDone: run);
    });
  }

  for (int i = 0; i < 4; i++) {
    run();
  }
}
