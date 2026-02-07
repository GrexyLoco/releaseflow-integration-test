function New-BackflowPRs {
    <#
    .SYNOPSIS
        Creates backflow PRs from main to all open dev trains.

    .DESCRIPTION
        After a stable release, creates PRs to sync changes from main
        back to all open dev branches that have draft intents.

    .PARAMETER Version
        The version that was just released (for PR title/body).

    .OUTPUTS
        [string[]] Array of created PR URLs.

    .NOTES
        Internal function - not exported.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    Write-Verbose "New-BackflowPRs: Creating backflow PRs for version $Version..."

    $repository = $env:GITHUB_REPOSITORY
    $backflowPRs = [System.Collections.Generic.List[string]]::new()

    # Find all open draft intents (= active dev trains)
    $releasesJson = & gh api "repos/$repository/releases" --paginate 2>$null
    if (-not $releasesJson) {
        Write-Verbose "New-BackflowPRs: No releases found."
        return @()
    }

    $releases = $releasesJson | ConvertFrom-Json

    # Filter for draft releases targeting dev branches
    $openIntents = $releases | Where-Object {
        $_.draft -eq $true -and $_.target_commitish -match '^dev/v'
    }

    if (-not $openIntents) {
        Write-Verbose "New-BackflowPRs: No open dev intents found."
        return @()
    }

    foreach ($intent in $openIntents) {
        $devBranch = $intent.target_commitish
        $intentVersion = $intent.tag_name

        Write-Information "Creating backflow PR: main → $devBranch"

        # Check if branch exists
        $branchExists = & gh api "repos/$repository/branches/$devBranch" 2>$null
        if (-not $branchExists) {
            Write-Warning "Branch '$devBranch' does not exist. Skipping backflow PR."
            continue
        }

        # Check if PR already exists
        $existingPR = & gh pr list --repo $repository --base $devBranch --head 'main' --json number -q '.[0].number' 2>$null
        if ($existingPR) {
            Write-Verbose "New-BackflowPRs: Backflow PR already exists for $devBranch (#$existingPR)"
            continue
        }

        # Create backflow PR
        $prBody = @"
## 🔄 Backflow: Changes from $Version

This PR syncs changes from `main` (after release $Version) back to `$devBranch`.

### What's included
All changes merged to `main` since the last backflow, including:
- Bug fixes
- Documentation updates
- Dependency updates

### ⚠️ Merge Conflicts
If this PR has conflicts, they must be resolved manually:
1. Checkout `$devBranch`
2. Merge `main` locally
3. Resolve conflicts
4. Push to `$devBranch`

### Labels
- `backflow` - Automated backflow PR
- `$intentVersion` - Target version

---
*This PR was created automatically by K.Actions.ReleaseFlow*
"@

        try {
            $prUrl = & gh pr create `
                --repo $repository `
                --base $devBranch `
                --head 'main' `
                --title "[Backflow] Changes from $Version → $intentVersion" `
                --body $prBody `
                --label 'backflow' `
                --draft

            $backflowPRs.Add($prUrl)
            Write-Information "Created backflow PR: $prUrl"
        }
        catch {
            Write-Warning "Failed to create backflow PR for $devBranch`: $_"
        }
    }

    $backflowPRs.ToArray()
}
