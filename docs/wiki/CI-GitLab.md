# GitLab CI

Verify every merge request, publish the report, and let a person accept the changes with one click.

## Verify

```yaml
# swiftshot-recipe: gitlab-ci
stages: [verify, accept]

# iOS needs a Mac runner (add its tags); Android needs a JDK 21+ image.
verify:
  stage: verify
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  script:
    - curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
    - ~/.swiftshot/bin/swiftshot verify
  # Exit 1 means differences: the job warns and the accept job can follow. Other codes still fail.
  allow_failure:
    exit_codes: 1
  artifacts:
    when: always
    expire_in: 14 days
    paths:
      - screenshots-report/
    expose_as: swiftshot report
    reports:
      junit: screenshots-report/junit.xml
```

`junit.xml` fills the merge request's test summary, `expose_as` links the report in the merge
request, and `summary.md` is in the report folder.

## Accept

```yaml
# swiftshot-recipe: gitlab-ci
swiftshot-accept:
  stage: accept
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: manual
      allow_failure: true
  needs:
    - job: verify
      artifacts: true
  script:
    - curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
    # The runner's origin carries the job token; push with SWIFTSHOT_HOST_TOKEN instead.
    - git remote set-url origin "$CI_SERVER_URL/$CI_PROJECT_PATH.git"
    - ~/.swiftshot/bin/swiftshot accept --from screenshots-report --push
```

Run the job from the merge request's pipeline. It commits the new screenshots to the merge
request's source branch, which starts a new pipeline. To take only some, add
`--only "<id>,<id>"`.

## Comment

Set `SWIFTSHOT_HOST_TOKEN` (CI/CD variable, masked) to a **project access token** with the scopes
`api` (merge request comments) and `write_repository` (push) and the Developer role or higher.
Without it nothing is posted and the push uses the runner's own credentials, which usually
can't push.

## Notes

- A job token can't comment, and can push only if the project allows it (Settings, CI/CD, Job
  token permissions); the access token above works either way.
- Merge request pipelines from a fork run in the fork: accept refuses them.
- With "merged results" pipelines the job renders the merge, not the source branch; use plain
  merge request pipelines for screenshot tests.
- Reports expire with the artifacts (14 days above).
- `accept` pushes the commit with the access token over `https`; self-managed GitLab works the
  same, set `SWIFTSHOT_GIT_HOST=gitlab` if the host isn't recognised.
