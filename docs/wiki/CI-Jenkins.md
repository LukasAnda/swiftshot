# Jenkins

Verify pull requests in a multibranch pipeline, then approve an `input` stage to accept.

Checked against the docs only: Jenkins has no schema, so the Jenkinsfile below is checked for
balanced braces, not run.

## Verify

```groovy
// swiftshot-recipe: jenkins
// In a Jenkinsfile of the form: pipeline { agent none; stages { <the stages below> } }
stage('Verify') {
  agent { label 'mac' }
  steps {
    sh 'curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh'
    // Differences fail the stage and mark the build unstable; the accept stage still follows.
    catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
      sh '~/.swiftshot/bin/swiftshot verify'
    }
  }
  post {
    always {
      junit 'screenshots-report/junit.xml'
      archiveArtifacts artifacts: 'screenshots-report/**'
      stash name: 'swiftshot-report', includes: 'screenshots-report/**'
    }
  }
}
```

## Accept

```groovy
// swiftshot-recipe: jenkins
stage('Accept screenshots') {
  options {
    timeout(time: 1, unit: 'DAYS')
  }
  when {
    beforeInput true
    allOf {
      changeRequest()
      expression { !env.CHANGE_FORK }
      // Only when verify found differences; a clean pull request never waits for a person.
      expression { currentBuild.currentResult == 'UNSTABLE' }
    }
  }
  input {
    message 'Accept the new screenshots?'
    ok 'Accept'
  }
  agent { label 'git' }
  steps {
    checkout scm
    unstash 'swiftshot-report'
    withCredentials([string(credentialsId: 'swiftshot-host-token', variable: 'SWIFTSHOT_HOST_TOKEN')]) {
      sh '''
        curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
        git checkout -B "$CHANGE_BRANCH"
        ~/.swiftshot/bin/swiftshot accept --from screenshots-report --push
      '''
    }
  }
}
```

Both stages go into the same `stages`, one after the other. Anyone who may use the build
(add `submitter 'alice,bob'` to limit it) presses Accept on the stage; `stash` carries the report
to it. The stage only appears when the build is unstable (the differences), and gives up after a
day. On a Linux agent swiftshot runs on Java: the `git` agent needs JDK 21+.

## Comment

Add a *Secret text* credential `swiftshot-host-token` with a token for your git host. It posts the
comment and pushes over `https`. GitHub: fine-grained, Contents and Pull requests write. GitLab:
`api` and `write_repository`. Bitbucket: repository access token with `repository:write` and
`pullrequest`. Set `SWIFTSHOT_GIT_HOST` (github, gitlab, bitbucket) if the remote's host isn't
`github.com`, `gitlab.com` or `bitbucket.org`.

## Notes

- In the multibranch project's branch source, set the pull request discovery strategy to
  **The current pull request revision**. With the merge strategy `GIT_COMMIT` is a merge
  commit and the report would not match the branch; in that case set `SWIFTSHOT_COMMIT` to
  the pull request's head commit yourself.
- `stash` lasts for the run, so accept must happen in the same build. The `input` stage uses
  no executor while it waits (`agent none` at the top).
- Differences fail the Verify stage and mark the build unstable (yellow, not green); the
  `catchError` keeps the pipeline going so the accept stage can follow.
- Pull requests from forks: accept refuses them (`CHANGE_FORK`).
