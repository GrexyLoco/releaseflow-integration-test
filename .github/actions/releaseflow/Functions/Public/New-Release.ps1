function New-Release {
    <#
    .SYNOPSIS
        Single entry point for all release operations in K.Actions.ReleaseFlow.

    .DESCRIPTION
        New-Release automatically detects the current release phase based on the
        GitHub event context (source/target branches of merged PR) and executes
        the appropriate release action.

        Phase Detection:
        - feature/* → dev/vX.Y.Z  = Alpha Release
        - fix/* → dev/vX.Y.Z      = Alpha Release
        - dev/vX.Y.Z → release/vX.Y.Z = Freeze (Promotion)
        - fix/* → release/vX.Y.Z  = Beta Release
        - release/vX.Y.Z → main   = Stable Release + Backflow PRs

        This function orchestrates the entire release process including:
        - Guardrail validation (G1-G5)
        - Tag creation via K.PSGallery.Smartagr
        - GitHub Release creation
        - Backflow PR creation (for stable releases)

    .PARAMETER WhatIf
        Shows what would happen without making any changes.

    .PARAMETER Confirm
        Prompts for confirmation before each action.

    .OUTPUTS
        [PSCustomObject] with properties:
        - Phase: Detected phase (alpha, beta, stable, freeze)
        - Version: Released version
        - ReleaseUrl: URL of created GitHub release
        - TagsCreated: Array of created tags
        - BackflowPRs: Array of backflow PR URLs (stable only)
        - GuardrailsValidated: Array of passed guardrails

    .EXAMPLE
        New-Release

        Automatically detects phase and creates release.

    .EXAMPLE
        New-Release -WhatIf

        Shows what would happen without making changes.

    .EXAMPLE
        New-Release -Verbose

        Creates release with detailed logging.

    .NOTES
        Author: GrexyLoco
        Requires: PowerShell 7.4+, GitHub CLI (gh), K.PSGallery.Smartagr

    .LINK
        https://github.com/GrexyLoco/K.Actions.ReleaseFlow
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param()

    begin {
        Write-Verbose "New-Release: Starting release process"

        # Verify we're running in GitHub Actions context
        if (-not $env:GITHUB_EVENT_PATH) {
            throw [System.InvalidOperationException]::new(
                "New-Release must be run in GitHub Actions context. " +
                "GITHUB_EVENT_PATH environment variable is not set."
            )
        }

        # Verify Smartagr module is available
        if (-not (Get-Module -Name 'K.PSGallery.Smartagr' -ListAvailable)) {
            throw [System.InvalidOperationException]::new(
                "K.PSGallery.Smartagr module is required but not installed. " +
                "Install it with: Install-Module K.PSGallery.Smartagr -Force"
            )
        }
    }

    process {
        # Step 1: Detect release context (phase, version, branches)
        Write-Verbose "New-Release: Detecting release context..."
        $context = Get-ReleaseContext
        Write-Information "Detected phase: $($context.Phase) for version $($context.Version)"

        # Step 2: Validate guardrails
        Write-Verbose "New-Release: Validating guardrails..."
        $guardrailResult = Test-ReleaseGuardrails -Context $context
        if (-not $guardrailResult.Passed) {
            throw [System.InvalidOperationException]::new(
                "Guardrail validation failed: $($guardrailResult.FailedGuardrail) - $($guardrailResult.Message)"
            )
        }
        Write-Information "Guardrails passed: $($guardrailResult.ValidatedGuardrails -join ', ')"

        # Step 3: Execute phase-specific release logic
        $releaseResult = switch ($context.Phase) {
            'alpha' {
                if ($PSCmdlet.ShouldProcess("Alpha release $($context.Version)", "Create")) {
                    New-AlphaRelease -Context $context
                }
            }
            'beta' {
                if ($PSCmdlet.ShouldProcess("Beta release $($context.Version)", "Create")) {
                    New-BetaRelease -Context $context
                }
            }
            'freeze' {
                if ($PSCmdlet.ShouldProcess("Freeze promotion for $($context.Version)", "Execute")) {
                    # Freeze is a promotion from dev to release branch
                    # No release created, just validation
                    [PSCustomObject]@{
                        ReleaseUrl  = $null
                        TagsCreated = @()
                    }
                }
            }
            'stable' {
                if ($PSCmdlet.ShouldProcess("Stable release $($context.Version)", "Publish")) {
                    $stableResult = Publish-StableRelease -Context $context

                    # Create backflow PRs after stable release
                    Write-Verbose "New-Release: Creating backflow PRs..."
                    $backflowPRs = New-BackflowPRs -Version $context.Version

                    $stableResult | Add-Member -NotePropertyName 'BackflowPRs' -NotePropertyValue $backflowPRs -PassThru
                }
            }
            default {
                throw [System.InvalidOperationException]::new(
                    "Unknown release phase: $($context.Phase). " +
                    "Valid phases are: alpha, beta, freeze, stable."
                )
            }
        }

        # Step 4: Build and return result object
        # Use PSObject.Properties for strict-mode-safe property access
        $backflowPRs = @()
        if ($releaseResult -and $releaseResult.PSObject.Properties['BackflowPRs']) {
            $backflowPRs = $releaseResult.BackflowPRs
        }
        
        [PSCustomObject]@{
            Phase               = $context.Phase
            Version             = $context.Version
            ReleaseUrl          = $releaseResult.ReleaseUrl
            TagsCreated         = $releaseResult.TagsCreated
            BackflowPRs         = $backflowPRs
            GuardrailsValidated = $guardrailResult.ValidatedGuardrails
            SourceBranch        = $context.SourceBranch
            TargetBranch        = $context.TargetBranch
        }
    }

    end {
        Write-Verbose "New-Release: Release process completed"
    }
}
