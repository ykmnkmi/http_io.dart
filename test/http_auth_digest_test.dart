// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:async';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:http_io/http_io.dart';

import 'expect.dart';

class Server {
  late HttpServer server;
  int unauthCount = 0; // Counter of the 401 responses.
  int successCount = 0; // Counter of the successful responses.
  int nonceCount = 0; // Counter of use of current nonce.
  late String ha1;

  static Future<Server> start(String? algorithm, String? qop,
      {int? nonceStaleAfter, bool useNextNonce = false}) {
    return Server()._start(algorithm, qop, nonceStaleAfter, useNextNonce);
  }

  Future<Server> _start(String? serverAlgorithm, String? serverQop,
      int? nonceStaleAfter, bool useNextNonce) {
    Set<String?> ncs = <String?>{};
    // Calculate ha1.
    String realm = 'test';
    String username = 'dart';
    String password = 'password';
    var hasher = md5.convert('$username:$realm:$password'.codeUnits);
    ha1 = hex.encode(hasher.bytes);

    var nonce = '12345678'; // No need for random nonce in test.

    var completer = Completer<Server>();
    HttpServer.bind('127.0.0.1', 0).then((s) {
      server = s;
      server.listen((HttpRequest request) {
        void sendUnauthorizedResponse(HttpResponse response,
            {bool stale = false}) {
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

        var response = request.response;
        if (request.headers[HttpHeaders.authorizationHeader] != null) {
          Expect.equals(
              1, request.headers[HttpHeaders.authorizationHeader]!.length);
          String authorization =
              request.headers[HttpHeaders.authorizationHeader]![0];
          HeaderValue header =
              HeaderValue.parse(authorization, parameterSeparator: ',');
          if (header.value.toLowerCase() == 'basic') {
            sendUnauthorizedResponse(response);
          } else if (!useNextNonce && nonceCount == nonceStaleAfter) {
            nonce = '87654321';
            nonceCount = 0;
            sendUnauthorizedResponse(response, stale: true);
          } else {
            var uri = header.parameters['uri'];
            var qop = header.parameters['qop'];
            var cnonce = header.parameters['cnonce'];
            var nc = header.parameters['nc'];
            Expect.equals('digest', header.value.toLowerCase());
            Expect.equals('dart', header.parameters['username']);
            Expect.equals(realm, header.parameters['realm']);
            Expect.equals('MD5', header.parameters['algorithm']);
            Expect.equals(nonce, header.parameters['nonce']);
            Expect.equals(request.uri.toString(), uri);
            if (qop != null) {
              // A server qop of auth-int is downgraded to none by the client.
              Expect.equals('auth', serverQop);
              Expect.equals('auth', header.parameters['qop']);
              Expect.isNotNull(cnonce);
              Expect.isNotNull(nc);
              Expect.isFalse(ncs.contains(nc));
              ncs.add(nc);
            } else {
              Expect.isNull(cnonce);
              Expect.isNull(nc);
            }
            Expect.isNotNull(header.parameters['response']);

            var hasher = md5.convert('${request.method}:$uri'.codeUnits);
            var ha2 = hex.encode(hasher.bytes);

            Digest digest;
            if (qop == null || qop == '' || qop == 'none') {
              digest = md5.convert('$ha1:$nonce:$ha2'.codeUnits);
            } else {
              digest =
                  md5.convert('$ha1:$nonce:$nc:$cnonce:$qop:$ha2'.codeUnits);
            }
            Expect.equals(
                hex.encode(digest.bytes), header.parameters['response']);

            successCount++;
            nonceCount++;

            // Add a bogus Authentication-Info for testing.
            var info = 'rspauth="77180d1ab3d6c9de084766977790f482", '
                'cnonce="8f971178", '
                'nc=000002c74, '
                'qop=auth';
            if (useNextNonce && nonceCount == nonceStaleAfter) {
              nonce = 'abcdef01';
              info += ', nextnonce="$nonce"';
            }
            response.headers.set('Authentication-Info', info);
          }
        } else {
          sendUnauthorizedResponse(response);
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

void testNoCredentials(String? algorithm, String? qop) {
  Server.start(algorithm, qop).then((server) {
    HttpClient client = HttpClient();

    // Add digest credentials which does not match the path requested.
    client.addCredentials(Uri.parse('http://127.0.0.1:${server.port}/xxx'),
        'test', HttpClientDigestCredentials('dart', 'password'));

    // Add basic credentials for the path requested.
    client.addCredentials(Uri.parse('http://127.0.0.1:${server.port}/digest'),
        'test', HttpClientBasicCredentials('dart', 'password'));

    Future<void> makeRequest(Uri url) {
      return client
          .getUrl(url)
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        Expect.equals(HttpStatus.unauthorized, response.statusCode);
        return response.drain<void>();
      });
    }

    var futures = <Future<void>>[];
    for (int i = 0; i < 5; i++) {
      futures.add(
          makeRequest(Uri.parse('http://127.0.0.1:${server.port}/digest')));
    }
    Future.wait(futures).then((_) {
      server.shutdown();
      client.close();
    });
  });
}

void testCredentials(String? algorithm, String? qop) {
  Server.start(algorithm, qop).then((server) {
    HttpClient client = HttpClient();

    Future<void> makeRequest(Uri url) {
      return client
          .getUrl(url)
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        Expect.equals(HttpStatus.ok, response.statusCode);
        Expect.equals(1, response.headers['Authentication-Info']?.length);
        return response.fold(null, (x, y) {});
      });
    }

    client.addCredentials(Uri.parse('http://127.0.0.1:${server.port}/digest'),
        'test', HttpClientDigestCredentials('dart', 'password'));

    var futures = <Future<void>>[];
    for (int i = 0; i < 2; i++) {
      String uriBase = 'http://127.0.0.1:${server.port}/digest';
      futures.add(makeRequest(Uri.parse(uriBase)));
      futures.add(makeRequest(Uri.parse('$uriBase?querystring')));
      futures.add(makeRequest(Uri.parse('$uriBase?querystring#fragment')));
    }
    Future.wait(futures).then((_) {
      server.shutdown();
      client.close();
    });
  });
}

void testAuthenticateCallback(String? algorithm, String? qop) {
  Server.start(algorithm, qop).then((server) {
    HttpClient client = HttpClient();

    client.authenticate = (url, scheme, realm) {
      Expect.equals('Digest', scheme);
      Expect.equals('test', realm);
      var completer = Completer<bool>();
      Timer(const Duration(milliseconds: 10), () {
        client.addCredentials(
            Uri.parse('http://127.0.0.1:${server.port}/digest'),
            'test',
            HttpClientDigestCredentials('dart', 'password'));
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
        Expect.equals(1, response.headers['Authentication-Info']?.length);
        return response.fold(null, (x, y) {});
      });
    }

    var futures = <Future<void>>[];
    for (int i = 0; i < 5; i++) {
      futures.add(
          makeRequest(Uri.parse('http://127.0.0.1:${server.port}/digest')));
    }
    Future.wait(futures).then((_) {
      server.shutdown();
      client.close();
    });
  });
}

void testStaleNonce() {
  Server.start('MD5', 'auth', nonceStaleAfter: 2).then((server) {
    HttpClient client = HttpClient();

    Future<void> makeRequest(Uri url) {
      return client
          .getUrl(url)
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        Expect.equals(HttpStatus.ok, response.statusCode);
        Expect.equals(1, response.headers['Authentication-Info']?.length);
        return response.fold(null, (x, y) {});
      });
    }

    Uri uri = Uri.parse('http://127.0.0.1:${server.port}/digest');
    var credentials = HttpClientDigestCredentials('dart', 'password');
    client.addCredentials(uri, 'test', credentials);

    makeRequest(uri)
        .then((_) => makeRequest(uri))
        .then((_) => makeRequest(uri))
        .then((_) => makeRequest(uri))
        .then((_) {
      Expect.equals(2, server.unauthCount);
      Expect.equals(4, server.successCount);
      server.shutdown();
      client.close();
    });
  });
}

void testNextNonce() {
  Server.start('MD5', 'auth', nonceStaleAfter: 2, useNextNonce: true)
      .then((server) {
    HttpClient client = HttpClient();

    Future<void> makeRequest(Uri url) {
      return client
          .getUrl(url)
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        Expect.equals(HttpStatus.ok, response.statusCode);
        Expect.equals(1, response.headers['Authentication-Info']?.length);
        return response.fold(null, (x, y) {});
      });
    }

    Uri uri = Uri.parse('http://127.0.0.1:${server.port}/digest');
    var credentials = HttpClientDigestCredentials('dart', 'password');
    client.addCredentials(uri, 'test', credentials);

    makeRequest(uri)
        .then((_) => makeRequest(uri))
        .then((_) => makeRequest(uri))
        .then((_) => makeRequest(uri))
        .then((_) {
      Expect.equals(1, server.unauthCount);
      Expect.equals(4, server.successCount);
      server.shutdown();
      client.close();
    });
  });
}

