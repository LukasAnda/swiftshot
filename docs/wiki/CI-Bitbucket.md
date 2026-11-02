# Bitbucket Pipelines

Verify every pull request and accept the changes with a manual step in the same pipeline.

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
            # The pipeline's own remote is a local proxy: name the real one for the comment.
            - git remote set-url origin "https://bitbucket.org/$BITBUCKET_REPO_FULL_NAME.git"
            # Exit 1 means differences: the step stays green so the accept step can follow.
            - ~/.swiftshot/bin/swiftshot verify || [ $? -eq 1 ]
          artifacts:
            - screenshots-report/**
```

A failing step stops a Bitbucket pipeline, so differences are reported in the pull request
comment and in the Tests tab (`junit.xml` is copied to `test-results/`), not as a red step.
Exit codes 2 and 64 still fail the step.

## Accept

```yaml
# swiftshot-recipe: bitbucket-pipelines
pipelines:
  pull-requests:
    '**':
      - step:
          name: Accept screenshots
          trigger: manual
          script:
            - curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
            - git remote set-url origin "https://bitbucket.org/$BITBUCKET_REPO_FULL_NAME.git"
            - git fetch origin "$BITBUCKET_BRANCH"
            # Back to the source commit the report is from.
            - git checkout -B "$BITBUCKET_BRANCH" "$BITBUCKET_COMMIT"
            - ~/.swiftshot/bin/swiftshot accept --from screenshots-report --push --branch "$BITBUCKET_BRANCH"
```

Put it after the verify step in the same `pull-requests` pipeline (the two snippets are one
file). It runs when someone presses Run on it in the pipeline.

## Comment

Set `SWIFTSHOT_HOST_TOKEN` (secured repository variable) to a **repository access token** with
the scopes `repository`, `repository:write` (push) and `pullrequest` (comments). Export
`SWIFTSHOT_GIT_HOST=bitbucket` if your remote isn't `bitbucket.org`.

## Notes

- Bitbucket has no API to fetch a previous pipeline's artifacts, so accept must be a step of
  the same pipeline as verify. Artifacts last 14 days at most.
- Pull request pipelines merge the destination branch into the working tree before they run.
  `BITBUCKET_COMMIT` is the pull request's source commit, so `SWIFTSHOT_COMMIT` is set from it,
  and the accept step goes back to that commit before it accepts.
- Pull requests from forks don't start pipelines.
- A push starts a new pipeline, which verifies the new baseline.
