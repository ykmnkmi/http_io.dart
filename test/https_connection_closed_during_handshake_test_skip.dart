// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process, exit;

import 'package:http_io/http_io.dart';

import "async_helper.dart";
import "expect.dart";

String getFilename(String path) => Platform.script.resolve(path).toFilePath();

final SecurityContext serverSecurityContext = () {
  final context = SecurityContext();
  context.usePrivateKey(getFilename('localhost.key'));
  context.useCertificateChain(getFilename('localhost.crt'));
  return context;
}();

final SecurityContext clientSecurityContext = () {
  final context = SecurityContext(withTrustedRoots: true);
  context.setTrustedCertificates(getFilename('localhost.crt'));
  return context;
}();

void main(List<String> args) async {
  if (args.length >= 1 && args[0] == 'server') {
    final server =
        await SecureServerSocket.bind('localhost', 0, serverSecurityContext);
    print('ok ${server.port}');
    server.listen((socket) {
      print('server: got connection');
      socket.close();
    });
    await Future.delayed(Duration(seconds: 2));
    print('server: exiting');
    exit(1);
  }

  asyncStart();

  final serverProcess = await Process.start(Platform.executable, [
    ...Platform.executableArguments,
    Platform.script.toFilePath(),
    'server'
  ]);
  final serverPortCompleter = Completer<int>();

  serverProcess.stdout
      .transform(utf8.decoder)
      .transform(LineSplitter())
      .listen((line) {
    print('server stdout: $line');
    if (line.startsWith('ok')) {
      serverPortCompleter.complete(int.parse(line.substring('ok'.length)));
    }
  });
  serverProcess.stderr
      .transform(utf8.decoder)
      .transform(LineSplitter())
      .listen((line) => print('server stderr: $line'));

  int port = await serverPortCompleter.future;

  final errorCompleter = Completer();
  await runZoned(() async {
    var socket = await SecureSocket.connect('localhost', port,
        context: clientSecurityContext);
    socket.write(<int>[1, 2, 3]);
  }, onError: (e) {
    // Even if server disconnects during later parts of handshake, since
    // TLS v1.3 client might not notice it until attempt to communicate with
    // the server.
    print('thrownException: $e');
    errorCompleter.complete(e);
  });
  Expect.isTrue((await errorCompleter.future) is SocketException);
  serverProcess.kill();

  asyncEnd();
}
