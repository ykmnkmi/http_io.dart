// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: library_private_types_in_public_api

part of 'http.dart';

abstract final class HttpProfiler {
  static final Map<String, _HttpProfileData> _profile =
      <String, _HttpProfileData>{};

  static _HttpProfileData? startRequest(
    String method,
    Uri uri, {
    _HttpProfileData? parentRequest,
  }) {
    if (const bool.fromEnvironment('dart.vm.product')) {
      return null;
    }

    _HttpProfileData data = _HttpProfileData(
      method,
      uri,
      parentRequest?._timeline,
    );

    _profile[data.id] = data;
    return data;
  }

  static _HttpProfileData? getHttpProfileRequest(String id) {
    return _profile[id];
  }

  static void clear() {
    _profile.clear();
  }

  /// Returns a list of Maps, where each map conforms to the @HttpProfileRequest
  /// type defined in the dart:io service extension spec.
  static List<Map<String, Object?>> serializeHttpProfileRequests(
    int? updatedSince,
  ) {
    return _profile.values
        .where((e) => updatedSince == null || e.lastUpdateTime >= updatedSince)
        .map<Map<String, Object?>>((e) => e.toJson(ref: true))
        .toList();
  }
}

final class _HttpProfileEvent {
  _HttpProfileEvent(this.name, this.arguments);

  final int timestamp = DateTime.now().microsecondsSinceEpoch;
  final String name;
  final Map<Object?, Object?>? arguments;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'timestamp': timestamp,
      'event': name,
      if (arguments != null) 'arguments': arguments,
    };
  }
}

final class _HttpProfileData {
  _HttpProfileData(String method, this.uri, TimelineTask? parent)
    : method = method.toUpperCase(),
      _timeline = TimelineTask(filterKey: 'HTTP/client', parent: parent) {
    // Grab the ID from the timeline event so HTTP profile IDs can be matched
    // to the timeline.
    id = _timeline.pass().toString();
    requestInProgress = true;
    requestStartTimestamp = DateTime.now().microsecondsSinceEpoch;

    _timeline.start(
      'HTTP CLIENT $method',
      arguments: <Object?, Object?>{
        'method': method.toUpperCase(),
        'uri': uri.toString(),
      },
    );

    _updated();
  }

  void requestEvent(String name, {Map<Object?, Object?>? arguments}) {
    _timeline.instant(name, arguments: arguments);
    requestEvents.add(_HttpProfileEvent(name, arguments));
    _updated();
  }

  void proxyEvent(_Proxy proxy) {
    proxyDetails = <String, Object?>{
      if (proxy.host != null) 'host': proxy.host,
      if (proxy.port != null) 'port': proxy.port,
      if (proxy.username != null) 'username': proxy.username,
    };

    _timeline.instant(
      'Establishing proxy tunnel',
      arguments: <Object?, Object?>{'proxyDetails': proxyDetails},
    );

    _updated();
  }

  void appendRequestData(Uint8List data) {
    requestBody.addAll(data);
    _updated();
  }

  Map<String, List<String>> formatHeaders(HttpHeaders headers) {
    Map<String, List<String>> newHeaders = <String, List<String>>{};

    headers.forEach((name, values) {
      newHeaders[name] = values;
    });

    return newHeaders;
  }

  Map<String, Object>? formatConnectionInfo(
    HttpConnectionInfo? connectionInfo,
  ) {
    return connectionInfo == null
        ? null
        : {
          'localPort': connectionInfo.localPort,
          'remoteAddress': connectionInfo.remoteAddress.address,
          'remotePort': connectionInfo.remotePort,
        };
  }

  void finishRequest({required HttpClientRequest request}) {
    // TODO(bkonyi): include encoding?
    requestInProgress = false;
    requestEndTimestamp = DateTime.now().microsecondsSinceEpoch;

    requestDetails = <String, Object?>{
      // TODO(bkonyi): consider exposing certificate information?
      // 'certificate': response.certificate,
      'headers': formatHeaders(request.headers),
      'connectionInfo': formatConnectionInfo(request.connectionInfo),
      'contentLength': request.contentLength,
      'cookies': [for (final cookie in request.cookies) cookie.toString()],
      'followRedirects': request.followRedirects,
      'maxRedirects': request.maxRedirects,
      'method': request.method,
      'persistentConnection': request.persistentConnection,
      'uri': request.uri.toString(),
    };

    _timeline.finish(arguments: requestDetails);
    _updated();
  }

  void startResponse({required HttpClientResponse response}) {
    List<Map<String, Object?>> formatRedirectInfo() {
      List<Map<String, Object?>> redirects = <Map<String, Object?>>[];

      for (RedirectInfo redirect in response.redirects) {
        redirects.add(<String, Object?>{
          'location': redirect.location.toString(),
          'method': redirect.method,
          'statusCode': redirect.statusCode,
        });
      }

      return redirects;
    }

    responseDetails = <String, Object?>{
      'headers': formatHeaders(response.headers),
      'compressionState': response.compressionState.toString(),
      'connectionInfo': formatConnectionInfo(response.connectionInfo),
      'contentLength': response.contentLength,
      'cookies': <String>[
        for (final cookie in response.cookies) cookie.toString(),
      ],
      'isRedirect': response.isRedirect,
      'persistentConnection': response.persistentConnection,
      'reasonPhrase': response.reasonPhrase,
      'redirects': formatRedirectInfo(),
      'statusCode': response.statusCode,
    };

    assert(!requestInProgress);
    responseInProgress = true;

    _responseTimeline = TimelineTask(
      parent: _timeline,
      filterKey: 'HTTP/client',
    );

    responseStartTimestamp = DateTime.now().microsecondsSinceEpoch;

    _responseTimeline.start(
      'HTTP CLIENT response of $method',
      arguments: <Object?, Object?>{
        'requestUri': uri.toString(),
        ...responseDetails!,
      },
    );

    _updated();
  }

  void finishRequestWithError(String error) {
    requestInProgress = false;
    requestEndTimestamp = DateTime.now().microsecondsSinceEpoch;
    requestError = error;
    _timeline.finish(arguments: <Object?, Object?>{'error': error});
    _updated();
  }

  void finishResponse() {
    // Guard against the response being completed more than once or being
    // completed before the response actually finished starting.
    if (responseInProgress != true) {
      return;
    }

    responseInProgress = false;
    responseEndTimestamp = DateTime.now().microsecondsSinceEpoch;
    requestEvent('Content Download');
    _responseTimeline.finish();
    _updated();
  }

  void finishResponseWithError(String error) {
    // Return if finishResponseWithError has already been called. Can happen if
    // the response stream is listened to with `cancelOnError: false`.
    if (!responseInProgress!) {
      return;
    }

    responseInProgress = false;
    responseEndTimestamp = DateTime.now().microsecondsSinceEpoch;
    responseError = error;
    _responseTimeline.finish(arguments: <Object?, Object?>{'error': error});
    _updated();
  }

  void appendResponseData(Uint8List data) {
    responseBody.addAll(data);
    _updated();
  }

  Map<String, Object?> toJson({required bool ref}) {
    return <String, Object?>{
      'type': '${ref ? '@' : ''}HttpProfileRequest',
      'id': id,
      'isolateId': isolateId,
      'method': method,
      'uri': uri.toString(),
      'events': <Map<String, Object?>>[
        for (_HttpProfileEvent event in requestEvents) event.toJson(),
      ],
      'startTime': requestStartTimestamp,
      if (!requestInProgress) 'endTime': requestEndTimestamp,
      if (!requestInProgress)
        'request': <String, Object?>{
          if (proxyDetails != null) 'proxyDetails': proxyDetails!,
          if (requestDetails != null) ...requestDetails!,
          if (requestError != null) 'error': requestError,
        },
      if (responseInProgress != null)
        'response': <String, Object?>{
          'startTime': responseStartTimestamp,
          ...responseDetails!,
          if (!responseInProgress!) 'endTime': responseEndTimestamp,
          if (responseError != null) 'error': responseError,
        },
      if (!ref) ...<String, Object?>{
        if (!requestInProgress) 'requestBody': requestBody,
        if (responseInProgress != null) 'responseBody': responseBody,
      },
    };
  }

  void _updated() {
    _lastUpdateTime = DateTime.now().microsecondsSinceEpoch;
  }

  static final String isolateId = Service.getIsolateId(Isolate.current)!;

  bool requestInProgress = true;
  bool? responseInProgress;

  late final String id;
  final String method;
  final Uri uri;

  late final int requestStartTimestamp;
  late final int requestEndTimestamp;
  Map<String, Object?>? requestDetails;
  Map<String, Object?>? proxyDetails;
  final List<int> requestBody = <int>[];
  String? requestError;
  final List<_HttpProfileEvent> requestEvents = <_HttpProfileEvent>[];

  late final int responseStartTimestamp;
  late final int responseEndTimestamp;
  Map<String, Object?>? responseDetails;
  final List<int> responseBody = <int>[];
  String? responseError;

  int get lastUpdateTime {
    return _lastUpdateTime;
  }

  int _lastUpdateTime = 0;

  final TimelineTask _timeline;
  late TimelineTask _responseTimeline;
}

int _nextServiceId = 1;

// TODO(ajohnsen): Use other way of getting a unique id.
mixin _ServiceObject {
  int __serviceId = 0;

  int get _serviceId {
    if (__serviceId == 0) {
      __serviceId = _nextServiceId++;
    }

    return __serviceId;
  }
}

final class _CopyingBytesBuilder implements BytesBuilder {
  // Start with 1024 bytes.
  static const int _initSize = 1024;

  static final Uint8List _emptyList = Uint8List(0);

  _CopyingBytesBuilder([int initialCapacity = 0])
    : _buffer =
          (initialCapacity <= 0)
              ? _emptyList
              : Uint8List(_pow2roundup(initialCapacity));

  int _length = 0;
  Uint8List _buffer;

  @override
  void add(List<int> bytes) {
    int bytesLength = bytes.length;

    if (bytesLength == 0) {
      return;
    }

    int required = _length + bytesLength;

    if (_buffer.length < required) {
      _grow(required);
    }

    assert(_buffer.length >= required);

    if (bytes is Uint8List) {
      _buffer.setRange(_length, required, bytes);
    } else {
      for (int i = 0; i < bytesLength; i++) {
        _buffer[_length + i] = bytes[i];
      }
    }

    _length = required;
  }

  @override
  void addByte(int byte) {
    if (_buffer.length == _length) {
      // The grow algorithm always at least doubles.
      // If we added one to _length it would quadruple unnecessarily.
      _grow(_length);
    }

    assert(_buffer.length > _length);
    _buffer[_length] = byte;
    _length++;
  }

  void _grow(int required) {
    // We will create a list in the range of 2-4 times larger than
    // required.
    int newSize = required * 2;

    if (newSize < _initSize) {
      newSize = _initSize;
    } else {
      newSize = _pow2roundup(newSize);
    }

    Uint8List newBuffer = Uint8List(newSize);
    newBuffer.setRange(0, _buffer.length, _buffer);
    _buffer = newBuffer;
  }

  @override
  Uint8List takeBytes() {
    if (_length == 0) {
      return _emptyList;
    }

    Uint8List buffer = Uint8List.view(
      _buffer.buffer,
      _buffer.offsetInBytes,
      _length,
    );

    clear();
    return buffer;
  }

  @override
  Uint8List toBytes() {
    if (_length == 0) {
      return _emptyList;
    }

    return Uint8List.fromList(
      Uint8List.view(_buffer.buffer, _buffer.offsetInBytes, _length),
    );
  }

  @override
  int get length {
    return _length;
  }

  @override
  bool get isEmpty {
    return _length == 0;
  }

  @override
  bool get isNotEmpty {
    return _length != 0;
  }

  @override
  void clear() {
    _length = 0;
    _buffer = _emptyList;
  }

  static int _pow2roundup(int x) {
    assert(x > 0);
    --x;
    x |= x >> 1;
    x |= x >> 2;
    x |= x >> 4;
    x |= x >> 8;
    x |= x >> 16;
    return x + 1;
  }
}

const int _outgoingBufferSize = 8 * 1024;

typedef _BytesConsumer = void Function(List<int> bytes);

final class _HttpIncoming extends Stream<Uint8List> {
  _HttpIncoming(this.headers, this._transferLength, this._stream);

  final int _transferLength;
  final Completer<bool> _dataCompleter = Completer<bool>();
  final Stream<Uint8List> _stream;

  bool fullBodyRead = false;

  // Common properties.
  final _HttpHeaders headers;
  bool upgraded = false;

  // ClientResponse properties.
  int? statusCode;
  String? reasonPhrase;

  // Request properties.
  String? method;
  Uri? uri;

  bool hasSubscriber = false;

  // The transfer length if the length of the message body as it
  // appears in the message (RFC 2616 section 4.4). This can be -1 if
  // the length of the massage body is not known due to transfer
  // codings.
  int get transferLength {
    return _transferLength;
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    hasSubscriber = true;
    return _stream
        .handleError((Object error) {
          throw HttpException((error as HttpException).message, uri: uri);
        }, test: (Object? error) => error is HttpException)
        .listen(
          onData,
          onError: onError,
          onDone: onDone,
          cancelOnError: cancelOnError,
        );
  }

  // Is completed once all data have been received.
  Future<bool> get dataDone {
    return _dataCompleter.future;
  }

  void close(bool closing) {
    fullBodyRead = true;
    hasSubscriber = true;
    _dataCompleter.complete(closing);
  }
}

abstract base class _HttpInboundMessageListInt extends Stream<List<int>> {
  _HttpInboundMessageListInt(this._incoming);

  final _HttpIncoming _incoming;
  List<Cookie>? _cookies;

  List<Cookie> get cookies {
    return _cookies ??= headers._parseCookies();
  }

  _HttpHeaders get headers {
    return _incoming.headers;
  }

  String get protocolVersion {
    return headers.protocolVersion;
  }

  int get contentLength {
    return headers.contentLength;
  }

  bool get persistentConnection {
    return headers.persistentConnection;
  }
}

abstract base class _HttpInboundMessage extends Stream<Uint8List> {
  _HttpInboundMessage(this._incoming);

  final _HttpIncoming _incoming;
  List<Cookie>? _cookies;

  List<Cookie> get cookies => _cookies ??= headers._parseCookies();

  _HttpHeaders get headers => _incoming.headers;
  String get protocolVersion => headers.protocolVersion;
  int get contentLength => headers.contentLength;
  bool get persistentConnection => headers.persistentConnection;
}

final class _HttpRequest extends _HttpInboundMessage implements HttpRequest {
  _HttpRequest(
    this.response,
    _HttpIncoming _incoming,
    this._httpServer,
    this._httpConnection,
  ) : super(_incoming) {
    if (headers.protocolVersion == '1.1') {
      response.headers
        ..chunkedTransferEncoding = true
        ..persistentConnection = headers.persistentConnection;
    }

    if (_httpServer._sessionManagerInstance != null) {
      // Map to session if exists.
      var sessionIds = cookies
          .where((cookie) => cookie.name.toUpperCase() == _dartSessionId)
          .map<String>((cookie) => cookie.value);
      for (var sessionId in sessionIds) {
        var session = _httpServer._sessionManager.getSession(sessionId);
        _session = session;
        if (session != null) {
          session._markSeen();
          break;
        }
      }
    }
  }

