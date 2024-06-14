// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show Platform, Process;

import 'package:http_io/http_io.dart';

const clientScript = "http_server_close_response_after_error_client.dart";

void main() {
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      request.listen(null, onError: (e) {}, onDone: () {
        request.response.close();
      });
    });
    Process.run(
            Platform.executable,
            []
              ..addAll(Platform.executableArguments)
              ..addAll([
                Platform.script.resolve(clientScript).toString(),
                server.port.toString()
              ]))
        .then((result) {
      if (result.exitCode != 0) throw "Bad exit code";
      server.close();
    });
  });
}
