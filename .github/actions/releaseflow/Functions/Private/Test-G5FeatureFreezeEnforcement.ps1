function Test-G5FeatureFreezeEnforcement {
    <#
    .SYNOPSIS
        G5 - Feature-Freeze-Enforcement: Blocks features when freeze is active.

    .DESCRIPTION
        When the repository variable ISFEATUREFREEZE is set to 'true',
        only fix/* branches are allowed to be merged. This is a global
        freeze that applies regardless of which version is being worked on.

        Can be bypassed by setting ISFEATUREFREEZE_OVERRIDE=true (secret).

    .PARAMETER Context
        Release context from Get-ReleaseContext.

    .OUTPUTS
        [PSCustomObject] with Passed, Message properties.

    .NOTES
        Internal guardrail function.

        Environment variables used:
        - ISFEATUREFREEZE: Repository variable, 'true' to enable freeze
        - ISFEATUREFREEZE_OVERRIDE: Secret, 'true' to bypass freeze
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Context
    )

    Write-Verbose "Test-G5FeatureFreezeEnforcement: Checking global feature freeze..."

    # Check environment variables
    $isFeatureFreeze = $env:ISFEATUREFREEZE -eq 'true'
    $hasOverride = $env:ISFEATUREFREEZE_OVERRIDE -eq 'true'

    # If no freeze active, always pass
    if (-not $isFeatureFreeze) {
        return [PSCustomObject]@{
            Passed  = $true
            Message = "No global feature freeze active (ISFEATUREFREEZE not set)"
            Skipped = $false
        }
    }

    # If override is set, always pass
    if ($hasOverride) {
        Write-Warning "Test-G5FeatureFreezeEnforcement: Feature freeze bypassed via ISFEATUREFREEZE_OVERRIDE"
        return [PSCustomObject]@{
            Passed  = $true
            Message = "Feature freeze bypassed via ISFEATUREFREEZE_OVERRIDE"
            Skipped = $false
        }
    }

    # Check if this is a feature branch
    $isFeatureBranch = $Context.SourceBranch -match '^feature/'

    if ($isFeatureBranch) {
        $howToFix = @"

🧊 GLOBAL FEATURE FREEZE ACTIVE

The repository has ISFEATUREFREEZE=true set, blocking all feature merges.

Your branch: $($Context.SourceBranch)

📋 Options:
1. Wait for the freeze to be lifted
2. Convert to a fix branch if it's critical (rename to fix/...)
3. Ask a maintainer to set ISFEATUREFREEZE_OVERRIDE=true for this merge

Why freeze?
Feature freezes are typically used before major releases to stabilize
the codebase. Only bug fixes are allowed during this period.
"@
        return [PSCustomObject]@{
            Passed  = $false
            Message = "Feature branch blocked by global feature freeze.$howToFix"
            Skipped = $false
        }
    }

    [PSCustomObject]@{
        Passed  = $true
        Message = "Global freeze active but '$($Context.SourceBranch)' is not a feature branch"
        Skipped = $false
    }
}
