# K.Actions.ReleaseFlow

[![PowerShell 7.4+](https://img.shields.io/badge/PowerShell-7.4%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Automated release orchestration** with guardrails, backflow PRs, and semantic versioning for GitHub Actions.

## 🎯 Purpose

ReleaseFlow automates the entire release process based on branch context:

- **Phase Detection**: Automatically detects Alpha, Beta, or Stable release based on PR branches
- **Guardrails (G1-G5)**: Prevents process violations before they happen
- **Backflow PRs**: Automatically creates PRs to sync main → dev branches after stable releases
- **Single Entry Point**: Just call `New-Release` - everything else is automatic

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    K.Actions.ReleaseFlow/action.yml                     │
│                         (Minimal, nur Boilerplate)                      │
└────────────────────────────────────────┬────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│              K.Actions.ReleaseFlow.psm1 (Orchestrator)                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  EXPORT: New-Release (single public entry point)                        │
│                                                                         │
│  INTERNAL:                                                              │
│  ├── Get-ReleaseContext      → Detects phase from branches              │
│  ├── Test-ReleaseGuardrails  → G1-G5 validation                         │
│  ├── New-AlphaRelease        → Alpha tag + GitHub Release               │
│  ├── New-BetaRelease         → Beta tag + GitHub Release                │
│  ├── Publish-StableRelease   → Publish Draft + Smart tags               │
│  ├── New-BackflowPRs         → PRs to open dev trains                   │
│  └── Get-DraftIntent         → Intent from GitHub API                   │
│                                                                         │
└────────────────────────────────────────┬────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                   K.PSGallery.Smartagr (Tagging Backend)                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  EXPORT:                                                                │
│  ├── New-SemanticReleaseTags     → Creates/updates tags (incl. smart)   │
│  ├── Get-SemanticVersionTags     → Lists all SemVer tags                │
│  ├── Get-LatestSemanticTag       → Latest stable tag                    │
│  ├── Get-NextPreReleaseNumber    → Next alpha/beta number               │
│  ├── Compare-SemanticVersion     → Version comparison                   │
│  └── Test-IsValidSemanticVersion → Validation                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Separation of Concerns

| Component | Responsible for | Knows NOTHING about |
|-----------|----------------|---------------------|
| **ReleaseFlow** | Process orchestration, guardrails, branch/PR management, GitHub API | Tag strategy (moving/static) |
| **Smartagr** | Git tagging, SemVer parsing, smart tags, tag queries | Draft intents, guardrails, PRs |

## 🚀 Quick Start

```yaml
name: Release
on:
  pull_request:
    types: [closed]
    branches: [main, 'dev/v*', 'release/v*']

jobs:
  release:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: GrexyLoco/K.Actions.ReleaseFlow@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
        # No additional parameters needed - everything is auto-detected!
```

## 📊 Phase Detection

`New-Release` automatically detects the phase based on branch context:

| Source Branch | Target Branch | Detected Action |
|---------------|---------------|-----------------|
| `feature/*` | `dev/vX.Y.Z` | → Create Alpha Release |
| `fix/*` | `dev/vX.Y.Z` | → Create Alpha Release |
| `dev/vX.Y.Z` | `release/vX.Y.Z` | → Initiate Freeze (Promotion) |
| `fix/*` | `release/vX.Y.Z` | → Create Beta Release |
| `release/vX.Y.Z` | `main` | → Publish Stable + Backflow PRs |

## 🛡️ Guardrails

| ID | Name | Validates | Blocks |
|----|------|-----------|--------|
| **G1** | Dev-Gate | Draft intent exists for target branch | Merge without intent |
| **G2** | Freeze-Gate | Release branch exists → no new features | Feature PRs after freeze |
| **G3** | Beta-Gate | Only fix commits since freeze | Unauthorized changes |
| **G4** | Stable-Gate | CI green, all betas successful | Broken release |
| **G5** | Feature-Freeze-Enforcement | `ISFEATUREFREEZE=true` → only bugfixes | Feature PRs during freeze |

## 🔄 Version Updates

ReleaseFlow automatically updates project version files during each release:

### Supported Project Types

- **PowerShell Modules** (`.psd1`): Updates `ModuleVersion` and `Prerelease` in module manifests
- **.NET Projects** (`.csproj`, `Directory.Build.props`): Updates `VersionPrefix` and `VersionSuffix`

### How It Works

1. **Automatic Detection**: ReleaseFlow scans for project files in your repository
2. **Version Update**: Updates version numbers based on the release tag (e.g., `v1.2.3-alpha1`)
3. **Commit with [skip ci]**: Creates a commit with `[skip ci]` to prevent infinite loops
4. **Push to Branch**: Pushes the version update commit to the appropriate branch

### Version Format

- **Alpha/Beta**: Uses format without dots (e.g., `alpha1`, `beta2`)
- **Stable**: No prerelease suffix
- **Example**:
  - Alpha: `ModuleVersion = '1.2.3'` + `Prerelease = 'alpha1'`
  - Stable: `ModuleVersion = '1.2.3'` (Prerelease removed)

### Implementation Details

The version update process uses three internal functions:

- `Update-ProjectVersion`: Orchestrator that detects project types
- `Update-PowerShellVersion`: Handler for `.psd1` files
- `Update-DotNetVersion`: Handler for `.csproj` and `Directory.Build.props` files

All version updates are tested with comprehensive Pester tests.

## ✅ Validation Workflow

To prevent syntax errors in version files from being committed unnoticed, ReleaseFlow includes a **validation workflow** that runs even when commits include `[skip ci]`.

### Why Validation is Important

Version updates are committed with `[skip ci]` to avoid infinite CI loops. However, this means no validations are performed, and syntax errors in `.psd1` or `.csproj` files could slip through undetected.

### How It Works

The validation workflow uses **path filters** to trigger only when version files are modified:

- **PowerShell Manifests** (`.psd1`): Validated with `Test-ModuleManifest`
- **.NET Projects** (`.csproj`, `Directory.Build.props`): XML syntax validation + MSBuild validation

### Setup

Copy the template workflow to your repository:

```bash
cp examples/version-validation.yml .github/workflows/version-validation.yml
```

Or use it directly in this repository - it's already configured at `.github/workflows/version-validation.yml`.

### Extensibility

The workflow is modular and can be extended for other project types:

- **Node.js**: Add `**/package.json` to paths and validate JSON syntax
- **SQL Projects**: Add `**/*.sqlproj` and validate XML
- **Maven/Gradle**: Add `**/pom.xml` or `**/build.gradle` with appropriate validation

See [examples/version-validation.yml](examples/version-validation.yml) for the complete template with extension examples.

## 📥 Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `github-token` | ✅ | - | GitHub token for API access |
| `smartagr-version` | ❌ | `latest` | Version of K.PSGallery.Smartagr |

## 📤 Outputs

| Output | Description |
|--------|-------------|
| `phase` | Detected phase (alpha, beta, stable, freeze) |
| `version` | Released version |
| `release-url` | URL of created GitHub release |
| `tags-created` | Comma-separated list of tags |
| `backflow-prs` | Backflow PR URLs (stable only) |

## 🎬 PO Dispatch: Planning New Releases

The `New-ReleaseTrain` function allows Product Owners to start a new release train by creating a **Version Intent** and corresponding **dev branch** atomically.

### Quick Start

```yaml
name: Plan Release (PO Dispatch)

on:
  workflow_dispatch:
    inputs:
      target_version:
        description: 'Zielversion (ohne v-Prefix, z.B. 2.0.0)'
        required: true
        type: string

jobs:
  plan-release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Import ReleaseFlow
        shell: pwsh
        run: |
          Import-Module ./K.Actions.ReleaseFlow.psd1

      - name: Create Release Train
        shell: pwsh
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          New-ReleaseTrain -TargetVersion '${{ inputs.target_version }}'
```

### What Gets Created

When you run `New-ReleaseTrain -TargetVersion "2.0.0"`:

1. **Draft Release (Intent)**: A draft GitHub release with tag `v2.0.0` that serves as the version intent
2. **Dev Branch**: Branch `dev/v2.0.0` created from the latest stable tag (or `main` if no stable tags exist)

### Guardrails

| ID | Name | Validates |
|----|------|-----------|
| **PD-1** | Intent-Exists | Prevents creating duplicate draft intents |
| **PD-2** | Tag-Exists | Prevents using an already-tagged version |
| **PD-3** | Branch-Exists | Prevents creating duplicate dev branches |
| **PD-4** | Base-Valid | Ensures the base commit/tag exists |

### Atomic Operation

If any step fails (e.g., draft creation fails after branch creation), all changes are automatically rolled back to maintain consistency.

### Usage Examples

```powershell
# Start new release train from latest stable tag
New-ReleaseTrain -TargetVersion "2.0.0"

# Start from specific tag
New-ReleaseTrain -TargetVersion "1.5.0" -Base "v1.4.0"

# Start from main branch
New-ReleaseTrain -TargetVersion "3.0.0" -Base "main"

# Dry-run to see what would happen
New-ReleaseTrain -TargetVersion "2.0.0" -WhatIf
```

For a complete workflow example, see [examples/plan-release.yml](examples/plan-release.yml).

## 📚 Documentation

- [USAGE.md](USAGE.md) - Detailed usage guide, troubleshooting, and FAQ
- [examples/](examples/) - Ready-to-use workflow templates
- [Concept Document](K/branching_semver_cicd_concept_backflow_updated.md) - Full branching and versioning strategy
- [K.PSGallery.Smartagr](https://github.com/GrexyLoco/K.PSGallery.Smartagr) - Tagging backend

## 📋 Project Structure

```
K.Actions.ReleaseFlow/
├── action.yml                      # GitHub Action definition
├── LICENSE                         # MIT License
├── README.md                       # This file
├── USAGE.md                        # Detailed usage guide
├── K.Actions.ReleaseFlow.psd1      # Module manifest
├── K.Actions.ReleaseFlow.psm1      # Module loader
├── .github/
│   └── workflows/
│       └── version-validation.yml  # Version file validation workflow
├── examples/
│   ├── basic.yml                   # Minimal workflow
│   ├── advanced.yml                # With outputs and notifications
│   ├── plan-release.yml            # PO Dispatch workflow
│   └── version-validation.yml      # Validation workflow template
├── Functions/
│   ├── Public/
│   │   ├── New-Release.ps1         # Single entry point
│   │   └── New-ReleaseTrain.ps1    # PO Dispatch: Create release train
│   └── Private/
│       ├── Get-ReleaseContext.ps1
│       ├── Test-ReleaseGuardrails.ps1
│       ├── New-AlphaRelease.ps1
│       ├── New-BetaRelease.ps1
│       ├── Publish-StableRelease.ps1
│       ├── New-BackflowPRs.ps1
│       ├── Get-DraftIntent.ps1
│       ├── Update-ProjectVersion.ps1
│       └── Handlers/
│           ├── Update-PowerShellVersion.ps1
│           └── Update-DotNetVersion.ps1
└── Tests/
    └── *.Tests.ps1
```

## 🔗 Related Projects

- [K.PSGallery.Smartagr](https://github.com/GrexyLoco/K.PSGallery.Smartagr) - Semantic versioning and smart tagging
- [K.Actions.NextVersion](https://github.com/GrexyLoco/K.Actions.NextVersion) - Version calculation from commits

## 📄 License

[MIT](LICENSE) © GrexyLoco
