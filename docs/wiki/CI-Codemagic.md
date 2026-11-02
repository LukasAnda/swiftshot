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
          ~/.swiftshot/bin/swiftshot verify
        test_report: screenshots-report/junit.xml
      - name: Zip the report
        ignore_failure: true
        script: zip -qr swiftshot-report.zip screenshots-report
    artifacts:
      - swiftshot-report.zip
      - screenshots-report/**
```

`test_report` shows the differences in the build's test results. The zip step always runs, also
after a failed verify. The workflow runs on pull request branches.

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
          artifact=$(curl -fsS -H "x-auth-token: $CODEMAGIC_TOKEN" "https://api.codemagic.io/builds/$SWIFTSHOT_VERIFY_BUILD" |
            pick "print(next(a['url'] for a in json.load(sys.stdin)['build']['artefacts'] if a['url'].endswith('/swiftshot-report.zip')))")
          url=$(curl -fsS -H "x-auth-token: $CODEMAGIC_TOKEN" -H "Content-Type: application/json" \
            -d "{\"expiresAt\": $(( $(date +%s) + 600 ))}" "$artifact/public-url" |
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
- Codemagic describes `CM_COMMIT` as the pull request's source commit, which is what verify
  records.
- The artifact list of a build is read from the builds API (`build.artefacts`, with that
  spelling); check it against your account if the lookup fails.
