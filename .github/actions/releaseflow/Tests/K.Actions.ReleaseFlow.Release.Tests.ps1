#Requires -Version 7.4
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for release creation functions.

.DESCRIPTION
    Tests New-AlphaRelease, New-BetaRelease, and Publish-StableRelease.
    Heavy mocking required since these call external tools (gh, Smartagr).
#>

BeforeAll {
    # Import module
    $modulePath = Join-Path $PSScriptRoot '..' 'K.Actions.ReleaseFlow.psd1'
    $script:TestModule = Import-Module $modulePath -Force -PassThru

    # Create stub functions for Smartagr (since module isn't installed in test env)
    # These are defined in the module scope so they can be mocked
    InModuleScope $script:TestModule.Name {
        function Get-NextPreReleaseNumber {
            param([string]$Version, [string]$Type)
            throw "Stub - should be mocked"
        }

        function New-SemanticReleaseTags {
            param([string]$TargetVersion, [switch]$PushToRemote)
            throw "Stub - should be mocked"
        }
    }
}

AfterAll {
    if ($script:TestModule) {
        Remove-Module $script:TestModule.Name -Force -ErrorAction SilentlyContinue
    }
}

#region Helper Functions

function script:New-TestContext {
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
    param(
        [int]$Id = 12345,
        [string]$TagName = 'v1.0.0'
    )

    [PSCustomObject]@{
        Id              = $Id
        TagName         = $TagName
        Name            = "Release $TagName"
        Body            = "Release notes"
        TargetCommitish = 'dev/v1.0.0'
        Prerelease      = $false
        Url             = "https://github.com/TestOwner/TestRepo/releases/$Id"
        CreatedAt       = (Get-Date).ToString('o')
    }
}

#endregion

#region New-AlphaRelease Tests

Describe 'New-AlphaRelease' {
    Context 'When creating alpha release' {
        It 'Should call Smartagr functions for tagging' {
            $ctx = New-TestContext -Phase 'alpha' -Version 'v1.0.0'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                # Define stub functions that can be mocked
                function Get-NextPreReleaseNumber { param($Version, $Type) }
                function New-SemanticReleaseTags { param($TargetVersion, [switch]$PushToRemote) }

                # Mock Import-Module for Smartagr (no-op)
                Mock Import-Module { } -ParameterFilter { $Name -eq 'K.PSGallery.Smartagr' }

                # Mock Smartagr functions
                Mock Get-NextPreReleaseNumber { return 1 }
                Mock New-SemanticReleaseTags {
                    return [PSCustomObject]@{
                        SmartTags = @('v1', 'v1.0')
                    }
                }

                # Mock gh CLI
                Mock gh {
                    if ($args -contains 'release' -and $args -contains 'create') {
                        return 'Release created'
                    }
                    if ($args -contains 'release' -and $args -contains 'view') {
                        return 'https://github.com/TestOwner/TestRepo/releases/tag/v1.0.0-alpha1'
                    }
                    return ''
                }

                $result = New-AlphaRelease -Context $Context

                Should -Invoke Get-NextPreReleaseNumber -Times 1
                Should -Invoke New-SemanticReleaseTags -Times 1
            }
        }

        It 'Should return correct output structure' {
            $ctx = New-TestContext -Phase 'alpha' -Version 'v2.0.0'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                function Get-NextPreReleaseNumber { param($Version, $Type) }
                function New-SemanticReleaseTags { param($TargetVersion, [switch]$PushToRemote) }

                Mock Import-Module { } -ParameterFilter { $Name -eq 'K.PSGallery.Smartagr' }
                Mock Get-NextPreReleaseNumber { return 3 }
                Mock New-SemanticReleaseTags {
                    return [PSCustomObject]@{ SmartTags = @('v2') }
                }
                Mock gh {
                    if ($args -contains 'view') {
                        return 'https://github.com/TestOwner/TestRepo/releases/tag/v2.0.0-alpha3'
                    }
                    return ''
                }

                $result = New-AlphaRelease -Context $Context

                $result.ReleaseUrl | Should -Not -BeNullOrEmpty
                $result.TagsCreated | Should -Contain 'v2.0.0-alpha3'
            }
        }
    }
}

#endregion

#region New-BetaRelease Tests

