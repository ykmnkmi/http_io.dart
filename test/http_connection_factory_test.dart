// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:convert';
import 'dart:io';

import 'package:http_io/http_io.dart';

import 'expect.dart';
import 'http_proxy_test.dart' show setupProxyServer;
import 'test_utils.dart' show withTempDir;

Future<void> testDirectConnection() async {
  var server = await HttpServer.bind(InternetAddress.anyIPv6, 0);
  server.forEach((HttpRequest request) {
    request.response.write('Hello, world!');
    request.response.close();
  });
  var serverUri = Uri.http('127.0.0.1:${server.port}', '/');
  var client = HttpClient()
    ..connectionFactory = (uri, proxyHost, proxyPort) {
      Expect.isNull(proxyHost);
      Expect.isNull(proxyPort);
      Expect.equals(serverUri, uri);
      return Socket.startConnect(uri.host, uri.port);
    }
    ..findProxy = (uri) => 'DIRECT';
  var response = await client.getUrl(serverUri).then((request) {
    return request.close();
  });
  Expect.equals(200, response.statusCode);
  var responseText = await response
      .transform(utf8.decoder)
      .fold('', (String x, String y) => x + y);
  Expect.equals('Hello, world!', responseText);
  client.close();
  server.close();
}

Future<void> testConnectionViaProxy() async {
  var proxyServer = await setupProxyServer();
  var server = await HttpServer.bind(InternetAddress.anyIPv6, 0);
  server.forEach((HttpRequest request) {
    request.response.write('Hello via Proxy');
    request.response.close();
  });
  var serverUri = Uri.http('127.0.0.1:${server.port}', '/');
  var client = HttpClient()
    ..connectionFactory = (uri, proxyHost, proxyPort) {
      Expect.equals('localhost', proxyHost);
      Expect.equals(proxyServer.port, proxyPort);
      Expect.equals(serverUri, uri);
      return Socket.startConnect(proxyHost, proxyPort as int);
    }
    ..findProxy = (uri) => 'PROXY localhost:${proxyServer.port}';
  var response = await client.getUrl(serverUri).then((request) {
    return request.close();
  });
  Expect.equals(200, response.statusCode);
  var responseText = await response
      .transform(utf8.decoder)
      .fold('', (String x, String y) => x + y);
  Expect.equals('Hello via Proxy', responseText);
  client.close();
  server.close();
  proxyServer.shutdown();
}

Future<void> testDifferentAddressFamiliesAndProxySettings(String dir) async {
  // Test a custom connection factory for Unix domain sockets that also allows
  // regular INET/INET6 access with and without a proxy.
  var proxyServer = await setupProxyServer();
  var inet6Server = await HttpServer.bind(InternetAddress.anyIPv6, 0);
  inet6Server.forEach((HttpRequest request) {
    request.response.write('Hello via Proxy');
    request.response.close();
  });
  var inet6ServerUri = Uri.http('127.0.0.1:${inet6Server.port}', '/');
  var unixPath = '$dir/sock';
  var unixAddress = InternetAddress(unixPath, type: InternetAddressType.unix);
  var unixServer = await HttpServer.bind(unixAddress, 0);
  unixServer.forEach((HttpRequest request) {
    request.response.write('Hello via Unix');
    request.response.close();
  });
  var client = HttpClient()
    ..connectionFactory = (uri, proxyHost, proxyPort) {
      if (uri.scheme == 'unix') {
        assert(proxyHost == null);
        assert(proxyPort == null);
        var address = InternetAddress(unixPath, type: InternetAddressType.unix);
        return Socket.startConnect(address, 0);
      } else {
        if (proxyHost != null && proxyPort != null) {
          return Socket.startConnect(proxyHost, proxyPort);
        }
        return Socket.startConnect(uri.host, uri.port);
      }
    }
    ..findProxy = (uri) {
      if (uri.scheme == 'unix') {
        // Proxy settings are not meaningful for Unix domain sockets.
        return 'DIRECT';
      } else {
        return 'PROXY localhost:${proxyServer.port}';
      }
    };
  // Fetch a URL from the INET6 server and verify the results.
  var inet6Response = await client.getUrl(inet6ServerUri).then((request) {
    return request.close();
  });
  Expect.equals(200, inet6Response.statusCode);
  var inet6ResponseText = await inet6Response
      .transform(utf8.decoder)
      .fold('', (String x, String y) => x + y);
  Expect.equals('Hello via Proxy', inet6ResponseText);
  // Fetch a URL from the Unix server and verify the results.
  var unixResponse = await client
      .getUrl(Uri(
          scheme: 'unix',
          // Connection pooling is based on the host/port combination
          // so ensure that the host is unique for unique logical
          // endpoints. Also, the `host` property is converted to
          // lowercase so you cannot use it directly for file paths.
          host: 'dummy',
          path: '/'))
      .then((request) {
    return request.close();
  });
  Expect.equals(200, unixResponse.statusCode);
  var unixResponseText = await unixResponse
      .transform(utf8.decoder)
      .fold('', (String x, String y) => x + y);
  Expect.equals('Hello via Unix', unixResponseText);
  client.close();
  inet6Server.close();
  unixServer.close();
  proxyServer.shutdown();
}

void main() async {
  await testDirectConnection();
  await testConnectionViaProxy();
  if (Platform.isMacOS || Platform.isLinux || Platform.isAndroid) {
    await withTempDir('unix_socket_test', (Directory dir) async {
      await testDifferentAddressFamiliesAndProxySettings(dir.path);
    });
  }
}
