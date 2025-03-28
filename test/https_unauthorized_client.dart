// Copyright (c) 2013, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Client that makes HttpClient secure gets from a server that replies with
// a certificate that can't be authenticated.  This checks that all the
// futures returned from these connection attempts complete (with errors).

// ignore_for_file: avoid_print

import 'dart:async';

import 'package:http_io/http_io.dart';

class ExpectException implements Exception {
  ExpectException(this.message);
  @override
  String toString() => 'ExpectException: $message';
  String message;
}

void expect(bool condition, String message) {
  if (!condition) {
    throw ExpectException(message);
  }
}

const hostName = 'localhost';

Future<void> runClients(int port) {
  HttpClient client = HttpClient();

  var testFutures = <Future<void>>[];
  for (int i = 0; i < 20; ++i) {
    testFutures.add(
      client
          .getUrl(Uri.parse('https://$hostName:$port/'))
          .then(
            (HttpClientRequest request) {
              expect(false, 'Request succeeded');
            },
            onError: (Object e) {
              // Remove ArgumentError once null default context is supported.
              expect(
                e is HandshakeException ||
                    e is SocketException ||
                    e is ArgumentError,
                'Error is wrong type: $e',
              );
            },
          ),
    );
  }
  return Future.wait(testFutures);
}

void main(List<String> args) {
  runClients(int.parse(args[0])).then((_) => print('SUCCESS'));
}
