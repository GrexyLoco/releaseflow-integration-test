function Test-G2FreezeGate {
    <#
    .SYNOPSIS
        G2 - Freeze-Gate: Blocks feature branches after release branch exists.

    .DESCRIPTION
        Once a release/vX.Y.Z branch exists, the version is "frozen" for stabilization.
        No new features can be merged to dev/vX.Y.Z after this point - only fixes.

    .PARAMETER Context
        Release context from Get-ReleaseContext.

    .OUTPUTS
        [PSCustomObject] with Passed, Message properties.

    .NOTES
        Internal guardrail function.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Context
    )

    Write-Verbose "Test-G2FreezeGate: Checking freeze status for $($Context.Version)..."

    # G2 only applies to alpha phase (merging to dev branch)
    if ($Context.Phase -ne 'alpha') {
        return [PSCustomObject]@{
            Passed  = $true
            Message = "G2 not applicable for phase '$($Context.Phase)'"
            Skipped = $true
        }
    }

    # Check if this is a feature branch
    $isFeatureBranch = $Context.SourceBranch -match '^feature/'

    if (-not $isFeatureBranch) {
        # Fix branches are always allowed
        return [PSCustomObject]@{
            Passed  = $true
            Message = "Source branch '$($Context.SourceBranch)' is not a feature branch"
            Skipped = $false
        }
    }

    # Check if release branch exists (= frozen)
    $releaseBranch = "release/$($Context.Version)"

    try {
        $branchResponse = & gh api "repos/$($Context.Repository)/branches/$releaseBranch" 2>&1
        $branchExists = $LASTEXITCODE -eq 0
    }
    catch {
        $branchExists = $false
    }

    if ($branchExists) {
        $howToFix = @"

🧊 Version $($Context.Version) is FROZEN

The release branch '$releaseBranch' exists, which means:
- No new features can be added to this version
- Only bug fixes (fix/* branches) are allowed

📋 Options:
1. Convert your feature to a fix if it's critical
2. Target the next version instead (create new intent first)
3. Wait for $($Context.Version) to release, then merge to next version

Your branch: $($Context.SourceBranch)
"@
        return [PSCustomObject]@{
            Passed  = $false
            Message = "Feature branch blocked - version is frozen.$howToFix"
            Skipped = $false
        }
    }

    [PSCustomObject]@{
        Passed  = $true
        Message = "No freeze detected - feature branches allowed for $($Context.Version)"
        Skipped = $false
    }
}
