# http_io (3.6)

The HTTP APIs in `dart:io` are pure Dart code not relying on native runtime
calls. To enable faster development and bug fixes, these APIs are moving out of
`dart:io` into this package.

TODO:
- Add `WebSocket` implementation with tests.
- Add related `sdk/tests/standalone/io/regress*` tests.
- Add `Socket`, `SecureSocket`, `ServerSocket`, `SecureServerSocket`
  implementations and tests.
