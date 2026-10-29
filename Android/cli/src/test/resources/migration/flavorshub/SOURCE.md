# flavorshub

- Source: https://github.com/droidcon-academy/android-screenshot-testing (commit f7ab5c0237fdb16757792ec4e62220b60de7adf4, directory `source-code/final-project`)
- Licence: Apache-2.0, see `LICENSE` (the project's own licence file, unchanged).

A trimmed copy for Swiftshot's migration tests (`MigrationFixturesTest`): the settings and build scripts, version
catalogs, build-logic sources, the test sources of the modules with screenshot tests, `robolectric.properties`, and the
main sources that declare `@Preview`s or snapshot helpers. Every other file was left out. Copied files are unchanged,
except `strings*.xml`: their strings were removed (only the files' presence is read), which the files say.

`LICENSE` is the repository's root licence; the fixture is its `source-code/final-project` directory.

`expected-*` are what `swiftshot init` writes for this copy, checked by hand against the project's tests.