Describe 'New-BetaRelease' {
    Context 'When creating beta release' {
        It 'Should call Smartagr functions for tagging' {
            $ctx = New-TestContext -Phase 'beta' -Version 'v1.0.0' -SourceBranch 'fix/bug' -TargetBranch 'release/v1.0.0'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                function Get-NextPreReleaseNumber { param($Version, $Type) }
                function New-SemanticReleaseTags { param($TargetVersion, [switch]$PushToRemote) }

                Mock Import-Module { } -ParameterFilter { $Name -eq 'K.PSGallery.Smartagr' }
                Mock Get-NextPreReleaseNumber { return 2 }
                Mock New-SemanticReleaseTags {
                    return [PSCustomObject]@{ SmartTags = @('v1', 'v1.0') }
                }
                Mock gh { return '' }

                $result = New-BetaRelease -Context $Context

                Should -Invoke Get-NextPreReleaseNumber -Times 1 -ParameterFilter { $Type -eq 'beta' }
            }
        }

        It 'Should return beta tag in output' {
            $ctx = New-TestContext -Phase 'beta' -Version 'v1.5.0'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                function Get-NextPreReleaseNumber { param($Version, $Type) }
                function New-SemanticReleaseTags { param($TargetVersion, [switch]$PushToRemote) }

                Mock Import-Module { } -ParameterFilter { $Name -eq 'K.PSGallery.Smartagr' }
                Mock Get-NextPreReleaseNumber { return 1 }
                Mock New-SemanticReleaseTags {
                    return [PSCustomObject]@{ SmartTags = @() }
                }
                Mock gh {
                    if ($args -contains 'view') {
                        return 'https://github.com/TestOwner/TestRepo/releases/tag/v1.5.0-beta1'
                    }
                    return ''
                }

                $result = New-BetaRelease -Context $Context

                $result.TagsCreated | Should -Contain 'v1.5.0-beta1'
            }
        }
    }
}

#endregion

#region Publish-StableRelease Tests

Describe 'Publish-StableRelease' {
    Context 'When draft intent exists' {
        It 'Should publish the existing draft release' {
            $intent = New-TestIntent -Id 99999 -TagName 'v1.0.0'
            $ctx = New-TestContext -Phase 'stable' -Version 'v1.0.0' -Intent $intent -TargetBranch 'main'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                function New-SemanticReleaseTags { param($TargetVersion, [switch]$PushToRemote) }

                Mock Import-Module { } -ParameterFilter { $Name -eq 'K.PSGallery.Smartagr' }
                Mock New-SemanticReleaseTags {
                    return [PSCustomObject]@{ SmartTags = @('v1', 'v1.0', 'latest') }
                }
                Mock gh { return '' }
                Mock New-BackflowPRs { return @() }

                $result = Publish-StableRelease -Context $Context

                # Should call PATCH API to update draft
                Should -Invoke gh -Times 1 -ParameterFilter {
                    $args -contains 'api' -and $args -contains '--method' -and $args -contains 'PATCH'
                }
            }
        }

        It 'Should use intent URL as release URL' {
            $intent = New-TestIntent -Id 12345 -TagName 'v2.0.0'
            $ctx = New-TestContext -Phase 'stable' -Version 'v2.0.0' -Intent $intent

            $result = InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                function New-SemanticReleaseTags { param($TargetVersion, [switch]$PushToRemote) }

                Mock Import-Module { } -ParameterFilter { $Name -eq 'K.PSGallery.Smartagr' }
                Mock New-SemanticReleaseTags {
                    return [PSCustomObject]@{ SmartTags = @() }
                }
                Mock gh { return '' }
                Mock New-BackflowPRs { return @() }

                Publish-StableRelease -Context $Context
            }

            $result.ReleaseUrl | Should -Be $intent.Url
        }
    }

    Context 'When no draft intent exists' {
        It 'Should create new release via gh release create' {
            $ctx = New-TestContext -Phase 'stable' -Version 'v3.0.0' -Intent $null -TargetBranch 'main'

            InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                function New-SemanticReleaseTags { param($TargetVersion, [switch]$PushToRemote) }

                Mock Import-Module { } -ParameterFilter { $Name -eq 'K.PSGallery.Smartagr' }
                Mock New-SemanticReleaseTags {
                    return [PSCustomObject]@{ SmartTags = @('v3', 'latest') }
                }
                Mock gh {
                    if ($args -contains 'release' -and $args -contains 'create') {
                        return 'Release created'
                    }
                    if ($args -contains 'release' -and $args -contains 'view') {
                        return 'https://github.com/TestOwner/TestRepo/releases/tag/v3.0.0'
                    }
                    return ''
                }
                Mock New-BackflowPRs { return @() }

                $result = Publish-StableRelease -Context $Context

                Should -Invoke gh -Times 1 -ParameterFilter {
                    $args -contains 'release' -and $args -contains 'create'
                }
            }
        }
    }

    Context 'Output structure' {
        It 'Should include version and smart tags' {
            $ctx = New-TestContext -Phase 'stable' -Version 'v1.2.3' -Intent $null

            $result = InModuleScope $script:TestModule.Name -Parameters @{ Context = $ctx } {
                param($Context)

                function New-SemanticReleaseTags { param($TargetVersion, [switch]$PushToRemote) }

                Mock Import-Module { } -ParameterFilter { $Name -eq 'K.PSGallery.Smartagr' }
                Mock New-SemanticReleaseTags {
                    return [PSCustomObject]@{ SmartTags = @('v1', 'v1.2', 'latest') }
                }
                Mock gh {
                    if ($args -contains 'view') {
                        return 'https://github.com/TestOwner/TestRepo/releases/tag/v1.2.3'
                    }
                    return ''
                }
                Mock New-BackflowPRs { return @() }

                Publish-StableRelease -Context $Context
            }

            $result.TagsCreated | Should -Contain 'v1.2.3'
            $result.TagsCreated | Should -Contain 'v1'
            $result.TagsCreated | Should -Contain 'latest'
        }
    }
}

#endregion
