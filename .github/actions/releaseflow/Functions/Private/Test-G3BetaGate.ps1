function Test-G3BetaGate {
    <#
    .SYNOPSIS
        G3 - Beta-Gate: Only fix branches can merge to release branch.

    .DESCRIPTION
        During the beta phase (after freeze), only bug fixes are allowed.
        This ensures the release branch remains stable and focused on fixes.

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

    Write-Verbose "Test-G3BetaGate: Checking source branch for beta phase..."

    # G3 only applies to beta phase (merging to release branch)
    if ($Context.Phase -ne 'beta') {
        return [PSCustomObject]@{
            Passed  = $true
            Message = "G3 not applicable for phase '$($Context.Phase)'"
            Skipped = $true
        }
    }

    # Check if source is a fix branch
    $isFixBranch = $Context.SourceBranch -match '^fix/'

    if (-not $isFixBranch) {
        $howToFix = @"

🔧 Only fix branches allowed in beta phase

The release branch is for stabilization only. Your branch:
  $($Context.SourceBranch)

📋 How to fix:
1. Rename your branch to fix/... if it's actually a bug fix
2. Or wait until after $($Context.Version) releases to merge features

Allowed patterns: fix/*, hotfix/*
Blocked patterns: feature/*, feat/*, dev/*
"@
        return [PSCustomObject]@{
            Passed  = $false
            Message = "Non-fix branch cannot merge to release during beta phase.$howToFix"
            Skipped = $false
        }
    }

    [PSCustomObject]@{
        Passed  = $true
        Message = "Fix branch '$($Context.SourceBranch)' is allowed in beta phase"
        Skipped = $false
    }
}
