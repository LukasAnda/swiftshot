# cascade

- Source: https://github.com/saket/cascade (commit 7736224c749c0ad2309ff5b90dcf6e18926d350d)
- Licence: Apache-2.0, see `LICENSE.txt` (the project's own licence file, unchanged).

A trimmed copy for Swiftshot's migration tests (`MigrationFixturesTest`): the settings and build scripts, version
catalogs, build-logic sources, the test sources of the modules with screenshot tests, `robolectric.properties`, and the
main sources that declare `@Preview`s or snapshot helpers. Every other file was left out. Copied files are unchanged,
except `strings*.xml`: their strings were removed (only the files' presence is read), which the files say.

`expected-*` are what `swiftshot init` writes for this copy, checked by hand against the project's tests.
