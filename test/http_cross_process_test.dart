// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io' show Platform, Process, ProcessResult;

import 'package:http_io/http_io.dart';

import 'expect.dart';

const int numServers = 10;

void main(List<String> args) {
  if (args.isEmpty) {
    for (int i = 0; i < numServers; ++i) {
      makeServer().then((server) {
        runClientProcess(server.port).then((_) => server.close());
      });
    }
  } else if (args[0] == '--client') {
    int port = int.parse(args[1]);
    runClient(port);
  } else {
    Expect.fail('Unknown arguments to http_cross_process_test.dart');
  }
}

Future<HttpServer> makeServer() {
  return HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) {
    server.listen((request) {
      request.cast<List<int>>().pipe(request.response);
    });
    return server;
  });
}

Future<void> runClientProcess(int port) {
  return Process.run(Platform.executable, <String>[
    ...Platform.executableArguments,
    Platform.script.toFilePath(),
    '--client',
    port.toString()
  ]).then((ProcessResult result) {
    if (result.exitCode != 0 ||
        !(result.stdout as String).contains('SUCCESS')) {
      print('Client failed, exit code ${result.exitCode}');
      print('  stdout:');
      print(result.stdout);
      print('  stderr:');
      print(result.stderr);
      Expect.fail('Client subprocess exit code: ${result.exitCode}');
    }
  });
}

void runClient(int port) {
  var client = HttpClient();
  client
      .get('127.0.0.1', port, '/')
      .then((request) => request.close())
      .then((response) => response.drain<void>())
      .then((_) => client.close())
      .then((_) => print('SUCCESS'));
}
