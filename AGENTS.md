# kube-powertools AGENTS.md

Repository: https://github.com/chgl/kube-powertools

## Overview

Docker image bundling 30+ Kubernetes and Helm linting/auditing tools. Built for CI/CD pipelines and local validation of K8s manifests and Helm charts.

## Quick Start

```bash
# Build locally
docker build -t kube-powertools:dev .

# Run with local charts mounted
docker run --rm -it -v $PWD:/root/workspace kube-powertools:dev

# Inside container: lint sample charts
CHARTS_DIR=samples/charts chart-powerlint.sh
```

## Key Scripts

Located in `scripts/`:

- `chart-powerlint.sh` - Comprehensive linting (helm lint, kubeconform, pluto, polaris, optional kube-linter/kube-score/kubescape)
- `generate-docs.sh` - Auto-generates chart READMEs via `chart-doc-gen` (if `doc.yaml` exists) or `helm-docs`
- `generate-schemas.sh` - Generates JSON schemas from `values.yaml`
- `generate-chart-changelog.sh` - Creates CHANGELOG from Chart.yaml `artifacthub.io/changes` annotations

## CI/CD Architecture

Uses **reusable workflows** from `chgl/.github` repository:

- `standard-build.yaml` - Docker build, test, sign (cosign), SLSA Level 3 provenance
- `standard-lint.yaml` - MegaLinter, Trivy, Checkov
- `standard-release.yaml` - Semantic release with conventional commits

Image publishes to both `ghcr.io/chgl/kube-powertools` and `docker.io/chgl/kube-powertools`.

## Linting & Scanning Config

| Tool         | Config File          | Notes                                                       |
| ------------ | -------------------- | ----------------------------------------------------------- |
| MegaLinter   | `.mega-linter.yml`   | Disables SPELL, COPYPASTE, YAML linting                     |
| Checkov      | `.checkov.yml`       | Skips Docker and K8s checks (CKV*DOCKER*_, CKV*K8S*_)       |
| KICS         | `.kics.yaml`         | Excludes `samples/charts/`                                  |
| ShellCheck   | `.shellcheckrc`      | Disables SC2086 (word splitting)                            |
| Yamllint     | `.yamllint`          | Line-length disabled; ignores `samples/charts/**/templates` |
| Markdownlint | `.markdownlint.yaml` | MD013 (line length) disabled                                |
| Lychee       | `.lychee.toml`       | Excludes nip.io, example URLs, GitHub compare links         |

## Release Process

- **Semantic Release**: Configured in `.releaserc.json`
- **Preset**: `conventionalcommits`
- **Special rules**: `chore(deps)` and `build` types trigger patch releases
- **Auto-updates**: README.md image tags are replaced on release
- **Requires**: Conventional commit messages (`feat:`, `fix:`, `chore(deps):`, etc.)

## Dependency Management

Renovate config (`.renovaterc.json`):

- Weekly schedule, groups non-major updates
- Auto-merge minor and digest updates
- Custom regex manager for Dockerfile ARG versions (reads `datasource=... depName=...` comments)
- Special handling for Kustomize, kube-linter, polaris, kubent, checkov versioning

## Sample Charts

`samples/charts/` contains example Helm charts:

- `sample/` - Full application chart with security best practices (non-root, read-only root fs, seccomp)
- `library/` - Library chart example
- `empty-changelog/` - Demonstrates changelog generation

Charts use `artifacthub.io/changes` annotation for changelog generation.

## Security & Signing

- Images signed with **cosign** (keyless via OIDC)
- **SLSA Level 3** provenance attestations
- Verification commands in README.md

## Important Patterns

### Dockerfile Tool Installation

Tools installed via versioned ARGs with Renovate-tracked comments:

```dockerfile
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION=4.1.3
```

### Chart Linting Environment Variables

| Variable                     | Default                | Purpose                                                 |
| ---------------------------- | ---------------------- | ------------------------------------------------------- |
| `CHARTS_DIR`                 | `charts`               | Directory containing Helm charts                        |
| `SHOULD_UPDATE_DEPENDENCIES` | `""`                   | Set to `1` to run `helm dependency update`              |
| `KUBERNETES_VERSIONS`        | `1.32.0 1.33.0 1.34.0` | Space-separated K8s versions to validate against        |
| `POLARIS_SCORE_THRESHOLD`    | `90`                   | Minimum Polaris audit score                             |
| `SKIP_KUBE_SCORE`            | `1`                    | Set to `0` to enable kube-score                         |
| `SKIP_KUBE_LINTER`           | `1`                    | Set to `0` to enable kube-linter                        |
| `SKIP_KUBE_SCAPE`            | `1`                    | Set to `0` to enable kubescape (NSA + MITRE frameworks) |

### Pre-commit Hooks

Standard hooks only: trailing-whitespace, end-of-file-fixer, check-yaml (allows multi-doc YAML, excludes templates).

## EditorConfig

- Shell scripts: LF line endings
- JSON/YAML: 2-space indent
- All files: UTF-8, final newline

## Gotchas

- **Helm version in Dockerfile**: Set to `4.1.3` (seems like a placeholder - actual Helm versions are v3.x)
- **Requirements.txt**: Generated via `uv pip compile --generate-hashes requirements.in`
- **Package.json**: Only for `markdownlint-cli` and `prettier` (Node tools)
- **CI workflows**: Referenced by commit SHA, not tag (pinning for security)
- **Trivy/Grype**: Disabled in MegaLinter (run separately via reusable workflow)
