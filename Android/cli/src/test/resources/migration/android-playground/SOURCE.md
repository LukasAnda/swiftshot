# android-playground

- Source: https://github.com/SimonMarquis/Android-Playground (commit dab3405cb72f36ed011e6c9b03493a12376fab4b)
- Licence: MIT, see `LICENSE` (the project's own licence file, unchanged).

A trimmed copy for Swiftshot's migration tests (`MigrationFixturesTest`): the settings and build scripts, version
catalogs, build-logic sources, the test sources of the modules with screenshot tests, `robolectric.properties`, and the
main sources that declare `@Preview`s or snapshot helpers. Every other file was left out. Copied files are unchanged,
except `strings*.xml`: their strings were removed (only the files' presence is read), which the files say.

`expected-*` are what `swiftshot init` writes for this copy, checked by hand against the project's tests.
