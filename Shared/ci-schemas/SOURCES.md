# CI schemas

JSON schemas that `bin/check-recipes` validates the CI pages' YAML against. Fetched 2026-11-02, unmodified.
Refresh by fetching the URL again and updating the date.

| file | listed in the SchemaStore catalog (https://www.schemastore.org/api/json/catalog.json) as | fetched from |
|---|---|---|
| `gitlab-ci.json` | gitlab-ci | https://gitlab.com/gitlab-org/gitlab-foss/-/raw/master/app/assets/javascripts/editor/schema/ci.json |
| `bitbucket-pipelines.json` | bitbucket-pipelines | https://api.bitbucket.org/schemas/pipelines-configuration |
| `bitrise.json` | bitrise | https://www.schemastore.org/bitrise.json |
| `bitrise-step.json` | bitrise-step, referenced by `bitrise.json` as a relative `$ref` | https://www.schemastore.org/bitrise-step.json |
| `codemagic.json` | codemagic | https://codemagic.io/codemagic-schema.json |
| `circleciconfig.json` | CircleCI config.yml: https://www.schemastore.org/circleciconfig.json is only a `$ref` to this file, vendored so the check needs no network | https://raw.githubusercontent.com/CircleCI-Public/circleci-yaml-language-server/refs/heads/main/schema.json |
| `azure-pipelines.json` | Azure Pipelines | https://raw.githubusercontent.com/microsoft/azure-pipelines-vscode/master/service-schema.json |

GitHub Actions workflows are checked with actionlint, Jenkinsfiles are only checked for balanced
braces and are marked "checked against the docs only" on their page. GitLab, Bitbucket and Azure
publish their schemas themselves (SchemaStore lists them by URL), so these are the same files
SchemaStore points editors at.
