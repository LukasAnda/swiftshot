# Bitrise

Verify in one workflow, accept in a second one you start by hand.

## Verify

```yaml
# swiftshot-recipe: bitrise
format_version: "11"

workflows:
  swiftshot-verify:
    steps:
      - git-clone@8:
          inputs:
            - merge_pr: "no"
      - script@1:
          title: swiftshot verify
          inputs:
            - content: |
                #!/usr/bin/env bash
                set -eu
                curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
                ~/.swiftshot/bin/swiftshot verify
      - deploy-to-bitrise-io@2:
          is_always_run: true
```

Start it from a trigger on pull requests. `verify` writes `swiftshot-report.zip` to
`$BITRISE_DEPLOY_DIR` and its test results to the Test Reports tab itself; the deploy step
uploads both, also when verify failed.

## Accept

```yaml
# swiftshot-recipe: bitrise
format_version: "11"

workflows:
  swiftshot-accept:
    steps:
      - git-clone@8:
          inputs:
            - merge_pr: "no"
      - script@1:
          title: swiftshot accept
          inputs:
            - content: |
                #!/usr/bin/env bash
                set -eu
                curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
                api="https://api.bitrise.io/v0.1/apps/$BITRISE_APP_SLUG/builds/$SWIFTSHOT_VERIFY_BUILD/artifacts"
                pick() { python3 -c "import json,sys; $1"; }
                # The header comes from stdin, so the token is not on curl's command line.
                get() { printf 'Authorization: %s\n' "$BITRISE_TOKEN" | curl -fsS -H @- "$1"; }
                slug=$(get "$api" |
                  pick "print(next(a['slug'] for a in json.load(sys.stdin)['data'] if a['title'] == 'swiftshot-report.zip'))")
                url=$(get "$api/$slug" | pick "print(json.load(sys.stdin)['data']['expiring_download_url'])")
                ~/.swiftshot/bin/swiftshot accept --from "$url" --push
```

Start `swiftshot-accept` on the pull request's branch ("Start/Schedule a build") with the
environment variable `SWIFTSHOT_VERIFY_BUILD` set to the slug of the verify build (the last part
of its URL). The download link is signed and short-lived, so no token goes with it.

## Comment

Set these as secrets:

- `BITRISE_TOKEN`: a Bitrise personal access token, to list the verify build's artifacts.
- `SWIFTSHOT_HOST_TOKEN`: a token for your git host. GitHub: fine-grained, Contents and Pull
  requests write. GitLab: `api` and `write_repository`. Bitbucket: repository access token with
  `repository:write` and `pullrequest`. It posts the comment and, over `https`, pushes.

To push over SSH instead, give the app an SSH key with write access: Bitrise's default
deploy key is usually read-only. Without a push token the SSH key is what accept uses.

## Notes

- Bitrise builds the merge of the pull request by default; `merge_pr: "no"` checks out its head
  so the report and the accept refer to the same commit.
- Artifacts are kept for 365 days; a signed link lasts about ten minutes, so the accept build
  fetches it when it runs.
- Accept won't run for pull requests from forks.