  @override
  final HttpResponse response;

  final _HttpServer _httpServer;

  final _HttpConnection _httpConnection;

  _HttpSession? _session;

  Uri? _requestedUri;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _incoming.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Uri get uri {
    return _incoming.uri!;
  }

  @override
  Uri get requestedUri {
    Uri? requestedUri = _requestedUri;

    if (requestedUri != null) {
      return requestedUri;
    }

    // `uri` can be an absoluteURI or an abs_path (RFC 2616 section 5.1.2).
    // If `uri` is already absolute then use it as-is. Otherwise construct an
    // absolute URI using `uri` and header information.

    // RFC 3986 section 4.3 says that an absolute URI must have a scheme and
    // cannot have a fragment. But any URI with a scheme is sufficient for the
    // purpose of providing the `requestedUri`.
    if (uri.hasScheme) {
      return _requestedUri = uri;
    }

    List<String>? proto = headers['x-forwarded-proto'];

    String scheme =
        proto != null
            ? proto.first
            : _httpConnection._socket is SecureSocket
            ? 'https'
            : 'http';

    List<String>? hostList = headers['x-forwarded-host'];
    String host;

    if (hostList != null) {
      host = hostList.first;
    } else {
      hostList = headers[HttpHeaders.hostHeader];

      if (hostList != null) {
        host = hostList.first;
      } else {
        host = '${_httpServer.address.host}:${_httpServer.port}';
      }
    }

    return _requestedUri = Uri.parse('$scheme://$host$uri');
  }

  @override
  String get method {
    return _incoming.method!;
  }

  @override
  HttpSession get session {
    _HttpSession? session = _session;

    if (session != null && !session._destroyed) {
      return session;
    }

    // Create session, store it in connection, and return.
    return _session = _httpServer._sessionManager.createSession();
  }

  @override
  HttpConnectionInfo? get connectionInfo {
    return _httpConnection.connectionInfo;
  }

  @override
  X509Certificate? get certificate {
    Socket socket = _httpConnection._socket;

    if (socket is SecureSocket) {
      return socket.peerCertificate;
    }

    return null;
  }
}

final class _HttpClientResponse extends _HttpInboundMessageListInt
    implements HttpClientResponse {
  _HttpClientResponse(
    _HttpIncoming incoming,
    this._httpRequest,
    this._httpClient,
    this._profileData,
  ) : compressionState = _getCompressionState(_httpClient, incoming.headers),
      super(incoming) {
    // Set uri for potential exceptions.
    incoming.uri = _httpRequest.uri;
    // Ensure the response profile is completed, even if the response stream is
    // never actually listened to.
    incoming.dataDone.then<void>((_) => _profileData?.finishResponse());
  }

  @override
  List<RedirectInfo> get redirects {
    return _httpRequest._responseRedirects;
  }

  // The HttpClient this response belongs to.
  final _HttpClient _httpClient;

  // The HttpClientRequest of this response.
  final _HttpClientRequest _httpRequest;

  // The compression state of this response.
  @override
  final HttpClientResponseCompressionState compressionState;

  final _HttpProfileData? _profileData;

  static HttpClientResponseCompressionState _getCompressionState(
    _HttpClient httpClient,
    _HttpHeaders headers,
  ) {
    if (headers.value(HttpHeaders.contentEncodingHeader) == 'gzip') {
      return httpClient.autoUncompress
          ? HttpClientResponseCompressionState.decompressed
          : HttpClientResponseCompressionState.compressed;
    }

    return HttpClientResponseCompressionState.notCompressed;
  }

  @override
  int get statusCode {
    return _incoming.statusCode!;
  }

  @override
  String get reasonPhrase {
    return _incoming.reasonPhrase!;
  }

  @override
  X509Certificate? get certificate {
    Socket socket = _httpRequest._httpClientConnection._socket;

    if (socket is SecureSocket) {
      return socket.peerCertificate;
    }

    return null;
  }

  @override
  List<Cookie> get cookies {
    List<Cookie>? cookies = _cookies;

    if (cookies != null) {
      return cookies;
    }

    cookies = <Cookie>[];

    List<String>? values = headers[HttpHeaders.setCookieHeader];

    if (values != null) {
      for (String value in values) {
        cookies.add(Cookie.fromSetCookieValue(value));
      }
    }

    _cookies = cookies;
    return cookies;
  }

  @override
  bool get isRedirect {
    if (_httpRequest.method == 'GET' || _httpRequest.method == 'HEAD') {
      return statusCode == HttpStatus.movedPermanently ||
          statusCode == HttpStatus.permanentRedirect ||
          statusCode == HttpStatus.found ||
          statusCode == HttpStatus.seeOther ||
          statusCode == HttpStatus.temporaryRedirect;
    }

    if (_httpRequest.method == 'POST') {
      return statusCode == HttpStatus.seeOther;
    }

    return false;
  }

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) {
    if (method == null) {
      // Set method as defined by RFC 2616 section 10.3.4.
      if (statusCode == HttpStatus.seeOther && _httpRequest.method == 'POST') {
        method = 'GET';
      } else {
        method = _httpRequest.method;
      }
    }

    if (url == null) {
      String? location = headers.value(HttpHeaders.locationHeader);

      if (location == null) {
        throw RedirectException(
          'Server response has no Location header for redirect',
          redirects,
        );
      }

      url = Uri.parse(location);
    }

    if (followLoops != true) {
      for (var redirect in redirects) {
        if (redirect.location == url) {
          return Future<HttpClientResponse>.error(
            RedirectException('Redirect loop detected', redirects),
          );
        }
      }
    }

    return _httpClient
        ._openUrlFromRequest(method, url, _httpRequest, isRedirect: true)
        .then<HttpClientResponse>((request) {
          request._responseRedirects
            ..addAll(redirects)
            ..add(_RedirectInfo(statusCode, method!, url!));

          return request.close();
        });
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_incoming.upgraded) {
      _profileData?.finishResponseWithError('Connection was upgraded');

      // If upgraded, the connection is already 'removed' form the client.
      // Since listening to upgraded data is 'bogus', simply close and
      // return empty stream subscription.
      _httpRequest._httpClientConnection.destroy();
      return Stream<Uint8List>.empty().listen(null, onDone: onDone);
    }

    Stream<Uint8List> stream = _incoming;

    if (compressionState == HttpClientResponseCompressionState.decompressed) {
      stream = stream
          .cast<List<int>>()
          .transform(gzip.decoder)
          .transform(const _ToUint8List());
    }

    if (_profileData != null) {
      // If _timeline is not set up, don't add unnecessary map() to the stream.
      stream = stream.map<Uint8List>((data) {
        _profileData.appendResponseData(data);
        return data;
      });
    }

    return stream.listen(
      onData,
      onError: (Object error, StackTrace stackTrace) {
        _profileData?.finishResponseWithError(error.toString());

        if (onError == null) {
          return;
        }

        if (onError is void Function(Object, StackTrace)) {
          onError(error, stackTrace);
        } else {
          (onError as void Function(Object))(error);
        }
      },
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<Socket> detachSocket() {
    _profileData?.finishResponseWithError('Socket has been detached');
    _httpClient._connectionClosed(_httpRequest._httpClientConnection);
    return _httpRequest._httpClientConnection.detachSocket();
  }

  @override
  HttpConnectionInfo? get connectionInfo {
    return _httpRequest.connectionInfo;
  }

  bool get _shouldAuthenticateProxy {
    // Only try to authenticate if there is a challenge in the response.
    List<String>? challenge = headers[HttpHeaders.proxyAuthenticateHeader];
    return statusCode == HttpStatus.proxyAuthenticationRequired &&
        challenge != null &&
        challenge.length == 1;
  }

  bool get _shouldAuthenticate {
    // Only try to authenticate if there is a challenge in the response.
    List<String>? challenge = headers[HttpHeaders.wwwAuthenticateHeader];
    return statusCode == HttpStatus.unauthorized &&
        challenge != null &&
        challenge.length == 1;
  }

  Future<HttpClientResponse> _authenticate(bool proxyAuth) {
    _httpRequest._profileData?.requestEvent('Authentication');

    Future<HttpClientResponse> retry() {
      _httpRequest._profileData?.requestEvent('Retrying');
      // Drain body and retry.
      return drain<void>().then<HttpClientResponse>((_) {
        return _httpClient
            ._openUrlFromRequest(
              _httpRequest.method,
              _httpRequest.uri,
              _httpRequest,
              isRedirect: false,
            )
            .then((request) {
              return request.close();
            });
      });
    }

    List<String>? authChallenge() {
      return proxyAuth
          ? headers[HttpHeaders.proxyAuthenticateHeader]
          : headers[HttpHeaders.wwwAuthenticateHeader];
    }

    _Credentials? findCredentials(_AuthenticationScheme scheme) {
      return proxyAuth
          ? _httpClient._findProxyCredentials(_httpRequest._proxy, scheme)
          : _httpClient._findCredentials(_httpRequest.uri, scheme);
    }

    void removeCredentials(_Credentials cr) {
      if (proxyAuth) {
        _httpClient._removeProxyCredentials(cr);
      } else {
        _httpClient._removeCredentials(cr);
      }
    }

    Future<bool> requestAuthentication(
      _AuthenticationScheme scheme,
      String? realm,
    ) {
      if (proxyAuth) {
        Future<bool> Function(String, int, String, String?)? authenticateProxy =
            _httpClient._authenticateProxy;

        if (authenticateProxy == null) {
          return Future<bool>.value(false);
        }

        _Proxy proxy = _httpRequest._proxy;

        if (!proxy.isDirect) {
          return authenticateProxy(
            proxy.host!,
            proxy.port!,
            scheme.toString(),
            realm,
          );
        }
      }

      Future<bool> Function(Uri, String, String?)? authenticate =
          _httpClient._authenticate;

      if (authenticate == null) {
        return Future<bool>.value(false);
      }

      return authenticate(_httpRequest.uri, scheme.toString(), realm);
    }

    List<String> challenge = authChallenge()!;
    assert(challenge.length == 1);

    _HeaderValue header;

    try {
      header = _HeaderValue.parse(challenge[0], parameterSeparator: ',');
    } on HttpException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        HttpException(
          'The authentication challenge sent by the server is '
          'not correctly formatted.',
        ),
        stackTrace,
      );
    }

    _AuthenticationScheme scheme = _AuthenticationScheme.fromString(
      header.value,
    );

    String? realm = header.parameters['realm'];

    // See if any matching credentials are available.
    _Credentials? credentials = findCredentials(scheme);

    if (credentials != null) {
      // For basic authentication don't retry already used credentials
      // as they must have already been added to the request causing
      // this authenticate response.
      if (credentials.scheme == _AuthenticationScheme.basic &&
          !credentials.used) {
        // Credentials were found, prepare for retrying the request.
        return retry();
      }

      // Digest authentication only supports the MD5 algorithm.
      if (credentials.scheme == _AuthenticationScheme.digest) {
        String? algorithm = header.parameters['algorithm'];

        if (algorithm == null || algorithm.toLowerCase() == 'md5') {
          String? nonce = credentials.nonce;

          if (nonce == null || nonce == header.parameters['nonce']) {
            // If the nonce is not set then this is the first authenticate
            // response for these credentials. Set up authentication state.
            if (nonce == null) {
              credentials
                ..nonce = header.parameters['nonce']
                ..algorithm = 'MD5'
                ..qop = header.parameters['qop']
                ..nonceCount = 0;
            }

            // Credentials were found, prepare for retrying the request.
            return retry();
          }

          String? staleHeader = header.parameters['stale'];

          if (staleHeader != null && staleHeader.toLowerCase() == 'true') {
            // If stale is true retry with new nonce.
            credentials.nonce = header.parameters['nonce'];

            // Credentials were found, prepare for retrying the request.
            return retry();
          }
        }
      }
    }

    // Ask for more credentials if none found or the one found has
    // already been used. If it has already been used it must now be
    // invalid and is removed.
    if (credentials != null) {
      removeCredentials(credentials);
      credentials = null;
    }

    return requestAuthentication(scheme, realm).then<HttpClientResponse>((
      credsAvailable,
    ) {
      if (credsAvailable) {
        credentials = _httpClient._findCredentials(_httpRequest.uri, scheme);
        return retry();
      }

      // No credentials available, complete with original response.
      return this;
    });
  }
}

final class _ToUint8List extends Converter<List<int>, Uint8List> {
  const _ToUint8List();

  @override
  Uint8List convert(List<int> input) {
    return Uint8List.fromList(input);
  }

  @override
  Sink<List<int>> startChunkedConversion(Sink<Uint8List> sink) {
    return _Uint8ListConversionSink(sink);
  }
}

final class _Uint8ListConversionSink implements Sink<List<int>> {
  const _Uint8ListConversionSink(this._target);

  final Sink<Uint8List> _target;

  @override
  void add(List<int> data) {
    _target.add(Uint8List.fromList(data));
  }

  @override
  void close() {
    _target.close();
  }
}

