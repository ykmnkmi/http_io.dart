// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:http_io/http_io.dart';

import 'expect.dart';

class Server {
  late HttpServer server;
  bool passwordChanged = false;

  Future<Server> start() {
    var completer = Completer<Server>();
    HttpServer.bind('127.0.0.1', 0).then((s) {
      server = s;
      server.listen((HttpRequest request) {
        var response = request.response;
        if (request.uri.path == '/passwdchg') {
          passwordChanged = true;
          response.close();
          return;
        }

        String username;
        String password;
        if (request.uri.path == '/') {
          username = 'username';
          password = 'password';
        } else {
          username = request.uri.path.substring(1, 6);
          password = request.uri.path.substring(1, 6);
        }
        if (passwordChanged) {
          password = '${password}1';
        }
        if (request.headers[HttpHeaders.authorizationHeader] != null) {
          Expect.equals(
              1, request.headers[HttpHeaders.authorizationHeader]!.length);
          String authorization =
              request.headers[HttpHeaders.authorizationHeader]![0];
          List<String> tokens = authorization.split(' ');
          Expect.equals('Basic', tokens[0]);
          String auth = base64.encode(utf8.encode('$username:$password'));
          if (passwordChanged && auth != tokens[1]) {
            response.statusCode = HttpStatus.unauthorized;
            response.headers
                .set(HttpHeaders.wwwAuthenticateHeader, 'Basic, realm=realm');
          } else {
            Expect.equals(auth, tokens[1]);
          }
        } else {
          response.statusCode = HttpStatus.unauthorized;
          response.headers
              .set(HttpHeaders.wwwAuthenticateHeader, 'Basic, realm=realm');
        }
        response.close();
      });
      completer.complete(this);
    });
    return completer.future;
  }

  void shutdown() {
    server.close();
  }

  int get port => server.port;
}

Future<Server> setupServer() {
  return Server().start();
}

void testUrlUserInfo() {
  setupServer().then((server) {
    HttpClient client = HttpClient();

    client
        .getUrl(Uri.parse('http://username:password@127.0.0.1:${server.port}/'))
        .then((request) => request.close())
        .then((HttpClientResponse response) {
      response.listen((_) {}, onDone: () {
        server.shutdown();
        client.close();
      });
    });
  });
}

void testBasicNoCredentials() {
  setupServer().then((server) {
    HttpClient client = HttpClient();

    Future<void> makeRequest(Uri url) {
      return client
          .getUrl(url)
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        Expect.equals(HttpStatus.unauthorized, response.statusCode);
        return response.fold(null, (x, y) {});
      });
    }

    var futures = <Future<void>>[];
    for (int i = 0; i < 5; i++) {
      futures.add(
          makeRequest(Uri.parse('http://127.0.0.1:${server.port}/test$i')));
      futures.add(
          makeRequest(Uri.parse('http://127.0.0.1:${server.port}/test$i/xxx')));
    }
    Future.wait(futures).then((_) {
      server.shutdown();
      client.close();
    });
  });
}

void testBasicCredentials() {
  setupServer().then((server) {
    HttpClient client = HttpClient();

    Future<void> makeRequest(Uri url) {
      return client
          .getUrl(url)
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        Expect.equals(HttpStatus.ok, response.statusCode);
        return response.fold(null, (x, y) {});
      });
    }

    for (int i = 0; i < 5; i++) {
      client.addCredentials(Uri.parse('http://127.0.0.1:${server.port}/test$i'),
          'realm', HttpClientBasicCredentials('test$i', 'test$i'));
    }

    var futures = <Future<void>>[];
    for (int i = 0; i < 5; i++) {
      futures.add(
          makeRequest(Uri.parse('http://127.0.0.1:${server.port}/test$i')));
      futures.add(
          makeRequest(Uri.parse('http://127.0.0.1:${server.port}/test$i/xxx')));
    }
    Future.wait(futures).then((_) {
      server.shutdown();
      client.close();
    });
  });
}

void testBasicAuthenticateCallback() {
  setupServer().then((server) {
    HttpClient client = HttpClient();
    bool passwordChanged = false;

    client.authenticate = (Uri url, String scheme, String? realm) {
      Expect.equals('Basic', scheme);
      Expect.equals('realm', realm);
      String username = url.path.substring(1, 6);
      String password = url.path.substring(1, 6);
      if (passwordChanged) {
        password = '${password}1';
      }
      var completer = Completer<bool>();
      Timer(const Duration(milliseconds: 10), () {
        client.addCredentials(
            url, realm!, HttpClientBasicCredentials(username, password));
        completer.complete(true);
      });
      return completer.future;
    };

    Future<void> makeRequest(Uri url) {
      return client
          .getUrl(url)
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        Expect.equals(HttpStatus.ok, response.statusCode);
        return response.fold(null, (x, y) {});
      });
    }

    List<Future<void>> makeRequests() {
      var futures = <Future<void>>[];
      for (int i = 0; i < 5; i++) {
        futures.add(
            makeRequest(Uri.parse('http://127.0.0.1:${server.port}/test$i')));
        futures.add(makeRequest(
            Uri.parse('http://127.0.0.1:${server.port}/test$i/xxx')));
      }
      return futures;
    }

    Future.wait(makeRequests()).then((_) {
      makeRequest(Uri.parse('http://127.0.0.1:${server.port}/passwdchg'))
          .then((_) {
        passwordChanged = true;
        Future.wait(makeRequests()).then((_) {
          server.shutdown();
          client.close();
        });
      });
    });
  });
}

void testLocalServerBasic() {
  HttpClient client = HttpClient();

  client.authenticate = (Uri url, String scheme, String? realm) {
    client.addCredentials(Uri.parse('http://127.0.0.1/basic'), 'test',
        HttpClientBasicCredentials('test', 'test'));
    return Future.value(true);
  };

  client
      .getUrl(Uri.parse('http://127.0.0.1/basic/test'))
      .then((HttpClientRequest request) => request.close())
      .then((HttpClientResponse response) {
    Expect.equals(HttpStatus.ok, response.statusCode);
    response.drain<void>().then((_) {
      client.close();
    });
  });
}

void testLocalServerDigest() {
  HttpClient client = HttpClient();

  client.authenticate = (Uri url, String scheme, String? realm) {
    print('url: $url, scheme: $scheme, realm: $realm');
    client.addCredentials(Uri.parse('http://127.0.0.1/digest'), 'test',
        HttpClientDigestCredentials('test', 'test'));
    return Future.value(true);
  };

  client
      .getUrl(Uri.parse('http://127.0.0.1/digest/test'))
      .then((HttpClientRequest request) => request.close())
      .then((HttpClientResponse response) {
    Expect.equals(HttpStatus.ok, response.statusCode);
    response.drain<void>().then((_) {
      client.close();
    });
  });
}

void main() {
  testUrlUserInfo();
  testBasicNoCredentials();
  testBasicCredentials();
  testBasicAuthenticateCallback();
  // These teste are not normally run. They can be used for locally
  // testing with another web server (e.g. Apache).
  //testLocalServerBasic();
  //testLocalServerDigest();
}
