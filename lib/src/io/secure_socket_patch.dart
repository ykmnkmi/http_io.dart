// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of '../io.dart';

class _SecureSocket extends _Socket implements SecureSocket {
  RawSecureSocket? get _raw => super._raw as RawSecureSocket?;

  _SecureSocket(RawSecureSocket raw) : super(raw);

  void renegotiate({
    bool useSessionCache = true,
    bool requestClientCertificate = false,
    bool requireClientCertificate = false,
  }) {}

  X509Certificate? get peerCertificate {
    if (_raw == null) {
      throw StateError("peerCertificate called on destroyed SecureSocket");
    }
    return _raw!.peerCertificate;
  }

  String? get selectedProtocol {
    if (_raw == null) {
      throw StateError("selectedProtocol called on destroyed SecureSocket");
    }
    return _raw!.selectedProtocol;
  }
}
