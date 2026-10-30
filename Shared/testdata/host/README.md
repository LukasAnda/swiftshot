Golden fixture for git host detection (`Host.detect`, [docs/wiki/Baseline-format.md](../../../docs/wiki/Baseline-format.md#git-host)),
shared by the Swift and the JVM implementation. `remotes.json` is a list of

```json
{"remote": "<git remote get-url origin, or null>", "env": {…}, "expected": {"kind", "api", "project", "web"} | null}
```

`env` is the whole environment of the process (nothing else is read). `expected` is `null` when the host is unknown.