base class _StreamSinkImpl<T> implements StreamSink<T> {
  _StreamSinkImpl(this._target);

  final StreamConsumer<T> _target;
  final Completer<Object?> _doneCompleter = Completer<Object?>();
  StreamController<T>? _controllerInstance;
  Completer<_StreamSinkImpl<T>>? _controllerCompleter;
  bool _isClosed = false;
  bool _isBound = false;
  bool _hasError = false;

  @override
  void add(T data) {
    if (_isClosed) {
      throw StateError('StreamSink is closed');
    }

    _controller.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_isClosed) {
      throw StateError('StreamSink is closed');
    }

    _controller.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<T> stream) {
    if (_isBound) {
      throw StateError('StreamSink is already bound to a stream');
    }

    _isBound = true;

    if (_hasError) {
      return done;
    }

    // Wait for any sync operations to complete.
    Future<void> targetAddStream() {
      return _target.addStream(stream).whenComplete(() {
        _isBound = false;
      });
    }

    StreamController<T>? controller = _controllerInstance;

    if (controller == null) {
      return targetAddStream();
    }

    Future<_StreamSinkImpl<T>> future = _controllerCompleter!.future;
    controller.close();

    return future.then<void>((_) {
      return targetAddStream();
    });
  }

  Future<void> flush() {
    if (_isBound) {
      throw StateError('StreamSink is bound to a stream');
    }

    StreamController<T>? controller = _controllerInstance;

    if (controller == null) {
      return Future<_StreamSinkImpl<T>>.value(this);
    }

    // Adding an empty stream-controller will return a future that will complete
    // when all data is done.
    _isBound = true;

    Future<_StreamSinkImpl<T>> future = _controllerCompleter!.future;
    controller.close();

    return future.whenComplete(() {
      _isBound = false;
    });
  }

  @override
  Future<void> close() {
    if (_isBound) {
      throw StateError('StreamSink is bound to a stream');
    }

    if (!_isClosed) {
      _isClosed = true;

      StreamController<T>? controller = _controllerInstance;

      if (controller != null) {
        controller.close();
      } else {
        _closeTarget();
      }
    }

    return done;
  }

  void _closeTarget() {
    _target.close().then<void>(_completeDoneValue, onError: _completeDoneError);
  }

  @override
  Future<void> get done {
    return _doneCompleter.future;
  }

  void _completeDoneValue(Object? value) {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete(value);
    }
  }

  void _completeDoneError(Object error, StackTrace stackTrace) {
    if (!_doneCompleter.isCompleted) {
      _hasError = true;
      _doneCompleter.completeError(error, stackTrace);
    }
  }

  StreamController<T> get _controller {
    if (_isBound) {
      throw StateError('StreamSink is bound to a stream');
    }

    if (_isClosed) {
      throw StateError('StreamSink is closed');
    }

    if (_controllerInstance == null) {
      _controllerInstance = StreamController<T>(sync: true);
      _controllerCompleter = Completer<_StreamSinkImpl<T>>();

      _target
          .addStream(_controller.stream)
          .then<void>(
            (_) {
              if (_isBound) {
                // A new stream takes over - forward values to that stream.
                _controllerCompleter!.complete(this);
                _controllerCompleter = null;
                _controllerInstance = null;
              } else {
                // No new stream, .close was called. Close _target.
                _closeTarget();
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (_isBound) {
                // A new stream takes over - forward errors to that stream.
                _controllerCompleter!.completeError(error, stackTrace);
                _controllerCompleter = null;
                _controllerInstance = null;
              } else {
                // No new stream. No need to close target, as it has already
                // failed.
                _completeDoneError(error, stackTrace);
              }
            },
          );
    }

    return _controllerInstance!;
  }
}

base class _IOSinkImpl extends _StreamSinkImpl<List<int>> implements IOSink {
  _IOSinkImpl(super.target, this._encoding, this._profileData);

  Encoding _encoding;
  bool _encodingMutable = true;

  final _HttpProfileData? _profileData;

  @override
  Encoding get encoding {
    return _encoding;
  }

  @override
  set encoding(Encoding value) {
    if (!_encodingMutable) {
      throw StateError('IOSink encoding is not mutable');
    }

    _encoding = value;
  }

  void _writeString(String string) {
    Uint8List? utf8Encoding;
    _profileData?.appendRequestData(utf8Encoding = utf8.encode(string));

    super.add(
      utf8Encoding != null && identical(_encoding, utf8)
          ? utf8Encoding
          : _encoding.encode(string),
    );
  }

  @override
  void write(Object? object) {
    String string = '$object';

    if (string.isEmpty) {
      return;
    }

    _writeString(string);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    Iterator<Object?> iterator = objects.iterator;

    if (!iterator.moveNext()) {
      return;
    }

    if (separator.isEmpty) {
      do {
        write(iterator.current);
      } while (iterator.moveNext());
    } else {
      write(iterator.current);

      while (iterator.moveNext()) {
        write(separator);
        write(iterator.current);
      }
    }
  }

  @override
  void writeln([Object? object = '']) {
    write('$object\n');
  }

  @override
  void writeCharCode(int charCode) {
    write(String.fromCharCode(charCode));
  }
}

abstract base class _HttpOutboundMessage extends _IOSinkImpl {
  _HttpOutboundMessage(
    Uri uri,
    String protocolVersion,
    _HttpOutgoing outgoing,
    _HttpProfileData? profileData, {
    _HttpHeaders? initialHeaders,
  }) : _uri = uri,
       headers = _HttpHeaders(
         protocolVersion,
         defaultPortForScheme:
             uri.isScheme('https')
                 ? HttpClient.defaultHttpsPort
                 : HttpClient.defaultHttpPort,
         initialHeaders: initialHeaders,
       ),
       _outgoing = outgoing,
       super(outgoing, latin1, profileData) {
    _outgoing.outbound = this;
    _encodingMutable = false;
  }

  // Used to mark when the body should be written. This is used for HEAD
  // requests and in error handling.
  bool _encodingSet = false;

  bool _bufferOutput = true;

  final Uri _uri;
  final _HttpOutgoing _outgoing;

  final _HttpHeaders headers;

  int get contentLength {
    return headers.contentLength;
  }

  set contentLength(int contentLength) {
    headers.contentLength = contentLength;
  }

  bool get persistentConnection {
    return headers.persistentConnection;
  }

  set persistentConnection(bool persistentConnection) {
    headers.persistentConnection = persistentConnection;
  }

  bool get bufferOutput {
    return _bufferOutput;
  }

  set bufferOutput(bool bufferOutput) {
    if (_outgoing.headersWritten) {
      throw StateError('Header already sent');
    }

    _bufferOutput = bufferOutput;
  }

  @override
  Encoding get encoding {
    if (_encodingSet && _outgoing.headersWritten) {
      return _encoding;
    }

    String charset;
    ContentType? contentType = headers.contentType;

    if (contentType != null && contentType.charset != null) {
      charset = contentType.charset!;
    } else {
      charset = 'iso-8859-1';
    }

    return Encoding.getByName(charset) ?? latin1;
  }

  @override
  void add(List<int> data) {
    if (data.isEmpty) {
      return;
    }

    _profileData?.appendRequestData(Uint8List.fromList(data));
    super.add(data);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    if (_profileData == null) {
      return super.addStream(stream);
    }

    return super.addStream(
      stream.map<List<int>>((data) {
        _profileData.appendRequestData(Uint8List.fromList(data));
        return data;
      }),
    );
  }

  @override
  void write(Object? obj) {
    if (!_encodingSet) {
      _encoding = encoding;
      _encodingSet = true;
    }

    super.write(obj);
  }

  void _writeHeader();

  bool get _isConnectionClosed {
    return false;
  }
}

final class _HttpResponse extends _HttpOutboundMessage implements HttpResponse {
  _HttpResponse(
    Uri uri,
    String protocolVersion,
    _HttpOutgoing outgoing,
    HttpHeaders defaultHeaders,
    String? serverHeader,
  ) : super(
        uri,
        protocolVersion,
        outgoing,
        null,
        initialHeaders: defaultHeaders as _HttpHeaders,
      ) {
    if (serverHeader != null) {
      headers.set(HttpHeaders.serverHeader, serverHeader);
    }
  }

  int _statusCode = 200;
  String? _reasonPhrase;
  List<Cookie>? _cookies;
  _HttpRequest? _httpRequest;
  Duration? _deadline;
  Timer? _deadlineTimer;

  bool get _isConnectionClosed {
    return _httpRequest!._httpConnection._isClosing;
  }

  @override
  List<Cookie> get cookies {
    return _cookies ??= <Cookie>[];
  }

  @override
  int get statusCode {
    return _statusCode;
  }

  @override
  set statusCode(int statusCode) {
    if (_outgoing.headersWritten) {
      throw StateError('Header already sent');
    }

    _statusCode = statusCode;
  }

  @override
  String get reasonPhrase {
    return _findReasonPhrase(statusCode);
  }

  @override
  set reasonPhrase(String reasonPhrase) {
    if (_outgoing.headersWritten) {
      throw StateError('Header already sent');
    }

    _reasonPhrase = reasonPhrase;
  }

  @override
  Future<void> redirect(
    Uri location, {
    int status = HttpStatus.movedTemporarily,
  }) {
    if (_outgoing.headersWritten) {
      throw StateError('Header already sent');
    }

    statusCode = status;
    headers.set(HttpHeaders.locationHeader, location.toString());
    return close();
  }

  @override
  Future<Socket> detachSocket({bool writeHeaders = true}) {
    if (_outgoing.headersWritten) {
      throw StateError('Headers already sent');
    }

    deadline = null; // Be sure to stop any deadline.

    Future<Socket> future = _httpRequest!._httpConnection.detachSocket();

    if (writeHeaders) {
      Future<void>? headersFuture = _outgoing.writeHeaders(
        drainRequest: false,
        setOutgoing: false,
      );

      assert(headersFuture == null);
    } else {
      // Imitate having written the headers.
      _outgoing.headersWritten = true;
    }

    // Close connection so the socket is 'free'.
    close();

    done.catchError((_) {
      // Catch any error on done, as they automatically will be
      // propagated to the websocket.
      return null;
    });

    return future;
  }

  @override
  HttpConnectionInfo? get connectionInfo {
    return _httpRequest!.connectionInfo;
  }

  @override
  Duration? get deadline {
    return _deadline;
  }

  @override
  set deadline(Duration? duration) {
    _deadlineTimer?.cancel();
    _deadline = duration;

    if (duration == null) {
      return;
    }

    _deadlineTimer = Timer(duration, () {
      _httpRequest!._httpConnection.destroy();
    });
  }

  void _writeHeader() {
    BytesBuilder buffer = _CopyingBytesBuilder(_outgoingBufferSize);

    // Write status line.
    if (headers.protocolVersion == '1.1') {
      buffer.add(_Const.http11);
    } else {
      buffer.add(_Const.http10);
    }

    buffer
      ..addByte(_CharCode.sp)
      ..add(statusCode.toString().codeUnits)
      ..addByte(_CharCode.sp)
      ..add(reasonPhrase.codeUnits)
      ..addByte(_CharCode.cr)
      ..addByte(_CharCode.lf);

    _HttpSession? session = _httpRequest!._session;

    if (session != null && !session._destroyed) {
      // Mark as not new.
      session._isNew = false;

      // Make sure we only send the current session id.
      bool found = false;

      for (int i = 0; i < cookies.length; i++) {
        if (cookies[i].name.toUpperCase() == _dartSessionId) {
          cookies[i]
            ..value = session.id
            ..httpOnly = true
            ..path = '/';

          found = true;
        }
      }

      if (!found) {
        Cookie cookie =
            Cookie(_dartSessionId, session.id)
              ..httpOnly = true
              ..path = '/';

        cookies.add(cookie);
      }
    }
    // Add all the cookies set to the headers.
    _cookies?.forEach((cookie) {
      headers.add(HttpHeaders.setCookieHeader, cookie);
    });

    headers._finalize();

    // Write headers.
    headers._build(buffer);

    buffer
      ..addByte(_CharCode.cr)
      ..addByte(_CharCode.lf);

    Uint8List headerBytes = buffer.takeBytes();
    _outgoing.setHeader(headerBytes, headerBytes.length);
  }

  String _findReasonPhrase(int statusCode) {
    String? reasonPhrase = _reasonPhrase;

    if (reasonPhrase != null) {
      return reasonPhrase;
    }

    switch (statusCode) {
      case HttpStatus.continue_:
        return 'Continue';

      case HttpStatus.switchingProtocols:
        return 'Switching Protocols';

      case HttpStatus.ok:
        return 'OK';

      case HttpStatus.created:
        return 'Created';

      case HttpStatus.accepted:
        return 'Accepted';

      case HttpStatus.nonAuthoritativeInformation:
        return 'Non-Authoritative Information';

      case HttpStatus.noContent:
        return 'No Content';

      case HttpStatus.resetContent:
        return 'Reset Content';

      case HttpStatus.partialContent:
        return 'Partial Content';

      case HttpStatus.multipleChoices:
        return 'Multiple Choices';

      case HttpStatus.movedPermanently:
        return 'Moved Permanently';

      case HttpStatus.found:
        return 'Found';

      case HttpStatus.seeOther:
        return 'See Other';

      case HttpStatus.notModified:
        return 'Not Modified';

      case HttpStatus.useProxy:
        return 'Use Proxy';

      case HttpStatus.temporaryRedirect:
        return 'Temporary Redirect';

      case HttpStatus.badRequest:
        return 'Bad Request';

      case HttpStatus.unauthorized:
        return 'Unauthorized';

      case HttpStatus.paymentRequired:
        return 'Payment Required';

      case HttpStatus.forbidden:
        return 'Forbidden';

      case HttpStatus.notFound:
        return 'Not Found';

      case HttpStatus.methodNotAllowed:
        return 'Method Not Allowed';

      case HttpStatus.notAcceptable:
        return 'Not Acceptable';

      case HttpStatus.proxyAuthenticationRequired:
        return 'Proxy Authentication Required';

      case HttpStatus.requestTimeout:
        return 'Request Time-out';

      case HttpStatus.conflict:
        return 'Conflict';

      case HttpStatus.gone:
        return 'Gone';

      case HttpStatus.lengthRequired:
        return 'Length Required';

      case HttpStatus.preconditionFailed:
        return 'Precondition Failed';

      case HttpStatus.requestEntityTooLarge:
        return 'Request Entity Too Large';

      case HttpStatus.requestUriTooLong:
        return 'Request-URI Too Long';

      case HttpStatus.unsupportedMediaType:
        return 'Unsupported Media Type';

      case HttpStatus.requestedRangeNotSatisfiable:
        return 'Requested range not satisfiable';

      case HttpStatus.expectationFailed:
        return 'Expectation Failed';

      case HttpStatus.internalServerError:
        return 'Internal Server Error';

      case HttpStatus.notImplemented:
        return 'Not Implemented';

      case HttpStatus.badGateway:
        return 'Bad Gateway';

      case HttpStatus.serviceUnavailable:
        return 'Service Unavailable';

      case HttpStatus.gatewayTimeout:
        return 'Gateway Time-out';

      case HttpStatus.httpVersionNotSupported:
        return 'Http Version not supported';

      default:
        return 'Status $statusCode';
    }
  }
}

