// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show Platform;

import 'package:http_io/http_io.dart';

import 'async_helper.dart';
import 'expect.dart';

const hostName = 'localhost';
String localFile(String path) => Platform.script.resolve(path).toFilePath();

SecurityContext serverContext = SecurityContext()
  ..useCertificateChain(localFile('certificates/server_chain.pem'))
  ..usePrivateKey(localFile('certificates/server_key.pem'),
      password: 'dartdart')
  ..setTrustedCertificates(
    localFile('certificates/client_authority.pem'),
  )
  ..setClientAuthorities(
    localFile('certificates/client_authority.pem'),
  );

SecurityContext clientContext = SecurityContext()
  ..setTrustedCertificates(localFile('certificates/trusted_certs.pem'))
  ..useCertificateChain(localFile('certificates/client1.pem'))
  ..usePrivateKey(localFile('certificates/client1_key.pem'),
      password: 'dartdart');

void main() {
  asyncStart();
  HttpServer.bindSecure(hostName, 0, serverContext,
          backlog: 5, requestClientCertificate: true)
      .then((server) {
    server.listen((HttpRequest request) {
      Expect.isNotNull(request.certificate);
      Expect.equals('/CN=user1', request.certificate!.subject);
      request.response.write('Hello');
      request.response.close();
    });

    HttpClient client = HttpClient(context: clientContext);
    client
        .getUrl(Uri.parse('https://$hostName:${server.port}/'))
        .then((request) => request.close())
        .then((response) {
      Expect.equals('/CN=localhost', response.certificate!.subject);
      Expect.equals('/CN=intermediateauthority', response.certificate!.issuer);
      return response
          .fold<List<int>>(<int>[], (message, data) => message..addAll(data));
    }).then((message) {
      String received = String.fromCharCodes(message);
      Expect.equals(received, 'Hello');
      client.close();
      server.close();
      asyncEnd();
    });
  });
}
