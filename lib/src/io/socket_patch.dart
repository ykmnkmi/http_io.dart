// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of '../io.dart';

class _ServerSocket extends Stream<Socket> implements ServerSocket {
  final _socket;

  static Future<_ServerSocket> bind(
    address,
    int port,
    int backlog,
    bool v6Only,
    bool shared,
  ) {
    return RawServerSocket.bind(
      address,
      port,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
    ).then((socket) => _ServerSocket(socket));
  }

  _ServerSocket(this._socket);

  StreamSubscription<Socket> listen(
    void onData(Socket event)?, {
    Function? onError,
    void onDone()?,
    bool? cancelOnError,
  }) {
    return _socket
        .map<Socket>((rawSocket) => _Socket(rawSocket))
        .listen(
          onData,
          onError: onError,
          onDone: onDone,
          cancelOnError: cancelOnError,
        );
  }

  int get port => _socket.port;

  InternetAddress get address => _socket.address;

  Future<ServerSocket> close() =>
      _socket.close().then<ServerSocket>((_) => this);

  void set _owner(owner) {
    _socket._owner = owner;
  }
}

class _SocketStreamConsumer implements StreamConsumer<List<int>> {
  StreamSubscription? subscription;
  final _Socket socket;
  int? offset;
  List<int>? buffer;
  bool paused = false;
  Completer<Socket>? streamCompleter;

  _SocketStreamConsumer(this.socket);

  Future<Socket> addStream(Stream<List<int>> stream) {
    socket._ensureRawSocketSubscription();
    final completer = streamCompleter = Completer<Socket>();
    if (socket._raw != null) {
      subscription = stream.listen(
        (data) {
          assert(!paused);
          assert(buffer == null);
          buffer = data;
          offset = 0;
          try {
            write();
          } catch (e) {
            buffer = null;
            offset = 0;

            socket.destroy();
            stop();
            done(e);
          }
        },
        onError: (error, [stackTrace]) {
          socket.destroy();
          done(error, stackTrace);
        },
        onDone: () {
          // Note: stream only delivers done event if subscription is not paused.
          // so it is crucial to keep subscription paused while writes are
          // in flight.
          assert(buffer == null);
          done();
        },
        cancelOnError: true,
      );
    } else {
      done();
    }
    return completer.future;
  }

  Future<Socket> close() {
    socket._consumerDone();
    return Future.value(socket);
  }

  bool get _previousWriteHasCompleted {
    // _RawSecureSocket has an internal buffering mechanism and it is going
    // to flush its buffer before it shutsdown.
    return true;
  }

  void write() {
    final sub = subscription;
    if (sub == null) return;

    // We have something to write out.
    if (offset! < buffer!.length) {
      offset =
          offset! + socket._write(buffer!, offset!, buffer!.length - offset!);
    }

    if (offset! < buffer!.length || !_previousWriteHasCompleted) {
      // On Windows we might have written the whole buffer out but we are
      // still waiting for the write to complete. We should not resume the
      // subscription until the pending write finishes and we receive a
      // writeEvent signaling that we can write the next chunk or that we
      // can consider all data flushed from our side into kernel buffers.
      if (!paused) {
        paused = true;
        sub.pause();
      }
      socket._enableWriteEvent();
    } else {
      // Write fully completed.
      buffer = null;
      if (paused) {
        paused = false;
        sub.resume();
      }
    }
  }

  void done([error, stackTrace]) {
    final completer = streamCompleter;
    if (completer != null) {
      if (error != null) {
        completer.completeError(error, stackTrace);
      } else {
        completer.complete(socket);
      }
      streamCompleter = null;
    }
  }

  void stop() {
    final sub = subscription;
    if (sub == null) return;
    sub.cancel();
    subscription = null;
    paused = false;
    socket._disableWriteEvent();
  }
}

class _Socket extends Stream<Uint8List> implements Socket {
  RawSocket? _raw; // Set to null when the raw socket is closed.
  bool _closed = false; // Set to true when the raw socket is closed.
  final _controller = StreamController<Uint8List>(sync: true);
  bool _controllerClosed = false;
  late _SocketStreamConsumer _consumer;
  late IOSink _sink;
  StreamSubscription? _subscription;
  Completer<Object?>? _detachReady;

  _Socket(RawSocket raw) : _raw = raw {
    _controller
      ..onListen = _onSubscriptionStateChange
      ..onCancel = _onSubscriptionStateChange
      ..onPause = _onPauseStateChange
      ..onResume = _onPauseStateChange;
    _consumer = _SocketStreamConsumer(this);
    _sink = IOSink(_consumer);

    // Disable read events until there is a subscription.
    raw.readEventsEnabled = false;

    // Disable write events until the consumer needs it for pending writes.
    raw.writeEventsEnabled = false;
  }

