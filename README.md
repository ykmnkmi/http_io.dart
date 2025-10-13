# http_io (3.9.4)

> The HTTP APIs in `dart:io` are pure Dart code not relying on native runtime
> calls. To enable faster development and bug fixes, these APIs are moving out of
> `dart:io` into this package.

Currently, only the stable branch is synced.

TODO:
- Add related `sdk/tests/standalone/io/regress*` tests.
- Add `Socket`, `SecureSocket`, `ServerSocket`, `SecureServerSocket` classes
  and tests.

TESTING:
- Run `dart run tools/run_all_tests.dart` to run all tests.
