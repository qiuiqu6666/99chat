# Local sqflite_common patch

Upstream version: 2.5.8. Original LICENSE and source are retained.

The common database mixin sets `isClosed` before native close and previously
swallowed native close errors. This patch retains and rethrows that error on
the original and subsequent close calls. The application lifecycle host can
then keep its write/open fence closed instead of treating an unconfirmed
native close as successful. It does not retry native close or force reopen.

Regression: `test/sqflite_native_close_contract_test.dart`, using the actual
sqflite plugin/common mixin with a failing platform channel acknowledgment.
