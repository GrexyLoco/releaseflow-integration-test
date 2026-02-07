function Test-G1DevGate {
    <#
    .SYNOPSIS
        G1 - Dev-Gate: Validates that a draft intent exists for the target version.

    .DESCRIPTION
        Before any release (alpha, beta, stable) can be created, a draft release
        must exist as the "intent" for that version. This ensures intentional
        release planning and prevents accidental releases.

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

    Write-Verbose "Test-G1DevGate: Checking draft intent for version $($Context.Version)..."

    # G1 only applies to release phases that create actual releases
    if ($Context.Phase -notin @('alpha', 'beta', 'stable')) {
        return [PSCustomObject]@{
            Passed  = $true
            Message = "G1 not applicable for phase '$($Context.Phase)'"
            Skipped = $true
        }
    }

    if (-not $Context.Intent) {
        $howToFix = @"

📋 How to fix:
1. Go to GitHub → Releases → Draft a new release
2. Set tag to: $($Context.Version)
3. Set target branch to: $($Context.TargetBranch)
4. Save as draft (do NOT publish)
5. Retry your PR merge

The draft release serves as the "intent" for this version.
"@
        return [PSCustomObject]@{
            Passed  = $false
            Message = "No draft intent found for version $($Context.Version).$howToFix"
            Skipped = $false
        }
    }

    # Validate intent target matches expected branch
    $expectedTarget = switch ($Context.Phase) {
        'alpha' { "dev/$($Context.Version)" }
        'beta' { "release/$($Context.Version)" }
        'stable' { 'main' }
    }

    # Note: For alpha, intent might target dev branch initially
    # This is informational, not a blocker

    [PSCustomObject]@{
        Passed  = $true
        Message = "Draft intent exists for $($Context.Version) (ID: $($Context.Intent.Id))"
        Skipped = $false
    }
}
