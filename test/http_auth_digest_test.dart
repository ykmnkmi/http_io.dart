// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:async';

import "package:convert/convert.dart";
import "package:crypto/crypto.dart";
import "package:http_io/http_io.dart";
import "package:test/test.dart";

final class Server {
  late HttpServer server;

  int unauthCount = 0; // Counter of the 401 responses.

  int successCount = 0; // Counter of the successful responses.

  int nonceCount = 0; // Counter of use of current nonce.

  late String ha1;

  int get port => server.port;

  Future<void> start(
    String? serverAlgorithm,
    String? serverQop,
    int? nonceStaleAfter,
    bool useNextNonce,
  ) async {
    Set ncs = Set();

    // Calculate ha1.
    String realm = "test";
    String username = "dart";
    String password = "password";

    Digest hasher = md5.convert("$username:$realm:$password".codeUnits);
    ha1 = hex.encode(hasher.bytes);

    String nonce = "12345678"; // No need for random nonce in test.

    this.server = await HttpServer.bind("127.0.0.1", 0);

    server.listen((HttpRequest request) {
      void sendUnauthorizedResponse(
        HttpResponse response, {
        bool stale = false,
      }) {
        response.statusCode = HttpStatus.unauthorized;

        StringBuffer authHeader = StringBuffer();
        authHeader.write('Digest');
        authHeader.write(', realm="$realm"');
        authHeader.write(', nonce="$nonce"');

        if (stale) {
          authHeader.write(', stale="true"');
        }

        if (serverAlgorithm != null) {
          authHeader.write(', algorithm=$serverAlgorithm');
        }

        authHeader.write(', domain="/digest/"');

        if (serverQop != null) {
          authHeader.write(', qop="$serverQop"');
        }

        response.headers.set(HttpHeaders.wwwAuthenticateHeader, authHeader);
        unauthCount++;
      }

      HttpResponse response = request.response;

      if (request.headers[HttpHeaders.authorizationHeader] != null) {
        expect(1,
            equals(request.headers[HttpHeaders.authorizationHeader]!.length));

        String authorization =
            request.headers[HttpHeaders.authorizationHeader]![0];
        HeaderValue header =
            HeaderValue.parse(authorization, parameterSeparator: ",");

        if (header.value.toLowerCase() == "basic") {
          sendUnauthorizedResponse(response);
        } else if (!useNextNonce && nonceCount == nonceStaleAfter) {
          nonce = "87654321";
          nonceCount = 0;
          sendUnauthorizedResponse(response, stale: true);
        } else {
          String? uri = header.parameters["uri"];
          String? qop = header.parameters["qop"];
          String? cnonce = header.parameters["cnonce"];
          String? nc = header.parameters["nc"];
          expect("digest", equals(header.value.toLowerCase()));
          expect("dart", equals(header.parameters["username"]));
          expect(realm, equals(header.parameters["realm"]));
          expect("MD5", equals(header.parameters["algorithm"]));
          expect(nonce, equals(header.parameters["nonce"]));
          expect(request.uri.toString(), equals(uri));

          if (qop != null) {
            // A server qop of auth-int is downgraded to none by the client.
            expect("auth", equals(serverQop));
            expect("auth", equals(header.parameters["qop"]));
            expect(cnonce, isNotNull);
            expect(nc, isNotNull);
            expect(ncs.contains(nc), isFalse);
            ncs.add(nc);
          } else {
            expect(cnonce, isNull);
            expect(nc, isNull);
          }

          expect(header.parameters["response"], isNotNull);

          Digest hasher = md5.convert("${request.method}:${uri}".codeUnits);
          String ha2 = hex.encode(hasher.bytes);

          Digest digest;

          if (qop == null || qop == "" || qop == "none") {
            digest = md5.convert("$ha1:${nonce}:$ha2".codeUnits);
          } else {
            digest = md5
                .convert("$ha1:${nonce}:${nc}:${cnonce}:${qop}:$ha2".codeUnits);
          }

          expect(
              hex.encode(digest.bytes), equals(header.parameters["response"]));

          successCount++;
          nonceCount++;

          // Add a bogus Authentication-Info for testing.
          String info = 'rspauth="77180d1ab3d6c9de084766977790f482", '
              'cnonce="8f971178", '
              'nc=000002c74, '
              'qop=auth';

          if (useNextNonce && nonceCount == nonceStaleAfter) {
            nonce = "abcdef01";
            info += ', nextnonce="$nonce"';
          }

          response.headers.set("Authentication-Info", info);
        }
      } else {
        sendUnauthorizedResponse(response);
      }

      response.close();
    });
  }

  void shutdown() {
    server.close();
  }

  static Future<Server> setupServer(
    String? algorithm,
    String? qop, {
    int? nonceStaleAfter,
    bool useNextNonce = false,
  }) async {
    Server server = Server();
    await server.start(algorithm, qop, nonceStaleAfter, useNextNonce);
    return server;
  }
}

Future<void> testNoCredentials(String? algorithm, String? qop) async {
  Server server = await Server.setupServer(algorithm, qop);
  HttpClient client = HttpClient();

  // Add digest credentials which does not match the path requested.
  client.addCredentials(Uri.parse("http://127.0.0.1:${server.port}/xxx"),
      "test", HttpClientDigestCredentials("dart", "password"));

  // Add basic credentials for the path requested.
  client.addCredentials(Uri.parse("http://127.0.0.1:${server.port}/digest"),
      "test", HttpClientBasicCredentials("dart", "password"));

  Future<void> makeRequest(Uri url) async {
    HttpClientRequest request = await client.getUrl(url);
    HttpClientResponse response = await request.close();
    expect(HttpStatus.unauthorized, equals(response.statusCode));
    await response.drain<void>();
  }

  List<Future<void>> futures = List<Future<void>>.generate(5, (int i) {
    Uri url = Uri.parse("http://127.0.0.1:${server.port}/digest");
    return makeRequest(url);
  });

  await Future.wait<void>(futures);
  server.shutdown();
  client.close();
}

