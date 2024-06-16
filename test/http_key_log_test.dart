// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' show FileSystemException, Platform;

import 'package:http_io/http_io.dart';

import 'async_helper.dart';
import 'expect.dart';

late InternetAddress host;

String localFile(String path) => Platform.script.resolve(path).toFilePath();

SecurityContext serverContext = SecurityContext()
  ..useCertificateChain(localFile('certificates/server_chain.pem'))
  ..usePrivateKey(localFile('certificates/server_key.pem'),
      password: 'dartdart');

Future<HttpServer> startEchoServer() {
  return HttpServer.bindSecure(host, 0, serverContext).then((server) {
    server.listen((HttpRequest req) {
      var res = req.response;
      res.write('Test');
      res.close();
    });
    return server;
  });
}

Future<void> testSuccess(HttpServer server) async {
  var log = '';
  SecurityContext clientContext = SecurityContext()
    ..setTrustedCertificates(localFile('certificates/trusted_certs.pem'));

  var client = HttpClient(context: clientContext);
  client.keyLog = (String line) {
    log += line;
  };
  var request =
      await client.getUrl(Uri.parse('https://localhost:${server.port}/test'));
  var response = await request.close();
  await response.drain<void>();

  Expect.contains('CLIENT_HANDSHAKE_TRAFFIC_SECRET', log);
}

Future<void> testExceptionInKeyLogFunction(HttpServer server) async {
  SecurityContext clientContext = SecurityContext()
    ..setTrustedCertificates(localFile('certificates/trusted_certs.pem'));

  var client = HttpClient(context: clientContext);
  var numCalls = 0;
  client.keyLog = (String line) {
    ++numCalls;
    throw FileSystemException('Something bad happened');
  };
  var request =
      await client.getUrl(Uri.parse('https://localhost:${server.port}/test'));
  var response = await request.close();
  await response.drain<void>();

  Expect.notEquals(0, numCalls);
}

void main() async {
  asyncStart();
  await InternetAddress.lookup('localhost').then((hosts) => host = hosts.first);
  var server = await startEchoServer();

  await testSuccess(server);
  await testExceptionInKeyLogFunction(server);

  await server.close();
  asyncEnd();
}
