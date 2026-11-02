# Azure Pipelines

Verify pull requests, then approve a stage of the same run to accept.

## Verify

```yaml
# swiftshot-recipe: azure-pipelines
trigger: none
pr:
  - main

stages:
  - stage: Verify
    jobs:
      - job: verify
        pool:
          vmImage: macos-latest
        steps:
          - checkout: self
          - script: |
              curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
              ~/.swiftshot/bin/swiftshot verify
            displayName: Verify
          - task: PublishPipelineArtifact@1
            condition: succeededOrFailed()
            inputs:
              targetPath: screenshots-report
              artifact: swiftshot-report
```

`verify` publishes the JUnit results and the summary to the run itself. Add a
`PublishTestResults@2` task for `screenshots-report/junit.xml` only if you want it in your own
test run. For Azure Repos, use a branch policy (build validation) instead of `pr:`.

## Accept

```yaml
# swiftshot-recipe: azure-pipelines
stages:
  - stage: Accept
    displayName: Accept screenshots
    dependsOn: Verify
    condition: and(succeededOrFailed(), eq(variables['Build.Reason'], 'PullRequest'))
    jobs:
      - job: wait
        pool: server
        timeoutInMinutes: "4320"
        steps:
          - task: ManualValidation@0
            timeoutInMinutes: 1440
            inputs:
              notifyUsers: ''
              instructions: Accept the new screenshots?
              onTimeout: reject
      - job: accept
        dependsOn: wait
        pool:
          vmImage: macos-latest
        steps:
          - checkout: self
            persistCredentials: "true"
            fetchDepth: "0"
          - task: DownloadPipelineArtifact@2
            inputs:
              artifactName: swiftshot-report
              targetPath: $(Pipeline.Workspace)/swiftshot-report
          - script: |
              curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
              branch="${SYSTEM_PULLREQUEST_SOURCEBRANCH#refs/heads/}"
              git fetch origin "$branch"
              git checkout -B "$branch" "origin/$branch"
              ~/.swiftshot/bin/swiftshot accept --from "$(Pipeline.Workspace)/swiftshot-report" --push
            displayName: Accept
```

Both snippets are stages of one file. Users with the **Queue builds** permission approve the
`Accept screenshots` stage in the run, and the stage rejects itself after a day.

## Comment

- **Azure Repos**: no token. Give `<project> Build Service (<organization>)` the permissions
  Contribute, Create branch and Read on the repository (Project settings, Repos, Security);
  `persistCredentials: true` lets `accept` push with it. Azure Repos has no comment support:
  the run's summary and test results carry the result.
- **GitHub or Bitbucket repository**: set `SWIFTSHOT_HOST_TOKEN` as a secret variable and pass it
  to the verify and accept scripts with `env: SWIFTSHOT_HOST_TOKEN: $(SWIFTSHOT_HOST_TOKEN)`;
  secrets aren't exposed to scripts otherwise. Use `persistCredentials: false` there. GitHub:
  fine-grained token with Contents and Pull requests write. Bitbucket: repository access token
  with `repository:write` and `pullrequest`.

## Notes

- Azure builds the merge of the pull request; `verify` records the pull request's source commit
  (`System.PullRequest.SourceCommitId`), and the accept job checks out the source branch so both
  refer to the same commit. If the branch moved on, accept refuses and says to verify again.
- The pipeline artifact is read in the accept job with `DownloadPipelineArtifact@2`; no token goes
  to the REST API.
- The server job that holds the approval can't run scripts, hence the second job.
- Fork pull requests: accept refuses them.
