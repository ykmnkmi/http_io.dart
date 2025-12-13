// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of '../io.dart';

/// A TCP socket using TLS and SSL.
///
/// See [Socket] for more information.
abstract interface class SecureSocket implements Socket {
  factory SecureSocket._(RawSecureSocket rawSocket) => _SecureSocket(rawSocket);

  /// Constructs a new secure client socket and connects it to the given
  /// [host] on port [port].
  ///
  /// The returned Future will complete with a
  /// [SecureSocket] that is connected and ready for subscription.
  ///
  /// The certificate provided by the server is checked
  /// using the trusted certificates set in the SecurityContext object.
  /// The default SecurityContext object contains a built-in set of trusted
  /// root certificates for well-known certificate authorities.
  ///
  /// [onBadCertificate] is an optional handler for unverifiable certificates.
  /// The handler receives the [X509Certificate], and can inspect it and
  /// decide (or let the user decide) whether to accept
  /// the connection or not.  The handler should return true
  /// to continue the [SecureSocket] connection.
  ///
  /// [keyLog] is an optional callback that will be called when new TLS keys
  /// are exchanged with the server. [keyLog] will receive one line of text in
  /// [NSS Key Log Format](https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS/Key_Log_Format)
  /// for each call. Writing these lines to a file will allow tools (such as
  /// [Wireshark](https://gitlab.com/wireshark/wireshark/-/wikis/TLS#tls-decryption))
  /// to decrypt content sent through this socket. This is meant to allow
  /// network-level debugging of secure sockets and should not be used in
  /// production code. For example:
  /// ```dart
  /// final log = File('keylog.txt');
  /// final socket = await SecureSocket.connect('www.example.com', 443,
  ///     keyLog: (line) => log.writeAsStringSync(line, mode: FileMode.append));
  /// ```
  ///
  /// [supportedProtocols] is an optional list of protocols (in decreasing
  /// order of preference) to use during the ALPN protocol negotiation with the
  /// server.  Example values are "http/1.1" or "h2".  The selected protocol
  /// can be obtained via [SecureSocket.selectedProtocol].
  ///
  /// The argument [timeout] is used to specify the maximum allowed time to wait
  /// for a connection to be established. If [timeout] is longer than the system
  /// level timeout duration, a timeout may occur sooner than specified in
  /// [timeout]. On timeout, a [SocketException] is thrown and all ongoing
  /// connection attempts to [host] are cancelled.
  static Future<SecureSocket> connect(
    host,
    int port, {
    SecurityContext? context,
    bool onBadCertificate(X509Certificate certificate)?,
    void keyLog(String line)?,
    List<String>? supportedProtocols,
    Duration? timeout,
  }) {
    return RawSecureSocket.connect(
      host,
      port,
      context: context,
      onBadCertificate: onBadCertificate,
      keyLog: keyLog,
      supportedProtocols: supportedProtocols,
      timeout: timeout,
    ).then((rawSocket) => SecureSocket._(rawSocket));
  }

  /// Like [connect], but returns a [Future] that completes with a
  /// [ConnectionTask] that can be cancelled if the [SecureSocket] is no
  /// longer needed.
  static Future<ConnectionTask<SecureSocket>> startConnect(
    host,
    int port, {
    SecurityContext? context,
    bool onBadCertificate(X509Certificate certificate)?,
    void keyLog(String line)?,
    List<String>? supportedProtocols,
  }) {
    return RawSecureSocket.startConnect(
      host,
      port,
      context: context,
      onBadCertificate: onBadCertificate,
      keyLog: keyLog,
      supportedProtocols: supportedProtocols,
    ).then((rawState) {
      Future<SecureSocket> socket = rawState.socket.then(
        (rawSocket) => SecureSocket._(rawSocket),
      );
      return ConnectionTask<SecureSocket>._(socket, rawState.cancel);
    });
  }

