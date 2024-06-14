// Copyright (c) 2013, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import "dart:async";
import "dart:io" show Platform, Process, ProcessResult;

import "package:http_io/http_io.dart";

import "expect.dart";

const HOST_NAME = "localhost";
const CERTIFICATE = "localhost_cert";

String localFile(path) => Platform.script.resolve(path).toFilePath();

SecurityContext untrustedServerContext = SecurityContext()
  ..useCertificateChain(localFile('certificates/untrusted_server_chain.pem'))
  ..usePrivateKey(localFile('certificates/untrusted_server_key.pem'),
      password: 'dartdart');

SecurityContext clientContext = SecurityContext()
  ..setTrustedCertificates(localFile('certificates/trusted_certs.pem'));

Future<HttpServer> runServer() {
  return HttpServer.bindSecure(HOST_NAME, 0, untrustedServerContext, backlog: 5)
      .then((server) {
    server.listen((HttpRequest request) {
      request.listen((_) {}, onDone: () {
        request.response.close();
      });
    }, onError: (e) {
      if (e is! HandshakeException) throw e;
    });
    return server;
  });
}

void main() {
  var clientScript = localFile('https_unauthorized_client.dart');
  Future clientProcess(int port) {
    return Process.run(
            Platform.executable,
            []
              ..addAll(Platform.executableArguments)
              ..addAll([clientScript, port.toString()]))
        .then((ProcessResult result) {
      if (result.exitCode != 0 || !result.stdout.contains('SUCCESS')) {
        print("Client failed");
        print("  stdout:");
        print(result.stdout);
        print("  stderr:");
        print(result.stderr);
        Expect.fail('Client subprocess exit code: ${result.exitCode}');
      }
    });
  }

  runServer().then((server) {
    clientProcess(server.port).then((_) {
      server.close();
    });
  });
}
