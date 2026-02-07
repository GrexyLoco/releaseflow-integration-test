#Requires -Version 7.4
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for K.Actions.ReleaseFlow guardrail functions.

.DESCRIPTION
    Tests all guardrail functions (G1-G5) and the orchestrator.
    Uses mocking to isolate from GitHub API calls.
#>

BeforeAll {
    # Import module
    $modulePath = Join-Path $PSScriptRoot '..' 'K.Actions.ReleaseFlow.psd1'
    $script:TestModule = Import-Module $modulePath -Force -PassThru
}

AfterAll {
    # Cleanup module
    if ($script:TestModule) {
        Remove-Module $script:TestModule.Name -Force -ErrorAction SilentlyContinue
    }
}

#region Helper Functions (Script Scope für Tests)

function script:New-TestContext {
    <#
    .SYNOPSIS
        Creates a mock release context for testing.
    #>
    param(
        [string]$Phase = 'alpha',
        [string]$Version = 'v1.0.0',
        [string]$SourceBranch = 'feature/test',
        [string]$TargetBranch = 'dev/v1.0.0',
        [object]$Intent = $null,
        [string]$Repository = 'TestOwner/TestRepo',
        [int]$PullRequest = 42
    )

    [PSCustomObject]@{
        Phase        = $Phase
        Version      = $Version
        SourceBranch = $SourceBranch
        TargetBranch = $TargetBranch
        Intent       = $Intent
        Repository   = $Repository
        PullRequest  = $PullRequest
    }
}

function script:New-TestIntent {
    <#
    .SYNOPSIS
        Creates a mock draft intent for testing.
    #>
    param(
        [int]$Id = 12345,
        [string]$TagName = 'v1.0.0',
        [string]$TargetCommitish = 'dev/v1.0.0'
    )

    [PSCustomObject]@{
        Id              = $Id
        TagName         = $TagName
        Name            = "Release $TagName"
        Body            = "Release notes"
        TargetCommitish = $TargetCommitish
        Prerelease      = $false
        Url             = "https://github.com/TestOwner/TestRepo/releases/$Id"
        CreatedAt       = (Get-Date).ToString('o')
    }
}

#endregion

#region G1 Tests

Describe 'Test-G1DevGate' {
    Context 'When intent exists' {
        It 'Should pass for alpha phase with intent' {
            $intent = New-TestIntent
            $ctx = New-TestContext -Phase 'alpha' -Intent $intent

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G1DevGate -Context $Context

                $result.Passed | Should -BeTrue
                $result.Skipped | Should -BeFalse
                $result.Message | Should -Match 'Draft intent exists'
            }
        }

        It 'Should pass for beta phase with intent' {
            $intent = New-TestIntent
            $ctx = New-TestContext -Phase 'beta' -Intent $intent

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G1DevGate -Context $Context

                $result.Passed | Should -BeTrue
            }
        }

        It 'Should pass for stable phase with intent' {
            $intent = New-TestIntent
            $ctx = New-TestContext -Phase 'stable' -Intent $intent

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G1DevGate -Context $Context

                $result.Passed | Should -BeTrue
            }
        }
    }

    Context 'When intent is missing' {
        It 'Should fail for alpha phase without intent' {
            $ctx = New-TestContext -Phase 'alpha' -Intent $null

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G1DevGate -Context $Context

                $result.Passed | Should -BeFalse
                $result.Message | Should -Match 'No draft intent found'
                $result.Message | Should -Match 'How to fix'
            }
        }

        It 'Should fail for beta phase without intent' {
            $ctx = New-TestContext -Phase 'beta' -Intent $null

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G1DevGate -Context $Context

                $result.Passed | Should -BeFalse
            }
        }

        It 'Should fail for stable phase without intent' {
            $ctx = New-TestContext -Phase 'stable' -Intent $null

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G1DevGate -Context $Context

                $result.Passed | Should -BeFalse
            }
        }
    }

    Context 'When phase does not require intent' {
        It 'Should skip for freeze phase' {
            $ctx = New-TestContext -Phase 'freeze' -Intent $null

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G1DevGate -Context $Context

                $result.Passed | Should -BeTrue
                $result.Skipped | Should -BeTrue
                $result.Message | Should -Match 'not applicable'
            }
        }
    }
}

#endregion

#region G2 Tests

