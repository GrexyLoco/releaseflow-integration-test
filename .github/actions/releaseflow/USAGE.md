# K.Actions.ReleaseFlow – Usage Guide

This guide covers all usage scenarios for ReleaseFlow.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Basic Setup](#basic-setup)
- [Release Phases](#release-phases)
  - [Alpha Releases](#alpha-releases)
  - [Freeze (Promotion to Release)](#freeze-promotion-to-release)
  - [Beta Releases](#beta-releases)
  - [Stable Releases](#stable-releases)
- [Backflow PRs](#backflow-prs)
- [Guardrails](#guardrails)
- [Environment Variables](#environment-variables)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

---

## Prerequisites

1. **GitHub Repository** with branch protection enabled
2. **Draft Release Intent** created before starting development (see [Concept](K/branching_semver_cicd_concept_backflow_updated.md))
3. **K.PSGallery.Smartagr** available (auto-installed by the action)

---

## Basic Setup

### Minimal Workflow

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
        with:
          fetch-depth: 0  # Required for tag operations
      
      - uses: GrexyLoco/K.Actions.ReleaseFlow@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### With Outputs

```yaml
- uses: GrexyLoco/K.Actions.ReleaseFlow@v1
  id: release
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}

- name: Show Results
  run: |
    echo "Phase: ${{ steps.release.outputs.phase }}"
    echo "Version: ${{ steps.release.outputs.version }}"
    echo "Release URL: ${{ steps.release.outputs.release-url }}"
    echo "Tags: ${{ steps.release.outputs.tags-created }}"
```

---

## Release Phases

### Alpha Releases

**Trigger:** Merge `feature/*` or `fix/*` → `dev/vX.Y.Z`

**What happens:**
1. Guardrail G1 checks for draft intent
2. Creates alpha tag: `vX.Y.Z-alphaN`
3. Creates GitHub Release (prerelease)

**Example:**
```
feature/add-login → dev/v1.2.0
Result: v1.2.0-alpha1
```

### Freeze (Promotion to Release)

**Trigger:** Merge `dev/vX.Y.Z` → `release/vX.Y.Z`

**What happens:**
1. Guardrail G2 activates freeze protection
2. No tag created (just branch promotion)
3. Future feature PRs are blocked

**Example:**
```
dev/v1.2.0 → release/v1.2.0
Result: Feature freeze active for v1.2.0
```

### Beta Releases

**Trigger:** Merge `fix/*` → `release/vX.Y.Z`

**What happens:**
1. Guardrail G3 ensures only fixes allowed
2. Creates beta tag: `vX.Y.Z-betaN`
3. Creates GitHub Release (prerelease)

**Example:**
```
fix/login-crash → release/v1.2.0
Result: v1.2.0-beta1
```

### Stable Releases

**Trigger:** Merge `release/vX.Y.Z` → `main`

**What happens:**
1. Guardrail G4 checks CI status
2. Publishes draft release as stable
3. Creates smart tags (`v1`, `v1.2`)
4. Creates backflow PRs to all open dev branches

**Example:**
```
release/v1.2.0 → main
Result: v1.2.0 + v1 + v1.2 tags, backflow PRs created
```

---

## Backflow PRs

After a stable release, ReleaseFlow automatically creates PRs to sync changes back to development:

```
main (after v1.0.0)
  │
  ├──► PR → dev/v1.1.0  (if intent exists)
  ├──► PR → dev/v2.0.0  (if intent exists)
  └──► PR → dev/v1.0.1  (hotfix train, if intent exists)
```

**PR Title Format:** `[Backflow] Changes from vX.Y.Z`

**Important:** Backflow PRs may have merge conflicts. These must be resolved manually.

---

## Guardrails

### G1: Dev-Gate

Ensures a draft intent exists before development starts.

**Blocked:** Merge to `dev/v*` without draft release

**Fix:** Create a draft release titled `vX.Y.Z` before merging

### G2: Freeze-Gate

Prevents new features after freeze (promotion to release branch).

**Blocked:** Feature PR to `dev/v*` when `release/v*` exists

**Fix:** Target a different version or wait for stable release

### G3: Beta-Gate

Ensures only bug fixes are merged during beta phase.

**Blocked:** Non-fix branches to `release/v*`

**Fix:** Rename branch to `fix/*` or target dev branch

### G4: Stable-Gate

Ensures CI is green before stable release.

**Blocked:** Merge to `main` with failing checks

**Fix:** Fix failing tests/builds, then retry

### G5: Feature-Freeze-Enforcement

Global feature freeze via environment variable.

**Blocked:** Feature PRs when `ISFEATUREFREEZE=true`

**Override:** Set `ISFEATUREFREEZE_OVERRIDE=true`

---

## Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `GITHUB_REPOSITORY` | Owner/repo (auto-set) | - |
| `GITHUB_EVENT_PATH` | PR event JSON (auto-set) | - |
| `ISFEATUREFREEZE` | Enable global feature freeze | `false` |
| `ISFEATUREFREEZE_OVERRIDE` | Bypass feature freeze | `false` |

---

## Troubleshooting

### "No draft intent found for version X.Y.Z"

**Cause:** Guardrail G1 failed – no draft release exists.

**Solution:**
1. Go to GitHub → Releases → Draft a new release
2. Set title to `vX.Y.Z` (matching your dev branch version)
3. Save as draft
4. Retry the merge

### "Feature freeze is active"

**Cause:** Guardrail G2 or G5 blocked the merge.

**Solution:**
- If `release/vX.Y.Z` exists: Target a newer version
- If `ISFEATUREFREEZE=true`: Wait or use `ISFEATUREFREEZE_OVERRIDE`

### "CI checks are not passing"

**Cause:** Guardrail G4 blocked stable release.

**Solution:**
1. Check the failing workflow runs
2. Fix the issues
3. Re-run the release workflow

### Backflow PR has conflicts

**Cause:** `main` and `dev/v*` have diverged.

**Solution:**
1. Check out the backflow PR branch locally
2. Resolve conflicts manually
3. Push and merge

---

## FAQ

### Q: Do I need to create tags manually?

**A:** No. ReleaseFlow creates all tags automatically via Smartagr.

### Q: What if I merge without a draft intent?

**A:** The workflow fails at G1 guardrail. Create a draft release and retry.

### Q: Can I skip guardrails?

**A:** No. Guardrails are mandatory to ensure process integrity.

### Q: How do smart tags work?

**A:** After `v1.2.3`, Smartagr creates/moves `v1` and `v1.2` tags to point to the same commit. This allows users to reference `@v1` in workflows.

### Q: What happens if a backflow PR already exists?

**A:** ReleaseFlow skips it to avoid duplicates.

### Q: Can I use this with GitHub Enterprise?

**A:** Yes, as long as `gh` CLI has access to your instance.

### Q: What permissions does the token need?

**A:** `contents: write`, `pull-requests: write`, `releases: write`

---

## See Also

- [README.md](README.md) – Quick start and architecture
- [Concept Document](K/branching_semver_cicd_concept_backflow_updated.md) – Full branching strategy
- [K.PSGallery.Smartagr](https://github.com/GrexyLoco/K.PSGallery.Smartagr) – Tagging backend
