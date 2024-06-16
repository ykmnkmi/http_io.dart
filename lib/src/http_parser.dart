// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'http.dart';

// Global constants.
class _Const {
  // Bytes for "HTTP".
  static const http = [72, 84, 84, 80];
  // Bytes for "HTTP/1.".
  static const http1dot = [72, 84, 84, 80, 47, 49, 46];
  // Bytes for "HTTP/1.0".
  static const http10 = [72, 84, 84, 80, 47, 49, 46, 48];
  // Bytes for "HTTP/1.1".
  static const http11 = [72, 84, 84, 80, 47, 49, 46, 49];

  static const bool T = true;
  static const bool F = false;
  // Loopup-map for the following characters: '()<>@,;:\\"/[]?={} \t'.
  static const separatorMap = [
    F, F, F, F, F, F, F, F, F, T, F, F, F, F, F, F, F, F, F, F, F, F, F, F, //
    F, F, F, F, F, F, F, F, T, F, T, F, F, F, F, F, T, T, F, F, T, F, F, T, //
    F, F, F, F, F, F, F, F, F, F, T, T, T, T, T, T, T, F, F, F, F, F, F, F, //
    F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, T, T, T, F, F, //
    F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, //
    F, F, F, T, F, T, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, //
    F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, //
    F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, //
    F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, //
    F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, //
    F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F
  ];
}

// Frequently used character codes.
class _CharCode {
  static const int ht = 9;
  static const int lf = 10;
  static const int cr = 13;
  static const int sp = 32;
  static const int comma = 44;
  static const int slash = 47;
  static const int zero = 48;
  static const int one = 49;
  static const int colon = 58;
  static const int semiColon = 59;
}

// States of the HTTP parser state machine.
class _State {
  static const int start = 0;
  static const int methodOrResponseHttpVersion = 1;
  static const int responseHttpVersion = 2;
  static const int requestLineMethod = 3;
  static const int requestLineUri = 4;
  static const int requestLineHttpVersion = 5;
  static const int requestLineEnding = 6;
  static const int responseLineStatusCode = 7;
  static const int responseLineReasonPhrase = 8;
  static const int responseLineEnding = 9;
  static const int headerStart = 10;
  static const int headerField = 11;
  static const int headerValueStart = 12;
  static const int headerValue = 13;
  static const int headerValueFoldOrEndCr = 14;
  static const int headerValueFoldOrEnd = 15;
  static const int headerEnding = 16;

  static const int chunkSizeStartingCr = 17;
  static const int chunkSizeStarting = 18;
  static const int chunkSize = 19;
  static const int chunkSizeExtension = 20;
  static const int chunkSizeEnding = 21;
  static const int chunkedBodyDoneCr = 22;
  static const int chunkedBodyDone = 23;
  static const int body = 24;
  static const int closed = 25;
  static const int upgrade = 26;
  static const int failure = 27;

  static const int firstBodyState = chunkSizeStartingCr;
}

// HTTP version of the request or response being parsed.
class _HttpVersion {
  static const int undetermined = 0;
  static const int http10 = 1;
  static const int http11 = 2;
}

// States of the HTTP parser state machine.
class _MessageType {
  static const int undetermined = 0;
  static const int request = 1;
  static const int response = 0;
}

/// The _HttpDetachedStreamSubscription takes a subscription and some extra data,
/// and makes it possible to "inject" the data in from of other data events
/// from the subscription.
///
/// It does so by overriding pause/resume, so that once the
/// _HttpDetachedStreamSubscription is resumed, it'll deliver the data before
/// resuming the underlying subscription.
class _HttpDetachedStreamSubscription implements StreamSubscription<Uint8List> {
  final StreamSubscription<Uint8List> _subscription;
  Uint8List? _injectData;
  void Function(Uint8List data)? _userOnData;
  bool _isCanceled = false;
  bool _scheduled = false;
  int _pauseCount = 1;

  _HttpDetachedStreamSubscription(
      this._subscription, this._injectData, this._userOnData);

  @override
  bool get isPaused => _subscription.isPaused;

  @override
  Future<T> asFuture<T>([T? futureValue]) =>
      _subscription.asFuture<T>(futureValue as T);

  @override
  Future<void> cancel() {
    _isCanceled = true;
    _injectData = null;
    return _subscription.cancel();
  }

  @override
  void onData(void Function(Uint8List data)? handleData) {
    _userOnData = handleData;
    _subscription.onData(handleData);
  }

  @override
  void onDone(void Function()? handleDone) {
    _subscription.onDone(handleDone);
  }

  @override
  void onError(Function? handleError) {
    _subscription.onError(handleError);
  }