final class _HttpClientRequest extends _HttpOutboundMessage
    implements HttpClientRequest {
  _HttpClientRequest(
    _HttpOutgoing outgoing,
    this.uri,
    this.method,
    this._proxy,
    this._httpClient,
    this._httpClientConnection,
    _HttpProfileData? _profileData,
  ) : super(uri, '1.1', outgoing, _profileData) {
    _profileData?.requestEvent('Request sent');
    // GET and HEAD have 'content-length: 0' by default.
    if (method == 'GET' || method == 'HEAD') {
      contentLength = 0;
    } else {
      headers.chunkedTransferEncoding = true;
    }

    _responseCompleter.future.then((response) {
      _profileData?.requestEvent('Waiting (TTFB)');
      _profileData?.startResponse(
        // TODO(bkonyi): consider exposing certificate information?
        // 'certificate': response.certificate,
        response: response,
      );
    }, onError: (e) {});
  }

  @override
  final String method;
  @override
  final Uri uri;
  @override
  final List<Cookie> cookies = <Cookie>[];

  // The HttpClient this request belongs to.
  final _HttpClient _httpClient;
  final _HttpClientConnection _httpClientConnection;

  final Completer<HttpClientResponse> _responseCompleter =
      Completer<HttpClientResponse>();

  final _Proxy _proxy;

  Future<HttpClientResponse>? _response;

  // TODO(ajohnsen): Get default value from client?
  bool _followRedirects = true;

  int _maxRedirects = 5;

  final List<RedirectInfo> _responseRedirects = <RedirectInfo>[];

  bool _aborted = false;

  @override
  Future<HttpClientResponse> get done {
    return _response ??= Future.wait<Object?>(<Future<Object?>>[
      _responseCompleter.future,
      super.done,
    ], eagerError: true).then<HttpClientResponse>((list) {
      return list[0] as HttpClientResponse;
    });
  }

  @override
  Future<HttpClientResponse> close() {
    if (!_aborted) {
      // It will send out the request.
      super.close();
    }

    return done;
  }

  @override
  int get maxRedirects {
    return _maxRedirects;
  }

  @override
  set maxRedirects(int maxRedirects) {
    if (_outgoing.headersWritten) {
      throw StateError('Request already sent');
    }

    _maxRedirects = maxRedirects;
  }

  @override
  bool get followRedirects {
    return _followRedirects;
  }

  @override
  set followRedirects(bool followRedirects) {
    if (_outgoing.headersWritten) {
      throw StateError('Request already sent');
    }

    _followRedirects = followRedirects;
  }

  @override
  HttpConnectionInfo? get connectionInfo {
    return _httpClientConnection.connectionInfo;
  }

  void _onIncoming(_HttpIncoming incoming) {
    if (_aborted) {
      return;
    }

    _HttpClientResponse response = _HttpClientResponse(
      incoming,
      this,
      _httpClient,
      _profileData,
    );

    Future<HttpClientResponse> future;

    if (followRedirects && response.isRedirect) {
      if (response.redirects.length < maxRedirects) {
        // Redirect and drain response.
        future = response.drain<void>().then<HttpClientResponse>(
          (_) => response.redirect(),
        );
      } else {
        // End with exception, too many redirects.
        future = response.drain<void>().then<HttpClientResponse>((_) {
          return Future<HttpClientResponse>.error(
            RedirectException('Redirect limit exceeded', response.redirects),
          );
        });
      }
    } else if (response._shouldAuthenticateProxy) {
      future = response._authenticate(true);
    } else if (response._shouldAuthenticate) {
      future = response._authenticate(false);
    } else {
      future = Future<HttpClientResponse>.value(response);
    }

    future.then<void>(
      (response) {
        if (!_responseCompleter.isCompleted) {
          _responseCompleter.complete(response);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_responseCompleter.isCompleted) {
          _responseCompleter.completeError(error, stackTrace);
        }
      },
    );
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (!_responseCompleter.isCompleted) {
      _responseCompleter.completeError(error, stackTrace);
    }
  }

  // Generate the request URI based on the method and proxy.
  String _requestUri() {
    // Generate the request URI starting from the path component.
    String uriStartingFromPath() {
      String result = uri.path;

      if (result.isEmpty) {
        result = '/';
      }

      if (uri.hasQuery) {
        result = '$result?${uri.query}';
      }

      return result;
    }

    if (_proxy.isDirect) {
      return uriStartingFromPath();
    }

    if (method == 'CONNECT') {
      // For the connect method the request URI is the host:port of
      // the requested destination of the tunnel (see RFC 2817
      // section 5.2)
      return '${uri.host}:${uri.port}';
    }

    if (_httpClientConnection._proxyTunnel) {
      return uriStartingFromPath();
    }

    return uri.removeFragment().toString();
  }

  @override
  void add(List<int> data) {
    if (data.isEmpty || _aborted) {
      return;
    }

    super.add(data);
  }

  @override
  void write(Object? obj) {
    if (_aborted) {
      return;
    }

    super.write(obj);
  }

  void _writeHeader() {
    if (_aborted) {
      _outgoing.setHeader(Uint8List(0), 0);
      return;
    }

    BytesBuilder buffer = _CopyingBytesBuilder(_outgoingBufferSize);

    // Write the request method.
    buffer
      ..add(method.codeUnits)
      ..addByte(_CharCode.sp)
      // Write the request URI.
      ..add(_requestUri().codeUnits)
      ..addByte(_CharCode.sp)
      // Write HTTP/1.1.
      ..add(_Const.http11)
      ..addByte(_CharCode.cr)
      ..addByte(_CharCode.lf);

    // Add the cookies to the headers.
    if (cookies.isNotEmpty) {
      StringBuffer buffer = StringBuffer();

      for (int i = 0; i < cookies.length; i++) {
        if (i > 0) {
          buffer.write('; ');
        }

        buffer
          ..write(cookies[i].name)
          ..write('=')
          ..write(cookies[i].value);
      }

      headers.add(HttpHeaders.cookieHeader, buffer.toString());
    }

    headers._finalize();

    // Write headers.
    headers._build(
      buffer,
      skipZeroContentLength:
          method == 'CONNECT' ||
          method == 'DELETE' ||
          method == 'GET' ||
          method == 'HEAD',
    );

    buffer
      ..addByte(_CharCode.cr)
      ..addByte(_CharCode.lf);

    Uint8List headerBytes = buffer.takeBytes();
    _outgoing.setHeader(headerBytes, headerBytes.length);
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _aborted = true;

    if (!_responseCompleter.isCompleted) {
      exception ??= HttpException('Request has been aborted');
      _responseCompleter.completeError(exception, stackTrace);
      _httpClientConnection.destroy();
    }
  }
}

// Used by _HttpOutgoing as a target of a chunked converter for gzip
// compression.
final class _HttpGZipSink extends ByteConversionSink {
  _HttpGZipSink(this._consume);

  final _BytesConsumer _consume;

  @override
  void add(List<int> chunk) {
    _consume(chunk);
  }

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    if (chunk is Uint8List) {
      _consume(
        Uint8List.view(chunk.buffer, chunk.offsetInBytes + start, end - start),
      );
    } else {
      _consume(chunk.sublist(start, end - start));
    }
  }

  @override
  void close() {}
}

// The _HttpOutgoing handles all of the following:
//  - Buffering
//  - GZip compression
//  - Content-Length validation.
//  - Errors.
//
// Most notable is the GZip compression, that uses a double-buffering system,
// one before gzip (_gzipBuffer) and one after (_buffer).
final class _HttpOutgoing implements StreamConsumer<List<int>> {
  static const List<int> _footerAndChunk0Length = <int>[
    _CharCode.cr,
    _CharCode.lf,
    0x30,
    _CharCode.cr,
    _CharCode.lf,
    _CharCode.cr,
    _CharCode.lf,
  ];

  static const List<int> _chunk0Length = <int>[
    0x30,
    _CharCode.cr,
    _CharCode.lf,
    _CharCode.cr,
    _CharCode.lf,
  ];

  _HttpOutgoing(this.socket);

  final Completer<Socket> _doneCompleter = Completer<Socket>();
  final Socket socket;

  bool ignoreBody = false;
  bool headersWritten = false;

  Uint8List? _buffer;
  int _length = 0;

  Future<void>? _closeFuture;

  bool chunked = false;
  int _pendingChunkedFooter = 0;

  int? contentLength;
  int _bytesWritten = 0;

  bool _gzip = false;
  ByteConversionSink? _gzipSink;
  // _gzipAdd is set iff the sink is being added to. It's used to specify where
  // gzipped data should be taken (sometimes a controller, sometimes a socket).
  _BytesConsumer? _gzipAdd;
  Uint8List? _gzipBuffer;
  int _gzipBufferLength = 0;

  bool _socketError = false;

  _HttpOutboundMessage? outbound;

  // Returns either a future or 'null', if it was able to write headers
  // immediately.
  Future<void>? writeHeaders({
    bool drainRequest = true,
    bool setOutgoing = true,
  }) {
    if (headersWritten) {
      return null;
    }

    headersWritten = true;

    Future<void>? drainFuture;
    bool gzip = false;
    _HttpOutboundMessage response = outbound!;

    if (response is _HttpResponse) {
      // Server side.
      if (response._httpRequest!._httpServer.autoCompress &&
          response.bufferOutput &&
          response.headers.chunkedTransferEncoding) {
        List<String>? acceptEncodings =
            response._httpRequest!.headers[HttpHeaders.acceptEncodingHeader];

        List<String>? contentEncoding =
            response.headers[HttpHeaders.contentEncodingHeader];

        if (acceptEncodings != null &&
            contentEncoding == null &&
            acceptEncodings
                .expand((list) => list.split(','))
                .any((encoding) => encoding.trim().toLowerCase() == 'gzip')) {
          response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
          gzip = true;
        }
      }

      if (drainRequest && !response._httpRequest!._incoming.hasSubscriber) {
        drainFuture = response._httpRequest!.drain<void>().catchError((_) {});
      }
    } else {
      drainRequest = false;
    }

    if (!ignoreBody) {
      if (setOutgoing) {
        int contentLength = response.headers.contentLength;

        if (response.headers.chunkedTransferEncoding) {
          chunked = true;

          if (gzip) {
            this.gzip = true;
          }
        } else if (contentLength >= 0) {
          this.contentLength = contentLength;
        }
      }

      if (drainFuture != null) {
        return drainFuture.then((_) => response._writeHeader());
      }
    }

    response._writeHeader();
    return null;
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    if (_socketError) {
      stream.listen(null).cancel();
      return Future<_HttpOutboundMessage>.value(outbound);
    }

    if (ignoreBody) {
      stream.drain<void>().catchError((_) {});

      Future<void>? future = writeHeaders();

      if (future != null) {
        return future.then<void>((_) => close());
      }

      return close();
    }
    // Use new stream so we are able to pause (see below listen). The
    // alternative is to use stream.expand, but that won't give us a way of
    // pausing.
    var controller = StreamController<List<int>>(sync: true);

    void onData(List<int> data) {
      if (_socketError) {
        return;
      }

      if (data.isEmpty) {
        return;
      }

      if (chunked) {
        if (_gzip) {
          _gzipAdd = controller.add;
          _addGZipChunk(data, _gzipSink!.add);
          _gzipAdd = null;
          return;
        }

        _addChunk(_chunkHeader(data.length), controller.add);
        _pendingChunkedFooter = 2;
      } else {
        int? contentLength = this.contentLength;

        if (contentLength != null) {
          _bytesWritten += data.length;

          if (_bytesWritten > contentLength) {
            controller.addError(
              HttpException(
                'Content size exceeds specified contentLength. '
                '$_bytesWritten bytes written while expected '
                '$contentLength. '
                '[${String.fromCharCodes(data)}]',
              ),
            );

            return;
          }
        }
      }

      _addChunk(data, controller.add);
    }

    StreamSubscription<List<int>> subscription = stream.listen(
      onData,
      onError: controller.addError,
      onDone: controller.close,
      cancelOnError: true,
    );

    controller
      ..onCancel = subscription.cancel
      ..onPause = subscription.pause
      ..onResume = subscription.resume;

    // Write headers now that we are listening to the stream.
    if (!headersWritten) {
      Future<void>? future = writeHeaders();

      if (future != null) {
        // While incoming is being drained, the pauseFuture is non-null. Pause
        // output until it's drained.
        subscription.pause(future);
      }
    }

    return socket
        .addStream(controller.stream)
        .then<_HttpOutboundMessage?>(
          (_) => outbound,
          onError: (Object error, StackTrace stackTrace) {
            // Be sure to close it in case of an error.
            if (_gzip) {
              _gzipSink!.close();
            }

            _socketError = true;
            _doneCompleter.completeError(error, stackTrace);

            if (_ignoreError(error)) {
              return outbound;
            }

            throw error;
          },
        );
  }

  @override
  Future<void> close() {
    // If we are already closed, return that future.
    Future<void>? closeFuture = _closeFuture;

    if (closeFuture != null) {
      return closeFuture;
    }

    _HttpOutboundMessage outbound = this.outbound!;

    // If we earlier saw an error, return immediate. The notification to
    // _Http*Connection is already done.
    if (_socketError) {
      return Future<_HttpOutboundMessage>.value(outbound);
    }

    if (outbound._isConnectionClosed) {
      return Future<_HttpOutboundMessage>.value(outbound);
    }

    if (!headersWritten && !ignoreBody) {
      if (outbound.headers.contentLength == -1) {
        // If no body was written, ignoreBody is false (it's not a HEAD
        // request) and the content-length is unspecified, set contentLength to
        // 0.
        outbound.headers.chunkedTransferEncoding = false;
        outbound.headers.contentLength = 0;
      } else if (outbound.headers.contentLength > 0) {
        HttpException error = HttpException(
          'No content even though contentLength was specified to be '
          'greater than 0: ${outbound.headers.contentLength}.',
          uri: outbound._uri,
        );

        _doneCompleter.completeError(error);
        return _closeFuture = Future<void>.error(error);
      }
    }

    // If contentLength was specified, validate it.
    int? contentLength = this.contentLength;

    if (contentLength != null) {
      if (_bytesWritten < contentLength) {
        HttpException error = HttpException(
          'Content size below specified contentLength. '
          ' $_bytesWritten bytes written but expected '
          '$contentLength.',
          uri: outbound._uri,
        );

        _doneCompleter.completeError(error);
        return _closeFuture = Future<void>.error(error);
      }
    }

    Future<void> finalize() {
      // In case of chunked encoding (and gzip), handle remaining gzip data and
      // append the 'footer' for chunked encoding.
      if (chunked) {
        if (_gzip) {
          _gzipAdd = socket.add;

          if (_gzipBufferLength > 0) {
            _gzipSink!.add(
              Uint8List.view(
                _gzipBuffer!.buffer,
                _gzipBuffer!.offsetInBytes,
                _gzipBufferLength,
              ),
            );
          }

          _gzipBuffer = null;
          _gzipSink!.close();
          _gzipAdd = null;
        }

        _addChunk(_chunkHeader(0), socket.add);
      }

      // Add any remaining data in the buffer.
      if (_length > 0) {
        socket.add(
          Uint8List.view(_buffer!.buffer, _buffer!.offsetInBytes, _length),
        );
      }

      // Clear references, for better GC.
      _buffer = null;

      // And finally flush it. As we support keep-alive, never close it from
      // here. Once the socket is flushed, we'll be able to reuse it (signaled
      // by the 'done' future).
      return socket.flush().then<_HttpOutboundMessage>(
        (_) {
          _doneCompleter.complete(socket);
          return outbound;
        },
        onError: (Object error, StackTrace stackTrace) {
          _doneCompleter.completeError(error, stackTrace);

          if (_ignoreError(error)) {
            return outbound;
          }

          throw error;
        },
      );
    }

    Future<void>? future = writeHeaders();

    if (future != null) {
      return _closeFuture = future.whenComplete(finalize);
    }

    return _closeFuture = finalize();
  }

  Future<Socket> get done {
    return _doneCompleter.future;
  }

  void setHeader(List<int> data, int length) {
    assert(_length == 0);
    _buffer = data as Uint8List;
    _length = length;
  }

  set gzip(bool value) {
    _gzip = value;

    if (value) {
      _gzipBuffer = Uint8List(_outgoingBufferSize);
      assert(_gzipSink == null);

      _gzipSink = ZLibEncoder(gzip: true).startChunkedConversion(
        _HttpGZipSink((data) {
          // We are closing down prematurely, due to an error. Discard.
          if (_gzipAdd == null) {
            return;
          }

          _addChunk(_chunkHeader(data.length), _gzipAdd!);
          _pendingChunkedFooter = 2;
          _addChunk(data, _gzipAdd!);
        }),
      );
    }
  }

