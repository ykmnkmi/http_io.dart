// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This library contains an `Expect` class with static methods that can be used
/// for simple unit-tests.
///
/// The library is deliberately written to use as few and simple language
/// features as reasonable to perform the tests.
/// This ensures that it can be used to test as many language features as
/// possible.
///
/// Error reporting as allowed to use more features, under the assumption
/// that it will either work as desired, or break in some other way.
/// As long as the *success path* is simple, a successful test can be trusted.
library;

/// Expect is used for tests that do not want to make use of the
/// Dart unit test library - for example, the core language tests.
/// Third parties are discouraged from using this, and should use
/// the expect() function in the unit test library instead for
/// test assertions.
abstract interface class Expect {
  /// A slice of a string for inclusion in error messages.
  ///
  /// The [start] and [end] represents a slice of a string which
  /// has failed a test. For example, it's a part of a string
  /// which is not equal to an expected string value.
  ///
  /// The [length] limits the length of the representation of the slice,
  /// to avoid a long difference being shown in its entirety.
  ///
  /// The slice will contain at least some part of the substring from [start]
  /// to the lower of [end] and `start + length`.
  /// If the result is no more than `length - 10` characters long,
  /// context may be added by extending the range of the slice, by decreasing
  /// [start] and increasing [end], up to at most length characters.
  /// If the start or end of the slice are not matching the start or end of
  /// the string, ellipses (`"..."`) are added before or after the slice.
  /// Characters other than printable ASCII are escaped.
  static String _truncateString(String string, int start, int end, int length) {
    if (end - start > length) {
      end = start + length;
    } else if (end - start < length) {
      int overflow = length - (end - start);

      if (overflow > 10) {
        overflow = 10;
      }

      // Add context.
      start = start - ((overflow + 1) ~/ 2);
      end = end + (overflow ~/ 2);

      if (start < 0) {
        start = 0;
      }

      if (end > string.length) {
        end = string.length;
      }
    }

    StringBuffer buffer = StringBuffer();

    if (start > 0) {
      buffer.write('...');
    }

    _escapeSubstring(buffer, string, 0, string.length);

    if (end < string.length) {
      buffer.write('...');
    }

    return buffer.toString();
  }

  /// The [string] with non printable-ASCII characters escaped.
  ///
  /// Any character of [string] which is not ASCII or an ASCII control character
  /// is represented as either `"\xXX"` or `"\uXXXX"` hex escapes.
  /// Backslashes are escaped as `"\\"`.
  static String _escapeString(String string) {
    StringBuffer buffer = StringBuffer();
    _escapeSubstring(buffer, string, 0, string.length);
    return buffer.toString();
  }

