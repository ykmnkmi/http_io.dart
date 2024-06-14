// Copied from https://github.com/dart-lang/sdk/blob/main/tests/standalone/io/test_utils.dart

// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

// Create a temporary directory and delete it when the test function exits.
Future<void> withTempDir(
    String prefix, Future<void> Function(Directory dir) test) async {
  var tempDir = Directory.systemTemp.createTempSync(prefix);
  try {
    await runZonedGuarded(() => test(tempDir), (e, st) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // ignore errors
      }
      throw e;
    });
  } finally {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // ignore errors
    }
  }
}
