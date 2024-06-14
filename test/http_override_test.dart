// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import "package:http_io/http_io.dart";

import "expect.dart";

class MyHttpClient1 implements HttpClient {
  @override
  String? userAgent = "MyHttpClient1";

  MyHttpClient1(SecurityContext? context);

  @override
  Duration idleTimeout = Duration.zero;
  @override
  Duration? connectionTimeout;
  @override
  int? maxConnectionsPerHost;
  @override
  bool autoUncompress = true;
  bool enableTimelineLogging = false;

  @override
  Future<HttpClientRequest> open(
          String method, String host, int port, String path) =>
      throw "";
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => throw "";
  @override
  Future<HttpClientRequest> get(String host, int port, String path) => throw "";
  @override
  Future<HttpClientRequest> getUrl(Uri url) => throw "";
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      throw "";
  @override
  Future<HttpClientRequest> postUrl(Uri url) => throw "";
  @override
  Future<HttpClientRequest> put(String host, int port, String path) => throw "";
  @override
  Future<HttpClientRequest> putUrl(Uri url) => throw "";
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      throw "";
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => throw "";
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      throw "";
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => throw "";
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      throw "";
  @override
  Future<HttpClientRequest> headUrl(Uri url) => throw "";
  @override
  set authenticate(
      Future<bool> Function(Uri url, String scheme, String realm)? f) {}
  @override
  void addCredentials(
      Uri url, String realm, HttpClientCredentials credentials) {}
  @override
  set connectionFactory(
      Future<ConnectionTask<Socket>> Function(
              Uri url, String? proxyHost, int? proxyPort)?
          f) {}
  @override
  set findProxy(String Function(Uri url)? f) {}
  @override
  set authenticateProxy(
      Future<bool> Function(String host, int port, String scheme, String realm)?
          f) {}
  @override
  void addProxyCredentials(
      String host, int port, String realm, HttpClientCredentials credentials) {}
  @override
  set badCertificateCallback(
      bool Function(X509Certificate cert, String host, int port)? callback) {}
  @override
  set keyLog(Function(String line)? callback) {}
  @override
  void close({bool force = false}) {}
}

class MyHttpClient2 implements HttpClient {
  @override
  String? userAgent = "MyHttpClient2";

  MyHttpClient2(SecurityContext? context);

  @override
  Duration idleTimeout = Duration.zero;
  @override
  Duration? connectionTimeout;
  @override
  int? maxConnectionsPerHost;
  @override
  bool autoUncompress = true;
  bool enableTimelineLogging = false;

  @override
  Future<HttpClientRequest> open(
          String method, String host, int port, String path) =>
      throw "";
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => throw "";
  @override
  Future<HttpClientRequest> get(String host, int port, String path) => throw "";
  @override
  Future<HttpClientRequest> getUrl(Uri url) => throw "";
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      throw "";
  @override
  Future<HttpClientRequest> postUrl(Uri url) => throw "";
  @override
  Future<HttpClientRequest> put(String host, int port, String path) => throw "";
  @override
  Future<HttpClientRequest> putUrl(Uri url) => throw "";
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      throw "";
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => throw "";
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      throw "";
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => throw "";
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      throw "";
  @override
  Future<HttpClientRequest> headUrl(Uri url) => throw "";
  @override
  set authenticate(
      Future<bool> Function(Uri url, String scheme, String realm)? f) {}
  @override
  void addCredentials(
      Uri url, String realm, HttpClientCredentials credentials) {}
  @override
  set connectionFactory(
      Future<ConnectionTask<Socket>> Function(
              Uri url, String? proxyHost, int? proxyPort)?
          f) {}
  @override
  set findProxy(String Function(Uri url)? f) {}
  @override
  set authenticateProxy(
      Future<bool> Function(String host, int port, String scheme, String realm)?
          f) {}
  @override
  void addProxyCredentials(
      String host, int port, String realm, HttpClientCredentials credentials) {}
  @override
  set badCertificateCallback(
      bool Function(X509Certificate cert, String host, int port)? callback) {}
  @override
  set keyLog(Function(String line)? callback) {}
  @override
  void close({bool force = false}) {}
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return MyHttpClient1(context);
  }
}

HttpClient myCreateHttp1Client(SecurityContext? context) {
  return MyHttpClient1(context);
}

HttpClient myCreateHttp2Client(SecurityContext? context) {
  return MyHttpClient2(context);
}

String myFindProxyFromEnvironment(Uri url, Map<String, String>? environment) {
  return "proxy";
}

