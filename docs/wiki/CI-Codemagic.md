# Codemagic

Verify in one workflow, accept in a second one you start by hand.

## Verify

```yaml
# swiftshot-recipe: codemagic
workflows:
  swiftshot-verify:
    name: swiftshot verify
    instance_type: mac_mini_m2
    triggering:
      events:
        - pull_request
      branch_patterns:
        - pattern: '*'
          include: true
          source: true
    scripts:
      - name: swiftshot verify
        script: |
          curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
          ~/.swiftshot/bin/swiftshot verify && status=0 || status=$?
          # Zip also after differences, then fail the build with verify's exit code.
          [ ! -d screenshots-report ] || zip -qr swiftshot-report.zip screenshots-report
          exit $status
        test_report: screenshots-report/junit.xml
    artifacts:
      - swiftshot-report.zip
      - screenshots-report/**
```

`test_report` shows the differences in the build's test results. The script zips the report before
it exits with verify's exit code, so a build with differences fails and still has the zip.
The workflow runs on pull request branches. Unzip the report and open `index.html`; Codemagic gives
no build URL, so the comment has no **Full report** link.

## Accept

```yaml
# swiftshot-recipe: codemagic
workflows:
  swiftshot-accept:
    name: swiftshot accept
    instance_type: mac_mini_m2
    scripts:
      - name: swiftshot accept
        script: |
          set -eu
          curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
          pick() { python3 -c "import json,sys; $1"; }
          # The headers come from stdin, so the token is not on curl's command line.
          api() { printf 'x-auth-token: %s\nContent-Type: application/json\n' "$CODEMAGIC_TOKEN" | curl -fsS -H @- "$@"; }
          artifact=$(api "https://api.codemagic.io/builds/$SWIFTSHOT_VERIFY_BUILD" |
            pick "print(next(a['url'] for a in json.load(sys.stdin)['build']['artefacts'] if a['url'].endswith('/swiftshot-report.zip')))")
          url=$(api -d "{\"expiresAt\": $(( $(date +%s) + 600 ))}" "$artifact/public-url" |
            pick "print(json.load(sys.stdin)['url'])")
          ~/.swiftshot/bin/swiftshot accept --from "$url" --push
```

This workflow has no triggers, so it only starts by hand: "Start new build" on the pull request's
branch with the workflow `swiftshot-accept` and the variable `SWIFTSHOT_VERIFY_BUILD` set to the
verify build's id (the last part of its URL), or the same through the builds API.

## Comment

Set these as secure variables:

- `CODEMAGIC_TOKEN`: a Codemagic API token, to find the verify build's artifact.
- `SWIFTSHOT_HOST_TOKEN`: a token for your git host, which comments and pushes over `https`.
  GitHub: fine-grained, Contents and Pull requests write. GitLab: `api` and `write_repository`.
  Bitbucket: repository access token with `repository:write` and `pullrequest`.

Codemagic documents pushing only over `https` with a token, so there is no SSH variant.

## Notes

- The link from the public-url call is short-lived and open to anyone who has it, so it expires in
  ten minutes and is passed to `accept` without a token.
- Codemagic's docs don't say whether artifacts and `test_report` are kept for a failed build; check
  that the zip appears on your first build with a difference.
- Codemagic describes `CM_COMMIT` as the pull request's source commit, which is what verify
  records.
- The artifact list of a build is read from the builds API (`build.artefacts`, with that
  spelling); check it against your account if the lookup fails.
