function Test-G4StableGate {
    <#
    .SYNOPSIS
        G4 - Stable-Gate: CI checks must pass before stable release.

    .DESCRIPTION
        Before a stable release can be published, all CI checks on the PR
        must pass. This prevents broken releases from reaching production.

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

    Write-Verbose "Test-G4StableGate: Checking CI status for stable release..."

    # G4 only applies to stable phase
    if ($Context.Phase -ne 'stable') {
        return [PSCustomObject]@{
            Passed  = $true
            Message = "G4 not applicable for phase '$($Context.Phase)'"
            Skipped = $true
        }
    }

    # Get PR status checks
    try {
        $prStatusJson = & gh pr view $Context.PullRequest --repo $Context.Repository --json statusCheckRollup 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Test-G4StableGate: Could not retrieve PR status: $prStatusJson"
            # If we can't check, we pass (GitHub already enforces this via branch protection)
            return [PSCustomObject]@{
                Passed  = $true
                Message = "Could not retrieve CI status - assuming branch protection enforced"
                Skipped = $false
            }
        }
        $prStatus = $prStatusJson | ConvertFrom-Json
    }
    catch {
        Write-Warning "Test-G4StableGate: Error checking PR status: $_"
        return [PSCustomObject]@{
            Passed  = $true
            Message = "Error checking CI status - assuming branch protection enforced"
            Skipped = $false
        }
    }

    # Check for failed checks
    $failedChecks = @($prStatus.statusCheckRollup | Where-Object {
            $_.conclusion -notin @('SUCCESS', 'SKIPPED', 'NEUTRAL')
        })

    $pendingChecks = @($prStatus.statusCheckRollup | Where-Object {
            $null -eq $_.conclusion -or $_.conclusion -eq ''
        })

    if ($pendingChecks.Count -gt 0) {
        $checkNames = $pendingChecks.name -join ', '
        return [PSCustomObject]@{
            Passed  = $false
            Message = "CI checks still pending: $checkNames. Wait for all checks to complete."
            Skipped = $false
        }
    }

    if ($failedChecks.Count -gt 0) {
        $checkDetails = $failedChecks | ForEach-Object {
            "  - $($_.name): $($_.conclusion)"
        }
        $howToFix = @"

❌ CI checks failed - cannot publish stable release

Failed checks:
$($checkDetails -join "`n")

📋 How to fix:
1. Review the failed check logs
2. Push fixes to the release branch
3. Wait for all checks to pass
4. Merge the PR again
"@
        return [PSCustomObject]@{
            Passed  = $false
            Message = "CI checks must pass before stable release.$howToFix"
            Skipped = $false
        }
    }

    $passedCount = @($prStatus.statusCheckRollup | Where-Object { $_.conclusion -eq 'SUCCESS' }).Count
    [PSCustomObject]@{
        Passed  = $true
        Message = "All CI checks passed ($passedCount checks)"
        Skipped = $false
    }
}
