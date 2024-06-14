// Copyright (c) 2013, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:http_io/http_io.dart';

import 'expect.dart';

final hostName = 'localhost';

String localFile(String path) => Platform.script.resolve(path).toFilePath();

SecurityContext serverContext = SecurityContext()
  ..useCertificateChain(localFile('certificates/server_chain.pem'))
  ..usePrivateKey(localFile('certificates/server_key.pem'),
      password: 'dartdart');

class CustomException {}

Future<void> main() async {
  var host = (await InternetAddress.lookup(hostName)).first;
  var server = await HttpServer.bindSecure(host, 0, serverContext, backlog: 5);
  server.listen((request) {
    request.listen((_) {}, onDone: () {
      request.response.close();
    });
  });

  SecurityContext goodContext = SecurityContext()
    ..setTrustedCertificates(localFile('certificates/trusted_certs.pem'));
  SecurityContext badContext = SecurityContext();
  SecurityContext defaultContext = SecurityContext.defaultContext;

  await runClient(server.port, goodContext, true, 'pass');
  await runClient(server.port, goodContext, false, 'pass');
  await runClient(server.port, goodContext, 'fisk', 'pass');
  await runClient(server.port, goodContext, 'exception', 'pass');
  await runClient(server.port, badContext, true, 'pass');
  await runClient(server.port, badContext, false, 'fail');
  await runClient(server.port, badContext, 'fisk', 'fail');
  await runClient(server.port, badContext, 'exception', 'throw');
  await runClient(server.port, defaultContext, true, 'pass');
  await runClient(server.port, defaultContext, false, 'fail');
  await runClient(server.port, defaultContext, 'fisk', 'fail');
  await runClient(server.port, defaultContext, 'exception', 'throw');
  server.close();
}

Future<void> runClient(int port, SecurityContext context,
    Object callbackReturns, String result) async {
  HttpClient client = HttpClient(context: context);
  client.badCertificateCallback = (X509Certificate certificate, host, port) {
    Expect.isTrue(certificate.subject.contains('rootauthority'));
    Expect.isTrue(certificate.issuer.contains('rootauthority'));
    // Throw exception if one is requested.
    if (callbackReturns == 'exception') {
      throw CustomException();
    }
    return callbackReturns as bool;
  };

  try {
    var request = await client.getUrl(Uri.parse('https://$hostName:$port/'));
    Expect.equals('pass', result);
    await request.close();
  } catch (error) {
    Expect.notEquals(result, 'pass');
    if (result == 'fail') {
      Expect.isTrue(error is HandshakeException ||
          (callbackReturns is! bool && error is TypeError));
    } else if (result == 'throw') {
      Expect.isTrue(error is CustomException);
    } else {
      Expect.fail('Unknown expectation $result');
    }
  }
}
