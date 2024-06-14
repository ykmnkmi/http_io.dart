// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show File, Platform;
import 'dart:isolate';

import 'package:http_io/http_io.dart';

import 'expect.dart';

late InternetAddress host;

String localFile(String path) => Platform.script.resolve(path).toFilePath();

SecurityContext serverContext = SecurityContext()
  ..useCertificateChain(localFile('certificates/server_chain.pem'))
  ..usePrivateKey(localFile('certificates/server_key.pem'),
      password: 'dartdart');

SecurityContext clientContext = SecurityContext()
  ..setTrustedCertificates(localFile('certificates/trusted_certs.pem'));

void testListenOn() {
  void test(void Function() onDone) {
    HttpServer.bindSecure(host, 0, serverContext, backlog: 5).then((server) {
      ReceivePort serverPort = ReceivePort();
      server.listen((HttpRequest request) {
        request.listen((_) {}, onDone: () {
          request.response.close();
          serverPort.close();
        });
      });

      HttpClient client = HttpClient(context: clientContext);
      ReceivePort clientPort = ReceivePort();
      client
          .getUrl(Uri.parse('https://${host.host}:${server.port}/'))
          .then((HttpClientRequest request) {
        return request.close();
      }).then((HttpClientResponse response) {
        response.listen((_) {}, onDone: () {
          client.close();
          clientPort.close();
          server.close();
          Expect.throws(() => server.port);
          onDone();
        });
      }).catchError((Object e, StackTrace trace) {
        Expect.fail('Unexpected error in Https client: $e\nStackTrace: $trace');
      });
    });
  }

  // Test two servers in succession.
  test(() {
    test(() {});
  });
}

void testEarlyClientClose() {
  HttpServer.bindSecure(host, 0, serverContext).then((server) {
    server.listen((request) {
      String name = Platform.script.toFilePath();
      File(name)
          .openRead()
          .cast<List<int>>()
          .pipe(request.response)
          .catchError((e) {/* ignore */});
    });

    var count = 0;
    void makeRequest() {
      Socket.connect(host, server.port).then((socket) {
        var data = 'Invalid TLS handshake';
        socket.write(data);
        socket.close();
        socket.done.then((_) {
          socket.destroy();
          if (++count < 10) {
            makeRequest();
          } else {
            server.close();
          }
        });
      });
    }

    makeRequest();
  });
}

void main() {
  InternetAddress.lookup('localhost').then((hosts) {
    host = hosts.first;
    testListenOn();
    testEarlyClientClose();
  });
}