  bool _ignoreError(Object? error) {
    return (error is SocketException || error is TlsException) &&
        outbound is HttpResponse;
  }

  void _addGZipChunk(List<int> chunk, void Function(List<int> data) add) {
    bool bufferOutput = outbound!.bufferOutput;

    if (!bufferOutput) {
      add(chunk);
      return;
    }

    Uint8List gzipBuffer = _gzipBuffer!;

    if (chunk.length > gzipBuffer.length - _gzipBufferLength) {
      add(
        Uint8List.view(
          gzipBuffer.buffer,
          gzipBuffer.offsetInBytes,
          _gzipBufferLength,
        ),
      );

      _gzipBuffer = Uint8List(_outgoingBufferSize);
      _gzipBufferLength = 0;
    }

    if (chunk.length > _outgoingBufferSize) {
      add(chunk);
    } else {
      int currentLength = _gzipBufferLength;
      int newLength = currentLength + chunk.length;
      _gzipBuffer!.setRange(currentLength, newLength, chunk);
      _gzipBufferLength = newLength;
    }
  }

  void _addChunk(List<int> chunk, void Function(List<int> data) add) {
    bool bufferOutput = outbound!.bufferOutput;

    if (!bufferOutput) {
      if (_buffer != null) {
        // If _buffer is not null, we have not written the header yet. Write
        // it now.
        add(Uint8List.view(_buffer!.buffer, _buffer!.offsetInBytes, _length));
        _buffer = null;
        _length = 0;
      }

      add(chunk);
      return;
    }

    if (chunk.length > _buffer!.length - _length) {
      add(Uint8List.view(_buffer!.buffer, _buffer!.offsetInBytes, _length));
      _buffer = Uint8List(_outgoingBufferSize);
      _length = 0;
    }

    if (chunk.length > _outgoingBufferSize) {
      add(chunk);
    } else {
      _buffer!.setRange(_length, _length + chunk.length, chunk);
      _length += chunk.length;
    }
  }

  List<int> _chunkHeader(int length) {
    const List<int> hexDigits = <int>[
      0x30,
      0x31,
      0x32,
      0x33,
      0x34,
      0x35,
      0x36,
      0x37,
      0x38,
      0x39,
      0x41,
      0x42,
      0x43,
      0x44,
      0x45,
      0x46,
    ];

    if (length == 0) {
      if (_pendingChunkedFooter == 2) {
        return _footerAndChunk0Length;
      }

      return _chunk0Length;
    }

    int size = _pendingChunkedFooter;
    int len = length;

    // Compute a fast integer version of (log(length + 1) / log(16)).ceil().
    while (len > 0) {
      size++;
      len >>= 4;
    }

    Uint8List footerAndHeader = Uint8List(size + 2);

    if (_pendingChunkedFooter == 2) {
      footerAndHeader[0] = _CharCode.cr;
      footerAndHeader[1] = _CharCode.lf;
    }

    int index = size;

    while (index > _pendingChunkedFooter) {
      footerAndHeader[--index] = hexDigits[length & 15];
      length = length >> 4;
    }

    footerAndHeader[size + 0] = _CharCode.cr;
    footerAndHeader[size + 1] = _CharCode.lf;
    return footerAndHeader;
  }
}

final class _HttpClientConnection {
  _HttpClientConnection(
    this.key,
    this._socket,
    this._httpClient, [
    this._proxyTunnel = false,
    this._context,
  ]) : _httpParser = _HttpParser.responseParser() {
    _httpParser.listenToStream(_socket);

    // Set up handlers on the parser here, so we are sure to get 'onDone' from
    // the parser.
    _subscription = _httpParser.listen(
      (incoming) {
        // Only handle one incoming response at the time. Keep the
        // stream paused until the response have been processed.
        _subscription!.pause();

        // We assume the response is not here, until we have send the request.
        if (_nextResponseCompleter == null) {
          throw HttpException(
            'Unexpected response (unsolicited response without request).',
            uri: _currentUri,
          );
        }

        // Check for status code '100 Continue'. In that case just
        // consume that response as the final response will follow
        // it. There is currently no API for the client to wait for
        // the '100 Continue' response.
        if (incoming.statusCode == 100) {
          incoming
              .drain<void>()
              .then<void>((_) {
                _subscription!.resume();
              })
              .catchError(
                (Object error, StackTrace stackTrace) {
                  String message;

                  if (error is HttpException) {
                    message = error.message;
                  } else if (error is SocketException) {
                    message = error.message;
                  } else if (error is TlsException) {
                    message = error.message;
                  } else {
                    throw error;
                  }

                  _nextResponseCompleter!.completeError(
                    HttpException(message, uri: _currentUri),
                    stackTrace,
                  );

                  _nextResponseCompleter = null;
                },
                test: (error) {
                  return error is HttpException ||
                      error is SocketException ||
                      error is TlsException;
                },
              );
        } else {
          _nextResponseCompleter!.complete(incoming);
          _nextResponseCompleter = null;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        String message;

        if (error is HttpException) {
          message = error.message;
        } else if (error is SocketException) {
          message = error.message;
        } else if (error is TlsException) {
          message = error.message;
        } else {
          throw error;
        }

        _nextResponseCompleter?.completeError(
          HttpException(message, uri: _currentUri),
          stackTrace,
        );

        _nextResponseCompleter = null;
      },
      onDone: () {
        _nextResponseCompleter?.completeError(
          HttpException(
            'Connection closed before response was received',
            uri: _currentUri,
          ),
        );

        _nextResponseCompleter = null;

        if (!closed) {
          _close();
        }
      },
    );
  }

  final String key;
  final Socket _socket;
  final bool _proxyTunnel;
  final SecurityContext? _context;
  final _HttpParser _httpParser;
  StreamSubscription<_HttpIncoming>? _subscription;
  final _HttpClient _httpClient;
  bool _dispose = false;
  Timer? _idleTimer;
  bool closed = false;
  Uri? _currentUri;

  Completer<_HttpIncoming>? _nextResponseCompleter;
  Future<Socket>? _streamFuture;

  _HttpClientRequest send(
    Uri uri,
    int port,
    String method,
    _Proxy proxy,
    _HttpProfileData? profileData,
  ) {
    if (closed) {
      throw HttpException('Socket closed before request was sent', uri: uri);
    }

    _currentUri = uri;

    // Start with pausing the parser.
    _subscription!.pause();

    if (method == 'CONNECT') {
      // Parser will ignore Content-Length or Transfer-Encoding header
      _httpParser.connectMethod = true;
    }

    // Credentials used to authorize proxy.
    _ProxyCredentials? proxyCredentials;

    // Credentials used to authorize this request.
    _SiteCredentials? credentials;
    _HttpOutgoing outgoing = _HttpOutgoing(_socket);

    // Create new request object, wrapping the outgoing connection.
    _HttpClientRequest request = _HttpClientRequest(
      outgoing,
      uri,
      method,
      proxy,
      _httpClient,
      this,
      profileData,
    );

    // For the Host header an IPv6 address must be enclosed in []'s.
    String host = uri.host;

    if (host.contains(':')) {
      host = '[$host]';
    }

    request.headers
      ..host = host
      ..port = port
      ..add(HttpHeaders.acceptEncodingHeader, 'gzip');

    if (_httpClient.userAgent != null) {
      request.headers.add(HttpHeaders.userAgentHeader, _httpClient.userAgent!);
    }

    if (proxy.isAuthenticated) {
      // If the proxy configuration contains user information use that
      // for proxy basic authorization.
      String auth = base64Encode(
        utf8.encode('${proxy.username}:${proxy.password}'),
      );

      request.headers.set(HttpHeaders.proxyAuthorizationHeader, 'Basic $auth');
    } else if (!proxy.isDirect && _httpClient._proxyCredentials.isNotEmpty) {
      proxyCredentials = _httpClient._findProxyCredentials(proxy);

      if (proxyCredentials != null) {
        proxyCredentials.authorize(request);
      }
    }

    if (uri.userInfo.isNotEmpty) {
      // If the URL contains user information use that for basic
      // authorization.
      String auth = base64Encode(utf8.encode(uri.userInfo));
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic $auth');
    } else {
      // Look for credentials.
      credentials = _httpClient._findCredentials(uri);

      if (credentials != null) {
        credentials.authorize(request);
      }
    }

    // Start sending the request (lazy, delayed until the user provides
    // data).
    _httpParser.isHead = method == 'HEAD';

    _streamFuture = outgoing.done.then<Socket>((Socket socket) {
      // Request sent, details available for profiling
      profileData?.finishRequest(request: request);

      // Request sent, set up response completer.
      Completer<_HttpIncoming> nextResponseCompleter =
          Completer<_HttpIncoming>();

      _nextResponseCompleter = nextResponseCompleter;

      // Listen for response.
      nextResponseCompleter.future
          .then<void>((incoming) {
            _currentUri = null;

            incoming.dataDone.then<void>((closing) {
              if (incoming.upgraded) {
                _httpClient._connectionClosed(this);
                startTimer();
                return;
              }

              // Keep the connection open if the CONNECT request was successful.
              if (closed ||
                  (method == 'CONNECT' &&
                      incoming.statusCode == HttpStatus.ok)) {
                return;
              }

              if (!closing &&
                  !_dispose &&
                  incoming.headers.persistentConnection &&
                  request.persistentConnection) {
                // Return connection, now we are done.
                _httpClient._returnConnection(this);
                _subscription!.resume();
              } else {
                destroy();
              }
            });

            // For digest authentication if proxy check if the proxy
            // requests the client to start using a new nonce for proxy
            // authentication.
            if (proxyCredentials != null &&
                proxyCredentials.scheme == _AuthenticationScheme.digest) {
              List<String>? authInfo =
                  incoming.headers['proxy-authentication-info'];

              if (authInfo != null && authInfo.length == 1) {
                _HeaderValue header = _HeaderValue.parse(
                  authInfo[0],
                  parameterSeparator: ',',
                );

                String? nextnonce = header.parameters['nextnonce'];

                if (nextnonce != null) {
                  proxyCredentials.nonce = nextnonce;
                }
              }
            }

            // For digest authentication check if the server requests the
            // client to start using a new nonce.
            if (credentials != null &&
                credentials.scheme == _AuthenticationScheme.digest) {
              List<String>? authInfo = incoming.headers['authentication-info'];

              if (authInfo != null && authInfo.length == 1) {
                _HeaderValue header = _HeaderValue.parse(
                  authInfo[0],
                  parameterSeparator: ',',
                );

                String? nextnonce = header.parameters['nextnonce'];

                if (nextnonce != null) {
                  credentials.nonce = nextnonce;
                }
              }
            }

            request._onIncoming(incoming);
          })
          // If we see a state error, we failed to get the 'first'
          // element.
          .catchError((error) {
            throw HttpException(
              'Connection closed before data was received',
              uri: uri,
            );
          }, test: (error) => error is StateError)
          .catchError((Object error, StackTrace stackTrace) {
            // We are done with the socket.
            destroy();
            request._onError(error, stackTrace);
          });

      // Resume the parser now we have a handler.
      _subscription!.resume();
      return socket;
    });

    Future<Socket?>.value(_streamFuture).catchError((e) {
      destroy();
      return null;
    });

    return request;
  }

  Future<Socket> detachSocket() {
    return _streamFuture!.then<_DetachedSocket>((_) {
      return _DetachedSocket(_socket, _httpParser.detachIncoming());
    });
  }

  void destroy() {
    closed = true;
    _httpClient._connectionClosed(this);
    _socket.destroy();
  }

  void destroyFromExternal() {
    closed = true;
    _httpClient._connectionClosedNoFurtherClosing(this);
    _socket.destroy();
  }

  void _close() {
    closed = true;
    _httpClient._connectionClosed(this);

    _streamFuture!.timeout(_httpClient.idleTimeout).then<void>((_) {
      _socket.destroy();
    });
  }

  void closeFromExternal() {
    closed = true;
    _httpClient._connectionClosedNoFurtherClosing(this);

    _streamFuture!.timeout(_httpClient.idleTimeout).then<void>((_) {
      _socket.destroy();
    });
  }

  Future<_HttpClientConnection> createProxyTunnel(
    String host,
    int port,
    _Proxy proxy,
    bool Function(X509Certificate certificate) callback,
    _HttpProfileData? profileData,
  ) {
    String method = 'CONNECT';
    Uri uri = Uri(host: host, port: port);

    profileData?.proxyEvent(proxy);

    // Notify the profiler that we're starting a sub request.
    _HttpProfileData? proxyProfileData;

    if (profileData != null) {
      proxyProfileData = HttpProfiler.startRequest(
        method,
        uri,
        parentRequest: profileData,
      );
    }

    _HttpClientRequest request = send(
      Uri(host: host, port: port),
      port,
      method,
      proxy,
      proxyProfileData,
    );

    if (proxy.isAuthenticated) {
      // If the proxy configuration contains user information use that
      // for proxy basic authorization.
      String auth = base64Encode(
        utf8.encode('${proxy.username}:${proxy.password}'),
      );

      request.headers.set(HttpHeaders.proxyAuthorizationHeader, 'Basic $auth');
    }
    return request
        .close()
        .then<SecureSocket>((response) {
          if (response.statusCode != HttpStatus.ok) {
            String error =
                'Proxy failed to establish tunnel '
                '(${response.statusCode} ${response.reasonPhrase})';

            profileData?.requestEvent(error);
            throw HttpException(error, uri: request.uri);
          }

          Socket socket =
              (response as _HttpClientResponse)
                  ._httpRequest
                  ._httpClientConnection
                  ._socket;

          return SecureSocket.secure(
            socket,
            host: host,
            context: _context,
            onBadCertificate: callback,
          );
        })
        .then((secureSocket) {
          String key = _HttpClientConnection.makeKey(true, host, port);
          profileData?.requestEvent('Proxy tunnel established');

          return _HttpClientConnection(
            key,
            secureSocket,
            request._httpClient,
            true,
          );
        });
  }

  HttpConnectionInfo? get connectionInfo {
    return _HttpConnectionInfo.create(_socket);
  }

  static String makeKey(bool isSecure, String host, int port) {
    return isSecure ? 'ssh:$host:$port' : '$host:$port';
  }

  void stopTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void startTimer() {
    assert(_idleTimer == null);
    _idleTimer = Timer(_httpClient.idleTimeout, () {
      _idleTimer = null;
      _close();
    });
  }
}

final class _ConnectionInfo {
  _ConnectionInfo(this.connection, this.proxy);

  final _HttpClientConnection connection;
  final _Proxy proxy;
}

final class _ConnectionTarget {
  _ConnectionTarget(
    this.key,
    this.host,
    this.port,
    this.isSecure,
    this.context,
    this.connectionFactory,
  );

