// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' show Directory, Platform, Process;

import 'package:http_io/http_io.dart';

import 'expect.dart';

Future<void> testHttpServer(String name) async {
  var sockname = '$name/sock';
  var address = InternetAddress(sockname, type: InternetAddressType.unix);
  var httpServer = await HttpServer.bind(address, 0);
  late StreamSubscription<HttpRequest> sub;
  sub = httpServer.listen((HttpRequest request) {
    request.response.write('Hello, world!');
    request.response.close();
    sub.cancel();
  }, onDone: () {
    httpServer.close();
  });

  var result =
      await Process.run('curl', ['--unix-socket', sockname, 'localhost']);
  Expect.isTrue(result.stdout.toString().contains('Hello, world!'));
}

Future<void> main() async {
  var tmpDir = Directory.systemTemp.createTempSync('http_on_unix_socket_test');
  try {
    await testHttpServer(tmpDir.path);
  } catch (e) {
    if (Platform.isMacOS || Platform.isLinux || Platform.isAndroid) {
      Expect.fail('Unexpected exception $e is thrown');
    } else {
      Expect.isTrue(e is SocketException);
      Expect.isTrue(e.toString().contains('not available'));
    }
  } finally {
    tmpDir.deleteSync(recursive: true);
  }
}
