function Test-ReleaseGuardrails {
    <#
    .SYNOPSIS
        Validates all guardrails for the given release context.

    .DESCRIPTION
        Orchestrates guardrail checks G1-G5 based on the release phase.
        Each guardrail is implemented as a separate function for testability.

        G1 - Dev-Gate: Draft intent must exist for target branch
        G2 - Freeze-Gate: No new features after release branch exists
        G3 - Beta-Gate: Only fix commits since freeze
        G4 - Stable-Gate: CI green, all betas successful
        G5 - Feature-Freeze-Enforcement: ISFEATUREFREEZE=true blocks features

    .PARAMETER Context
        Release context from Get-ReleaseContext.

    .OUTPUTS
        [PSCustomObject] with properties:
        - Passed: Boolean indicating all guardrails passed
        - ValidatedGuardrails: Array of passed guardrail IDs
        - FailedGuardrail: ID of failed guardrail (if any)
        - Message: Error message (if failed)
        - Details: Array of individual guardrail results

    .EXAMPLE
        $context = Get-ReleaseContext
        $result = Test-ReleaseGuardrails -Context $context
        if (-not $result.Passed) {
            throw "Guardrail $($result.FailedGuardrail) failed: $($result.Message)"
        }

    .NOTES
        Internal function - not exported.
        Delegates to: Test-G1DevGate, Test-G2FreezeGate, Test-G3BetaGate,
                      Test-G4StableGate, Test-G5FeatureFreezeEnforcement
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Context
    )

    Write-Verbose "Test-ReleaseGuardrails: Validating for phase '$($Context.Phase)'..."

    $validatedGuardrails = [System.Collections.Generic.List[string]]::new()
    $guardrailDetails = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Define guardrails in order with their functions
    $guardrails = @(
        @{ Id = 'G1'; Name = 'Dev-Gate'; Function = 'Test-G1DevGate' }
        @{ Id = 'G2'; Name = 'Freeze-Gate'; Function = 'Test-G2FreezeGate' }
        @{ Id = 'G3'; Name = 'Beta-Gate'; Function = 'Test-G3BetaGate' }
        @{ Id = 'G4'; Name = 'Stable-Gate'; Function = 'Test-G4StableGate' }
        @{ Id = 'G5'; Name = 'Feature-Freeze-Enforcement'; Function = 'Test-G5FeatureFreezeEnforcement' }
    )

    foreach ($guardrail in $guardrails) {
        Write-Verbose "Test-ReleaseGuardrails: Checking $($guardrail.Id) ($($guardrail.Name))..."

        # Call the guardrail function
        $result = & $guardrail.Function -Context $Context

        # Record result
        $detail = [PSCustomObject]@{
            Id      = $guardrail.Id
            Name    = $guardrail.Name
            Passed  = $result.Passed
            Skipped = if ($result.Skipped) { $true } else { $false }
            Message = $result.Message
        }
        $guardrailDetails.Add($detail)

        if ($result.Skipped) {
            Write-Verbose "Test-ReleaseGuardrails: $($guardrail.Id) skipped - $($result.Message)"
            $validatedGuardrails.Add("$($guardrail.Id)-SKIP")
            continue
        }

        if (-not $result.Passed) {
            Write-Verbose "Test-ReleaseGuardrails: $($guardrail.Id) FAILED"

            return [PSCustomObject]@{
                Passed              = $false
                ValidatedGuardrails = $validatedGuardrails.ToArray()
                FailedGuardrail     = $guardrail.Id
                FailedGuardrailName = $guardrail.Name
                Message             = $result.Message
                Details             = $guardrailDetails.ToArray()
            }
        }

        Write-Verbose "Test-ReleaseGuardrails: $($guardrail.Id) passed"
        $validatedGuardrails.Add($guardrail.Id)
    }

    # All guardrails passed
    Write-Information "All guardrails passed: $($validatedGuardrails -join ', ')"

    [PSCustomObject]@{
        Passed              = $true
        ValidatedGuardrails = $validatedGuardrails.ToArray()
        FailedGuardrail     = $null
        FailedGuardrailName = $null
        Message             = "All $($guardrails.Count) guardrails passed"
        Details             = $guardrailDetails.ToArray()
    }
}
