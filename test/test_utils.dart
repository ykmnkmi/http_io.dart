// Copied from https://github.com/dart-lang/sdk/blob/main/tests/standalone/io/test_utils.dart

// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import "expect.dart";

int lastRetryId = 0;

Future retry(Future Function() fun, {int maxCount = 10}) async {
  final int id = lastRetryId++;
  for (int i = 0; i < maxCount; i++) {
    try {
      // If there is no exception this will simply return, otherwise we keep
      // trying.
      return await fun();
    } catch (e, stack) {
      print("Failed to execute test closure (retry id: ${id}) in attempt $i "
          "(${maxCount - i} retries left).");
      print("Exception: ${e}");
      print("Stacktrace: ${stack}");
    }
  }
  return await fun();
}

Future throws(Function f, bool Function(Object exception) check) async {
  try {
    await f();
  } catch (e) {
    if (!check(e)) {
      Expect.fail('Unexpected: $e');
    }
    return;
  }
  Expect.fail('Did not throw');
}

// Create a temporary directory and delete it when the test function exits.
Future withTempDir(
    String prefix, Future<void> Function(Directory dir) test) async {
  final tempDir = Directory.systemTemp.createTempSync(prefix);
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
