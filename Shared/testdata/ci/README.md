Golden fixtures for CI detection (`Ci.detect`, [docs/wiki/Baseline-format.md](../../../docs/wiki/Baseline-format.md#ci-detection)),
shared by the Swift and the JVM implementation. One file per case:

```json
{"env": {"GITLAB_CI": "true", …}, "files": {"<path>": <json>}, "expected": {…}}
```

- `env`: the whole environment of the process (nothing else is read).
- `files`: files `Ci.detect` may read, by the path the environment gives (`GITHUB_EVENT_PATH`). A path
  that is not listed is unreadable. A string value is the file's text, anything else its JSON.
- `expected`: every field of `Ci` (`provider`, `commit`, `branch`, `pullRequest`, `fork`, `buildUrl`,
  `repository`; `null` when unknown), `isCi` (whether the `ci` of a report is not `null`) and the
  `warnings` printed. Both implementations compare all of them; `python3 -I ../baseline/make.py`
  checks the files against its own reference.

Values are examples from each provider's documentation (see the contract for the sources).