withHttpOverridesTest() {
  HttpOverrides.runZoned(() {
    var httpClient = HttpClient();
    Expect.isNotNull(httpClient);
    Expect.isTrue(httpClient is MyHttpClient1);
    Expect.equals((MyHttpClient1(null)).userAgent, httpClient.userAgent);
  }, createHttpClient: myCreateHttp1Client);
  var httpClient = HttpClient();
  Expect.isTrue(httpClient is HttpClient);
  Expect.isTrue(httpClient is! MyHttpClient1);
}

nestedWithHttpOverridesTest() {
  HttpOverrides.runZoned(() {
    var httpClient = HttpClient();
    Expect.isNotNull(httpClient);
    Expect.isTrue(httpClient is MyHttpClient1);
    Expect.equals((MyHttpClient1(null)).userAgent, httpClient.userAgent);
    HttpOverrides.runZoned(() {
      var httpClient = HttpClient();
      Expect.isNotNull(httpClient);
      Expect.isTrue(httpClient is MyHttpClient2);
      Expect.equals((MyHttpClient2(null)).userAgent, httpClient.userAgent);
    }, createHttpClient: myCreateHttp2Client);
    httpClient = HttpClient();
    Expect.isNotNull(httpClient);
    Expect.isTrue(httpClient is MyHttpClient1);
    Expect.equals((MyHttpClient1(null)).userAgent, httpClient.userAgent);
  }, createHttpClient: myCreateHttp1Client);
  var httpClient = HttpClient();
  Expect.isTrue(httpClient is HttpClient);
  Expect.isTrue(httpClient is! MyHttpClient1);
  Expect.isTrue(httpClient is! MyHttpClient2);
}

nestedDifferentOverridesTest() {
  HttpOverrides.runZoned(() {
    var httpClient = HttpClient();
    Expect.isNotNull(httpClient);
    Expect.isTrue(httpClient is MyHttpClient1);
    Expect.equals((MyHttpClient1(null)).userAgent, httpClient.userAgent);
    HttpOverrides.runZoned(() {
      var httpClient = HttpClient();
      Expect.isNotNull(httpClient);
      Expect.isTrue(httpClient is MyHttpClient1);
      Expect.equals((MyHttpClient1(null)).userAgent, httpClient.userAgent);
      Expect.equals(myFindProxyFromEnvironment(Uri(), null),
          HttpClient.findProxyFromEnvironment(Uri()));
    }, findProxyFromEnvironment: myFindProxyFromEnvironment);
    httpClient = HttpClient();
    Expect.isNotNull(httpClient);
    Expect.isTrue(httpClient is MyHttpClient1);
    Expect.equals((MyHttpClient1(null)).userAgent, httpClient.userAgent);
  }, createHttpClient: myCreateHttp1Client);
  var httpClient = HttpClient();
  Expect.isTrue(httpClient is HttpClient);
  Expect.isTrue(httpClient is! MyHttpClient1);
  Expect.isTrue(httpClient is! MyHttpClient2);
}

zonedWithHttpOverridesTest() {
  HttpOverrides.runWithHttpOverrides(() {
    var httpClient = HttpClient();
    Expect.isNotNull(httpClient);
    Expect.isTrue(httpClient is MyHttpClient1);
    Expect.equals((MyHttpClient1(null)).userAgent, httpClient.userAgent);
  }, MyHttpOverrides());
}

globalHttpOverridesTest() {
  HttpOverrides.global = MyHttpOverrides();
  var httpClient = HttpClient();
  Expect.isNotNull(httpClient);
  Expect.isTrue(httpClient is MyHttpClient1);
  Expect.equals((MyHttpClient1(null)).userAgent, httpClient.userAgent);
  HttpOverrides.global = null;
  httpClient = HttpClient();
  Expect.isTrue(httpClient is HttpClient);
  Expect.isTrue(httpClient is! MyHttpClient1);
}

globalHttpOverridesZoneTest() {
  HttpOverrides.global = MyHttpOverrides();
  runZoned(() {
    runZoned(() {
      var httpClient = HttpClient();
      Expect.isNotNull(httpClient);
      Expect.isTrue(httpClient is MyHttpClient1);
      Expect.equals((MyHttpClient1(null)).userAgent, httpClient.userAgent);
    });
  });
  HttpOverrides.global = null;
  var httpClient = HttpClient();
  Expect.isTrue(httpClient is HttpClient);
  Expect.isTrue(httpClient is! MyHttpClient1);
}

main() {
  withHttpOverridesTest();
  nestedWithHttpOverridesTest();
  nestedDifferentOverridesTest();
  zonedWithHttpOverridesTest();
  globalHttpOverridesTest();
  globalHttpOverridesZoneTest();
}