  // Unique key for this connection target.
  final String key;
  final String host;
  final int port;
  final bool isSecure;
  final SecurityContext? context;
  final Future<ConnectionTask<Socket>> Function(Uri, String?, int?)?
  connectionFactory;
  final Set<_HttpClientConnection> _idle = HashSet<_HttpClientConnection>();
  final Set<_HttpClientConnection> _active = HashSet<_HttpClientConnection>();
  final Set<ConnectionTask<Socket>> _socketTasks =
      HashSet<ConnectionTask<Socket>>();
  final ListQueue<void Function()> _pending = ListQueue<void Function()>();
  int _connecting = 0;

  bool get isEmpty {
    return _idle.isEmpty && _active.isEmpty && _connecting == 0;
  }

  bool get hasIdle {
    return _idle.isNotEmpty;
  }

  bool get hasActive {
    return _active.isNotEmpty || _connecting > 0;
  }

  _HttpClientConnection takeIdle() {
    assert(hasIdle);

    _HttpClientConnection connection = _idle.first;
    _idle.remove(connection);
    connection.stopTimer();
    _active.add(connection);
    return connection;
  }

  void _checkPending() {
    if (_pending.isNotEmpty) {
      _pending.removeFirst()();
    }
  }

  void addNewActive(_HttpClientConnection connection) {
    _active.add(connection);
  }

  void returnConnection(_HttpClientConnection connection) {
    assert(_active.contains(connection));
    _active.remove(connection);
    _idle.add(connection);
    connection.startTimer();
    _checkPending();
  }

  void connectionClosed(_HttpClientConnection connection) {
    assert(!_active.contains(connection) || !_idle.contains(connection));
    _active.remove(connection);
    _idle.remove(connection);
    _checkPending();
  }

  void close(bool force) {
    // Always cancel pending socket connections.
    for (ConnectionTask<Socket> task in _socketTasks.toList()) {
      // Make sure the socket is destroyed if the ConnectionTask is cancelled.
      task.socket.then<void>((s) {
        s.destroy();
      }, onError: (e) {});

      task.cancel();
    }

    if (force) {
      for (_HttpClientConnection connection in _idle.toList()) {
        connection.destroyFromExternal();
      }

      for (_HttpClientConnection connection in _active.toList()) {
        connection.destroyFromExternal();
      }
    } else {
      for (_HttpClientConnection connection in _idle.toList()) {
        connection.closeFromExternal();
      }
    }
  }

  Future<_ConnectionInfo> connect(
    Uri uri,
    String uriHost,
    int uriPort,
    _Proxy proxy,
    _HttpClient client,
    _HttpProfileData? profileData,
  ) {
    if (hasIdle) {
      _HttpClientConnection connection = takeIdle();
      client._connectionsChanged();
      return Future.value(_ConnectionInfo(connection, proxy));
    }

    int? maxConnectionsPerHost = client.maxConnectionsPerHost;

    if (maxConnectionsPerHost != null &&
        _active.length + _connecting >= maxConnectionsPerHost) {
      Completer<_ConnectionInfo> completer = Completer<_ConnectionInfo>();

      _pending.add(() {
        completer.complete(
          connect(uri, uriHost, uriPort, proxy, client, profileData),
        );
      });

      return completer.future;
    }

    BadCertificateCallback? currentBadCertificateCallback =
        client._badCertificateCallback;

    bool callback(X509Certificate certificate) {
      if (currentBadCertificateCallback == null) {
        return false;
      }

      return currentBadCertificateCallback(certificate, uriHost, uriPort);
    }

    Future<ConnectionTask<Socket>> connectionTask;
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)?
    connectionFactory = this.connectionFactory;

    if (connectionFactory != null) {
      if (proxy.isDirect) {
        connectionTask = connectionFactory(uri, null, null);
      } else {
        connectionTask = connectionFactory(uri, host, port);
      }
    } else {
      connectionTask =
          (isSecure && proxy.isDirect
              ? SecureSocket.startConnect(
                host,
                port,
                context: context,
                onBadCertificate: callback,
                keyLog: client._keyLog,
              )
              : Socket.startConnect(host, port));
    }

    _connecting++;

    return connectionTask.then<_ConnectionInfo>(
      (task) {
        _socketTasks.add(task);

        Future<Socket> socketFuture = task.socket;
        Duration? connectionTimeout = client.connectionTimeout;

        if (connectionTimeout != null) {
          socketFuture = socketFuture.timeout(connectionTimeout);
        }

        return socketFuture.then<_ConnectionInfo>(
          (socket) {
            _connecting--;

            if (socket.address.type != InternetAddressType.unix) {
              socket.setOption(SocketOption.tcpNoDelay, true);
            }

            _HttpClientConnection connection = _HttpClientConnection(
              key,
              socket,
              client,
              false,
              context,
            );

            if (isSecure && !proxy.isDirect) {
              connection._dispose = true;

              return connection
                  .createProxyTunnel(
                    uriHost,
                    uriPort,
                    proxy,
                    callback,
                    profileData,
                  )
                  .then<_ConnectionInfo>((tunnel) {
                    client
                        ._getConnectionTarget(uriHost, uriPort, true)
                        .addNewActive(tunnel);
                    _socketTasks.remove(task);
                    return _ConnectionInfo(tunnel, proxy);
                  });
            } else {
              addNewActive(connection);
              _socketTasks.remove(task);
              return _ConnectionInfo(connection, proxy);
            }
          },
          onError: (Object error) {
            _connecting--;
            _socketTasks.remove(task);
            _checkPending();

            // When there is a timeout, cancel the ConnectionTask and propagate a
            // SocketException as specified by the HttpClient.connectionTimeout
            // docs.
            if (error is TimeoutException) {
              assert(connectionTimeout != null);
              task.cancel();

              throw SocketException(
                'HTTP connection timed out after $connectionTimeout, '
                'host: $host, port: $port',
              );
            }

            throw error;
          },
        );
      },
      onError: (Object error) {
        _connecting--;
        _checkPending();
        throw error;
      },
    );
  }
}

typedef BadCertificateCallback =
    bool Function(X509Certificate certificate, String host, int port);

final class _HttpClient implements HttpClient {
  _HttpClient(this._context);

  bool _closing = false;
  bool _closingForcefully = false;
  final Map<String, _ConnectionTarget> _connectionTargets =
      HashMap<String, _ConnectionTarget>();
  final List<_Credentials> _credentials = <_Credentials>[];
  final List<_ProxyCredentials> _proxyCredentials = <_ProxyCredentials>[];
  final SecurityContext? _context;
  Future<ConnectionTask<Socket>> Function(Uri, String?, int?)?
  _connectionFactory;
  Future<bool> Function(Uri, String, String?)? _authenticate;
  Future<bool> Function(String, int, String, String?)? _authenticateProxy;
  String Function(Uri)? _findProxy = HttpClient.findProxyFromEnvironment;
  Duration _idleTimeout = const Duration(seconds: 15);
  BadCertificateCallback? _badCertificateCallback;
  void Function(String line)? _keyLog;

  @override
  Duration get idleTimeout => _idleTimeout;

  @override
  Duration? connectionTimeout;

  @override
  int? maxConnectionsPerHost;

  @override
  bool autoUncompress = true;

  @override
  String? userAgent = _getHttpVersion();

  @override
  set idleTimeout(Duration timeout) {
    _idleTimeout = timeout;

    for (_ConnectionTarget target in _connectionTargets.values) {
      for (_HttpClientConnection connection in target._idle) {
        // Reset timer. This is fine, as it's not happening often.
        connection
          ..stopTimer()
          ..startTimer();
      }
    }
  }

  @override
  set badCertificateCallback(
    bool Function(X509Certificate, String, int)? badCertificateCallback,
  ) {
    _badCertificateCallback = badCertificateCallback;
  }

  @override
  set keyLog(void Function(String)? keyLog) {
    _keyLog = keyLog;
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) {
    const int hashMark = 0x23;
    const int questionMark = 0x3f;

    int fragmentStart = path.length;
    int queryStart = path.length;

    for (int i = path.length - 1; i >= 0; i--) {
      int char = path.codeUnitAt(i);

      if (char == hashMark) {
        fragmentStart = i;
        queryStart = i;
      } else if (char == questionMark) {
        queryStart = i;
      }
    }

    String? query;

    if (queryStart < fragmentStart) {
      query = path.substring(queryStart + 1, fragmentStart);
      path = path.substring(0, queryStart);
    }

    Uri uri = Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: path,
      query: query,
    );