  @override
  void pause([Future<void>? resumeSignal]) {
    if (_injectData == null) {
      _subscription.pause(resumeSignal);
    } else {
      _pauseCount++;
      if (resumeSignal != null) {
        resumeSignal.whenComplete(resume);
      }
    }
  }

  @override
  void resume() {
    if (_injectData == null) {
      _subscription.resume();
    } else {
      _pauseCount--;
      _maybeScheduleData();
    }
  }

  void _maybeScheduleData() {
    if (_scheduled) {
      return;
    }
    if (_pauseCount != 0) {
      return;
    }
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_pauseCount > 0 || _isCanceled) {
        return;
      }
      var data = _injectData!;
      _injectData = null;
      // To ensure that 'subscription.isPaused' is false, we resume the
      // subscription here. This is fine as potential events are delayed.
      _subscription.resume();
      _userOnData?.call(data);
    });
  }
}

class _HttpDetachedIncoming extends Stream<Uint8List> {
  final StreamSubscription<Uint8List>? _subscription;
  final Uint8List? _bufferedData;

  _HttpDetachedIncoming(this._subscription, this._bufferedData);

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    var subscription = _subscription;
    if (subscription != null) {
      subscription
        ..onData(onData)
        ..onError(onError)
        ..onDone(onDone);
      if (_bufferedData == null) {
        return subscription..resume();
      }
      return _HttpDetachedStreamSubscription(
          subscription, _bufferedData, onData)
        ..resume();
    } else {
      return Stream<Uint8List>.fromIterable([_bufferedData ?? Uint8List(0)])
          .listen(onData,
              onError: onError, onDone: onDone, cancelOnError: cancelOnError);
    }
  }
}

/// HTTP parser which parses the data stream given to [consume].
///
/// If an HTTP parser error occurs, the parser will signal an error to either
/// the current _HttpIncoming or the _parser itself.
///
/// The connection upgrades (e.g. switching from HTTP/1.1 to the
/// WebSocket protocol) is handled in a special way. If connection
/// upgrade is specified in the headers, then on the callback to
/// [:responseStart:] the [:upgrade:] property on the [:HttpParser:]
/// object will be [:true:] indicating that from now on the protocol is
/// not HTTP anymore and no more callbacks will happen, that is
/// [:dataReceived:] and [:dataEnd:] are not called in this case as
/// there is no more HTTP data. After the upgrade the method
/// [:readUnparsedData:] can be used to read any remaining bytes in the
/// HTTP parser which are part of the protocol the connection is
/// upgrading to. These bytes cannot be processed by the HTTP parser
/// and should be handled according to whatever protocol is being
/// upgraded to.
class _HttpParser extends Stream<_HttpIncoming> {
  // State.
  bool _parserCalled = false;

  // The data that is currently being parsed.
  Uint8List? _buffer;
  int _index = -1;

  // Whether a HTTP request is being parsed (as opposed to a response).
  final bool _requestParser;
  int _state = _State.start;
  int? _httpVersionIndex;
  int _messageType = _MessageType.undetermined;
  int _statusCode = 0;
  int _statusCodeLength = 0;
  final List<int> _method = [];
  final List<int> _uriOrReasonPhrase = [];
  final List<int> _headerField = [];
  final List<int> _headerValue = [];
  static const _headerTotalSizeLimit = 1024 * 1024;
  int _headersReceivedSize = 0;

  int _httpVersion = _HttpVersion.undetermined;
  int _transferLength = -1;
  bool _persistentConnection = false;
  bool _connectionUpgrade = false;
  bool _chunked = false;

  bool _noMessageBody = false;
  int _remainingContent = -1;
  bool _contentLength = false;
  bool _transferEncoding = false;
  bool connectMethod = false;

  _HttpHeaders? _headers;

  // The limit for parsing chunk size
  static const _chunkSizeLimit = 0x7FFFFFFF;

  // The current incoming connection.
  _HttpIncoming? _incoming;
  StreamSubscription<Uint8List>? _socketSubscription;
  bool _paused = true;
  bool _bodyPaused = false;
  final StreamController<_HttpIncoming> _controller;
  StreamController<Uint8List>? _bodyController;

  factory _HttpParser.requestParser() {
    return _HttpParser._(true);
  }

  factory _HttpParser.responseParser() {
    return _HttpParser._(false);
  }

  _HttpParser._(this._requestParser)
      : _controller = StreamController<_HttpIncoming>(sync: true) {
    _controller
      ..onListen = () {
        _paused = false;
      }
      ..onPause = () {
        _paused = true;
        _pauseStateChanged();
      }
      ..onResume = () {
        _paused = false;
        _pauseStateChanged();
      }
      ..onCancel = () {
        _socketSubscription?.cancel();
      };
    _reset();
  }

