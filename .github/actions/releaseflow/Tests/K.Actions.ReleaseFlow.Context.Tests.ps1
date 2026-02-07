#Requires -Version 7.4
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for context detection functions.

.DESCRIPTION
    Tests Get-ReleaseContext and Get-DraftIntent functions.
    Uses mocking to isolate from GitHub environment.
#>

BeforeAll {
    # Import module
    $modulePath = Join-Path $PSScriptRoot '..' 'K.Actions.ReleaseFlow.psd1'
    $script:TestModule = Import-Module $modulePath -Force -PassThru
}

AfterAll {
    if ($script:TestModule) {
        Remove-Module $script:TestModule.Name -Force -ErrorAction SilentlyContinue
    }
}

#region Helper Functions

function script:New-TestEventFile {
    <#
    .SYNOPSIS
        Creates a temporary GitHub event JSON file for testing.
    #>
    param(
        [string]$SourceBranch,
        [string]$TargetBranch,
        [string]$Repository = 'TestOwner/TestRepo',
        [int]$PullRequestNumber = 42
    )

    $eventContent = @{
        pull_request = @{
            number = $PullRequestNumber
            head   = @{ ref = $SourceBranch }
            base   = @{ ref = $TargetBranch }
        }
        repository   = @{
            full_name = $Repository
        }
    } | ConvertTo-Json -Depth 5

    $tempFile = [System.IO.Path]::GetTempFileName()
    $eventContent | Set-Content -Path $tempFile -Encoding utf8
    return $tempFile
}

#endregion

#region Get-ReleaseContext Tests