// An Apache virtual directory configuration like this can be used for
// running the local server tests.
//
//  <Directory "/usr/local/prj/website/digest/">
//    AllowOverride None
//    Order deny,allow
//    Deny from all
//    Allow from 127.0.0.0/255.0.0.0 ::1/128
//    AuthType Digest
//    AuthName "test"
//    AuthDigestDomain /digest/
//    AuthDigestAlgorithm MD5
//    AuthDigestQop auth
//    AuthDigestNonceLifetime 10
//    AuthDigestProvider file
//    AuthUserFile /usr/local/prj/apache/passwd/digest-passwd
//    Require valid-user
//  </Directory>
//

void testLocalServerDigest() {
  int count = 0;
  HttpClient client = HttpClient();

  Future<void> makeRequest() {
    return client
        .getUrl(Uri.parse('http://127.0.0.1/digest/test'))
        .then((HttpClientRequest request) => request.close())
        .then((HttpClientResponse response) {
      count++;
      if (count % 100 == 0) {
        print(count);
      }
      Expect.equals(HttpStatus.ok, response.statusCode);
      return response.fold(null, (x, y) {});
    });
  }

  client.addCredentials(Uri.parse('http://127.0.0.1/digest'), 'test',
      HttpClientDigestCredentials('dart', 'password'));

  client.authenticate = (url, scheme, realm) {
    client.addCredentials(Uri.parse('http://127.0.0.1/digest'), 'test',
        HttpClientDigestCredentials('dart', 'password'));
    return Future.value(true);
  };

  void next() {
    makeRequest().then((_) => next());
  }

  next();
}

void main() {
  testNoCredentials(null, null);
  testNoCredentials('MD5', null);
  testNoCredentials('MD5', 'auth');
  testCredentials(null, null);
  testCredentials('MD5', null);
  testCredentials('MD5', 'auth');
  testCredentials('MD5', 'auth-int');
  testAuthenticateCallback(null, null);
  testAuthenticateCallback('MD5', null);
  testAuthenticateCallback('MD5', 'auth');
  testAuthenticateCallback('MD5', 'auth-int');
  testStaleNonce();
  testNextNonce();
  // These teste are not normally run. They can be used for locally
  // testing with another web server (e.g. Apache).
  //testLocalServerDigest();
}
