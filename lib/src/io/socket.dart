// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of '../io.dart';

/// A listening socket.
///
/// A [ServerSocket] provides a stream of [Socket] objects,
/// one for each connection made to the listening socket.
///
/// See [Socket] for more info.
abstract interface class ServerSocket implements ServerSocketBase<Socket> {
  /// Listens on a given address and port.
  ///
  /// When the returned future completes the server socket is bound
  /// to the given [address] and [port] and has started listening on it.
  ///
  /// The [address] can either be a [String] or an
  /// [InternetAddress]. If [address] is a [String], [bind] will
  /// perform a [InternetAddress.lookup] and use the first value in the
  /// list. To listen on the loopback adapter, which will allow only
  /// incoming connections from the local host, use the value
  /// [InternetAddress.loopbackIPv4] or
  /// [InternetAddress.loopbackIPv6]. To allow for incoming
  /// connection from the network use either one of the values
  /// [InternetAddress.anyIPv4] or [InternetAddress.anyIPv6] to
  /// bind to all interfaces or the IP address of a specific interface.
  ///
  /// If an IP version 6 (IPv6) address is used, both IP version 6
  /// (IPv6) and version 4 (IPv4) connections will be accepted. To
  /// restrict this to version 6 (IPv6) only, use [v6Only] to set
  /// version 6 only.
  ///
  /// If [port] has the value `0` an ephemeral port will be chosen by
  /// the system. The actual port used can be retrieved using the
  /// [port] getter.
  ///
  /// The optional argument [backlog] can be used to specify the listen
  /// backlog for the underlying OS listen setup. If [backlog] has the
  /// value of `0` (the default) a reasonable value will be chosen by
  /// the system.
  ///
  /// The optional argument [shared] specifies whether additional ServerSocket
  /// objects can bind to the same combination of [address], [port] and
  /// [v6Only]. If [shared] is `true` and more server sockets from this
  /// isolate or other isolates are bound to the port, then the incoming
  /// connections will be distributed among all the bound server sockets.
  /// Connections can be distributed over multiple isolates this way.
  static Future<ServerSocket> bind(
    address,
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
  }) {
    final IOOverrides? overrides = IOOverrides.current;
    if (overrides == null) {
      return ServerSocket._bind(
        address,
        port,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
      );
    }
    return overrides.serverSocketBind(
      address,
      port,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
    );
  }

  static Future<ServerSocket> _bind(
    address,
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
  }) {
    return _ServerSocket.bind(address, port, backlog, v6Only, shared);
  }

  /// The port used by this socket.
  int get port;

  /// The address used by this socket.
  InternetAddress get address;

  /// Closes the socket.
  ///
  /// The returned future completes when the socket
  /// is fully closed and is no longer bound.
  Future<ServerSocket> close();
}

/// A cancelable connection attempt.
///
/// Returned by the `startConnect` methods on client-side socket types `S`,
/// `ConnectionTask<S>` allows canceling an attempt to connect to a host.
final class ConnectionTask<S> {
  /// A `Future` that completes with value that `S.connect()` would return
  /// unless [cancel] is called on this [ConnectionTask].
  ///
  /// If [cancel] is called, the future completes with a [SocketException]
  /// error whose message indicates that the connection attempt was cancelled.
  final Future<S> socket;
  final void Function() _onCancel;

  ConnectionTask._(Future<S> this.socket, void Function() onCancel)
    : _onCancel = onCancel;

  /// Create a `ConnectionTask` from an existing `Future<Socket>`.
  ///
  /// You can use this method to return existing socket connections in
  /// [HttpClient.connectionFactory].
  ///
  /// For example:
  ///
  /// ```dart
  /// final clientSocketFuture = Socket.connect(
  ///     serverUri.host, serverUri.port);
  /// final client = HttpClient()
  ///  ..connectionFactory = (uri, proxyHost, proxyPort) {
  ///    return Future.value(
  ///        ConnectionTask.fromSocket(clientSocketFuture, () {}));
  /// final response = await client.getUrl(serverUri);
  /// ```
  static ConnectionTask<T> fromSocket<T extends Socket>(
    Future<T> socket,
    void Function() onCancel,
  ) => ConnectionTask<T>._(socket, onCancel);

  /// Cancels the connection attempt.
  ///
  /// This also causes the [socket] `Future` to complete with a
  /// [SocketException] error.
  void cancel() {
    _onCancel();
  }
}

