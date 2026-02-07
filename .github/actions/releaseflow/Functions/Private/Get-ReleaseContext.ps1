function Get-ReleaseContext {
    <#
    .SYNOPSIS
        Detects the release context from GitHub Actions environment.

    .DESCRIPTION
        Analyzes the GitHub event context (GITHUB_EVENT_PATH) to determine:
        - Source branch (head ref of merged PR)
        - Target branch (base ref of merged PR)
        - Release phase (alpha, beta, freeze, stable)
        - Target version (extracted from branch name or intent)

    .OUTPUTS
        [PSCustomObject] with properties:
        - Phase: Release phase (alpha, beta, freeze, stable)
        - Version: Target version (e.g., v1.2.0)
        - SourceBranch: Source branch of merged PR
        - TargetBranch: Target branch of merged PR
        - Intent: Draft release intent (if exists)

    .NOTES
        Internal function - not exported.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    Write-Verbose "Get-ReleaseContext: Reading GitHub event context..."

    # Read GitHub event payload
    $eventPath = $env:GITHUB_EVENT_PATH
    if (-not (Test-Path $eventPath)) {
        throw [System.IO.FileNotFoundException]::new(
            "GitHub event file not found at: $eventPath"
        )
    }

    $event = Get-Content -Path $eventPath -Raw | ConvertFrom-Json

    # Extract branch information from PR
    $sourceBranch = $event.pull_request.head.ref
    $targetBranch = $event.pull_request.base.ref

    Write-Verbose "Get-ReleaseContext: Source=$sourceBranch, Target=$targetBranch"

    # Determine phase based on branch patterns
    $phase = switch -Regex ($targetBranch) {
        '^dev/v\d+\.\d+\.\d+$' {
            # Merging to dev branch = Alpha
            'alpha'
        }
        '^release/v\d+\.\d+\.\d+$' {
            if ($sourceBranch -match '^dev/v\d+\.\d+\.\d+$') {
                # dev → release = Freeze/Promotion
                'freeze'
            }
            else {
                # fix → release = Beta
                'beta'
            }
        }
        '^(main|master)$' {
            # release → main/master = Stable
            'stable'
        }
        default {
            throw [System.InvalidOperationException]::new(
                "Cannot determine release phase for target branch: $targetBranch. " +
                "Expected: dev/vX.Y.Z, release/vX.Y.Z, main, or master."
            )
        }
    }

    # Extract version from branch name
    $version = if ($targetBranch -match 'v(\d+\.\d+\.\d+)') {
        "v$($Matches[1])"
    }
    elseif ($sourceBranch -match 'v(\d+\.\d+\.\d+)') {
        "v$($Matches[1])"
    }
    else {
        throw [System.InvalidOperationException]::new(
            "Cannot extract version from branches. Source: $sourceBranch, Target: $targetBranch"
        )
    }

    # Try to get draft intent for additional context
    $intent = Get-DraftIntent -Version $version -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        Phase        = $phase
        Version      = $version
        SourceBranch = $sourceBranch
        TargetBranch = $targetBranch
        Intent       = $intent
        Repository   = $event.repository.full_name
        PullRequest  = $event.pull_request.number
    }
}