Describe 'Test-G2FreezeGate' {
    Context 'When version is not frozen' {
        It 'Should pass for feature branch when no release branch exists' {
            $ctx = New-TestContext -Phase 'alpha' -SourceBranch 'feature/new-feature' -Version 'v1.0.0'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                # Mock gh - return non-zero exit code (branch not found)
                Mock gh {
                    $script:LASTEXITCODE = 1
                    return 'Not Found'
                }

                $result = Test-G2FreezeGate -Context $Context

                $result.Passed | Should -BeTrue
                $result.Skipped | Should -BeFalse
            }
        }
    }

    Context 'When version is frozen' {
        It 'Should fail for feature branch when release branch exists' {
            $ctx = New-TestContext -Phase 'alpha' -SourceBranch 'feature/new-feature' -Version 'v1.0.0'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                # Mock gh - return success (branch exists)
                Mock gh {
                    $script:LASTEXITCODE = 0
                    return '{"name":"release/v1.0.0"}'
                }

                $result = Test-G2FreezeGate -Context $Context

                $result.Passed | Should -BeFalse
                $result.Message | Should -Match 'FROZEN'
            }
        }

        It 'Should pass for fix branch even when frozen' {
            $ctx = New-TestContext -Phase 'alpha' -SourceBranch 'fix/bugfix' -Version 'v1.0.0'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                # Mock not needed - fix branches are allowed before gh call
                $result = Test-G2FreezeGate -Context $Context

                $result.Passed | Should -BeTrue
            }
        }
    }

    Context 'When phase does not apply' {
        It 'Should skip for beta phase' {
            $ctx = New-TestContext -Phase 'beta' -SourceBranch 'feature/test'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G2FreezeGate -Context $Context

                $result.Passed | Should -BeTrue
                $result.Skipped | Should -BeTrue
            }
        }

        It 'Should skip for stable phase' {
            $ctx = New-TestContext -Phase 'stable' -SourceBranch 'feature/test'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G2FreezeGate -Context $Context

                $result.Passed | Should -BeTrue
                $result.Skipped | Should -BeTrue
            }
        }
    }
}

#endregion

#region G3 Tests

Describe 'Test-G3BetaGate' {
    Context 'When in beta phase' {
        It 'Should pass for fix branch' {
            $ctx = New-TestContext -Phase 'beta' -SourceBranch 'fix/critical-bug'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G3BetaGate -Context $Context

                $result.Passed | Should -BeTrue
                $result.Skipped | Should -BeFalse
            }
        }

        It 'Should fail for feature branch' {
            $ctx = New-TestContext -Phase 'beta' -SourceBranch 'feature/new-feature'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G3BetaGate -Context $Context

                $result.Passed | Should -BeFalse
                $result.Message | Should -Match 'fix'
            }
        }

        It 'Should fail for dev branch' {
            $ctx = New-TestContext -Phase 'beta' -SourceBranch 'dev/v1.0.0'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G3BetaGate -Context $Context

                $result.Passed | Should -BeFalse
            }
        }
    }

    Context 'When not in beta phase' {
        It 'Should skip for alpha phase' {
            $ctx = New-TestContext -Phase 'alpha' -SourceBranch 'feature/test'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G3BetaGate -Context $Context

                $result.Passed | Should -BeTrue
                $result.Skipped | Should -BeTrue
            }
        }

        It 'Should skip for stable phase' {
            $ctx = New-TestContext -Phase 'stable' -SourceBranch 'release/v1.0.0'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G3BetaGate -Context $Context

                $result.Passed | Should -BeTrue
                $result.Skipped | Should -BeTrue
            }
        }
    }
}

#endregion

#region G4 Tests

Describe 'Test-G4StableGate' {
    Context 'When CI checks pass' {
        It 'Should pass when all checks succeed' {
            $ctx = New-TestContext -Phase 'stable' -TargetBranch 'main' -PullRequest 42

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                # Mock gh pr view to return successful status
                Mock gh {
                    $script:LASTEXITCODE = 0
                    return '{"statusCheckRollup":[{"name":"test","conclusion":"SUCCESS"}]}'
                }

                $result = Test-G4StableGate -Context $Context

                $result.Passed | Should -BeTrue
            }
        }

        It 'Should pass when checks are skipped (neutral)' {
            $ctx = New-TestContext -Phase 'stable' -TargetBranch 'main' -PullRequest 42

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                Mock gh {
                    $script:LASTEXITCODE = 0
                    return '{"statusCheckRollup":[{"name":"test","conclusion":"SKIPPED"}]}'
                }

                $result = Test-G4StableGate -Context $Context

                $result.Passed | Should -BeTrue
            }
        }
    }

    Context 'When CI checks fail' {
        It 'Should fail when checks have failed' {
            $ctx = New-TestContext -Phase 'stable' -TargetBranch 'main' -PullRequest 42

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                Mock gh {
                    $script:LASTEXITCODE = 0
                    return '{"statusCheckRollup":[{"name":"test","conclusion":"FAILURE"}]}'
                }

                $result = Test-G4StableGate -Context $Context

                $result.Passed | Should -BeFalse
                $result.Message | Should -Match 'CI checks'
            }
        }

        It 'Should fail when checks are pending' {
            $ctx = New-TestContext -Phase 'stable' -TargetBranch 'main' -PullRequest 42

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                Mock gh {
                    $script:LASTEXITCODE = 0
                    return '{"statusCheckRollup":[{"name":"test","conclusion":null}]}'
                }

                $result = Test-G4StableGate -Context $Context

                $result.Passed | Should -BeFalse
                $result.Message | Should -Match 'pending'
            }
        }
    }

    Context 'When not in stable phase' {
        It 'Should skip for alpha phase' {
            $ctx = New-TestContext -Phase 'alpha' -TargetBranch 'dev/v1.0.0'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G4StableGate -Context $Context

                $result.Passed | Should -BeTrue
                $result.Skipped | Should -BeTrue
            }
        }

        It 'Should skip for beta phase' {
            $ctx = New-TestContext -Phase 'beta' -TargetBranch 'release/v1.0.0'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G4StableGate -Context $Context

                $result.Passed | Should -BeTrue
                $result.Skipped | Should -BeTrue
            }
        }
    }
}

