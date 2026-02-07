function New-ReleaseTrain {
    <#
    .SYNOPSIS
        Creates a new release train (Version Intent + Dev Branch).

    .DESCRIPTION
        Atomically creates:
        1. A Draft Release (Version Intent) with tag_name=vX.Y.Z
        2. A dev branch dev/vX.Y.Z from the specified base

        If any step fails, all changes are rolled back.

    .PARAMETER TargetVersion
        The target version without v-prefix (e.g., "2.0.0").

    .PARAMETER Base
        The base commit/tag for the dev branch.
        Special value "latest-stable" uses the most recent stable tag.
        Default: "latest-stable"

    .OUTPUTS
        [PSCustomObject] with DevBranch, IntentUrl, BaseCommit

    .EXAMPLE
        New-ReleaseTrain -TargetVersion "2.0.0"

    .EXAMPLE
        New-ReleaseTrain -TargetVersion "1.5.0" -Base "v1.4.0"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^\d+\.\d+\.\d+$')]
        [string]$TargetVersion,

        [string]$Base = 'latest-stable'
    )

    $version = "v$TargetVersion"
    $devBranch = "dev/$version"

    # === GUARDRAILS ===

    # PD-1: Check if Draft Intent exists
    $existingIntent = gh release list --json tagName,isDraft | 
        ConvertFrom-Json | 
        Where-Object { $_.tagName -eq $version -and $_.isDraft }
    if ($existingIntent) {
        throw "PD-1: Intent für $version existiert bereits."
    }

    # PD-2: Check if Git tag exists
    $existingTag = git tag -l $version
    if ($existingTag) {
        throw "PD-2: Tag $version existiert bereits."
    }

    # PD-3: Check if branch exists
    $existingBranch = git branch -r --list "origin/$devBranch"
    if ($existingBranch) {
        throw "PD-3: Branch $devBranch existiert bereits."
    }

    # PD-4: Resolve base
    if ($Base -eq 'latest-stable') {
        $baseRef = git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>$null
        if (-not $baseRef) {
            $baseRef = 'main'
            Write-Warning "Kein Stable-Tag gefunden, verwende 'main'"
        }
    } else {
        $baseRef = $Base
    }

    # Validate base exists
    $baseCommit = git rev-parse --verify "$baseRef^{commit}" 2>$null
    if (-not $baseCommit) {
        throw "PD-4: Basis '$Base' nicht gefunden."
    }

    # === ATOMIC CREATION ===

    if ($PSCmdlet.ShouldProcess("$devBranch + Draft Release $version", "Create")) {
        try {
            # Step 1: Create dev branch
            Write-Verbose "Creating dev branch $devBranch from $baseRef..."
            $checkoutResult = git checkout -b $devBranch $baseRef 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create branch $devBranch from $baseRef. Git error: $checkoutResult"
            }

            Write-Verbose "Pushing branch $devBranch to origin..."
            $pushResult = git push origin $devBranch 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to push branch $devBranch to origin. Git error: $pushResult"
            }

            # Step 2: Create Draft Release (Intent)
            Write-Verbose "Creating Draft Release $version..."
            $releaseBody = "## Version Intent: $version`n`nAutomatically created release train."
            gh release create $version `
                --draft `
                --title "Intent: $version" `
                --notes $releaseBody `
                --target $devBranch

            $intentUrl = gh release view $version --json url -q '.url'

            [PSCustomObject]@{
                DevBranch  = $devBranch
                IntentUrl  = $intentUrl
                BaseCommit = $baseCommit
            }
        }
        catch {
            # ROLLBACK: Delete branch if created
            Write-Warning "Rollback: Lösche $devBranch..."
            
            # Try to checkout main first
            $null = git checkout main 2>&1
            
            # Try to delete local branch
            $localDeleteResult = git branch -D $devBranch 2>&1
            if ($LASTEXITCODE -ne 0 -and $localDeleteResult -notmatch "not found") {
                Write-Warning "Failed to delete local branch $devBranch : $localDeleteResult"
            }
            
            # Try to delete remote branch
            $remoteDeleteResult = git push origin --delete $devBranch 2>&1
            if ($LASTEXITCODE -ne 0 -and $remoteDeleteResult -notmatch "not found|remote ref does not exist") {
                Write-Warning "Failed to delete remote branch $devBranch : $remoteDeleteResult"
            }
            
            throw
        }
    }
}
