# http_io (3.10.0)

> The HTTP APIs in `dart:io` are pure Dart code not relying on native runtime calls.
> To enable faster development and bug fixes, these APIs are moving out of `dart:io` into this package.

**NOTE**:
- Only the stable branch is synced.

**WORKING**:
- Add `Socket`, `SecureSocket`, `ServerSocket`, `SecureServerSocket` classes and tests.
  - I replaced `_SocketStreamConsumer._previousWriteHasCompleted`:
    ```dart
    bool get _previousWriteHasCompleted {
      final rawSocket = socket._raw;
      if (rawSocket is _RawSocket) {
        return rawSocket._socket.writeAvailable;
      }
      assert(rawSocket is _RawSecureSocket);
      // _RawSecureSocket has an internal buffering mechanism and it is going
      // to flush its buffer before it shutsdown.
      return true;
    }
    ```
    with
    ```dart
    bool get _previousWriteHasCompleted {
      // _RawSecureSocket has an internal buffering mechanism and it is going
      // to flush its buffer before it shutsdown.
      return true;
    }
    ```
    because, if the `RawSocket.write()` method returned the full number of
    bytes, I assume it is ready for more.

**TODO**:
- Add related `sdk/tests/standalone/io/regress*` tests.

**TESTING**:
- Run `dart run tools/run_all_tests.dart` to run all tests.
