# Bitbucket Pipelines

Verify every pull request, and accept the changes with a custom pipeline you run by hand.

## Verify

```yaml
# swiftshot-recipe: bitbucket-pipelines
# iOS needs a Mac runner (runs-on: [self.hosted, macos]); Android needs a JDK 21+ image.
image: atlassian/default-image:4

pipelines:
  pull-requests:
    '**':
      - step:
          name: Verify screenshots
          script:
            - curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
            # The pipeline checks out a merge with the destination; the report is for the source commit.
            - export SWIFTSHOT_COMMIT="$BITBUCKET_COMMIT"
            # The pipeline's own remote is a local proxy: name the real one, after the clone, for the comment.
            - git remote set-url origin "https://bitbucket.org/$BITBUCKET_REPO_FULL_NAME.git"
            - ~/.swiftshot/bin/swiftshot verify
          # Runs after a failed script too: keep the report where the accept pipeline finds it.
          after-script:
            - >
              if [ -d screenshots-report ]; then
              python3 -m zipfile -c "swiftshot-report-$BITBUCKET_COMMIT.zip" screenshots-report &&
              curl -fsS -X POST --header "Authorization: Bearer $SWIFTSHOT_HOST_TOKEN"
              -F "files=@swiftshot-report-$BITBUCKET_COMMIT.zip"
              "https://api.bitbucket.org/2.0/repositories/$BITBUCKET_REPO_FULL_NAME/downloads"; fi
```

A changed screenshot fails the step (`junit.xml` is copied to `test-results/` for the Tests tab).
The after-script uploads the report to the repository's Downloads as
`swiftshot-report-<commit>.zip`, because Bitbucket has no API for a pipeline's artifacts.

## Accept

```yaml
# swiftshot-recipe: bitbucket-pipelines
pipelines:
  custom:
    swiftshot-accept:
      - step:
          name: Accept screenshots
          script:
            - curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
            - export SWIFTSHOT_ARTIFACT_TOKEN="$SWIFTSHOT_HOST_TOKEN"
            # After the clone, so that the push goes to Bitbucket with the token.
            - git remote set-url origin "https://bitbucket.org/$BITBUCKET_REPO_FULL_NAME.git"
            - ~/.swiftshot/bin/swiftshot accept --from "https://api.bitbucket.org/2.0/repositories/$BITBUCKET_REPO_FULL_NAME/downloads/swiftshot-report-$BITBUCKET_COMMIT.zip" --push --branch "$BITBUCKET_BRANCH"
```

Add it to the same `pipelines` as the verify step. Run it from the Pipelines page: "Run
pipeline", the pull request's branch, `swiftshot-accept`. It picks the report of the branch's
latest commit; if the branch moved on, verify again first.

## Comment

Set `SWIFTSHOT_HOST_TOKEN` (secured repository variable) to a **repository access token** with
the scopes `repository`, `repository:write` (push, Downloads) and `pullrequest` (comments).
Set `SWIFTSHOT_GIT_HOST=bitbucket` if your remote isn't `bitbucket.org`.

## Notes

- A failed step stops a pipeline, so a manual step after verify could never be reached: accept is
  its own custom pipeline.
- Pull request pipelines merge the destination branch into the working tree before they run.
  `BITBUCKET_COMMIT` is the pull request's source commit, so `SWIFTSHOT_COMMIT` is set from it.
  The accept pipeline runs on the branch itself, where `BITBUCKET_COMMIT` is the same commit.
- The reports stay in the repository's Downloads (one per verified commit) until someone deletes
  them; remove old ones with `DELETE /2.0/repositories/<workspace>/<repo>/downloads/<name>`.
- Pull requests from forks don't start pipelines.
- A push starts a new pipeline, which verifies the new baseline.
