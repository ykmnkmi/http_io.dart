// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'http.dart';

/// Stubs and class aliases which make private names available for use in
/// tests.  These should never be exported publically.
///
/// To export a class to be used as a type, for its constructors, or for public
/// static members, define a typedef alias for it using the naming scheme
/// `TestingClass$<classname>`
///
/// To export private instance or static members from a class, define an
/// extension using the naming scheme `Testing$<classname>` and
/// add publicly named static or instance members to the stub class which
/// redirect to the corresponding privately named member, using the private name
/// prefixed with `test$`.  Private static members can then be accessed in tests
/// as:
/// ```markdown
///    `Testing$<classname>.test$_privateName`
/// ```
/// which redirects to:
/// ```markdown
///    `<classname>._privateName`
/// ```
///
/// Private instance members can be accessed in tests as:
/// ```markdown
///    `instance.test$_privateName`
/// ```
/// which redirects to:
/// ```markdown
///    `instance._privateName`
/// ```

typedef TestingClass$Cookie = _Cookie;
typedef TestingClass$HttpHeaders = _HttpHeaders;
typedef TestingClass$HttpParser = _HttpParser;
typedef TestingClass$SHA1 = _SHA1;
typedef TestingClass$WebSocketProtocolTransformer
    = _WebSocketProtocolTransformer;
typedef TestingClass$WebSocketImpl = _WebSocketImpl;

extension Testing$HttpDate on HttpDate {
  static DateTime test$_parseCookieDate(String date) =>
      HttpDate._parseCookieDate(date);
}

extension Testing$HttpHeaders on _HttpHeaders {
  void test$_build(BytesBuilder builder) => _build(builder);
  List<Cookie> test$_parseCookies() => _parseCookies();
}

extension Testing$WebSocketProtocolTransformer
    on _WebSocketProtocolTransformer {
  int get test$_state => _state;
}

extension Testing$WebSocketImpl on _WebSocketImpl {
  static Future<WebSocket> connect(String url, Iterable<String>? protocols,
          Map<String, dynamic>? headers,
          {CompressionOptions compression =
              CompressionOptions.compressionDefault,
          HttpClient? customClient}) =>
      _WebSocketImpl.connect(url, protocols, headers,
          compression: compression, customClient: customClient);
  Timer? get test$_pingTimer => _pingTimer;
}