    return _openUrl(method, uri);
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    return _openUrl(method, url);
  }

  @override
  Future<HttpClientRequest> get(String host, int port, String path) {
    return open('get', host, port, path);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    return _openUrl('get', url);
  }

  @override
  Future<HttpClientRequest> post(String host, int port, String path) {
    return open('post', host, port, path);
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    return _openUrl('post', url);
  }

  @override
  Future<HttpClientRequest> put(String host, int port, String path) {
    return open('put', host, port, path);
  }

  @override
  Future<HttpClientRequest> putUrl(Uri url) {
    return _openUrl('put', url);
  }

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) {
    return open('delete', host, port, path);
  }

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) {
    return _openUrl('delete', url);
  }

  @override
  Future<HttpClientRequest> head(String host, int port, String path) {
    return open('head', host, port, path);
  }

  @override
  Future<HttpClientRequest> headUrl(Uri url) {
    return _openUrl('head', url);
  }

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) {
    return open('patch', host, port, path);
  }

  @override
  Future<HttpClientRequest> patchUrl(Uri url) {
    return _openUrl('patch', url);
  }

  @override
  void close({bool force = false}) {
    _closing = true;
    _closingForcefully = force;
    _closeConnections(_closingForcefully);
    assert(!_connectionTargets.values.any((target) => target.hasIdle));
    assert(
      !force ||
          !_connectionTargets.values.any((target) => target._active.isNotEmpty),
    );
  }

  @override
  set authenticate(Future<bool> Function(Uri, String, String?)? authenticate) {
    _authenticate = authenticate;
  }

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) {
    _credentials.add(
      _SiteCredentials(url, realm, credentials as _HttpClientCredentials),
    );
  }

  @override
  set authenticateProxy(
    Future<bool> Function(String, int, String, String?)? authenticateProxy,
  ) {
    _authenticateProxy = authenticateProxy;
  }

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) {
    _proxyCredentials.add(
      _ProxyCredentials(
        host,
        port,
        realm,
        credentials as _HttpClientCredentials,
      ),
    );
  }

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)?
    connectionFactory,
  ) {
    _connectionFactory = connectionFactory;
  }

  @override
  set findProxy(String Function(Uri)? findProxy) {
    _findProxy = findProxy;
  }

  bool _isValidToken(String token) {
    // from https://www.rfc-editor.org/rfc/rfc2616#page-15
    //
    // CTL            = <any US-ASCII control character
    //                  (octets 0 - 31) and DEL (127)>
    // separators     = "(" | ")" | "<" | ">" | "@"
    //                | "," | ";" | ":" | "\" | <">
    //                | "/" | "[" | "]" | "?" | "="
    //                | "{" | "}" | SP | HT
    // token          = 1*<any CHAR except CTLs or separators>
    const String _validChars =
        '                                '
        r" ! #$%&'  *+ -. 0123456789      "
        ' ABCDEFGHIJKLMNOPQRSTUVWXYZ   ^_'
        '`abcdefghijklmnopqrstuvwxyz | ~ ';

    for (int codeUnit in token.codeUnits) {
      if (codeUnit >= _validChars.length ||
          _validChars.codeUnitAt(codeUnit) == 0x20) {
        return false;
      }
    }

    return true;
  }

  Future<_HttpClientRequest> _openUrl(String method, Uri uri) {
    if (_closing) {
      throw StateError('Client is closed');
    }

    // Ignore any fragments on the request URI.
    uri = uri.removeFragment();

    // from https://www.rfc-editor.org/rfc/rfc2616#page-35
    if (!_isValidToken(method)) {
      throw ArgumentError.value(method, 'method');
    }

    if (method != 'CONNECT') {
      if (uri.host.isEmpty) {
        throw ArgumentError('No host specified in URI $uri');
      }

      if (_connectionFactory == null &&
          !uri.isScheme('http') &&
          !uri.isScheme('https')) {
        throw ArgumentError("Unsupported scheme '${uri.scheme}' in URI $uri");
      }
    }

    _httpConnectionHook(uri);

    bool isSecure = uri.isScheme('https');

    int port = uri.port;

    if (port == 0) {
      port =
          isSecure ? HttpClient.defaultHttpsPort : HttpClient.defaultHttpPort;
    }

    // Check to see if a proxy server should be used for this connection.
    _ProxyConfiguration proxyConf = const _ProxyConfiguration.direct();
    String Function(Uri)? findProxy = _findProxy;

    if (findProxy != null) {
      // TODO(sgjesse): Keep a map of these as normally only a few
      // configuration strings will be used.
      try {
        proxyConf = _ProxyConfiguration(findProxy(uri));
      } catch (error, stackTrace) {
        return Future.error(error, stackTrace);
      }
    }

    _HttpProfileData? profileData;

    if (HttpClient.enableTimelineLogging &&
        !const bool.fromEnvironment('dart.vm.product')) {
      profileData = HttpProfiler.startRequest(method, uri);
    }

    return _getConnection(
      uri,
      uri.host,
      port,
      proxyConf,
      isSecure,
      profileData,
    ).then<_HttpClientRequest>(
      (info) {
        _HttpClientRequest send(_ConnectionInfo info) {
          profileData?.requestEvent('Connection established');
          return info.connection.send(
            uri,
            port,
            method.toUpperCase(),
            info.proxy,
            profileData,
          );
        }

        // If the connection was closed before the request was sent, create
        // and use another connection.
        if (info.connection.closed) {
          return _getConnection(
            uri,
            uri.host,
            port,
            proxyConf,
            isSecure,
            profileData,
          ).then(send);
        }

        return send(info);
      },
      onError: (Object error) {
        profileData?.finishRequestWithError(error.toString());
        throw error;
      },
    );
  }

  static bool _isSubdomain(Uri subdomain, Uri domain) {
    return subdomain.isScheme(domain.scheme) &&
        subdomain.port == domain.port &&
        (subdomain.host == domain.host ||
            subdomain.host.endsWith('.${domain.host}'));
  }

  // Only visible for testing.
  static bool shouldCopyHeaderOnRedirect(
    String headerKey,
    Uri originalUrl,
    Uri redirectUri,
  ) {
    if (_isSubdomain(redirectUri, originalUrl)) {
      return true;
    }

    const List<String> nonRedirectHeaders = <String>[
      'authorization',
      'www-authenticate',
      'cookie',
      'cookie2',
    ];

    return !nonRedirectHeaders.contains(headerKey.toLowerCase());
  }

  Future<_HttpClientRequest> _openUrlFromRequest(
    String method,
    Uri uri,
    _HttpClientRequest previous, {
    required bool isRedirect,
  }) {
    // If the new URI is relative (to either '/' or some sub-path),
    // construct a full URI from the previous one.
    Uri resolved = previous.uri.resolveUri(uri);

    return _openUrl(method, resolved).then<_HttpClientRequest>((request) {
      request
        // Only follow redirects if initial request did.
        ..followRedirects = previous.followRedirects
        // Allow same number of redirects.
        ..maxRedirects = previous.maxRedirects;

      // Copy headers.
      for (String header in previous.headers._headers.keys) {
        if (request.headers[header] == null &&
            (!isRedirect ||
                shouldCopyHeaderOnRedirect(header, resolved, previous.uri))) {
          request.headers.set(header, previous.headers[header]!);
        }
      }

      return request
        ..headers.chunkedTransferEncoding = false
        ..contentLength = 0;
    });
  }

  // Return a live connection to the idle pool.
  void _returnConnection(_HttpClientConnection connection) {
    _connectionTargets[connection.key]!.returnConnection(connection);
    _connectionsChanged();
  }

  // Remove a closed connection from the active set.
  void _connectionClosed(_HttpClientConnection connection) {
    connection.stopTimer();

    _ConnectionTarget? connectionTarget = _connectionTargets[connection.key];

    if (connectionTarget != null) {
      connectionTarget.connectionClosed(connection);

      if (connectionTarget.isEmpty) {
        _connectionTargets.remove(connection.key);
      }

      _connectionsChanged();
    }
  }

  // Remove a closed connection and not issue _closeConnections(). If the close
  // is signaled from user by calling close(), _closeConnections() was called
  // and prevent further calls.
  void _connectionClosedNoFurtherClosing(_HttpClientConnection connection) {
    connection.stopTimer();

    _ConnectionTarget? connectionTarget = _connectionTargets[connection.key];

    if (connectionTarget != null) {
      connectionTarget.connectionClosed(connection);

      if (connectionTarget.isEmpty) {
        _connectionTargets.remove(connection.key);
      }
    }
  }

  void _connectionsChanged() {
    if (_closing) {
      _closeConnections(_closingForcefully);
    }
  }

  void _closeConnections(bool force) {
    for (_ConnectionTarget connectionTarget
        in _connectionTargets.values.toList()) {
      connectionTarget.close(force);
    }
  }

  _ConnectionTarget _getConnectionTarget(String host, int port, bool isSecure) {
    String key = _HttpClientConnection.makeKey(isSecure, host, port);

    return _connectionTargets.putIfAbsent(key, () {
      return _ConnectionTarget(
        key,
        host,
        port,
        isSecure,
        _context,
        _connectionFactory,
      );
    });
  }

  // Get a new _HttpClientConnection, from the matching _ConnectionTarget.
  Future<_ConnectionInfo> _getConnection(
    Uri uri,
    String uriHost,
    int uriPort,
    _ProxyConfiguration proxyConf,
    bool isSecure,
    _HttpProfileData? profileData,
  ) {
    Iterator<_Proxy> proxies = proxyConf.proxies.iterator;

    Future<_ConnectionInfo> connect(Object error, StackTrace stackTrace) {
      if (!proxies.moveNext()) {
        return Future.error(error, stackTrace);
      }

      _Proxy proxy = proxies.current;
      String host = proxy.isDirect ? uriHost : proxy.host!;
      int port = proxy.isDirect ? uriPort : proxy.port!;

      return _getConnectionTarget(host, port, isSecure)
          .connect(uri, uriHost, uriPort, proxy, this, profileData)
          // On error, continue with next proxy.
          .catchError(connect);
    }

    return connect(HttpException('No proxies given'), StackTrace.current);
  }

  _SiteCredentials? _findCredentials(Uri url, [_AuthenticationScheme? scheme]) {
    // Look for credentials.
    _SiteCredentials? credentials = _credentials.fold(null, (previuos, value) {
      _SiteCredentials siteCredentials = value as _SiteCredentials;

      if (siteCredentials.applies(url, scheme)) {
        if (previuos == null) {
          return value;
        }

        return siteCredentials.uri.path.length > previuos.uri.path.length
            ? siteCredentials
            : previuos;
      }

      return previuos;
    });

    return credentials;
  }

  _ProxyCredentials? _findProxyCredentials(
    _Proxy proxy, [
    _AuthenticationScheme? scheme,
  ]) {
    // Look for credentials.
    for (_ProxyCredentials current in _proxyCredentials) {
      if (current.applies(proxy, scheme)) {
        return current;
      }
    }

    return null;
  }

  void _removeCredentials(_Credentials cr) {
    int index = _credentials.indexOf(cr);

    if (index != -1) {
      _credentials.removeAt(index);
    }
  }

  void _removeProxyCredentials(_Credentials cr) {
    _proxyCredentials.remove(cr);
  }

  static String _findProxyFromEnvironment(
    Uri url,
    Map<String, String>? environment,
  ) {
    String? checkNoProxy(String? option) {
      if (option == null) {
        return null;
      }

      Iterator<String> names = option.split(',').map((s) => s.trim()).iterator;

      while (names.moveNext()) {
        String name = names.current;

        if ((name.startsWith('[') &&
                name.endsWith(']') &&
                '[${url.host}]' == name) ||
            (name.isNotEmpty && url.host.endsWith(name))) {
          return 'DIRECT';
        }
      }

      return null;
    }

    String? checkProxy(String? option) {
      if (option == null) {
        return null;
      }

      option = option.trim();

      if (option.isEmpty) {
        return null;
      }

      int position = option.indexOf('://');

      if (position >= 0) {
        option = option.substring(position + 3);
      }

      position = option.indexOf('/');

      if (position >= 0) {
        option = option.substring(0, position);
      }

      // Add default port if no port configured.
      if (option.indexOf('[') == 0) {
        int position = option.lastIndexOf(':');

        if (option.indexOf(']') > position) {
          option = '$option:1080';
        }
      } else {
        if (!option.contains(':')) {
          option = '$option:1080';
        }
      }

      return 'PROXY $option';
    }

    // Default to using the process current environment.
    environment ??= _platformEnvironmentCache;

    String? proxyCfg;

    String? noProxy = environment['no_proxy'] ?? environment['NO_PROXY'];
    proxyCfg = checkNoProxy(noProxy);

    if (proxyCfg != null) {
      return proxyCfg;
    }

    if (url.isScheme('http')) {
      String? proxy = environment['http_proxy'] ?? environment['HTTP_PROXY'];
      proxyCfg = checkProxy(proxy);

      if (proxyCfg != null) {
        return proxyCfg;
      }
    } else if (url.isScheme('https')) {
      String? proxy = environment['https_proxy'] ?? environment['HTTPS_PROXY'];
      proxyCfg = checkProxy(proxy);

      if (proxyCfg != null) {
        return proxyCfg;
      }
    }

    return 'DIRECT';
  }

  static final Map<String, String> _platformEnvironmentCache =
      Platform.environment;
}

final class _HttpConnection extends LinkedListEntry<_HttpConnection>
    with _ServiceObject {
  static const int _active = 0;
  static const int _idle = 1;
  static const int _closing = 2;
  static const int _detached = 3;

  // Use HashMap, as we don't need to keep order.
  static final Map<int, _HttpConnection> _connections =
      HashMap<int, _HttpConnection>();

  _HttpConnection(this._socket, this._httpServer)
    : _httpParser = _HttpParser.requestParser() {
    _connections[_serviceId] = this;
    _httpParser.listenToStream(_socket);

    _subscription = _httpParser.listen(
      (incoming) {
        _httpServer._markActive(this);

        // If the incoming was closed, close the connection.
        incoming.dataDone.then<void>((closing) {
          if (closing) {
            destroy();
          }
        });

        // Only handle one incoming request at the time. Keep the
        // stream paused until the request has been send.
        _subscription!.pause();
        _state = _active;

        _HttpOutgoing outgoing = _HttpOutgoing(_socket);

        _HttpResponse response = _HttpResponse(
          incoming.uri!,
          incoming.headers.protocolVersion,
          outgoing,
          _httpServer.defaultResponseHeaders,
          _httpServer.serverHeader,
        );

        // Parser found badRequest and sent out Response.
        if (incoming.statusCode == HttpStatus.badRequest) {
          response.statusCode = HttpStatus.badRequest;
        }

        _HttpRequest request = _HttpRequest(
          response,
          incoming,
          _httpServer,
          this,
        );

        _streamFuture = outgoing.done.then<void>(
          (_) {
            response.deadline = null;

            if (_state == _detached) {
              return;
            }

            if (response.persistentConnection &&
                request.persistentConnection &&
                incoming.fullBodyRead &&
                !_httpParser.upgrade &&
                !_httpServer.closed) {
              _state = _idle;
              _idleMark = false;
              _httpServer._markIdle(this);

              // Resume the subscription for incoming requests as the
              // request is now processed.
              _subscription!.resume();
            } else {
              // Close socket, keep-alive not used or body sent before
              // received data was handled.
              destroy();
            }
          },
          onError: (Object _) {
            destroy();
          },
        );

        outgoing.ignoreBody = request.method == 'HEAD';
        response._httpRequest = request;
        _httpServer._handleRequest(request);
      },
      onDone: destroy,
      onError: (Object _) {
        // Ignore failed requests that was closed before headers was received.
        destroy();
      },
    );
  }

  final Socket _socket;
  final _HttpServer _httpServer;
  final _HttpParser _httpParser;
  int _state = _idle;
  StreamSubscription<_HttpIncoming>? _subscription;
  bool _idleMark = false;
  Future<void>? _streamFuture;

  void markIdle() {
    _idleMark = true;
  }

  bool get isMarkedIdle {
    return _idleMark;
  }

  void destroy() {
    if (_state == _closing || _state == _detached) {
      return;
    }

    _state = _closing;
    _socket.destroy();
    _httpServer._connectionClosed(this);
    _connections.remove(_serviceId);
  }

  Future<Socket> detachSocket() {
    _state = _detached;

    // Remove connection from server.
    _httpServer._connectionClosed(this);

    _HttpDetachedIncoming detachedIncoming = _httpParser.detachIncoming();

    return _streamFuture!.then<_DetachedSocket>((_) {
      _connections.remove(_serviceId);
      return _DetachedSocket(_socket, detachedIncoming);
    });
  }

  HttpConnectionInfo? get connectionInfo {
    return _HttpConnectionInfo.create(_socket);
  }

  bool get _isActive {
    return _state == _active;
  }

  bool get _isIdle {
    return _state == _idle;
  }

  bool get _isClosing {
    return _state == _closing;
  }
}

// Common interface of [ServerSocket] and [SecureServerSocket] used by
// [_HttpServer].
abstract interface class ServerSocketBase<T extends Socket>
    implements Stream<T> {
  int get port;

  InternetAddress get address;

  Future<void> close();
}