  @override
  StreamSubscription<_HttpIncoming> listen(
      void Function(_HttpIncoming event)? onData,
      {Function? onError,
      void Function()? onDone,
      bool? cancelOnError}) {
    return _controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  void listenToStream(Stream<Uint8List> stream) {
    // Listen to the stream and handle data accordingly. When a
    // _HttpIncoming is created, _dataPause, _dataResume, _dataDone is
    // given to provide a way of controlling the parser.
    // TODO(ajohnsen): Remove _dataPause, _dataResume and _dataDone and clean up
    // how the _HttpIncoming signals the parser.
    _socketSubscription =
        stream.listen(_onData, onError: _controller.addError, onDone: _onDone);
  }

  void _parse() {
    try {
      _doParse();
    } catch (e, s) {
      if (_state >= _State.chunkSizeStartingCr && _state <= _State.body) {
        _state = _State.failure;
        _reportBodyError(e, s);
      } else {
        _state = _State.failure;
        _reportHttpError(e, s);
      }
    }
  }

  // Process end of headers. Returns true if the parser should stop
  // parsing and return. This will be in case of either an upgrade
  // request or a request or response with an empty body.
  bool _headersEnd() {
    var headers = _headers!;
    // If method is CONNECT, response parser should ignore any Content-Length or
    // Transfer-Encoding header fields in a successful response.
    // [RFC 7231](https://tools.ietf.org/html/rfc7231#section-4.3.6)
    if (!_requestParser &&
        _statusCode >= 200 &&
        _statusCode < 300 &&
        connectMethod) {
      _transferLength = -1;
      headers.chunkedTransferEncoding = false;
      _chunked = false;
      headers.removeAll(HttpHeaders.contentLengthHeader);
      headers.removeAll(HttpHeaders.transferEncodingHeader);
    }
    headers._mutable = false;

    _transferLength = headers.contentLength;
    // Ignore the Content-Length header if Transfer-Encoding
    // is chunked (RFC 2616 section 4.4)
    if (_chunked) {
      _transferLength = -1;
    }

    // If a request message has neither Content-Length nor
    // Transfer-Encoding the message must not have a body (RFC
    // 2616 section 4.3).
    if (_messageType == _MessageType.request &&
        _transferLength < 0 &&
        _chunked == false) {
      _transferLength = 0;
    }
    if (_connectionUpgrade) {
      _state = _State.upgrade;
      _transferLength = 0;
    }
    var incoming = _createIncoming(_transferLength);
    if (_requestParser) {
      incoming.method = String.fromCharCodes(_method);
      incoming.uri = Uri.parse(String.fromCharCodes(_uriOrReasonPhrase));
    } else {
      incoming.statusCode = _statusCode;
      incoming.reasonPhrase = String.fromCharCodes(_uriOrReasonPhrase);
    }
    _method.clear();
    _uriOrReasonPhrase.clear();
    if (_connectionUpgrade) {
      incoming.upgraded = true;
      _parserCalled = false;
      _closeIncoming();
      _controller.add(incoming);
      return true;
    }
    if (_transferLength == 0 ||
        (_messageType == _MessageType.response && _noMessageBody)) {
      _reset();
      _closeIncoming();
      _controller.add(incoming);
      return false;
    } else if (_chunked) {
      _state = _State.chunkSize;
      _remainingContent = 0;
    } else if (_transferLength > 0) {
      _remainingContent = _transferLength;
      _state = _State.body;
    } else {
      // Neither chunked nor content length. End of body
      // indicated by close.
      _state = _State.body;
    }
    _parserCalled = false;
    _controller.add(incoming);
    return true;
  }

  // From RFC 2616.
  // generic-message = start-line
  //                   *(message-header CRLF)
  //                   CRLF
  //                   [ message-body ]
  // start-line      = Request-Line | Status-Line
  // Request-Line    = Method SP Request-URI SP HTTP-Version CRLF
  // Status-Line     = HTTP-Version SP Status-Code SP Reason-Phrase CRLF
  // message-header  = field-name ":" [ field-value ]
  //
  // Per section 19.3 "Tolerant Applications" CRLF treats LF as a terminator
  // and leading CR is ignored. Use of standalone CR is not allowed.

  void _doParse() {
    assert(!_parserCalled);
    _parserCalled = true;
    if (_state == _State.closed) {
      throw HttpException('Data on closed connection');
    }
    if (_state == _State.failure) {
      throw HttpException('Data on failed connection');
    }
    while (_buffer != null &&
        _index < _buffer!.length &&
        _state != _State.failure &&
        _state != _State.upgrade) {
      // Depending on _incoming, we either break on _bodyPaused or _paused.
      if ((_incoming != null && _bodyPaused) ||
          (_incoming == null && _paused)) {
        _parserCalled = false;
        return;
      }
      int index = _index;
      int byte = _buffer![index];
      _index = index + 1;
      switch (_state) {
        case _State.start:
          if (byte == _Const.http[0]) {
            // Start parsing method or HTTP version.
            _httpVersionIndex = 1;
            _state = _State.methodOrResponseHttpVersion;
          } else {
            // Start parsing method.
            if (!_isTokenChar(byte)) {
              throw HttpException('Invalid request method');
            }
            _addWithValidation(_method, byte);
            if (!_requestParser) {
              throw HttpException('Invalid response line');
            }
            _state = _State.requestLineMethod;
          }
          break;

        case _State.methodOrResponseHttpVersion:
          var httpVersionIndex = _httpVersionIndex!;
          if (httpVersionIndex < _Const.http.length &&
              byte == _Const.http[httpVersionIndex]) {
            // Continue parsing HTTP version.
            _httpVersionIndex = httpVersionIndex + 1;
          } else if (httpVersionIndex == _Const.http.length &&
              byte == _CharCode.slash) {
            // HTTP/ parsed. As method is a token this cannot be a
            // method anymore.
            _httpVersionIndex = httpVersionIndex + 1;
            if (_requestParser) {
              throw HttpException('Invalid request line');
            }
            _state = _State.responseHttpVersion;
          } else {
            // Did not parse HTTP version. Expect method instead.
            for (int i = 0; i < httpVersionIndex; i++) {
              _addWithValidation(_method, _Const.http[i]);
            }
            if (byte == _CharCode.sp) {
              _state = _State.requestLineUri;
            } else {
              _addWithValidation(_method, byte);
              _httpVersion = _HttpVersion.undetermined;
              if (!_requestParser) {
                throw HttpException('Invalid response line');
              }
              _state = _State.requestLineMethod;
            }
          }
          break;

        case _State.responseHttpVersion:
          var httpVersionIndex = _httpVersionIndex!;
          if (httpVersionIndex < _Const.http1dot.length) {
            // Continue parsing HTTP version.
            _expect(byte, _Const.http1dot[httpVersionIndex]);
            _httpVersionIndex = httpVersionIndex + 1;
          } else if (httpVersionIndex == _Const.http1dot.length &&
              byte == _CharCode.one) {
            // HTTP/1.1 parsed.
            _httpVersion = _HttpVersion.http11;
            _persistentConnection = true;
            _httpVersionIndex = httpVersionIndex + 1;
          } else if (httpVersionIndex == _Const.http1dot.length &&
              byte == _CharCode.zero) {
            // HTTP/1.0 parsed.
            _httpVersion = _HttpVersion.http10;
            _persistentConnection = false;
            _httpVersionIndex = httpVersionIndex + 1;
          } else if (httpVersionIndex == _Const.http1dot.length + 1) {
            _expect(byte, _CharCode.sp);
            // HTTP version parsed.
            _state = _State.responseLineStatusCode;
          } else {
            throw HttpException(
                'Invalid response line, failed to parse HTTP version');
          }
          break;

        case _State.requestLineMethod:
          if (byte == _CharCode.sp) {
            _state = _State.requestLineUri;
          } else {
            if (_Const.separatorMap[byte] ||
                byte == _CharCode.cr ||
                byte == _CharCode.lf) {
              throw HttpException('Invalid request method');
            }
            _addWithValidation(_method, byte);
          }
          break;

        case _State.requestLineUri:
          if (byte == _CharCode.sp) {
            if (_uriOrReasonPhrase.isEmpty) {
              throw HttpException('Invalid request, empty URI');
            }
            _state = _State.requestLineHttpVersion;
            _httpVersionIndex = 0;
          } else {
            if (byte == _CharCode.cr || byte == _CharCode.lf) {
              throw HttpException('Invalid request, unexpected $byte in URI');
            }
            _addWithValidation(_uriOrReasonPhrase, byte);
          }
          break;

        case _State.requestLineHttpVersion:
          var httpVersionIndex = _httpVersionIndex!;
          if (httpVersionIndex < _Const.http1dot.length) {
            _expect(byte, _Const.http11[httpVersionIndex]);
            _httpVersionIndex = httpVersionIndex + 1;
          } else if (_httpVersionIndex == _Const.http1dot.length) {
            if (byte == _CharCode.one) {
              // HTTP/1.1 parsed.
              _httpVersion = _HttpVersion.http11;
              _persistentConnection = true;
              _httpVersionIndex = httpVersionIndex + 1;
            } else if (byte == _CharCode.zero) {
              // HTTP/1.0 parsed.
              _httpVersion = _HttpVersion.http10;
              _persistentConnection = false;
              _httpVersionIndex = httpVersionIndex + 1;
            } else {
              throw HttpException('Invalid response, invalid HTTP version');
            }
          } else {
            if (byte == _CharCode.cr) {
              _state = _State.requestLineEnding;
            } else if (byte == _CharCode.lf) {
              _state = _State.requestLineEnding;
              _index = _index - 1; // Make the new state see the LF again.
            }
          }
          break;

        case _State.requestLineEnding:
          _expect(byte, _CharCode.lf);
          _messageType = _MessageType.request;
          _state = _State.headerStart;
          break;

        case _State.responseLineStatusCode:
          if (byte == _CharCode.sp) {
            _state = _State.responseLineReasonPhrase;
          } else if (byte == _CharCode.cr) {
            // Some HTTP servers do not follow the spec and send
            // \r?\n right after the status code.
            _state = _State.responseLineEnding;
          } else if (byte == _CharCode.lf) {
            _state = _State.responseLineEnding;
            _index = _index - 1; // Make the new state see the LF again.
          } else {
            _statusCodeLength++;
            if (byte < 0x30 || byte > 0x39) {
              throw HttpException('Invalid response status code with $byte');
            } else if (_statusCodeLength > 3) {
              throw HttpException(
                  'Invalid response, status code is over 3 digits');
            } else {
              _statusCode = _statusCode * 10 + byte - 0x30;
            }
          }
          break;

        case _State.responseLineReasonPhrase:
          if (byte == _CharCode.cr) {
            _state = _State.responseLineEnding;
          } else if (byte == _CharCode.lf) {
            _state = _State.responseLineEnding;
            _index = _index - 1; // Make the new state see the LF again.
          } else {
            _addWithValidation(_uriOrReasonPhrase, byte);
          }
          break;

        case _State.responseLineEnding:
          _expect(byte, _CharCode.lf);
          _messageType == _MessageType.response;
          // Check whether this response will never have a body.
          if (_statusCode <= 199 || _statusCode == 204 || _statusCode == 304) {
            _noMessageBody = true;
          }
          _state = _State.headerStart;
          break;

        case _State.headerStart:
          _headers = _HttpHeaders(version!);
          if (byte == _CharCode.cr) {
            _state = _State.headerEnding;
          } else if (byte == _CharCode.lf) {
            _state = _State.headerEnding;
            _index = _index - 1; // Make the new state see the LF again.
          } else {
            // Start of new header field.
            _addWithValidation(_headerField, _toLowerCaseByte(byte));
            _state = _State.headerField;
          }
          break;

        case _State.headerField:
          if (byte == _CharCode.colon) {
            _state = _State.headerValueStart;
          } else {
            if (!_isTokenChar(byte)) {
              throw HttpException('Invalid header field name, with $byte');
            }
            _addWithValidation(_headerField, _toLowerCaseByte(byte));
          }
          break;

        case _State.headerValueStart:
          if (byte == _CharCode.cr) {
            _state = _State.headerValueFoldOrEndCr;
          } else if (byte == _CharCode.lf) {
            _state = _State.headerValueFoldOrEnd;
          } else if (byte != _CharCode.sp && byte != _CharCode.ht) {
            // Start of new header value.
            _addWithValidation(_headerValue, byte);
            _state = _State.headerValue;
          }
          break;

        case _State.headerValue:
          if (byte == _CharCode.cr) {
            _state = _State.headerValueFoldOrEndCr;
          } else if (byte == _CharCode.lf) {
            _state = _State.headerValueFoldOrEnd;
          } else {
            _addWithValidation(_headerValue, byte);
          }
          break;

        case _State.headerValueFoldOrEndCr:
          _expect(byte, _CharCode.lf);
          _state = _State.headerValueFoldOrEnd;
          break;

        case _State.headerValueFoldOrEnd:
          if (byte == _CharCode.sp || byte == _CharCode.ht) {
            // This is an obs-fold as defined in RFC 7230 and we should
            // "...replace each received obs-fold with one or more SP octets
            // prior to interpreting the field value or forwarding the
            // message downstream."
            // See https://www.rfc-editor.org/rfc/rfc7230#section-3.2.4
            _addWithValidation(_headerValue, _CharCode.sp);
            _state = _State.headerValueStart; // Strips leading whitespace.
          } else {
            String headerField = String.fromCharCodes(_headerField);
            // The field value does not include any leading or trailing whitespace.
            // See https://www.rfc-editor.org/rfc/rfc7230#section-3.2.4
            _removeTrailingSpaces(_headerValue);
            String headerValue = String.fromCharCodes(_headerValue);

            // RFC-7230 3.3.3 says:
            // If a message is received with both a Transfer-Encoding and a
            // Content-Length header field, the Transfer-Encoding overrides
            // the Content-Length...
            // A sender MUST remove the received Content-Length field prior
            // to forwarding such a message downstream.
            if (headerField == HttpHeaders.contentLengthHeader) {
              // Content Length header should not have more than one occurrence.
              if (_contentLength) {
                throw HttpException('The Content-Length header occurred '
                    'more than once, at most one is allowed.');
              } else if (!_transferEncoding) {
                _contentLength = true;
              }
            } else if (headerField == HttpHeaders.transferEncodingHeader) {
              _transferEncoding = true;
              if (_caseInsensitiveCompare('chunked'.codeUnits, _headerValue)) {
                _chunked = true;
              }
              _contentLength = false;
            }
            var headers = _headers!;
            if (headerField == HttpHeaders.connectionHeader) {
              List<String> tokens = _tokenizeFieldValue(headerValue);
              bool isResponse = _messageType == _MessageType.response;
              bool isUpgradeCode =
                  (_statusCode == HttpStatus.upgradeRequired) ||
                      (_statusCode == HttpStatus.switchingProtocols);
              for (int i = 0; i < tokens.length; i++) {
                bool isUpgrade = _caseInsensitiveCompare(
                    'upgrade'.codeUnits, tokens[i].codeUnits);
                if ((isUpgrade && !isResponse) ||
                    (isUpgrade && isResponse && isUpgradeCode)) {
                  _connectionUpgrade = true;
                }
                headers._addConnection(headerField, tokens[i]);
              }
            } else if (headerField != HttpHeaders.contentLengthHeader ||
                !_transferEncoding) {
              // Calling `headers._add("transfer-encoding", "chunked")` will
              // remove the Content-Length header.
              headers._add(headerField, headerValue);
            }
            _headerField.clear();
            _headerValue.clear();

            if (byte == _CharCode.cr) {
              _state = _State.headerEnding;
            } else if (byte == _CharCode.lf) {
              _state = _State.headerEnding;
              _index = _index - 1; // Make the new state see the LF again.
            } else {
              // Start of new header field.
              _state = _State.headerField;
              _addWithValidation(_headerField, _toLowerCaseByte(byte));
            }
          }
          break;

        case _State.headerEnding:
          _expect(byte, _CharCode.lf);
          if (_headersEnd()) {
            return;
          }
          break;

        case _State.chunkSizeStartingCr:
          if (byte == _CharCode.lf) {
            _state = _State.chunkSizeStarting;
            _index = _index - 1; // Make the new state see the LF again.
            break;
          }
          _expect(byte, _CharCode.cr);
          _state = _State.chunkSizeStarting;
          break;

        case _State.chunkSizeStarting:
          _expect(byte, _CharCode.lf);
          _state = _State.chunkSize;
          break;

        case _State.chunkSize:
          if (byte == _CharCode.cr) {
            _state = _State.chunkSizeEnding;
          } else if (byte == _CharCode.lf) {
            _state = _State.chunkSizeEnding;
            _index = _index - 1; // Make the new state see the LF again.
          } else if (byte == _CharCode.semiColon) {
            _state = _State.chunkSizeExtension;
          } else {
            int value = _expectHexDigit(byte);
            // Checks whether (_remainingContent * 16 + value) overflows.
            if (_remainingContent > _chunkSizeLimit >> 4) {
              throw HttpException('Chunk size overflows the integer');
            }
            _remainingContent = _remainingContent * 16 + value;
          }
          break;

        case _State.chunkSizeExtension:
          if (byte == _CharCode.cr) {
            _state = _State.chunkSizeEnding;
          } else if (byte == _CharCode.lf) {
            _state = _State.chunkSizeEnding;
            _index = _index - 1; // Make the new state see the LF again.
          }
          break;

        case _State.chunkSizeEnding:
          _expect(byte, _CharCode.lf);
          if (_remainingContent > 0) {
            _state = _State.body;
          } else {
            _state = _State.chunkedBodyDoneCr;
          }
          break;

        case _State.chunkedBodyDoneCr:
          if (byte == _CharCode.lf) {
            _state = _State.chunkedBodyDone;
            _index = _index - 1; // Make the new state see the LF again.
            break;
          }
          _expect(byte, _CharCode.cr);
          break;

        case _State.chunkedBodyDone:
          _expect(byte, _CharCode.lf);
          _reset();
          _closeIncoming();
          break;

        case _State.body:
          // The body is not handled one byte at a time but in blocks.
          _index = _index - 1;
          var buffer = _buffer!;
          int dataAvailable = buffer.length - _index;
          if (_remainingContent >= 0 && dataAvailable > _remainingContent) {
            dataAvailable = _remainingContent;
          }
          // Always present the data as a view. This way we can handle all
          // cases like this, and the user will not experience different data
          // typed (which could lead to polymorphic user code).
          Uint8List data = Uint8List.view(
              buffer.buffer, buffer.offsetInBytes + _index, dataAvailable);
          _bodyController!.add(data);
          if (_remainingContent != -1) {
            _remainingContent -= data.length;
          }
          _index = _index + data.length;
          if (_remainingContent == 0) {
            if (!_chunked) {
              _reset();
              _closeIncoming();
            } else {
              _state = _State.chunkSizeStartingCr;
            }
          }
          break;

        case _State.failure:
          // Should be unreachable.
          assert(false);
          break;

        default:
          // Should be unreachable.
          assert(false);
          break;
      }
    }

    _parserCalled = false;
    var buffer = _buffer;
    if (buffer != null && _index == buffer.length) {
      // If all data is parsed release the buffer and resume receiving
      // data.
      _releaseBuffer();
      if (_state != _State.upgrade && _state != _State.failure) {
        _socketSubscription!.resume();
      }
    }
  }

  void _onData(Uint8List buffer) {
    _socketSubscription!.pause();
    assert(_buffer == null);
    _buffer = buffer;
    _index = 0;
    _parse();
  }

  void _onDone() {
    // onDone cancels the subscription.
    _socketSubscription = null;
    if (_state == _State.closed || _state == _State.failure) {
      return;
    }

    if (_incoming != null) {
      if (_state != _State.upgrade &&
          !(_state == _State.start && !_requestParser) &&
          !(_state == _State.body && !_chunked && _transferLength == -1)) {
        _reportBodyError(
            HttpException('Connection closed while receiving data'));
      }
      _closeIncoming(true);
      _controller.close();
      return;
    }
    // If the connection is idle the HTTP stream is closed.
    if (_state == _State.start) {
      if (!_requestParser) {
        _reportHttpError(
            HttpException('Connection closed before full header was received'));
      }
      _controller.close();
      return;
    }

    if (_state == _State.upgrade) {
      _controller.close();
      return;
    }

    if (_state < _State.firstBodyState) {
      _state = _State.failure;
      // Report the error through the error callback if any. Otherwise
      // throw the error.
      _reportHttpError(
          HttpException('Connection closed before full header was received'));
      _controller.close();
      return;
    }

    if (!_chunked && _transferLength == -1) {
      _state = _State.closed;
    } else {
      _state = _State.failure;
      // Report the error through the error callback if any. Otherwise
      // throw the error.
      _reportHttpError(
          HttpException('Connection closed before full body was received'));
    }
    _controller.close();
  }

  String? get version {
    switch (_httpVersion) {
      case _HttpVersion.http10:
        return '1.0';
      case _HttpVersion.http11:
        return '1.1';
    }
    return null;
  }

  int get messageType => _messageType;
  int get transferLength => _transferLength;
  bool get upgrade => _connectionUpgrade && _state == _State.upgrade;
  bool get persistentConnection => _persistentConnection;

  set isHead(bool value) {
    _noMessageBody = value;
  }

  _HttpDetachedIncoming detachIncoming() {
    // Simulate detached by marking as upgraded.
    _state = _State.upgrade;
    return _HttpDetachedIncoming(_socketSubscription, readUnparsedData());
  }

  Uint8List? readUnparsedData() {
    var buffer = _buffer;
    if (buffer == null) {
      return null;
    }
    var index = _index;
    if (index == buffer.length) {
      return null;
    }
    var result = buffer.sublist(index);
    _releaseBuffer();
    return result;
  }

  void _reset() {
    if (_state == _State.upgrade) {
      return;
    }
    _state = _State.start;
    _messageType = _MessageType.undetermined;
    _headerField.clear();
    _headerValue.clear();
    _headersReceivedSize = 0;
    _method.clear();
    _uriOrReasonPhrase.clear();

    _statusCode = 0;
    _statusCodeLength = 0;

    _httpVersion = _HttpVersion.undetermined;
    _transferLength = -1;
    _persistentConnection = false;
    _connectionUpgrade = false;
    _chunked = false;

    _noMessageBody = false;
    _remainingContent = -1;

    _contentLength = false;
    _transferEncoding = false;

    _headers = null;
  }

  void _releaseBuffer() {
    _buffer = null;
    _index = -1;
  }

  static bool _isTokenChar(int byte) {
    return byte > 31 && byte < 128 && !_Const.separatorMap[byte];
  }

  static bool _isValueChar(int byte) {
    return (byte > 31 && byte < 128) || (byte == _CharCode.ht);
  }

  static void _removeTrailingSpaces(List<int> value) {
    var length = value.length;
    while (length > 0 &&
        (value[length - 1] == _CharCode.sp ||
            value[length - 1] == _CharCode.ht)) {
      --length;
    }

    value.length = length;
  }

  static List<String> _tokenizeFieldValue(String headerValue) {
    List<String> tokens = <String>[];
    int start = 0;
    int index = 0;
    while (index < headerValue.length) {
      if (headerValue[index] == ',') {
        tokens.add(headerValue.substring(start, index));
        start = index + 1;
      } else if (headerValue[index] == ' ' || headerValue[index] == '\t') {
        start++;
      }
      index++;
    }
    tokens.add(headerValue.substring(start, index));
    return tokens;
  }

  static int _toLowerCaseByte(int x) {
    // Optimized version:
    //  -  0x41 is 'A'
    //  -  0x7f is ASCII mask
    //  -  26 is the number of alpha characters.
    //  -  0x20 is the delta between lower and upper chars.
    return (((x - 0x41) & 0x7f) < 26) ? (x | 0x20) : x;
  }

  // expected should already be lowercase.
  static bool _caseInsensitiveCompare(List<int> expected, List<int> value) {
    if (expected.length != value.length) {
      return false;
    }
    for (int i = 0; i < expected.length; i++) {
      if (expected[i] != _toLowerCaseByte(value[i])) {
        return false;
      }
    }
    return true;
  }

  void _expect(int val1, int val2) {
    if (val1 != val2) {
      throw HttpException('Failed to parse HTTP, $val1 does not match $val2');
    }
  }

  int _expectHexDigit(int byte) {
    if (0x30 <= byte && byte <= 0x39) {
      return byte - 0x30; // 0 - 9
    } else if (0x41 <= byte && byte <= 0x46) {
      return byte - 0x41 + 10; // A - F
    } else if (0x61 <= byte && byte <= 0x66) {
      return byte - 0x61 + 10; // a - f
    } else {
      throw HttpException(
          'Failed to parse HTTP, $byte is expected to be a Hex digit');
    }
  }

  void _addWithValidation(List<int> list, int byte) {
    _headersReceivedSize++;
    if (_headersReceivedSize < _headerTotalSizeLimit) {
      list.add(byte);
    } else {
      _reportSizeLimitError();
    }
  }

  void _reportSizeLimitError() {
    String method = '';
    switch (_state) {
      case _State.start:
      case _State.methodOrResponseHttpVersion:
      case _State.requestLineMethod:
        method = 'Method';
        break;

      case _State.requestLineUri:
        method = 'URI';
        break;

      case _State.responseLineReasonPhrase:
        method = 'Reason phrase';
        break;

      case _State.headerStart:
      case _State.headerField:
        method = 'Header field';
        break;

      case _State.headerValueStart:
      case _State.headerValue:
        method = 'Header value';
        break;

      default:
        throw UnsupportedError('Unexpected state: $_state');
    }
    throw HttpException(
        '$method exceeds the $_headerTotalSizeLimit size limit');
  }

  _HttpIncoming _createIncoming(int transferLength) {
    assert(_incoming == null);
    assert(_bodyController == null);
    assert(!_bodyPaused);
    var controller = _bodyController = StreamController<Uint8List>(sync: true);
    var incoming =
        _incoming = _HttpIncoming(_headers!, transferLength, controller.stream);
    controller
      ..onListen = () {
        if (incoming != _incoming) {
          return;
        }
        assert(_bodyPaused);
        _bodyPaused = false;
        _pauseStateChanged();
      }
      ..onPause = () {
        if (incoming != _incoming) {
          return;
        }
        assert(!_bodyPaused);
        _bodyPaused = true;
        _pauseStateChanged();
      }
      ..onResume = () {
        if (incoming != _incoming) {
          return;
        }
        assert(_bodyPaused);
        _bodyPaused = false;
        _pauseStateChanged();
      }
      ..onCancel = () {
        if (incoming != _incoming) {
          return;
        }
        _socketSubscription?.cancel();
        _closeIncoming(true);
        _controller.close();
      };
    _bodyPaused = true;
    _pauseStateChanged();
    return incoming;
  }

  void _closeIncoming([bool closing = false]) {
    // Ignore multiple close (can happen in re-entrance).
    var tmp = _incoming;
    if (tmp == null) {
      return;
    }
    tmp.close(closing);
    _incoming = null;
    var controller = _bodyController;
    if (controller != null) {
      controller.close();
      _bodyController = null;
    }
    _bodyPaused = false;
    _pauseStateChanged();
  }

  void _pauseStateChanged() {
    if (_incoming != null) {
      if (!_bodyPaused && !_parserCalled) {
        _parse();
      }
    } else {
      if (!_paused && !_parserCalled) {
        _parse();
      }
    }
  }

  void _reportHttpError(Object error, [StackTrace? stackTrace]) {
    _socketSubscription?.cancel();
    _state = _State.failure;
    _controller.addError(error, stackTrace);
    _controller.close();
  }

  void _reportBodyError(Object error, [StackTrace? stackTrace]) {
    _socketSubscription?.cancel();
    _state = _State.failure;
    _bodyController?.addError(error, stackTrace);
    // In case of drain(), error event will close the stream.
    _bodyController?.close();
  }
}
