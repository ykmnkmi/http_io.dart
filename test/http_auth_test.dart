// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import "package:http_io/http_io.dart";
import "package:test/test.dart";

class Server {
  late HttpServer server;

  bool passwordChanged = false;

  int get port => server.port;

  Future<void> start() async {
    this.server = await HttpServer.bind("127.0.0.1", 0);

    server.listen((HttpRequest request) {
      HttpResponse response = request.response;

      if (request.uri.path == "/passwdchg") {
        passwordChanged = true;
        response.close();
        return;
      }

      String username;
      String password;

      if (request.uri.path == "/") {
        username = "username";
        password = "password";
      } else {
        username = request.uri.path.substring(1, 6);
        password = request.uri.path.substring(1, 6);
      }

      if (passwordChanged) {
        password = "${password}1";
      }

      if (request.headers[HttpHeaders.authorizationHeader] != null) {
        expect(1,
            equals(request.headers[HttpHeaders.authorizationHeader]!.length));

        String authorization =
            request.headers[HttpHeaders.authorizationHeader]![0];
        List<String> tokens = authorization.split(" ");
        expect("Basic", equals(tokens[0]));

        String auth = base64.encode(utf8.encode("$username:$password"));

        if (passwordChanged && auth != tokens[1]) {
          response.statusCode = HttpStatus.unauthorized;
          response.headers
              .set(HttpHeaders.wwwAuthenticateHeader, "Basic, realm=realm");
        } else {
          expect(auth, equals(tokens[1]));
        }
      } else {
        response.statusCode = HttpStatus.unauthorized;
        response.headers
            .set(HttpHeaders.wwwAuthenticateHeader, "Basic, realm=realm");
      }

      response.close();
    });
  }

  void shutdown() {
    server.close();
  }
}

Future<Server> setupServer() async {
  Server server = Server();
  await server.start();
  return server;
}

Future<void> testUrlUserInfo() async {
  Completer<void> completer = Completer<void>();
  Server server = await setupServer();
  HttpClient client = HttpClient();

  Uri url = Uri.parse("http://username:password@127.0.0.1:${server.port}/");
  HttpClientRequest request = await client.getUrl(url);
  HttpClientResponse response = await request.close();

  response.listen(null, onDone: () {
    server.shutdown();
    client.close();
    completer.complete();
  });

  return completer.future;
}

Future<void> testBasicNoCredentials() async {
  Server server = await setupServer();
  HttpClient client = HttpClient();

  Future<void> makeRequest(Uri url) async {
    HttpClientRequest request = await client.getUrl(url);
    HttpClientResponse response = await request.close();
    expect(HttpStatus.unauthorized, equals(response.statusCode));
    await response.drain<void>();
  }

  List<Future> futures = <Future>[];

  for (int i = 0; i < 5; i++) {
    Uri url = Uri.parse("http://127.0.0.1:${server.port}/test$i");
    futures.add(makeRequest(url));

    Uri url2 = Uri.parse("http://127.0.0.1:${server.port}/test$i/xxx");
    futures.add(makeRequest(url2));
  }

  await Future.wait<void>(futures);
  server.shutdown();
  client.close();
}

Future<void> testBasicCredentials() async {
  Server server = await setupServer();
  HttpClient client = HttpClient();

  Future<void> makeRequest(Uri url) async {
    HttpClientRequest request = await client.getUrl(url);
    HttpClientResponse response = await request.close();
    expect(HttpStatus.ok, equals(response.statusCode));
    await response.drain<void>();
  }

  for (int i = 0; i < 5; i++) {
    client.addCredentials(Uri.parse("http://127.0.0.1:${server.port}/test$i"),
        "realm", HttpClientBasicCredentials("test$i", "test$i"));
  }

  List<Future> futures = <Future>[];

  for (int i = 0; i < 5; i++) {
    Uri url = Uri.parse("http://127.0.0.1:${server.port}/test$i");
    futures.add(makeRequest(url));

    Uri url2 = Uri.parse("http://127.0.0.1:${server.port}/test$i/xxx");
    futures.add(makeRequest(url2));
  }

  await Future.wait<void>(futures);
  server.shutdown();
  client.close();
}

Future<void> testBasicAuthenticateCallback() async {
  Completer<void> completer = Completer<void>();
  Server server = await setupServer();
  HttpClient client = HttpClient();
  bool passwordChanged = false;

  client.authenticate = (Uri url, String scheme, String? realm) async {
    expect("Basic", equals(scheme));
    expect("realm", equals(realm));

    String username = url.path.substring(1, 6);
    String password = url.path.substring(1, 6);

    if (passwordChanged) {
      password = "${password}1";
    }

    await Future<void>.delayed(const Duration(milliseconds: 10));

    HttpClientBasicCredentials credentials =
        HttpClientBasicCredentials(username, password);
    client.addCredentials(url, realm!, credentials);
    return true;
  };

  Future<void> makeRequest(Uri url) async {
    HttpClientRequest request = await client.getUrl(url);
    HttpClientResponse response = await request.close();
    expect(HttpStatus.ok, equals(response.statusCode));
    await response.drain<void>();
  }

  List<Future> makeRequests() {
    List<Future> futures = <Future>[];

    for (int i = 0; i < 5; i++) {
      Uri url = Uri.parse("http://127.0.0.1:${server.port}/test$i");
      futures.add(makeRequest(url));

      Uri url2 = Uri.parse("http://127.0.0.1:${server.port}/test$i/xxx");
      futures.add(makeRequest(url2));
    }

    return futures;
  }

  await Future.wait<void>(makeRequests());
  await makeRequest(Uri.parse("http://127.0.0.1:${server.port}/passwdchg"));
  passwordChanged = true;
  await Future.wait<void>(makeRequests());
  server.shutdown();
  client.close();
}

void main() {
  test("UrlUserInfo", testUrlUserInfo);

  test("BasicNoCredentials", testBasicNoCredentials);

  test("BasicCredentials", testBasicCredentials);

  test("BasicAuthenticateCallback", testBasicAuthenticateCallback);
}