Future<void> testCredentials(String? algorithm, String? qop) async {
  Server server = await Server.setupServer(algorithm, qop);
  HttpClient client = HttpClient();

  Future makeRequest(Uri url) async {
    HttpClientRequest request = await client.getUrl(url);
    HttpClientResponse response = await request.close();
    expect(HttpStatus.ok, equals(response.statusCode));
    expect(1, equals(response.headers["Authentication-Info"]?.length));
    await response.drain<void>();
  }

  client.addCredentials(Uri.parse("http://127.0.0.1:${server.port}/digest"),
      "test", HttpClientDigestCredentials("dart", "password"));

  List<Future<void>> futures = <Future<void>>[];

  for (int i = 0; i < 2; i++) {
    String uriBase = "http://127.0.0.1:${server.port}/digest";
    futures.add(makeRequest(Uri.parse(uriBase)));
    futures.add(makeRequest(Uri.parse("$uriBase?querystring")));
    futures.add(makeRequest(Uri.parse("$uriBase?querystring#fragment")));
  }

  await Future.wait(futures);
  server.shutdown();
  client.close();
}

Future<void> testAuthenticateCallback(String? algorithm, String? qop) async {
  Server server = await Server.setupServer(algorithm, qop);
  HttpClient client = HttpClient();

  client.authenticate = (Uri url, String scheme, String? realm) async {
    expect("Digest", equals(scheme));
    expect("test", equals(realm));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    client.addCredentials(Uri.parse("http://127.0.0.1:${server.port}/digest"),
        "test", HttpClientDigestCredentials("dart", "password"));
    return true;
  };

  Future<void> makeRequest(Uri url) async {
    HttpClientRequest request = await client.getUrl(url);
    HttpClientResponse response = await request.close();
    expect(HttpStatus.ok, equals(response.statusCode));
    expect(1, equals(response.headers["Authentication-Info"]?.length));
    await response.drain<void>();
  }

  List<Future<void>> futures = List<Future<void>>.generate(5, (int i) {
    Uri url = Uri.parse("http://127.0.0.1:${server.port}/digest");
    return makeRequest(url);
  });

  await Future.wait<void>(futures);
  server.shutdown();
  client.close();
}

Future<void> testStaleNonce() async {
  Server server = await Server.setupServer("MD5", "auth", nonceStaleAfter: 2);
  HttpClient client = HttpClient();

  Future<void> makeRequest(Uri url) async {
    HttpClientRequest request = await client.getUrl(url);
    HttpClientResponse response = await request.close();
    expect(HttpStatus.ok, equals(response.statusCode));
    expect(1, equals(response.headers["Authentication-Info"]?.length));
    await response.drain<void>();
  }

  Uri uri = Uri.parse("http://127.0.0.1:${server.port}/digest");
  HttpClientDigestCredentials credentials =
      HttpClientDigestCredentials("dart", "password");
  client.addCredentials(uri, "test", credentials);

  await makeRequest(uri);
  await makeRequest(uri);
  await makeRequest(uri);
  await makeRequest(uri);
  expect(2, equals(server.unauthCount));
  expect(4, equals(server.successCount));
  server.shutdown();
  client.close();
}

Future<void> testNextNonce() async {
  Server server = await Server.setupServer("MD5", "auth",
      nonceStaleAfter: 2, useNextNonce: true);
  HttpClient client = HttpClient();

  Future<void> makeRequest(Uri url) async {
    HttpClientRequest request = await client.getUrl(url);
    HttpClientResponse response = await request.close();
    expect(HttpStatus.ok, equals(response.statusCode));
    expect(1, equals(response.headers["Authentication-Info"]?.length));
    await response.drain();
  }

  Uri uri = Uri.parse("http://127.0.0.1:${server.port}/digest");
  HttpClientDigestCredentials credentials =
      HttpClientDigestCredentials("dart", "password");
  client.addCredentials(uri, "test", credentials);
  await makeRequest(uri);
  await makeRequest(uri);
  await makeRequest(uri);
  await makeRequest(uri);
  expect(1, equals(server.unauthCount));
  expect(4, equals(server.successCount));
  server.shutdown();
  client.close();
}

void main() {
  test("NoCredentials", () async {
    await testNoCredentials(null, null);
  });

  test("NoCredentials MD5", () async {
    await testNoCredentials("MD5", null);
  });

  test("NoCredentials MD5 auth", () async {
    await testNoCredentials("MD5", "auth");
  });

  test("Credentials", () async {
    await testCredentials(null, null);
  });

  test("Credentials MD5", () async {
    await testCredentials("MD5", null);
  });

  test("Credentials MD5 auth", () async {
    await testCredentials("MD5", "auth");
  });

  test("Credentials MD5 auth-int", () async {
    await testCredentials("MD5", "auth-int");
  });

  test("AuthenticateCallback", () async {
    await testAuthenticateCallback(null, null);
  });

  test("AuthenticateCallback MD5", () async {
    await testAuthenticateCallback("MD5", null);
  });

  test("AuthenticateCallback MD5 auth", () async {
    await testAuthenticateCallback("MD5", "auth");
  });

  test("AuthenticateCallback MD5 auth-int", () async {
    await testAuthenticateCallback("MD5", "auth-int");
  });

  test("StaleNonce", () async {
    await testStaleNonce();
  });

  test("NextNonce", () async {
    await testNextNonce();
  });
}