Describe 'Get-ReleaseContext' {
    BeforeEach {
        # Save original env values
        $script:OriginalEventPath = $env:GITHUB_EVENT_PATH
        $script:OriginalRepository = $env:GITHUB_REPOSITORY
    }

    AfterEach {
        # Restore env values
        $env:GITHUB_EVENT_PATH = $script:OriginalEventPath
        $env:GITHUB_REPOSITORY = $script:OriginalRepository

        # Cleanup temp files
        if ($script:TestEventFile -and (Test-Path $script:TestEventFile)) {
            Remove-Item $script:TestEventFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Phase Detection - Alpha' {
        It 'Should detect alpha phase for feature → dev merge' {
            $script:TestEventFile = New-TestEventFile -SourceBranch 'feature/new-feature' -TargetBranch 'dev/v1.2.0'
            $env:GITHUB_EVENT_PATH = $script:TestEventFile
            $env:GITHUB_REPOSITORY = 'TestOwner/TestRepo'

            InModuleScope $script:TestModule.Name {
                # Mock Get-DraftIntent to avoid API call
                Mock Get-DraftIntent { return $null }

                $result = Get-ReleaseContext

                $result.Phase | Should -Be 'alpha'
                $result.Version | Should -Be 'v1.2.0'
                $result.SourceBranch | Should -Be 'feature/new-feature'
                $result.TargetBranch | Should -Be 'dev/v1.2.0'
            }
        }

        It 'Should detect alpha phase for fix → dev merge' {
            $script:TestEventFile = New-TestEventFile -SourceBranch 'fix/bugfix' -TargetBranch 'dev/v1.0.0'
            $env:GITHUB_EVENT_PATH = $script:TestEventFile
            $env:GITHUB_REPOSITORY = 'TestOwner/TestRepo'

            InModuleScope $script:TestModule.Name {
                Mock Get-DraftIntent { return $null }

                $result = Get-ReleaseContext

                $result.Phase | Should -Be 'alpha'
            }
        }
    }

    Context 'Phase Detection - Freeze' {
        It 'Should detect freeze phase for dev → release merge' {
            $script:TestEventFile = New-TestEventFile -SourceBranch 'dev/v1.2.0' -TargetBranch 'release/v1.2.0'
            $env:GITHUB_EVENT_PATH = $script:TestEventFile
            $env:GITHUB_REPOSITORY = 'TestOwner/TestRepo'

            InModuleScope $script:TestModule.Name {
                Mock Get-DraftIntent { return $null }

                $result = Get-ReleaseContext

                $result.Phase | Should -Be 'freeze'
                $result.Version | Should -Be 'v1.2.0'
            }
        }
    }

    Context 'Phase Detection - Beta' {
        It 'Should detect beta phase for fix → release merge' {
            $script:TestEventFile = New-TestEventFile -SourceBranch 'fix/critical-bug' -TargetBranch 'release/v1.2.0'
            $env:GITHUB_EVENT_PATH = $script:TestEventFile
            $env:GITHUB_REPOSITORY = 'TestOwner/TestRepo'

            InModuleScope $script:TestModule.Name {
                Mock Get-DraftIntent { return $null }

                $result = Get-ReleaseContext

                $result.Phase | Should -Be 'beta'
                $result.Version | Should -Be 'v1.2.0'
            }
        }
    }

    Context 'Phase Detection - Stable' {
        It 'Should detect stable phase for release → main merge' {
            $script:TestEventFile = New-TestEventFile -SourceBranch 'release/v1.2.0' -TargetBranch 'main'
            $env:GITHUB_EVENT_PATH = $script:TestEventFile
            $env:GITHUB_REPOSITORY = 'TestOwner/TestRepo'

            InModuleScope $script:TestModule.Name {
                Mock Get-DraftIntent { return $null }

                $result = Get-ReleaseContext

                $result.Phase | Should -Be 'stable'
                $result.Version | Should -Be 'v1.2.0'
            }
        }
    }

    Context 'Error Handling' {
        It 'Should throw when event file does not exist' {
            $env:GITHUB_EVENT_PATH = 'C:\nonexistent\path\event.json'

            InModuleScope $script:TestModule.Name {
                { Get-ReleaseContext } | Should -Throw '*not found*'
            }
        }

        It 'Should throw for unknown target branch pattern' {
            $script:TestEventFile = New-TestEventFile -SourceBranch 'feature/test' -TargetBranch 'unknown-branch'
            $env:GITHUB_EVENT_PATH = $script:TestEventFile
            $env:GITHUB_REPOSITORY = 'TestOwner/TestRepo'

            InModuleScope $script:TestModule.Name {
                Mock Get-DraftIntent { return $null }

                { Get-ReleaseContext } | Should -Throw '*Cannot determine release phase*'
            }
        }
    }

    Context 'Output Properties' {
        It 'Should include all required properties' {
            $script:TestEventFile = New-TestEventFile `
                -SourceBranch 'feature/test' `
                -TargetBranch 'dev/v2.0.0' `
                -Repository 'MyOrg/MyRepo' `
                -PullRequestNumber 123
            $env:GITHUB_EVENT_PATH = $script:TestEventFile
            $env:GITHUB_REPOSITORY = 'MyOrg/MyRepo'

            InModuleScope $script:TestModule.Name {
                Mock Get-DraftIntent { return $null }

                $result = Get-ReleaseContext

                $result.Phase | Should -Not -BeNullOrEmpty
                $result.Version | Should -Not -BeNullOrEmpty
                $result.SourceBranch | Should -Not -BeNullOrEmpty
                $result.TargetBranch | Should -Not -BeNullOrEmpty
                $result.Repository | Should -Be 'MyOrg/MyRepo'
                $result.PullRequest | Should -Be 123
            }
        }
    }
}

#endregion

#region Get-DraftIntent Tests

Describe 'Get-DraftIntent' {
    BeforeEach {
        $script:OriginalRepository = $env:GITHUB_REPOSITORY
    }

    AfterEach {
        $env:GITHUB_REPOSITORY = $script:OriginalRepository
    }

    Context 'When draft intent exists' {
        It 'Should return draft release details' {
            $env:GITHUB_REPOSITORY = 'TestOwner/TestRepo'

            InModuleScope $script:TestModule.Name {
                $mockReleases = @(
                    @{
                        id               = 12345
                        draft            = $true
                        tag_name         = 'v1.2.0'
                        name             = 'Release v1.2.0'
                        body             = 'Release notes'
                        target_commitish = 'dev/v1.2.0'
                        prerelease       = $false
                        html_url         = 'https://github.com/TestOwner/TestRepo/releases/12345'
                        created_at       = '2024-01-01T00:00:00Z'
                    }
                ) | ConvertTo-Json

                Mock gh { return $mockReleases }

                $result = Get-DraftIntent -Version 'v1.2.0'

                $result | Should -Not -BeNull
                $result.Id | Should -Be 12345
                $result.TagName | Should -Be 'v1.2.0'
                $result.Name | Should -Be 'Release v1.2.0'
            }
        }

        It 'Should normalize version without v prefix' {
            $env:GITHUB_REPOSITORY = 'TestOwner/TestRepo'

            InModuleScope $script:TestModule.Name {
                $mockReleases = @(
                    @{
                        id               = 999
                        draft            = $true
                        tag_name         = 'v2.0.0'
                        name             = 'Release v2.0.0'
                        body             = 'Notes'
                        target_commitish = 'dev/v2.0.0'
                        prerelease       = $false
                        html_url         = 'https://github.com/TestOwner/TestRepo/releases/999'
                        created_at       = '2024-01-01T00:00:00Z'
                    }
                ) | ConvertTo-Json

                Mock gh { return $mockReleases }

                $result = Get-DraftIntent -Version '2.0.0'

                $result | Should -Not -BeNull
                $result.TagName | Should -Be 'v2.0.0'
            }
        }
    }

    Context 'When draft intent does not exist' {
        It 'Should return null when no draft matches version' {
            $env:GITHUB_REPOSITORY = 'TestOwner/TestRepo'

            InModuleScope $script:TestModule.Name {
                $mockReleases = @(
                    @{
                        id       = 1
                        draft    = $false  # Not a draft
                        tag_name = 'v1.0.0'
                    }
                ) | ConvertTo-Json

                Mock gh { return $mockReleases }

                $result = Get-DraftIntent -Version 'v1.0.0'

                $result | Should -BeNull
            }
        }

        It 'Should return null when no releases exist' {
            $env:GITHUB_REPOSITORY = 'TestOwner/TestRepo'

            InModuleScope $script:TestModule.Name {
                Mock gh { return $null }

                $result = Get-DraftIntent -Version 'v1.0.0'

                $result | Should -BeNull
            }
        }
    }

    Context 'Error Handling' {
        It 'Should throw when GITHUB_REPOSITORY is not set' {
            $env:GITHUB_REPOSITORY = $null

            InModuleScope $script:TestModule.Name {
                { Get-DraftIntent -Version 'v1.0.0' } | Should -Throw '*GITHUB_REPOSITORY*'
            }
        }
    }
}

#endregion