#endregion

#region G5 Tests

Describe 'Test-G5FeatureFreezeEnforcement' {
    BeforeEach {
        # Clear environment variables before each test
        $env:ISFEATUREFREEZE = $null
        $env:ISFEATUREFREEZE_OVERRIDE = $null
    }

    AfterAll {
        # Cleanup environment
        $env:ISFEATUREFREEZE = $null
        $env:ISFEATUREFREEZE_OVERRIDE = $null
    }

    Context 'When feature freeze is not active' {
        It 'Should pass for any branch' {
            $ctx = New-TestContext -Phase 'alpha' -SourceBranch 'feature/new-feature'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                # ISFEATUREFREEZE is not set (default)
                $result = Test-G5FeatureFreezeEnforcement -Context $Context

                $result.Passed | Should -BeTrue
                $result.Message | Should -Match 'No global feature freeze'
            }
        }
    }

    Context 'When feature freeze is active' {
        It 'Should fail for feature branch' {
            $env:ISFEATUREFREEZE = 'true'
            $ctx = New-TestContext -Phase 'alpha' -SourceBranch 'feature/new-feature'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G5FeatureFreezeEnforcement -Context $Context

                $result.Passed | Should -BeFalse
                $result.Message | Should -Match 'freeze'
            }
        }

        It 'Should pass for fix branch' {
            $env:ISFEATUREFREEZE = 'true'
            $ctx = New-TestContext -Phase 'alpha' -SourceBranch 'fix/bugfix'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G5FeatureFreezeEnforcement -Context $Context

                $result.Passed | Should -BeTrue
            }
        }

        It 'Should pass for feature branch with override' {
            $env:ISFEATUREFREEZE = 'true'
            $env:ISFEATUREFREEZE_OVERRIDE = 'true'
            $ctx = New-TestContext -Phase 'alpha' -SourceBranch 'feature/urgent'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-G5FeatureFreezeEnforcement -Context $Context

                $result.Passed | Should -BeTrue
                $result.Message | Should -Match 'bypass'
            }
        }
    }
}

#endregion

#region Orchestrator Tests

Describe 'Test-ReleaseGuardrails (Orchestrator)' {
    BeforeEach {
        # Clear environment variables
        $env:ISFEATUREFREEZE = $null
        $env:ISFEATUREFREEZE_OVERRIDE = $null
    }

    AfterAll {
        $env:ISFEATUREFREEZE = $null
        $env:ISFEATUREFREEZE_OVERRIDE = $null
    }

    Context 'When all guardrails pass' {
        It 'Should return passed with all guardrail IDs' {
            $intent = New-TestIntent
            $ctx = New-TestContext -Phase 'alpha' -Intent $intent -SourceBranch 'feature/test'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                # Mock gh to simulate no release branch (G2 passes)
                Mock gh {
                    $script:LASTEXITCODE = 1
                    return 'Not Found'
                }

                $result = Test-ReleaseGuardrails -Context $Context

                $result.Passed | Should -BeTrue
                $result.ValidatedGuardrails | Should -Contain 'G1'
            }
        }
    }

    Context 'When a guardrail fails' {
        It 'Should return failed with the specific guardrail ID' {
            $ctx = New-TestContext -Phase 'alpha' -Intent $null

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-ReleaseGuardrails -Context $Context

                $result.Passed | Should -BeFalse
                $result.FailedGuardrail | Should -Be 'G1'
            }
        }

        It 'Should stop at first failure (fail-fast)' {
            $ctx = New-TestContext -Phase 'alpha' -Intent $null

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)
                $result = Test-ReleaseGuardrails -Context $Context

                # G1 fails first, so G2-G5 should not be validated
                $result.ValidatedGuardrails | Should -BeNullOrEmpty
                $result.Details.Count | Should -Be 1
            }
        }
    }

    Context 'Details property' {
        It 'Should include details for each checked guardrail' {
            $intent = New-TestIntent
            $ctx = New-TestContext -Phase 'alpha' -Intent $intent -SourceBranch 'feature/test'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                Mock gh {
                    $script:LASTEXITCODE = 1
                    return 'Not Found'
                }

                $result = Test-ReleaseGuardrails -Context $Context

                $result.Details | Should -Not -BeNullOrEmpty
                $result.Details[0].Id | Should -Be 'G1'
                $result.Details[0].Passed | Should -BeTrue
            }
        }
    }
}

#endregion
