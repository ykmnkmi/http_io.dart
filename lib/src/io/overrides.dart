// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of '../io.dart';

final _ioOverridesToken = Object();

/// Facilities for overriding various APIs of `dart:io` with mock
/// implementations.
///
/// This abstract base class should be extended with overrides for the
/// operations needed to construct mocks. The implementations in this base class
/// default to the actual `dart:io` implementation. For example:
///
/// ```dart
/// class MyDirectory implements Directory {
///   ...
///   // An implementation of the Directory interface
///   ...
/// }
///
/// void main() {
///   IOOverrides.runZoned(() {
///     ...
///     // Operations will use MyDirectory instead of dart:io's Directory
///     // implementation whenever Directory is used.
///     ...
///   }, createDirectory: (String path) => new MyDirectory(path));
/// }
/// ```
abstract base class IOOverrides {
  static IOOverrides? _global;

  static IOOverrides? get current {
    return Zone.current[_ioOverridesToken] ?? _global;
  }

  /// The [IOOverrides] to use in the root [Zone].
  ///
  /// These are the [IOOverrides] that will be used in the root [Zone], and in
  /// [Zone]'s that do not set [IOOverrides] and whose ancestors up to the root
  /// [Zone] also do not set [IOOverrides].
  static set global(IOOverrides? overrides) {
    _global = overrides;
  }

  /// Runs [body] in a fresh [Zone] using the provided overrides.
  ///
  /// See the documentation on the corresponding methods of [IOOverrides] for
  /// information about what the optional arguments do.
  static R runZoned<R>(
    R body(), {
    // Socket
    Future<Socket> Function(
      dynamic,
      int, {
      dynamic sourceAddress,
      int sourcePort,
      Duration? timeout,
    })?
    socketConnect,
    Future<ConnectionTask<Socket>> Function(
      dynamic,
      int, {
      dynamic sourceAddress,
      int sourcePort,
    })?
    socketStartConnect,

    // ServerSocket
    Future<ServerSocket> Function(
      dynamic,
      int, {
      int backlog,
      bool v6Only,
      bool shared,
    })?
    serverSocketBind,
  }) {
    // Avoid building chains of override scopes. Just copy outer scope's
    // functions and `_previous`.
    var current = IOOverrides.current;
    _IOOverridesScope? currentScope;
    if (current is _IOOverridesScope) {
      currentScope = current;
      current = currentScope._previous;
    }
    IOOverrides overrides = _IOOverridesScope(
      current,
      // Socket
      socketConnect ?? currentScope?._socketConnect,
      socketStartConnect ?? currentScope?._socketStartConnect,

      // ServerSocket
      serverSocketBind ?? currentScope?._serverSocketBind,
    );
    return dart_async.runZoned<R>(
      body,
      zoneValues: {_ioOverridesToken: overrides},
    );
  }

  /// Runs [body] in a fresh [Zone] using the overrides found in [overrides].
  ///
  /// Note that [overrides] should be an instance of a class that extends
  /// [IOOverrides].
  static R runWithIOOverrides<R>(R body(), IOOverrides overrides) {
    return dart_async.runZoned<R>(
      body,
      zoneValues: {_ioOverridesToken: overrides},
    );
  }

  // Socket

  /// Asynchronously returns a [Socket] connected to the given host and port.
  ///
  /// When this override is installed, this function overrides the behavior of
  /// `Socket.connect(...)`.
  Future<Socket> socketConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) {
    return Socket._connect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      timeout: timeout,
    );
  }

  /// Asynchronously returns a [ConnectionTask] that connects to the given host
  /// and port when successful.
  ///
  /// When this override is installed, this function overrides the behavior of
  /// `Socket.startConnect(...)`.
  Future<ConnectionTask<Socket>> socketStartConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
  }) {
    return Socket._startConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
    );
  }

  // ServerSocket

  /// Asynchronously returns a [ServerSocket] that connects to the given address
  /// and port when successful.
  ///
  /// When this override is installed, this function overrides the behavior of
  /// `ServerSocket.bind(...)`.
  Future<ServerSocket> serverSocketBind(
    address,
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
  }) {
    return ServerSocket._bind(
      address,
      port,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
    );
  }
}

final class _IOOverridesScope extends IOOverrides {
  final IOOverrides? _previous;

  // Socket
  final Future<Socket> Function(
    dynamic,
    int, {
    dynamic sourceAddress,
    int sourcePort,
    Duration? timeout,
  })?
  _socketConnect;
  final Future<ConnectionTask<Socket>> Function(
    dynamic,
    int, {
    dynamic sourceAddress,
    int sourcePort,
  })?
  _socketStartConnect;

  // ServerSocket
  final Future<ServerSocket> Function(
    dynamic,
    int, {
    int backlog,
    bool v6Only,
    bool shared,
  })?
  _serverSocketBind;

  _IOOverridesScope(
    this._previous,

    // Socket
    this._socketConnect,
    this._socketStartConnect,

    // ServerSocket
    this._serverSocketBind,
  );

  // Socket
  @override
  Future<Socket> socketConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) =>
      _socketConnect?.call(
        host,
        port,
        sourceAddress: sourceAddress,
        sourcePort: sourcePort,
        timeout: timeout,
      ) ??
      _previous?.socketConnect(
        host,
        port,
        sourceAddress: sourceAddress,
        sourcePort: sourcePort,
        timeout: timeout,
      ) ??
      super.socketConnect(
        host,
        port,
        sourceAddress: sourceAddress,
        sourcePort: sourcePort,
        timeout: timeout,
      );

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
  }) =>
      _socketStartConnect?.call(
        host,
        port,
        sourceAddress: sourceAddress,
        sourcePort: sourcePort,
      ) ??
      _previous?.socketStartConnect(
        host,
        port,
        sourceAddress: sourceAddress,
        sourcePort: sourcePort,
      ) ??
      super.socketStartConnect(
        host,
        port,
        sourceAddress: sourceAddress,
        sourcePort: sourcePort,
      );

  // ServerSocket
  @override
  Future<ServerSocket> serverSocketBind(
    address,
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
  }) =>
      _serverSocketBind?.call(
        address,
        port,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
      ) ??
      _previous?.serverSocketBind(
        address,
        port,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
      ) ??
      super.serverSocketBind(
        address,
        port,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
      );
}
