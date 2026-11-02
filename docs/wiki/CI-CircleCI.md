# CircleCI

Verify on every push, then approve a job in the same workflow to accept.

## Verify

```yaml
# swiftshot-recipe: circleciconfig
version: 2.1

jobs:
  verify:
    # iOS: a Mac executor with an Xcode version CircleCI offers.
    # Android: a Linux image with JDK 21+ instead.
    macos:
      xcode: "26.0.0"
    steps:
      - checkout
      - run:
          name: Install swiftshot
          command: curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
      - run:
          name: Verify
          command: ~/.swiftshot/bin/swiftshot verify
      # The steps below run after a failed verify too.
      - store_test_results:
          when: always
          path: screenshots-report
      - store_artifacts:
          when: always
          path: screenshots-report
          destination: swiftshot-report
      - persist_to_workspace:
          when: always
          root: .
          paths:
            - screenshots-report
```

A changed screenshot fails the job. `store_test_results` reads `junit.xml` from the report folder; `store_artifacts` keeps the images
for the job's Artifacts tab.

## Accept

```yaml
# swiftshot-recipe: circleciconfig
version: 2.1

jobs:
  accept:
    docker:
      - image: cimg/openjdk:21.0
    steps:
      - checkout
      - attach_workspace:
          at: .
      # A read-write deploy key added under Project Settings, SSH Keys.
      - add_ssh_keys:
          fingerprints:
            - "SHA256:replace-with-the-fingerprint"
      - run:
          name: Install swiftshot
          command: curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=1.0.0 sh
      - run:
          name: Accept
          command: ~/.swiftshot/bin/swiftshot accept --from screenshots-report --push

workflows:
  screenshots:
    jobs:
      - verify
      - accept-screenshots:
          type: approval
          requires:
            - verify:
                - failed
      - accept:
          requires:
            - accept-screenshots
```

Both snippets are one `config.yml`. Whoever has push access
approves `accept-screenshots` in the workflow view; `accept` then pushes the new baseline.

## Comment

Set `SWIFTSHOT_HOST_TOKEN` as a project environment variable to post the pull request comment
(GitHub: fine-grained, Pull requests write; GitLab: `api`; Bitbucket: `pullrequest`). It also
pushes over `https` if you'd rather not add an SSH key (GitHub: Contents write; GitLab:
`write_repository`; Bitbucket: `repository:write`).

## Notes

- CircleCI's checkout key is read-only, hence `add_ssh_keys`. The key must be added in the
  project settings; an environment variable can't hold it.
- The approval only appears when verify failed, so a clean run never waits for a person
  (`requires` with a status is CircleCI's "flexible requires"). The workspace and the approval both
  live in the workflow, so verify and accept are one run. Workspaces are kept for 15 days; an
  approval can be given for 90.
- CircleCI's docs don't say that a failed job's workspace can be attached by a later job. If
  `attach_workspace` finds nothing in your first failing run, download the `swiftshot-report`
  artifact instead.
- A fork's pull request has no secrets and the key isn't available: accept refuses forks.
- `store_artifacts` links need a CircleCI login on private projects.