  /// Initiates TLS on an existing connection.
  ///
  /// Takes an already connected [socket] and starts client side TLS
  /// handshake to make the communication secure. When the returned
  /// future completes the [SecureSocket] has completed the TLS
  /// handshake. Using this function requires that the other end of the
  /// connection is prepared for TLS handshake.
  ///
  /// If the [socket] already has a subscription, this subscription
  /// will no longer receive and events. In most cases calling
  /// [StreamSubscription.pause] on this subscription before
  /// starting TLS handshake is the right thing to do.
  ///
  /// The given [socket] is closed and may not be used anymore.
  ///
  /// If the [host] argument is passed it will be used as the host name
  /// for the TLS handshake. If [host] is not passed the host name from
  /// the [socket] will be used. The [host] can be either a [String] or
  /// an [InternetAddress].
  ///
  /// [onBadCertificate] is an optional handler for unverifiable certificates.
  /// The handler receives the [X509Certificate], and can inspect it and
  /// decide (or let the user decide) whether to accept
  /// the connection or not.  The handler should return true
  /// to continue the [SecureSocket] connection.
  ///
  /// [keyLog] is an optional callback that will be called when new TLS keys
  /// are exchanged with the server. [keyLog] will receive one line of text in
  /// [NSS Key Log Format](https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS/Key_Log_Format)
  /// for each call. Writing these lines to a file will allow tools (such as
  /// [Wireshark](https://gitlab.com/wireshark/wireshark/-/wikis/TLS#tls-decryption))
  /// to decrypt content sent through this socket. This is meant to allow
  /// network-level debugging of secure sockets and should not be used in
  /// production code. For example:
  /// ```dart
  /// final log = File('keylog.txt');
  /// final socket = await SecureSocket.connect('www.example.com', 443,
  ///     keyLog: (line) => log.writeAsStringSync(line, mode: FileMode.append));
  /// ```
  ///
  /// [supportedProtocols] is an optional list of protocols (in decreasing
  /// order of preference) to use during the ALPN protocol negotiation with the
  /// server.  Example values are "http/1.1" or "h2".  The selected protocol
  /// can be obtained via [SecureSocket.selectedProtocol].
  ///
  /// Calling this function will _not_ cause a DNS host lookup. If the
  /// [host] passed is a [String], the [InternetAddress] for the
  /// resulting [SecureSocket] will have the passed in [host] as its
  /// host value and the internet address of the already connected
  /// socket as its address value.
  ///
  /// See [connect] for more information on the arguments.
  static Future<SecureSocket> secure(
    Socket socket, {
    host,
    SecurityContext? context,
    bool onBadCertificate(X509Certificate certificate)?,
    void keyLog(String line)?,
    List<String>? supportedProtocols,
  }) {
    return socket
        ._detachRaw()
        .then<RawSecureSocket>((detachedRaw) {
          return RawSecureSocket.secure(
            detachedRaw[0] as RawSocket,
            subscription: detachedRaw[1] as StreamSubscription<RawSocketEvent>?,
            host: host,
            context: context,
            onBadCertificate: onBadCertificate,
            keyLog: keyLog,
            supportedProtocols: supportedProtocols,
          );
        })
        .then<SecureSocket>((raw) => SecureSocket._(raw));
  }

  /// Initiates TLS on an existing server connection.
  ///
  /// Takes an already connected [socket] and starts server side TLS
  /// handshake to make the communication secure. When the returned
  /// future completes the [SecureSocket] has completed the TLS
  /// handshake. Using this function requires that the other end of the
  /// connection is going to start the TLS handshake.
  ///
  /// If the [socket] already has a subscription, this subscription
  /// will no longer receive and events. In most cases calling
  /// [StreamSubscription.pause] on this subscription
  /// before starting TLS handshake is the right thing to do.
  ///
  /// If some of the data of the TLS handshake has already been read
  /// from the socket this data can be passed in the [bufferedData]
  /// parameter. This data will be processed before any other data
  /// available on the socket.
  ///
  /// See [SecureServerSocket.bind] for more information on the
  /// arguments.
  static Future<SecureSocket> secureServer(
    Socket socket,
    SecurityContext? context, {
    List<int>? bufferedData,
    bool requestClientCertificate = false,
    bool requireClientCertificate = false,
    List<String>? supportedProtocols,
  }) {
    return socket
        ._detachRaw()
        .then<RawSecureSocket>((detachedRaw) {
          return RawSecureSocket.secureServer(
            detachedRaw[0] as RawSocket,
            context,
            subscription: detachedRaw[1] as StreamSubscription<RawSocketEvent>?,
            bufferedData: bufferedData,
            requestClientCertificate: requestClientCertificate,
            requireClientCertificate: requireClientCertificate,
            supportedProtocols: supportedProtocols,
          );
        })
        .then<SecureSocket>((raw) => SecureSocket._(raw));
  }

  /// The peer certificate for a connected SecureSocket.
  ///
  /// If this [SecureSocket] is the server end of a secure socket connection,
  /// [peerCertificate] will return the client certificate, or `null` if no
  /// client certificate was received.  If this socket is the client end,
  /// [peerCertificate] will return the server's certificate.
  X509Certificate? get peerCertificate;

  /// The protocol which was selected during ALPN protocol negotiation.
  ///
  /// Returns `null` if one of the peers does not have support for ALPN, did not
  /// specify a list of supported ALPN protocols or there was no common
  /// protocol between client and server.
  String? get selectedProtocol;

  /// Does nothing.
  ///
  /// The original intent was to allow TLS renegotiation of existing secure
  /// connections.
  @Deprecated("Not implemented")
  void renegotiate({
    bool useSessionCache = true,
    bool requestClientCertificate = false,
    bool requireClientCertificate = false,
  });
}

// Interface used by [RawSecureServerSocket] and [_RawSecureSocket] that exposes
// members of [_NativeSocket].
abstract interface class _RawSocketBase {
  bool get _closedReadEventSent;
  void set _owner(owner);
}