  StreamSubscription<Uint8List> listen(
    void onData(Uint8List event)?, {
    Function? onError,
    void onDone()?,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  Encoding get encoding => _sink.encoding;

  void set encoding(Encoding value) {
    _sink.encoding = value;
  }

  void write(Object? obj) => _sink.write(obj);

  void writeln([Object? obj = ""]) => _sink.writeln(obj);

  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);

  void writeAll(Iterable objects, [String sep = ""]) =>
      _sink.writeAll(objects, sep);

  void add(List<int> bytes) => _sink.add(bytes);

  /// Unsupported operation on sockets.
  ///
  /// Throws an [UnsupportedError] because errors cannot be transmitted over a
  /// [Socket].
  void addError(Object error, [StackTrace? stackTrace]) {
    throw UnsupportedError("Cannot send errors on sockets");
  }

  Future addStream(Stream<List<int>> stream) {
    return _sink.addStream(stream);
  }

  Future flush() => _sink.flush();

  Future close() => _sink.close();

  Future get done => _sink.done;

  void destroy() {
    // Destroy can always be called to get rid of a socket.
    if (_raw == null) return;
    _consumer.stop();
    _closeRawSocket();
    _controllerClosed = true;
    _controller.close();
  }

  bool setOption(SocketOption option, bool enabled) {
    final raw = _raw;
    if (raw == null) throw const SocketException.closed();
    return raw.setOption(option, enabled);
  }

  Uint8List getRawOption(RawSocketOption option) {
    final raw = _raw;
    if (raw == null) throw const SocketException.closed();
    return raw.getRawOption(option);
  }

  void setRawOption(RawSocketOption option) {
    final raw = _raw;
    if (raw == null) throw const SocketException.closed();
    raw.setRawOption(option);
  }

  int get port {
    final raw = _raw;
    if (raw == null) throw const SocketException.closed();
    return raw.port;
  }

  InternetAddress get address {
    final raw = _raw;
    if (raw == null) throw const SocketException.closed();
    return raw.address;
  }

  int get remotePort {
    final raw = _raw;
    if (raw == null) throw const SocketException.closed();
    return raw.remotePort;
  }

  InternetAddress get remoteAddress {
    final raw = _raw;
    if (raw == null) throw const SocketException.closed();
    return raw.remoteAddress;
  }

  Future<List<Object?>> _detachRaw() {
    var completer = Completer<Object?>();
    _detachReady = completer;
    _sink.close();
    return completer.future.then((_) {
      assert(_consumer.buffer == null);
      var raw = _raw;
      _raw = null;
      return [raw, _subscription];
    });
  }

  // Ensure a subscription on the raw socket. Both the stream and the
  // consumer needs a subscription as they share the error and done
  // events from the raw socket.
  void _ensureRawSocketSubscription() {
    final raw = _raw;
    if (_subscription == null && raw != null) {
      _subscription = raw.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: true,
      );
    }
  }

  _closeRawSocket() {
    var raw = _raw!;
    _raw = null;
    _closed = true;
    raw.close();
  }

  void _onSubscriptionStateChange() {
    final raw = _raw;
    if (_controller.hasListener) {
      _ensureRawSocketSubscription();
      // Enable read events for providing data to subscription.
      if (raw != null) {
        raw.readEventsEnabled = true;
      }
    } else {
      _controllerClosed = true;
      if (raw != null) {
        raw.shutdown(SocketDirection.receive);
      }
    }
  }

  void _onPauseStateChange() {
    _raw?.readEventsEnabled = !_controller.isPaused;
  }

  void _onData(event) {
    switch (event) {
      case RawSocketEvent.read:
        if (_raw == null) break;
        var buffer = _raw!.read();
        if (buffer != null) _controller.add(buffer);
        break;
      case RawSocketEvent.write:
        _consumer.write();
        break;
      case RawSocketEvent.readClosed:
        _controllerClosed = true;
        _controller.close();
        break;
    }
  }

  void _onDone() {
    if (!_controllerClosed) {
      _controllerClosed = true;
      _controller.close();
    }
    _consumer.done();
  }

  void _onError(error, stackTrace) {
    if (!_controllerClosed) {
      _controllerClosed = true;
      _controller.addError(error, stackTrace);
      _controller.close();
    }
    _consumer.done(error, stackTrace);
  }

  int _write(List<int> data, int offset, int length) {
    final raw = _raw;
    if (raw != null) {
      return raw.write(data, offset, length);
    }
    return 0;
  }

  void _enableWriteEvent() {
    _raw?.writeEventsEnabled = true;
  }

  void _disableWriteEvent() {
    _raw?.writeEventsEnabled = false;
  }

  void _consumerDone() {
    if (_detachReady != null) {
      _detachReady!.complete(null);
    } else {
      final raw = _raw;
      if (raw != null) {
        raw.shutdown(SocketDirection.send);
        _disableWriteEvent();
      }
    }
  }

  void set _owner(owner) {
    // Note: _raw can be _RawSocket and _RawSecureSocket.
    (_raw as _RawSocketBase)._owner = owner;
  }
}