  static void _escapeSubstring(
    StringBuffer buffer,
    String string,
    int start,
    int end,
  ) {
    const String hexDigits = '0123456789ABCDEF';
    const int backslash = 0x5c;

    int chunkStart = start; // No escapes since this point.

    for (int i = start; i < end; i++) {
      int code = string.codeUnitAt(i);

      if (0x20 <= code && code < 0x7F && code != backslash) {
        continue;
      }

      if (i > chunkStart) {
        buffer.write(string.substring(chunkStart, i));
      }

      if (code == backslash) {
        buffer.write(r'\');
      } else if (code < 0x100) {
        if (code == 0x09) {
          buffer.write(r'\t');
        } else if (code == 0x0a) {
          buffer.write(r'\n');
        } else if (code == 0x0d) {
          buffer.write(r'\r');
        } else if (code == 0x5c) {
          buffer.write(r'\');
        } else {
          buffer
            ..write(r'\x')
            ..write(hexDigits[code >> 4])
            ..write(hexDigits[code & 15]);
        }
      } else {
        buffer
          ..write(r'\u{')
          ..write(code.toRadixString(16).toUpperCase())
          ..write('}');
      }

      chunkStart = i + 1;
    }

    if (chunkStart < end) {
      buffer.write(string.substring(chunkStart, end));
    }
  }

  /// A string representing the difference between two strings.
  ///
  /// The two strings have already been checked as not being equal (`==`).
  ///
  /// This function finds the first point where the two strings differ,
  /// and returns a text describing the difference.
  ///
  /// For small strings (length less than 20) nothing is done, and "" is
  /// returned, representing that the entire string can be used to display
  /// the difference.
  /// Small strings can be compared visually, but for longer strings
  /// only a slice containing the first difference will be shown.
  static String _stringDifference(String expected, String actual) {
    if (expected.length < 20 && actual.length < 20) {
      return '';
    }

    for (int i = 0; i < expected.length && i < actual.length; i++) {
      if (expected.codeUnitAt(i) != actual.codeUnitAt(i)) {
        int start = i;
        i++;

        while (i < expected.length && i < actual.length) {
          if (expected.codeUnitAt(i) == actual.codeUnitAt(i)) {
            break;
          }

          i++;
        }

        int end = i;
        String truncatedExpected = _truncateString(expected, start, end, 20);
        String truncatedActual = _truncateString(actual, start, end, 20);
        return 'at index $start: Expected <$truncatedExpected>, Found: '
            '<$truncatedActual>';
      }
    }

    return '';
  }

  /// Checks that the expected and actual values are equal (using `==`).
  static void equals(Object? expected, Object? actual, [String reason = '']) {
    if (expected == actual) {
      return;
    }

    _failNotEqual(expected, actual, 'equals', reason);
  }

  /// Reports two values not equal.
  ///
  /// Used by, for example, `Expect.equals` and `Expect.deepEquals`.
  static void _failNotEqual(
    Object? expected,
    Object? actual,
    String test,
    String reason,
  ) {
    String msg = _getMessage(reason);

    if (expected is String && actual is String) {
      String stringDifference = _stringDifference(expected, actual);

      if (stringDifference.isNotEmpty) {
        _fail('Expect.$test($stringDifference$msg) fails.');
      }

      _fail(
        'Expect.$test(expected: <${_escapeString(expected)}>, actual: '
        '<${_escapeString(actual)}>$msg) fails.',
      );
    }

    _fail('Expect.$test(expected: <$expected>, actual: <$actual>$msg) fails.');
  }

  /// Checks that the actual value is a `bool` and its value is `true`.
  static void isTrue(Object? actual, [String reason = '']) {
    if (_identical(actual, true)) {
      return;
    }

    String message = _getMessage(reason);
    _fail('Expect.isTrue($actual$message) fails.');
  }

  /// Checks that the actual value is a `bool` and its value is `false`.
  static void isFalse(Object? actual, [String reason = '']) {
    if (_identical(actual, false)) {
      return;
    }

    String msg = _getMessage(reason);
    _fail('Expect.isFalse($actual$msg) fails.');
  }

  /// Checks that [actual] is null.
  static void isNull(Object? actual, [String reason = '']) {
    if (null == actual) {
      return;
    }

    String message = _getMessage(reason);
    _fail('Expect.isNull(actual: <$actual>$message) fails.');
  }

  /// Checks that [actual] is not null.
  static void isNotNull(Object? actual, [String reason = '']) {
    if (actual != null) {
      return;
    }

    String message = _getMessage(reason);
    _fail('Expect.isNotNull(actual: null$message) fails.');
  }

  /// Checks that the [Iterable] [actual] is empty.
  static void isEmpty(Iterable<Object?> actual, [String reason = '']) {
    if (actual.isEmpty) {
      return;
    }

    String message = _getMessage(reason);
    List<Object?> sample = actual.take(4).toList();
    String sampleString =
        sample.length < 4
            ? sample.join(', ')
            : "${sample.take(3).join(", ")}, ...";

    _fail('Expect.isEmpty(actual: <$sampleString>$message): Is not empty.');
  }

  /// Checks that the [Iterable] [actual] is not empty.
  static void isNotEmpty(Iterable<Object?> actual, [String reason = '']) {
    if (actual.isNotEmpty) {
      return; // ignore: prefer_is_not_empty
    }

    String message = _getMessage(reason);

    _fail(
      'Expect.isNotEmpty(actual: <${Error.safeToString(actual)}>$message): Is '
      'empty.',
    );
  }

  /// Checks that the expected and actual values are identical
  /// (using `identical`).
  // TODO(lrn): Rename to `same`, to match package:test, and to not
  // shadow `identical` from `dart:core`. (And `allIdentical` to `allSame`.)
  static void identical(
    Object? expected,
    Object? actual, [
    String reason = '',
  ]) {
    if (_identical(expected, actual)) {
      return;
    }

    String msg = _getMessage(reason);

    if (expected is String && actual is String) {
      String note =
          expected == actual ? ' Strings equal but not identical.' : '';

      _fail(
        'Expect.identical(expected: <${_escapeString(expected)}>, actual: '
        '<${_escapeString(actual)}>$msg) fails.$note',
      );
    }

    _fail(
      'Expect.identical(expected: <$expected>, actual: <$actual>$msg) fails.',
    );
  }

  /// Finds equivalence classes of objects (by index) wrt. identity.
  ///
  /// Returns a list of lists of identical object indices per object.
  /// That is, `objects[i]` is identical to objects with indices in
  /// `_findEquivalences(objects)[i]`.
  ///
  /// Uses `[]` for objects that are only identical to themselves.
  static List<List<int>> _findEquivalences(List<Object?> objects) {
    List<List<int>> equivalences = List<List<int>>.generate(
      objects.length,
      (_) => <int>[],
    );

    for (int i = 0; i < objects.length; i++) {
      if (equivalences[i].isNotEmpty) {
        continue;
      }

      Object? object = objects[i];

      for (int j = i + 1; j < objects.length; j++) {
        if (equivalences[j].isNotEmpty) {
          continue;
        }

        if (_identical(object, objects[j])) {
          if (equivalences[i].isEmpty) {
            equivalences[i].add(i);
          }

          equivalences[j] = equivalences[i]..add(j);
        }
      }
    }

    return equivalences;
  }

  static void _writeEquivalences(
    List<Object?> objects,
    List<List<int>> equivalences,
    StringBuffer buffer,
  ) {
    String separator = '';

    for (int i = 0; i < objects.length; i++) {
      buffer.write(separator);
      separator = ',';

      List<int> equivalence = equivalences[i];

      if (equivalence.isEmpty) {
        buffer.write('_');
      } else {
        int first = equivalence[0];

        buffer
          ..write('#')
          ..write(first);
        if (first == i) {
          buffer
            ..write('=')
            ..write(objects[i]);
        }
      }
    }
  }

  static void allIdentical(List<Object?> objects, [String reason = '']) {
    if (objects.length <= 1) {
      return;
    }

    bool allIdentical = true;
    Object? firstObject = objects[0];

    for (int i = 1; i < objects.length; i++) {
      if (!_identical(firstObject, objects[i])) {
        allIdentical = false;
      }
    }

    if (allIdentical) {
      return;
    }

    String msg = _getMessage(reason);
    List<List<int>> equivalences = _findEquivalences(objects);
    StringBuffer buffer = StringBuffer('Expect.allIdentical([');
    _writeEquivalences(objects, equivalences, buffer);

    buffer
      ..write(']')
      ..write(msg)
      ..write(')');

    _fail(buffer.toString());
  }

  /// Checks that the expected and actual values are *not* identical
  /// (using `identical`).
  static void notIdentical(
    Object? unexpected,
    Object? actual, [
    String reason = '',
  ]) {
    if (!_identical(unexpected, actual)) {
      return;
    }

    String message = _getMessage(reason);
    _fail('Expect.notIdentical(expected and actual: <$actual>$message) fails.');
  }

  /// Checks that no two [objects] are `identical`.
  static void allDistinct(List<Object?> objects, [String reason = '']) {
    if (objects.length <= 1) {
      return;
    }

    bool allDistinct = true;

    for (int i = 0; i < objects.length; i++) {
      Object? earlierObject = objects[i];

      for (int j = i + 1; j < objects.length; j++) {
        if (_identical(earlierObject, objects[j])) {
          allDistinct = false;
        }
      }
    }

    if (allDistinct) {
      return;
    }

    String message = _getMessage(reason);
    List<List<int>> equivalences = _findEquivalences(objects);
    StringBuffer buffer = StringBuffer('Expect.allDistinct([');
    _writeEquivalences(objects, equivalences, buffer);

    buffer
      ..write(']')
      ..write(message)
      ..write(')');

    _fail(buffer.toString());
  }

  // Unconditional failure.
  // This function always throws, as [_fail] always throws.
  // TODO(srawlins): It would be more correct to change the return type to
  // `Never`, which would require refactoring many language and co19 tests.
  static void fail(String msg) {
    _fail("Expect.fail('$msg')");
  }

  /// Checks that two numbers are relatively close.
  ///
  /// Intended for `double` computations with some tolerance in the result.
  ///
  /// Fails if the difference between expected and actual is greater than the
  /// given tolerance. If no tolerance is given, tolerance is assumed to be the
  /// value 4 significant digits smaller than the value given for expected.
  static void approxEquals(
    num expected,
    num actual, [
    num tolerance = -1,
    String reason = '',
  ]) {
    if (tolerance < 0) {
      tolerance = (expected / 1e4).abs();
    }

    // Note: Use success if `<=` rather than failing on `>`
    // so the test fails on NaNs.
    if ((expected - actual).abs() <= tolerance) {
      return;
    }

    String message = _getMessage(reason);

    _fail(
      'Expect.approxEquals(expected:<$expected>, actual:<$actual>, '
      'tolerance:<$tolerance>$message) fails',
    );
  }

  static void notEquals(
    Object? unexpected,
    Object? actual, [
    String reason = '',
  ]) {
    if (unexpected != actual) {
      return;
    }

    String message = _getMessage(reason);

    _fail(
      'Expect.notEquals(unexpected: <$unexpected>, actual:<$actual>$message) '
      'fails.',
    );
  }

  /// Checks that all elements in [expected] and [actual] are pairwise equal.
  ///
  /// This is different than the typical check for identity equality `identical`
  /// used by the standard list implementation.
  static void listEquals(
    List<Object?> expected,
    List<Object?> actual, [
    String reason = '',
  ]) {
    // Check elements before length.
    // It may show *which* element has been added or is missing.
    int n = (expected.length < actual.length) ? expected.length : actual.length;

    for (int i = 0; i < n; i++) {
      Object? expectedValue = expected[i];
      Object? actualValue = actual[i];

      if (expectedValue != actualValue) {
        String indexReason =
            reason.isEmpty ? 'at index $i' : '$reason, at index $i';
        _failNotEqual(expectedValue, actualValue, 'listEquals', indexReason);
      }
    }

    // Check that the lengths agree as well.
    if (expected.length != actual.length) {
      String message = _getMessage(reason);

      _fail(
        'Expect.listEquals(list length, '
        'expected: <${expected.length}>, actual: <${actual.length}>$message) '
        'fails: Next element <'
        '${expected.length > n ? expected[n] : actual[n]}>',
      );
    }
  }

  /// Checks that all [expected] and [actual] have the same set entries.
  ///
  /// Check that the maps have the same keys, using the semantics of
  /// [Map.containsKey] to determine what "same" means. For
  /// each key, checks that their values are equal using `==`.
  static void mapEquals(
    Map<Object?, Object?> expected,
    Map<Object?, Object?> actual, [
    String reason = '',
  ]) {
    String message = _getMessage(reason);

    // Make sure all of the values are present in both, and they match.
    List<Object?> expectedKeys = expected.keys.toList();

    for (int i = 0; i < expectedKeys.length; i++) {
      Object? key = expectedKeys[i];

      if (!actual.containsKey(key)) {
        _fail('Expect.mapEquals(missing expected key: <$key>$message) fails');
      }

      Object? expectedValue = expected[key];
      Object? actualValue = actual[key];

      if (expectedValue == actualValue) {
        continue;
      }

      _failNotEqual(expectedValue, actualValue, 'mapEquals', 'map[$key]');
    }

    // Make sure the actual map doesn't have any extra keys.
    List<Object?> actualKeys = actual.keys.toList();

    for (int i = 0; i < actualKeys.length; i++) {
      Object? key = actualKeys[i];

      if (!expected.containsKey(key)) {
        _fail('Expect.mapEquals(unexpected key: <$key>$message) fails');
      }
    }

    if (expectedKeys.length != actualKeys.length) {
      _failNotEqual(
        expectedKeys.length,
        actualKeys.length,
        'mapEquals',
        'map.length',
      );
    }
  }

  /// Specialized equality test for strings. When the strings don't match,
  /// this method shows where the mismatch starts and ends.
  static void stringEquals(
    String expected,
    String actual, [
    String reason = '',
  ]) {
    if (expected == actual) {
      return;
    }

    String message = _getMessage(reason);
    String defaultMessage =
        'Expect.stringEquals(expected: <$expected>", <$actual>$message) fails';

    // Scan from the left until we find the mismatch.
    int left = 0;
    int right = 0;
    int expectedLength = expected.length;
    int actualLength = actual.length;

    while (true) {
      if (left == expectedLength ||
          left == actualLength ||
          expected[left] != actual[left]) {
        break;
      }

      left++;
    }

    // Scan from the right until we find the mismatch.
    int expectedRemaining =
        expectedLength - left; // Remaining length ignoring left match.
    int actualRemaining = actualLength - left;

    while (true) {
      if (right == expectedRemaining ||
          right == actualRemaining ||
          expected[expectedLength - right - 1] !=
              actual[actualLength - right - 1]) {
        break;
      }

      right++;
    }

    // First difference is at index `left`, last at `length - right - 1`
    // Make useful difference message.
    // Example:
    // Diff (1209..1209/1246):
    // ...,{"name":"[  ]FallThroug...
    // ...,{"name":"[ IndexError","kind":"class"},{"name":" ]FallThroug...
    // (colors would be great!)

    // Make snippets of up to ten characters before and after differences.

    String leftSnippet = expected.substring(left < 10 ? 0 : left - 10, left);
    int rightSnippetLength = right < 10 ? right : 10;

    String rightSnippet = expected.substring(
      expectedLength - right,
      expectedLength - right + rightSnippetLength,
    );

    // Make snippets of the differences.
    String expectedSnippet = expected.substring(left, expectedLength - right);
    String actualSnippet = actual.substring(left, actualLength - right);

    // If snippets are long, elide the middle.
    if (expectedSnippet.length > 43) {
      expectedSnippet =
          '${expectedSnippet.substring(0, 20)}...'
          '${expectedSnippet.substring(expectedSnippet.length - 20)}';
    }

    if (actualSnippet.length > 43) {
      actualSnippet =
          '${actualSnippet.substring(0, 20)}...'
          '${actualSnippet.substring(actualSnippet.length - 20)}';
    }

    // Add "..." before and after, unless the snippets reach the end.
    String leftLead = '...';
    String rightTail = '...';

    if (left <= 10) {
      leftLead = '';
    }

    if (right <= 10) {
      rightTail = '';
    }

    String diff =
        '\nDiff ($left..${expectedLength - right}/${actualLength - right}):\n'
        '$leftLead$leftSnippet[ $expectedSnippet ]$rightSnippet$rightTail\n'
        '$leftLead$leftSnippet[ $actualSnippet ]$rightSnippet$rightTail';

    _fail('$defaultMessage$diff');
  }

  /// Checks that the [actual] string contains a given substring
  /// [expectedSubstring].
  ///
  /// For example, this succeeds:
  /// ```dart
  /// Expect.contains("a", "abcdefg");
  /// ```
  static void contains(
    String expectedSubstring,
    String actual, [
    String reason = '',
  ]) {
    if (actual.contains(expectedSubstring)) {
      return;
    }

    String message = _getMessage(reason);

    _fail(
      "Expect.contains('${_escapeString(expectedSubstring)}',"
      " '${_escapeString(actual)}'$message) fails",
    );
  }

  /// Checks that the [actual] string contains any of the [expectedSubstrings].
  ///
  /// For example, this succeeds since it contains at least one of the
  /// expected substrings:
  /// ```dart
  /// Expect.containsAny(["a", "e", "h"], "abcdefg");
  /// ```
  static void containsAny(
    List<String> expectedSubstrings,
    String actual, [
    String reason = '',
  ]) {
    for (int i = 0; i < expectedSubstrings.length; i++) {
      if (actual.contains(expectedSubstrings[i])) {
        return;
      }
    }

    String message = _getMessage(reason);

    _fail(
      "Expect.containsAny(..., '${_escapeString(actual)}$message): None of "
      "'${expectedSubstrings.join("', '")}' found",
    );
  }

  /// Checks that [actual] contains the list of [expectedSubstrings] in order.
  ///
  /// For example, this succeeds:
  /// ```dart
  /// Expect.containsInOrder(["a", "c", "e"], "abcdefg");
  /// ```
  static void containsInOrder(
    List<String> expectedSubstrings,
    String actual, [
    String reason = '',
  ]) {
    int start = 0;

    for (int i = 0; i < expectedSubstrings.length; i++) {
      String string = expectedSubstrings[i];
      int position = actual.indexOf(string, start);
      if (position < 0) {
        String msg = _getMessage(reason);

        _fail(
          "Expect.containsInOrder(..., '${_escapeString(actual)}'"
          "$msg): Did not find '${_escapeString(string)}' in the expected "
          "order: '${expectedSubstrings.map(_escapeString).join("', '")}'",
        );
      }
    }
  }

  /// Checks that [actual] contains the same elements as [expected].
  ///
  /// Intended to be used with sets, which has efficient [Set.contains],
  /// but can be used with any collection. The test behaves as if the
  /// collection was converted to a set.
  ///
  /// Should not be used with a lazy iterable, since it calls
  /// [Iterable.contains] repeatedly. Efficiency aside, if separate iterations
  /// can provide different results, the outcome of this test is unspecified.
  /// Should not be used with collections that contain the same value more than
  /// once.
  /// This is *not* an "unordered equality", which would consider `["a", "a"]`
  /// and `["a"]` different. This check would accept those inputs, as if
  /// calling `.toSet()` on the values first.
  ///
  /// Checks that the elements of [expected] are all in [actual],
  /// according to [actual.contains], and vice versa.
  /// Assumes that the sets use the same equality,
  /// which should be `==`-equality.
  static void setEquals(
    Iterable<Object?> expected,
    Iterable<Object?> actual, [
    String reason = '',
  ]) {
    List<Object?> missingElements = <Object?>[];
    List<Object?> extraElements = <Object?>[];
    List<Object?> expectedElements = expected.toList();
    List<Object?> actualElements = actual.toList();

    for (int i = 0; i < expectedElements.length; i++) {
      Object? expectedElement = expectedElements[i];

      if (!actual.contains(expectedElement)) {
        missingElements.add(expectedElement);
      }
    }

    for (int i = 0; i < actualElements.length; i++) {
      Object? actualElement = actualElements[i];

      if (!expected.contains(actualElement)) {
        extraElements.add(actualElement);
      }
    }

    if (missingElements.isEmpty && extraElements.isEmpty) {
      return;
    }

    String message = _getMessage(reason);

    StringBuffer buffer = StringBuffer('Expect.setEquals($message) fails');

    // Report any missing items.
    if (missingElements.isNotEmpty) {
      buffer.write('\nMissing expected elements: ');

      for (Object? value in missingElements) {
        buffer.write('$value ');
      }
    }

    // Report any extra items.
    if (extraElements.isNotEmpty) {
      buffer.write('\nUnexpected elements: ');

      for (Object? value in extraElements) {
        buffer.write('$value ');
      }
    }

    _fail(buffer.toString());
  }

  /// Checks that [expected] is equivalent to [actual].
  ///
  /// If the objects are both `Set`s, `Iterable`s, or `Map`s,
  /// check that they have the same structure:
  /// * For sets: Same elements, based on [Set.contains]. Not recursive.
  /// * For maps: Same keys, based on [Map.containsKey], and with
  ///   recursively deep-equal for the values of each key.
  /// * For other, non-set, iterables: Same length and elements that
  ///   are pair-wise deep-equal.
  ///
  /// Assumes expected and actual maps and sets use the same equality.
  static void deepEquals(Object? expected, Object? actual) {
    _deepEquals(expected, actual, <Object>[]);
  }

  static String _pathString(List<Object> path) {
    return "[${path.join("][")}]";
  }

  /// Recursive implementation of [deepEquals].
  ///
  /// The [path] contains a mutable list of the map keys or list indices
  /// traversed so far.
  static void _deepEquals(Object? expected, Object? actual, List<Object> path) {
    // Early exit check for equality.
    if (expected == actual) {
      return;
    }

    if (expected is Set && actual is Set) {
      List<Object?> expectedElements = expected.toList();
      List<Object?> actualElements = actual.toList();

      for (int i = 0; i < expectedElements.length; i++) {
        Object? value = expectedElements[i];

        if (!actual.contains(value)) {
          _fail(
            'Expect.deepEquals(${_pathString(path)}), '
            'missing value: <$value>',
          );
        }
      }

      for (Object? value in actualElements) {
        if (!expected.contains(value)) {
          _fail(
            'Expect.deepEquals(${_pathString(path)}), '
            'unexpected value: <$value>',
          );
        }
      }
    } else if (expected is Iterable && actual is Iterable) {
      List<Object?> expectedElements = expected.toList();
      List<Object?> actualElements = actual.toList();
      int expectedLength = expectedElements.length;
      int actualLength = actualElements.length;
      int minLength =
          expectedLength < actualLength ? expectedLength : actualLength;

      for (int i = 0; i < minLength; i++) {
        Object? expectedElement = expectedElements[i];
        Object? actualElement = actualElements[i];
        path.add(i);
        _deepEquals(expectedElement, actualElement, path);
        path.removeLast();
      }

      if (expectedLength != actualLength) {
        Object? nextElement =
            (expectedLength > actualLength
                ? expectedElements
                : actualElements)[minLength];

        _fail(
          'Expect.deepEquals(${_pathString(path)}.length, '
          'expected: <$expectedLength>, actual: <$actualLength>) '
          'fails: Next element <$nextElement>',
        );
      }
    } else if (expected is Map && actual is Map) {
      List<Object?> expectedKeys = expected.keys.toList();
      List<Object?> actualKeys = actual.keys.toList();

      // Make sure all of the keys are present in both, and match values.
      for (int i = 0; i < expectedKeys.length; i++) {
        Object? key = expectedKeys[i];

        if (!actual.containsKey(key)) {
          _fail(
            'Expect.deepEquals(${_pathString(path)}), '
            'missing map key: <$key>',
          );
        }

        path.add(key!);
        _deepEquals(expected[key], actual[key], path);
        path.removeLast();
      }

      for (Object? key in actualKeys) {
        if (!expected.containsKey(key)) {
          _fail(
            'Expect.deepEquals(${_pathString(path)}), '
            'unexpected map key: <$key>',
          );
        }
      }
    } else {
      _failNotEqual(expected, actual, 'deepEquals', _pathString(path));
    }
  }

  static bool _defaultCheck(Object? _) {
    return true;
  }

  /// Verifies that [computation] throws a [T].
  ///
  /// Calls the [computation] function and fails if that call doesn't throw,
  /// throws something which is not a [T], or throws a [T] which does not
  /// satisfy the optional [check] function.
  ///
  /// Returns the accepted thrown [T] object, if one is caught.
  /// This value can be checked further, instead of checking it in the [check]
  /// function. For example, to check the content of the thrown object,
  /// you could write this:
  /// ```
  /// var e = Expect.throws<MyException>(myThrowingFunction);
  /// Expect.isTrue(e.myMessage.contains("WARNING"));
  /// ```
  /// The type variable can be omitted, in which case it defaults to [Object],
  /// and the (sub-)type of the object can be checked in [check] instead.
  /// This was traditionally done before Dart had generic methods.
  ///
  /// If `computation` fails another test expectation
  /// (i.e., throws an [ExpectException]),
  /// that exception cannot be caught and accepted by [Expect.throws].
  /// The test is still considered failing.
  static T throws<T extends Object>(
    void Function() computation, [
    bool Function(T error)? check,
    String reason = '',
  ]) {
    try {
      computation();
    } catch (error, stackTrace) {
      // A test failure doesn't count as throwing, and can't be expected.
      if (error is ExpectException) {
        rethrow;
      }

      if (error is T && (check == null || check(error))) {
        return error;
      }

      // Throws something unexpected.
      String message = _getMessage(reason);
      String type = '';

      if (T != dynamic && T != Object) {
        type = '<$T>';
      }

      _fail(
        'Expect.throws$type$message: '
        "Unexpected '${Error.safeToString(error)}'\n$stackTrace",
      );
    }

    _fail('Expect.throws${_getMessage(reason)} fails: Did not throw');
  }

  /// Calls [computation] and checks that it throws an [E] when [condition] is
  /// `true`.
  ///
  /// If [condition] is `true`, the test succeeds if an [E] is thrown, and then
  /// that error is returned. The test fails if nothing is thrown or a different
  /// error is thrown.
  /// If [condition] is `false`, the test succeeds if nothing is thrown,
  /// returning `null`, and fails if anything is thrown.
  static E? throwsWhen<E extends Object>(
    bool condition,
    void Function() computation, [
    String reason = '',
  ]) {
    if (condition) {
      return throws<E>(computation, _defaultCheck, reason);
    }

    computation();
    return null;
  }

  static ArgumentError throwsArgumentError(
    void Function() f, [
    String reason = '',
  ]) {
    return Expect.throws<ArgumentError>(f, _defaultCheck, reason);
  }

  static AssertionError throwsAssertionError(
    void Function() f, [
    String reason = '',
  ]) {
    return Expect.throws<AssertionError>(f, _defaultCheck, reason);
  }

  static FormatException throwsFormatException(
    void Function() f, [
    String reason = '',
  ]) {
    return Expect.throws<FormatException>(f, _defaultCheck, reason);
  }

  static NoSuchMethodError throwsNoSuchMethodError(
    void Function() f, [
    String reason = '',
  ]) {
    return Expect.throws<NoSuchMethodError>(f, _defaultCheck, reason);
  }

  static RangeError throwsRangeError(void Function() f, [String reason = '']) {
    return Expect.throws<RangeError>(f, _defaultCheck, reason);
  }

  static StateError throwsStateError(void Function() f, [String reason = '']) {
    return Expect.throws<StateError>(f, _defaultCheck, reason);
  }

  static TypeError throwsTypeError(void Function() f, [String reason = '']) {
    return Expect.throws<TypeError>(f, _defaultCheck, reason);
  }

  /// Checks that [f] throws a [TypeError] if and only if [condition] is `true`.
  static TypeError? throwsTypeErrorWhen(
    bool condition,
    void Function() f, [
    String reason = '',
  ]) {
    return Expect.throwsWhen<TypeError>(condition, f, reason);
  }

  static UnsupportedError throwsUnsupportedError(
    void Function() f, [
    String reason = '',
  ]) {
    return Expect.throws<UnsupportedError>(f, _defaultCheck, reason);
  }

  /// Reports that there is an error in the test itself and not the code under
  /// test.
  ///
  /// It may be using the expect API incorrectly or failing some other
  /// invariant that the test expects to be true.
  static void testError(String message) {
    _fail('Test error: $message');
  }

  /// Checks that [object] has type [T].
  static void type<T>(Object? object, [String reason = '']) {
    if (object is T) {
      return;
    }

    String message = _getMessage(reason);

    _fail(
      'Expect.type($object is $T$message) fails '
      'on ${Error.safeToString(object)}',
    );
  }

  /// Checks that [object] does not have type [T].
  static void notType<T>(Object? object, [String reason = '']) {
    if (object is! T) {
      return;
    }

    String message = _getMessage(reason);

    _fail(
      'Expect.type($object is! $T$message) fails '
      'on ${Error.safeToString(object)}',
    );
  }

  /// Asserts that `S` is a subtype of `Super` at compile time and run time.
  ///
  /// The upper bound on [S] means that it must *statically* be a subtype
  /// of [Super]. Soundness should guarantee that it is also true at runtime.
  ///
  /// This is more of an assertion than a test.
  // TODO(lrn): Remove this method, or make it only do runtime checks.
  // It doesn't fit the `Expect` class.
  // Use `static_type_helper.dart` or make a `Chk` class a member of the
  // `expect` package for use in checking *static* type properties.
  static void subtype<S extends Super, Super>() {
    if ((<S>[] as Object) is List<Super>) {
      return;
    }

    _fail('Expect.subtype<$S, $Super>: $S is not a subtype of $Super');
  }

  /// Checks that `S` is a subtype of `Super` at runtime.
  ///
  /// This is similar to [S] but without the `Sub extends Super` generic
  /// constraint, so a compiler is less likely to optimize away the `is` check
  /// because the types appear to be unrelated.
  static void runtimeSubtype<S, Super>() {
    if (<S>[] is List<Super>) {
      return;
    }

    _fail(
      'Expect.runtimeSubtype<$S, $Super>: '
      '$S is not a subtype of $Super',
    );
  }

  /// Checks that `S` is not a subtype of `Super` at runtime.
  static void notSubtype<S, Super>() {
    if (<S>[] is List<Super>) {
      _fail('Expect.notSubtype<$S, $Super>: $S is a subtype of $Super');
    }
  }

  static String _getMessage(String reason) {
    return reason.isEmpty ? '' : ", '$reason'";
  }

  static Never _fail(String message) {
    throw ExpectException(message);
  }
}

/// Used in [Expect] because [Expect.identical] shadows the real [identical].
bool _identical(Object? a, Object? b) {
  return identical(a, b);
}

/// Exception thrown on a failed expectation check.
///
/// Always recognized by [Expect.throws] as an unexpected error.
final class ExpectException {
  ExpectException(this.message) : name = _getTestName();

  final String message;

  final String name;

  @override
  String toString() {
    if (name != '') {
      return 'In test "$name" $message';
    }

    return message;
  }

  static String Function() _getTestName = _kEmptyString;

  /// Initial value for _getTestName.
  static String _kEmptyString() {
    return '';
  }

  /// Call this to provide a function that associates a test name with this
  /// failure.
  ///
  /// Used by legacy/async_minitest.dart to inject logic to bind the
  /// `group()` and `test()` name strings to a test failure.
  static void setTestNameCallback(String Function() getName) {
    _getTestName = getName;
  }
}
