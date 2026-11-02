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
          # Exit 1 means differences: the job stays green so the approval can follow.
          command: ~/.swiftshot/bin/swiftshot verify || [ $? -eq 1 ]
      - store_test_results:
          path: screenshots-report
      - store_artifacts:
          path: screenshots-report
          destination: swiftshot-report
      - persist_to_workspace:
          root: .
          paths:
            - screenshots-report
```

`store_test_results` reads `junit.xml` from the report folder; `store_artifacts` keeps the images
for the job's Artifacts tab.

## Accept

```yaml
# swiftshot-recipe: circleciconfig
version: 2.1

jobs:
  accept:
    docker:
      - image: cimg/base:current
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
            - verify
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
- The workspace and the approval both live in the workflow, so verify and accept are one run.
  Workspaces are kept for 15 days; an approval can be given for 90.
- A fork's pull request has no secrets and the key isn't available: accept refuses forks.
- `store_artifacts` links need a CircleCI login on private projects.