// HTTP server waiting for socket connections.
class _HttpServer extends Stream<HttpRequest>
    with _ServiceObject
    implements HttpServer {
  // Use default Map so we keep order.
  static final Map<int, _HttpServer> _servers = <int, _HttpServer>{};

  _HttpServer._(this._serverSocket, this._closeServer)
    : _controller = StreamController<HttpRequest>(sync: true) {
    _controller.onCancel = close;
    idleTimeout = const Duration(seconds: 120);
    _servers[_serviceId] = this;
  }

  _HttpServer.listenOn(this._serverSocket)
    : _closeServer = false,
      _controller = StreamController<HttpRequest>(sync: true) {
    _controller.onCancel = close;
    idleTimeout = const Duration(seconds: 120);
    _servers[_serviceId] = this;
  }

  @override
  String? serverHeader;
  @override
  final HttpHeaders defaultResponseHeaders = _initDefaultResponseHeaders();
  @override
  bool autoCompress = false;

  Duration? _idleTimeout;
  Timer? _idleTimer;

  static Future<HttpServer> bind(
    Object address,
    int port,
    int backlog,
    bool v6Only,
    bool shared,
  ) {
    return ServerSocket.bind(
      address,
      port,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
    ).then<HttpServer>((socket) {
      return _HttpServer._(socket, true);
    });
  }

  static Future<HttpServer> bindSecure(
    Object address,
    int port,
    SecurityContext? context,
    int backlog,
    bool v6Only,
    bool requestClientCertificate,
    bool shared,
  ) {
    return SecureServerSocket.bind(
      address,
      port,
      context,
      backlog: backlog,
      v6Only: v6Only,
      requestClientCertificate: requestClientCertificate,
      shared: shared,
    ).then<HttpServer>((socket) {
      return _HttpServer._(socket, true);
    });
  }

  static HttpHeaders _initDefaultResponseHeaders() {
    _HttpHeaders defaultResponseHeaders = _HttpHeaders('1.1');
    defaultResponseHeaders.contentType = ContentType.text;
    defaultResponseHeaders.set('X-Frame-Options', 'SAMEORIGIN');
    defaultResponseHeaders.set('X-Content-Type-Options', 'nosniff');
    defaultResponseHeaders.set('X-XSS-Protection', '1; mode=block');
    return defaultResponseHeaders;
  }

  @override
  Duration? get idleTimeout {
    return _idleTimeout;
  }

  @override
  set idleTimeout(Duration? duration) {
    Timer? idleTimer = _idleTimer;

    if (idleTimer != null) {
      idleTimer.cancel();
      _idleTimer = null;
    }

    _idleTimeout = duration;

    if (duration != null) {
      _idleTimer = Timer.periodic(duration, (_) {
        for (_HttpConnection connection in _idleConnections.toList()) {
          if (connection.isMarkedIdle) {
            connection.destroy();
          } else {
            connection.markIdle();
          }
        }
      });
    }
  }

  @override
  StreamSubscription<HttpRequest> listen(
    void Function(HttpRequest event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    (_serverSocket as Stream<Socket>).listen(
      (socket) {
        if (socket.address.type != InternetAddressType.unix) {
          socket.setOption(SocketOption.tcpNoDelay, true);
        }

        // Accept the client connection.
        _HttpConnection connection = _HttpConnection(socket, this);
        _idleConnections.add(connection);
      },
      onError: (Object error, StackTrace stackTrace) {
        // Ignore HandshakeExceptions as they are bound to a single request,
        // and are not fatal for the server.
        if (error is! HandshakeException) {
          _controller.addError(error, stackTrace);
        }
      },
      onDone: _controller.close,
    );

    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<void> close({bool force = false}) {
    closed = true;

    Future<void> result;

    if (_closeServer) {
      result = _serverSocket.close() as Future;
    } else {
      result = Future<void>.value();
    }

    idleTimeout = null;

    if (force) {
      for (_HttpConnection connection in _activeConnections.toList()) {
        connection.destroy();
      }

      assert(_activeConnections.isEmpty);
    }

    for (_HttpConnection connection in _idleConnections.toList()) {
      connection.destroy();
    }

    _maybePerformCleanup();
    return result;
  }

  void _maybePerformCleanup() {
    _HttpSessionManager? sessionManager = _sessionManagerInstance;

    if (closed &&
        _idleConnections.isEmpty &&
        _activeConnections.isEmpty &&
        sessionManager != null) {
      sessionManager.close();
      _sessionManagerInstance = null;
      _servers.remove(_serviceId);
    }
  }

  @override
  int get port {
    if (closed) {
      throw HttpException('HttpServer is not bound to a socket');
    }

    return _serverSocket.port as int;
  }

  @override
  InternetAddress get address {
    if (closed) {
      throw HttpException('HttpServer is not bound to a socket');
    }

    return _serverSocket.address as InternetAddress;
  }

  @override
  set sessionTimeout(int timeout) {
    _sessionManager.sessionTimeout = timeout;
  }

  void _handleRequest(_HttpRequest request) {
    if (!closed) {
      _controller.add(request);
    } else {
      request._httpConnection.destroy();
    }
  }

  void _connectionClosed(_HttpConnection connection) {
    // Remove itself from either idle or active connections.
    connection.unlink();
    _maybePerformCleanup();
  }

  void _markIdle(_HttpConnection connection) {
    _activeConnections.remove(connection);
    _idleConnections.add(connection);
  }

  void _markActive(_HttpConnection connection) {
    _idleConnections.remove(connection);
    _activeConnections.add(connection);
  }

  // Lazy init.
  _HttpSessionManager get _sessionManager {
    return _sessionManagerInstance ??= _HttpSessionManager();
  }

  @override
  HttpConnectionsInfo connectionsInfo() {
    HttpConnectionsInfo result = HttpConnectionsInfo();
    result.total = _activeConnections.length + _idleConnections.length;

    for (_HttpConnection connection in _activeConnections) {
      if (connection._isActive) {
        result.active++;
      } else {
        assert(connection._isClosing);
        result.closing++;
      }
    }

    for (_HttpConnection connection in _idleConnections) {
      result.idle++;
      assert(connection._isIdle);
    }

    return result;
  }

  _HttpSessionManager? _sessionManagerInstance;

  // Indicated if the http server has been closed.
  bool closed = false;

  final /* ServerSocketBase */ dynamic _serverSocket;
  final bool _closeServer;

  // Set of currently connected clients.
  final LinkedList<_HttpConnection> _activeConnections =
      LinkedList<_HttpConnection>();
  final LinkedList<_HttpConnection> _idleConnections =
      LinkedList<_HttpConnection>();
  final StreamController<HttpRequest> _controller;
}

final class _ProxyConfiguration {
  static const String proxyPrefix = 'PROXY ';
  static const String directPrefix = 'DIRECT';

  _ProxyConfiguration(String configuration) : proxies = <_Proxy>[] {
    List<String> list = configuration.split(';');

    for (String proxy in list) {
      proxy = proxy.trim();

      if (proxy.isNotEmpty) {
        if (proxy.startsWith(proxyPrefix)) {
          String? username;
          String? password;

          // Skip the "PROXY " prefix.
          proxy = proxy.substring(proxyPrefix.length).trim();

          // Look for proxy authentication.
          int at = proxy.lastIndexOf('@');

          if (at != -1) {
            String userinfo = proxy.substring(0, at).trim();
            proxy = proxy.substring(at + 1).trim();

            int colon = userinfo.indexOf(':');

            if (colon == -1 || colon == 0 || colon == proxy.length - 1) {
              throw HttpException('Invalid proxy configuration $configuration');
            }

            username = userinfo.substring(0, colon).trim();
            password = userinfo.substring(colon + 1).trim();
          }

          // Look for proxy host and port.
          int colon = proxy.lastIndexOf(':');

          if (colon == -1 || colon == 0 || colon == proxy.length - 1) {
            throw HttpException('Invalid proxy configuration $configuration');
          }

          String host = proxy.substring(0, colon).trim();

          if (host.startsWith('[') && host.endsWith(']')) {
            host = host.substring(1, host.length - 1);
          }

          String portString = proxy.substring(colon + 1).trim();
          int port;

          try {
            port = int.parse(portString);
          } on FormatException {
            throw HttpException(
              'Invalid proxy configuration $configuration, '
              "invalid port '$portString'",
            );
          }

          proxies.add(_Proxy(host, port, username, password));
        } else if (proxy.trim() == directPrefix) {
          proxies.add(_Proxy.direct());
        } else {
          throw HttpException('Invalid proxy configuration $configuration');
        }
      }
    }
  }

  const _ProxyConfiguration.direct()
    : proxies = const <_Proxy>[_Proxy.direct()];

  final List<_Proxy> proxies;
}

final class _Proxy {
  const _Proxy(String this.host, int this.port, this.username, this.password)
    : isDirect = false;

  const _Proxy.direct()
    : host = null,
      port = null,
      username = null,
      password = null,
      isDirect = true;

  final String? host;
  final int? port;
  final String? username;
  final String? password;
  final bool isDirect;

  bool get isAuthenticated {
    return username != null;
  }
}

final class _HttpConnectionInfo implements HttpConnectionInfo {
  _HttpConnectionInfo(this.remoteAddress, this.remotePort, this.localPort);

  @override
  InternetAddress remoteAddress;
  @override
  int remotePort;
  @override
  int localPort;

  static _HttpConnectionInfo? create(Socket socket) {
    try {
      return _HttpConnectionInfo(
        socket.remoteAddress,
        socket.remotePort,
        socket.port,
      );
    } catch (e) {
      // ...
    }

    return null;
  }
}

final class _DetachedSocket extends Stream<Uint8List> implements Socket {
  _DetachedSocket(this._socket, this._incoming);

  final Stream<Uint8List> _incoming;
  final Socket _socket;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _incoming.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Encoding get encoding {
    return _socket.encoding;
  }

  @override
  set encoding(Encoding value) {
    _socket.encoding = value;
  }

  @override
  void write(Object? object) {
    _socket.write(object);
  }

  @override
  void writeln([Object? object = '']) {
    _socket.writeln(object);
  }

  @override
  void writeCharCode(int charCode) {
    _socket.writeCharCode(charCode);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _socket.writeAll(objects, separator);
  }

  @override
  void add(List<int> bytes) {
    _socket.add(bytes);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _socket.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    return _socket.addStream(stream);
  }

  @override
  void destroy() {
    _socket.destroy();
  }

  @override
  Future<void> flush() {
    return _socket.flush();
  }

  @override
  Future<void> close() {
    return _socket.close();
  }

  @override
  Future<void> get done {
    return _socket.done;
  }

  @override
  int get port {
    return _socket.port;
  }

  @override
  InternetAddress get address {
    return _socket.address;
  }

  @override
  InternetAddress get remoteAddress {
    return _socket.remoteAddress;
  }

  @override
  int get remotePort {
    return _socket.remotePort;
  }

  @override
  bool setOption(SocketOption option, bool enabled) {
    return _socket.setOption(option, enabled);
  }

  @override
  Uint8List getRawOption(RawSocketOption option) {
    return _socket.getRawOption(option);
  }

  @override
  void setRawOption(RawSocketOption option) {
    _socket.setRawOption(option);
  }
}

final class _AuthenticationScheme {
  const _AuthenticationScheme(this._scheme);

  factory _AuthenticationScheme.fromString(String scheme) {
    if (scheme.toLowerCase() == 'basic') {
      return basic;
    }
    if (scheme.toLowerCase() == 'digest') {
      return digest;
    }
    return unknown;
  }

  // ignore: unused_field
  final int _scheme;

  static const _AuthenticationScheme unknown = _AuthenticationScheme(-1);
  static const _AuthenticationScheme basic = _AuthenticationScheme(0);
  static const _AuthenticationScheme digest = _AuthenticationScheme(1);

  @override
  String toString() {
    if (this == basic) {
      return 'Basic';
    }

    if (this == digest) {
      return 'Digest';
    }

    return 'Unknown';
  }
}

abstract base class _Credentials {
  _Credentials(this.credentials, this.realm) {
    if (credentials.scheme == _AuthenticationScheme.digest) {
      // Calculate the H(A1) value once. There is no mentioning of
      // username/password encoding in RFC 2617. However there is an
      // open draft for adding an additional accept-charset parameter to
      // the WWW-Authenticate and Proxy-Authenticate headers, see
      // http://tools.ietf.org/html/draft-reschke-basicauth-enc-06. For
      // now always use UTF-8 encoding.
      var creds = credentials as _HttpClientDigestCredentials;
      var hasher =
          _MD5()
            ..add(utf8.encode(creds.username))
            ..add([_CharCode.colon])
            ..add(realm.codeUnits)
            ..add([_CharCode.colon])
            ..add(utf8.encode(creds.password));
      ha1 = _CryptoUtils.bytesToHex(hasher.close());
    }
  }

  _HttpClientCredentials credentials;
  String realm;
  bool used = false;

  // Digest specific fields.
  String? ha1;
  String? nonce;
  String? algorithm;
  String? qop;
  int? nonceCount;

  _AuthenticationScheme get scheme {
    return credentials.scheme;
  }

  void authorize(HttpClientRequest request);
}

final class _SiteCredentials extends _Credentials {
  Uri uri;

  _SiteCredentials(this.uri, String realm, _HttpClientCredentials creds)
    : super(creds, realm);

  bool applies(Uri uri, _AuthenticationScheme? scheme) {
    if (scheme != null && credentials.scheme != scheme) {
      return false;
    }

    if (uri.host != this.uri.host) {
      return false;
    }

    int thisPort =
        this.uri.port == 0 ? HttpClient.defaultHttpPort : this.uri.port;

    int otherPort = uri.port == 0 ? HttpClient.defaultHttpPort : uri.port;

    if (otherPort != thisPort) {
      return false;
    }

    return uri.path.startsWith(this.uri.path);
  }

  @override
  void authorize(HttpClientRequest request) {
    // Digest credentials cannot be used without a nonce from the
    // server.
    if (credentials.scheme == _AuthenticationScheme.digest && nonce == null) {
      return;
    }

    credentials.authorize(this, request as _HttpClientRequest);
    used = true;
  }
}

final class _ProxyCredentials extends _Credentials {
  _ProxyCredentials(
    this.host,
    this.port,
    String realm,
    _HttpClientCredentials creds,
  ) : super(creds, realm);

  String host;
  int port;

  bool applies(_Proxy proxy, _AuthenticationScheme? scheme) {
    if (scheme != null && credentials.scheme != scheme) {
      return false;
    }

    return proxy.host == host && proxy.port == port;
  }

  @override
  void authorize(HttpClientRequest request) {
    // Digest credentials cannot be used without a nonce from the
    // server.
    if (credentials.scheme == _AuthenticationScheme.digest && nonce == null) {
      return;
    }

    credentials.authorizeProxy(this, request as _HttpClientRequest);
  }
}

abstract interface class _HttpClientCredentials
    implements HttpClientCredentials {
  _AuthenticationScheme get scheme;

  void authorize(_Credentials credentials, _HttpClientRequest request);

  void authorizeProxy(_ProxyCredentials credentials, HttpClientRequest request);
}

final class _HttpClientBasicCredentials extends _HttpClientCredentials
    implements HttpClientBasicCredentials {
  _HttpClientBasicCredentials(this.username, this.password);

  String username;
  String password;

  @override
  _AuthenticationScheme get scheme {
    return _AuthenticationScheme.basic;
  }

  String authorization() {
    // There is no mentioning of username/password encoding in RFC
    // 2617. However there is an open draft for adding an additional
    // accept-charset parameter to the WWW-Authenticate and
    // Proxy-Authenticate headers, see
    // http://tools.ietf.org/html/draft-reschke-basicauth-enc-06. For
    // now always use UTF-8 encoding.
    String auth = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $auth';
  }

  @override
  void authorize(_Credentials _, HttpClientRequest request) {
    request.headers.set(HttpHeaders.authorizationHeader, authorization());
  }

  @override
  void authorizeProxy(_ProxyCredentials _, HttpClientRequest request) {
    request.headers.set(HttpHeaders.proxyAuthorizationHeader, authorization());
  }
}

final class _HttpClientDigestCredentials extends _HttpClientCredentials
    implements HttpClientDigestCredentials {
  _HttpClientDigestCredentials(this.username, this.password);

  String username;
  String password;

  @override
  _AuthenticationScheme get scheme {
    return _AuthenticationScheme.digest;
  }

  String authorization(_Credentials credentials, _HttpClientRequest request) {
    String requestUri = request._requestUri();
    _MD5 hasher =
        _MD5()
          ..add(request.method.codeUnits)
          ..add([_CharCode.colon])
          ..add(requestUri.codeUnits);

    String ha2 = _CryptoUtils.bytesToHex(hasher.close());

    bool isAuth = false;
    String cnonce = '';
    String nc = '';

    hasher =
        _MD5()
          ..add(credentials.ha1!.codeUnits)
          ..add([_CharCode.colon]);

    if (credentials.qop == 'auth') {
      isAuth = true;
      cnonce = _CryptoUtils.bytesToHex(_CryptoUtils.getRandomBytes(4));

      int nonceCount = credentials.nonceCount! + 1;
      credentials.nonceCount = nonceCount;
      nc = nonceCount.toRadixString(16).padLeft(9, '0');

      hasher
        ..add(credentials.nonce!.codeUnits)
        ..add([_CharCode.colon])
        ..add(nc.codeUnits)
        ..add([_CharCode.colon])
        ..add(cnonce.codeUnits)
        ..add([_CharCode.colon])
        ..add('auth'.codeUnits)
        ..add([_CharCode.colon])
        ..add(ha2.codeUnits);
    } else {
      hasher
        ..add(credentials.nonce!.codeUnits)
        ..add([_CharCode.colon])
        ..add(ha2.codeUnits);
    }

    String response = _CryptoUtils.bytesToHex(hasher.close());

    StringBuffer buffer =
        StringBuffer()
          ..write('Digest ')
          ..write('username="$username"')
          ..write(', realm="${credentials.realm}"')
          ..write(', nonce="${credentials.nonce}"')
          ..write(', uri="$requestUri"')
          ..write(', algorithm="${credentials.algorithm}"');

    if (isAuth) {
      buffer
        ..write(', qop="auth"')
        ..write(', cnonce="$cnonce"')
        ..write(', nc="$nc"');
    }

    buffer.write(', response="$response"');
    return buffer.toString();
  }

  @override
  void authorize(_Credentials credentials, HttpClientRequest request) {
    request.headers.set(
      HttpHeaders.authorizationHeader,
      authorization(credentials, request as _HttpClientRequest),
    );
  }

  @override
  void authorizeProxy(
    _ProxyCredentials credentials,
    HttpClientRequest request,
  ) {
    request.headers.set(
      HttpHeaders.proxyAuthorizationHeader,
      authorization(credentials, request as _HttpClientRequest),
    );
  }
}

final class _RedirectInfo implements RedirectInfo {
  const _RedirectInfo(this.statusCode, this.method, this.location);

  @override
  final int statusCode;
  @override
  final String method;
  @override
  final Uri location;
}

String _getHttpVersion() {
  String version = Platform.version;

  // Only include major and minor version numbers.
  int index = version.indexOf('.', version.indexOf('.') + 1);
  version = version.substring(0, index);
  return 'Dart/$version (dart:io)';
}