/// A TCP connection between two sockets.
///
/// A *socket connection* connects a *local* socket to a *remote* socket.
/// Data, as [Uint8List]s, is received by the local socket, made available
/// by the [Stream] interface of this class, and can be sent to the remote
/// socket through the [IOSink] interface of this class.
///
/// Transmission of the data sent through the [IOSink] interface may be
/// delayed unless [SocketOption.tcpNoDelay] is set with
/// [Socket.setOption].
abstract interface class Socket implements Stream<Uint8List>, IOSink {
  /// Creates a new socket connection to the host and port and returns a [Future]
  /// that will complete with either a [Socket] once connected or an error
  /// if the host-lookup or connection failed.
  ///
  /// [host] can either be a [String] or an [InternetAddress]. If [host] is a
  /// [String], [connect] will perform a [InternetAddress.lookup] and try
  /// all returned [InternetAddress]es, until connected. Unless a
  /// connection was established, the error from the first failing connection is
  /// returned.
  ///
  /// The argument [sourceAddress] can be used to specify the local
  /// address to bind when making the connection. The [sourceAddress] can either
  /// be a [String] or an [InternetAddress]. If a [String] is passed it must
  /// hold a numeric IP address.
  ///
  /// The [sourcePort] defines the local port to bind to. If [sourcePort] is
  /// not specified or zero, a port will be chosen.
  ///
  /// The argument [timeout] is used to specify the maximum allowed time to wait
  /// for a connection to be established. If [timeout] is longer than the system
  /// level timeout duration, a timeout may occur sooner than specified in
  /// [timeout]. On timeout, a [SocketException] is thrown and all ongoing
  /// connection attempts to [host] are cancelled.
  static Future<Socket> connect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) {
    final IOOverrides? overrides = IOOverrides.current;
    if (overrides == null) {
      return Socket._connect(
        host,
        port,
        sourceAddress: sourceAddress,
        sourcePort: sourcePort,
        timeout: timeout,
      );
    }
    return overrides.socketConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      timeout: timeout,
    );
  }

  /// Like [connect], but returns a [Future] that completes with a
  /// [ConnectionTask] that can be cancelled if the [Socket] is no
  /// longer needed.
  static Future<ConnectionTask<Socket>> startConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
  }) {
    final IOOverrides? overrides = IOOverrides.current;
    if (overrides == null) {
      return Socket._startConnect(
        host,
        port,
        sourceAddress: sourceAddress,
        sourcePort: sourcePort,
      );
    }
    return overrides.socketStartConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
    );
  }

  static Future<Socket> _connect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) {
    return RawSocket.connect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      timeout: timeout,
    ).then((socket) => _Socket(socket));
  }

  static Future<ConnectionTask<Socket>> _startConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
  }) {
    return RawSocket.startConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
    ).then((rawTask) {
      Future<Socket> socket = rawTask.socket.then(
        (rawSocket) => _Socket(rawSocket),
      );
      return ConnectionTask<Socket>._(socket, rawTask.cancel);
    });
  }

  Future<List<Object?>> _detachRaw();

  /// Destroys the socket in both directions.
  ///
  /// Calling [destroy] will make the send a close event on the stream
  /// and will no longer react on data being piped to it.
  ///
  /// Call [close] (inherited from [IOSink]) to only close the [Socket]
  /// for sending data.
  void destroy();

  /// Customizes the [RawSocket].
  ///
  /// See [SocketOption] for available options.
  ///
  /// Returns `true` if the option was set successfully, false otherwise.
  ///
  /// Throws a [SocketException] if the socket has been destroyed or upgraded to
  /// a secure socket.
  bool setOption(SocketOption option, bool enabled);

  /// Reads low level information about the [RawSocket].
  ///
  /// See [RawSocketOption] for available options.
  ///
  /// Returns the [RawSocketOption.value] on success.
  ///
  /// Throws an [OSError] on failure and a [SocketException] if the socket has
  /// been destroyed or upgraded to a secure socket.
  Uint8List getRawOption(RawSocketOption option);

  /// Customizes the [RawSocket].
  ///
  /// See [RawSocketOption] for available options.
  ///
  /// Throws an [OSError] on failure and a [SocketException] if the socket has
  /// been destroyed or upgraded to a secure socket.
  void setRawOption(RawSocketOption option);

  /// Unsupported operation on sockets.
  ///
  /// This method, which is inherited from [IOSink], is not supported on
  /// sockets, and **must not** be called.
  /// Sockets have no way to report errors, so any error passed in to
  /// a socket using [addError] would be lost.
  void addError(Object error, [StackTrace? stackTrace]);

  /// The port used by this socket.
  ///
  /// Throws a [SocketException] if the socket is closed.
  /// The port is 0 if the socket is a Unix domain socket.
  int get port;

  /// The remote port connected to by this socket.
  ///
  /// Throws a [SocketException] if the socket is closed.
  /// The port is 0 if the socket is a Unix domain socket.
  int get remotePort;

  /// The [InternetAddress] used to connect this socket.
  ///
  /// Throws a [SocketException] if the socket is closed.
  InternetAddress get address;

  /// The remote [InternetAddress] connected to by this socket.
  ///
  /// Throws a [SocketException] if the socket is closed.
  InternetAddress get remoteAddress;

  Future close();

  Future get done;
}
