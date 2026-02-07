#Requires -Version 7.4
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for Update-ProjectVersion and its handlers.

.DESCRIPTION
    Tests Update-ProjectVersion orchestrator and both handlers:
    - Update-PowerShellVersion
    - Update-DotNetVersion
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

Describe 'Update-PowerShellVersion' {
    Context 'Basic Version Updates' {
        It 'Should update ModuleVersion in .psd1' {
            InModuleScope $script:TestModule.Name {
                $psd1Content = @"
@{
    ModuleVersion = '0.1.0'
    PrivateData = @{
        PSData = @{
            Prerelease = ''
        }
    }
}
"@
                $testFile = Join-Path $TestDrive 'test.psd1'
                Set-Content -Path $testFile -Value $psd1Content

                $result = Update-PowerShellVersion -FilePath $testFile -Version '1.2.3'

                $content = Get-Content $testFile -Raw
                $content | Should -Match "ModuleVersion = '1.2.3'"
                $result.Updated | Should -Be $true
                $result.Version | Should -Be '1.2.3'
                $result.FileType | Should -Be 'PowerShell'
            }
        }

        It 'Should update ModuleVersion with PreRelease' {
            InModuleScope $script:TestModule.Name {
                $psd1Content = @"
@{
    ModuleVersion = '0.1.0'
    PrivateData = @{
        PSData = @{
            Prerelease = ''
        }
    }
}
"@
                $testFile = Join-Path $TestDrive 'test.psd1'
                Set-Content -Path $testFile -Value $psd1Content

                $result = Update-PowerShellVersion -FilePath $testFile -Version '1.2.3' -PreRelease 'alpha3'

                $content = Get-Content $testFile -Raw
                $content | Should -Match "ModuleVersion = '1.2.3'"
                $content | Should -Match "Prerelease = 'alpha3'"
                $result.PreRelease | Should -Be 'alpha3'
            }
        }

        It 'Should add Prerelease if not present' {
            InModuleScope $script:TestModule.Name {
                $psd1Content = @"
@{
    ModuleVersion = '0.1.0'
    PrivateData = @{
        PSData = @{
        }
    }
}
"@
                $testFile = Join-Path $TestDrive 'test-noprerelease.psd1'
                Set-Content -Path $testFile -Value $psd1Content

                Update-PowerShellVersion -FilePath $testFile -Version '1.2.3' -PreRelease 'beta2'

                $content = Get-Content $testFile -Raw
                $content | Should -Match "Prerelease = 'beta2'"
            }
        }

        It 'Should remove Prerelease for stable version' {
            InModuleScope $script:TestModule.Name {
                $psd1Content = @"
@{
    ModuleVersion = '0.1.0'
    PrivateData = @{
        PSData = @{
            Prerelease = 'alpha1'
        }
    }
}
"@
                $testFile = Join-Path $TestDrive 'test-stable.psd1'
                Set-Content -Path $testFile -Value $psd1Content

                Update-PowerShellVersion -FilePath $testFile -Version '1.0.0'

                $content = Get-Content $testFile -Raw
                $content | Should -Match "ModuleVersion = '1.0.0'"
                $content | Should -Not -Match "Prerelease = 'alpha1'"
            }
        }
    }

    Context 'Error Handling' {
        It 'Should throw if file not found' {
            InModuleScope $script:TestModule.Name {
                { Update-PowerShellVersion -FilePath '/nonexistent/file.psd1' -Version '1.0.0' } |
                    Should -Throw 'File not found*'
            }
        }
    }
}

Describe 'Update-DotNetVersion' {
    Context 'Basic Version Updates' {
        It 'Should update VersionPrefix in Directory.Build.props' {
            InModuleScope $script:TestModule.Name {
                $propsContent = @"
<Project>
  <PropertyGroup>
    <VersionPrefix>0.1.0</VersionPrefix>
  </PropertyGroup>
</Project>
"@
                $testFile = Join-Path $TestDrive 'Directory.Build.props'
                Set-Content -Path $testFile -Value $propsContent

                $result = Update-DotNetVersion -FilePath $testFile -Version '1.2.3'

                [xml]$content = Get-Content $testFile
                $content.Project.PropertyGroup.VersionPrefix | Should -Be '1.2.3'
                $result.Updated | Should -Be $true
                $result.Version | Should -Be '1.2.3'
                $result.FileType | Should -Be '.NET'
            }
        }

        It 'Should update VersionPrefix and add VersionSuffix' {
            InModuleScope $script:TestModule.Name {
                $propsContent = @"
<Project>
  <PropertyGroup>
    <VersionPrefix>0.1.0</VersionPrefix>
  </PropertyGroup>
</Project>
"@
                $testFile = Join-Path $TestDrive 'Directory.Build.props'
                Set-Content -Path $testFile -Value $propsContent

                $result = Update-DotNetVersion -FilePath $testFile -Version '1.2.3' -PreRelease 'beta2'

                [xml]$content = Get-Content $testFile
                $content.Project.PropertyGroup.VersionPrefix | Should -Be '1.2.3'
                $content.Project.PropertyGroup.VersionSuffix | Should -Be 'beta2'
                $result.PreRelease | Should -Be 'beta2'
            }
        }

        It 'Should create PropertyGroup if not exists' {
            InModuleScope $script:TestModule.Name {
                $propsContent = @"
<Project>
</Project>
"@
                $testFile = Join-Path $TestDrive 'empty.csproj'
                Set-Content -Path $testFile -Value $propsContent

                Update-DotNetVersion -FilePath $testFile -Version '1.0.0'

                [xml]$content = Get-Content $testFile
                $propertyGroup = $content.Project.PropertyGroup
                $propertyGroup | Should -Not -BeNullOrEmpty
                $propertyGroup.VersionPrefix | Should -Be '1.0.0'
            }
        }

        It 'Should remove VersionSuffix for stable version' {
            InModuleScope $script:TestModule.Name {
                $propsContent = @"
<Project>
  <PropertyGroup>
    <VersionPrefix>0.1.0</VersionPrefix>
    <VersionSuffix>alpha1</VersionSuffix>
  </PropertyGroup>
</Project>
"@
                $testFile = Join-Path $TestDrive 'stable.csproj'
                Set-Content -Path $testFile -Value $propsContent

                Update-DotNetVersion -FilePath $testFile -Version '1.0.0'

                [xml]$content = Get-Content $testFile
                $content.Project.PropertyGroup.VersionPrefix | Should -Be '1.0.0'
                $content.Project.PropertyGroup.SelectSingleNode('VersionSuffix') | Should -BeNullOrEmpty
            }
        }

        It 'Should remove old Version element if exists' {
            InModuleScope $script:TestModule.Name {
                $propsContent = @"
<Project>
  <PropertyGroup>
    <Version>0.1.0</Version>
  </PropertyGroup>
</Project>
"@
                $testFile = Join-Path $TestDrive 'oldversion.csproj'
                Set-Content -Path $testFile -Value $propsContent

                Update-DotNetVersion -FilePath $testFile -Version '1.2.3'

                [xml]$content = Get-Content $testFile
                $content.Project.PropertyGroup.SelectSingleNode('Version') | Should -BeNullOrEmpty
                $content.Project.PropertyGroup.VersionPrefix | Should -Be '1.2.3'
            }
        }
    }

    Context 'Error Handling' {
        It 'Should throw if file not found' {
            InModuleScope $script:TestModule.Name {
                { Update-DotNetVersion -FilePath '/nonexistent/file.csproj' -Version '1.0.0' } |
                    Should -Throw 'File not found*'
            }
        }
    }
}

Describe 'Update-ProjectVersion' {
    Context 'File Detection' {
        It 'Should detect and update .psd1 files' {
            InModuleScope $script:TestModule.Name {
                $psd1Content = @"
@{
    ModuleVersion = '0.1.0'
    PrivateData = @{
        PSData = @{
        }
    }
}
"@
                $testDir = Join-Path $TestDrive 'TestProject'
                New-Item -Path $testDir -ItemType Directory -Force | Out-Null
                $testFile = Join-Path $testDir 'Test.psd1'
                Set-Content -Path $testFile -Value $psd1Content

                Mock -CommandName git -MockWith { }

                $result = Update-ProjectVersion -Version '1.2.3' -PreRelease 'alpha1' -WorkingDirectory $testDir

                $result.UpdatedFiles.Count | Should -BeGreaterThan 0
                $result.UpdatedFiles[0].FileType | Should -Be 'PowerShell'
            }
        }

        It 'Should detect and update Directory.Build.props' {
            InModuleScope $script:TestModule.Name {
                $propsContent = @"
<Project>
  <PropertyGroup>
    <VersionPrefix>0.1.0</VersionPrefix>
  </PropertyGroup>
</Project>
"@
                $testDir = Join-Path $TestDrive 'DotNetProject'
                New-Item -Path $testDir -ItemType Directory -Force | Out-Null
                $testFile = Join-Path $testDir 'Directory.Build.props'
                Set-Content -Path $testFile -Value $propsContent

                Mock -CommandName git -MockWith { }

                $result = Update-ProjectVersion -Version '1.2.3' -WorkingDirectory $testDir

                $result.UpdatedFiles.Count | Should -BeGreaterThan 0
                $result.UpdatedFiles[0].FileType | Should -Be '.NET'
            }
        }

        It 'Should return empty result if no project files found' {
            InModuleScope $script:TestModule.Name {
                $testDir = Join-Path $TestDrive 'EmptyProject'
                New-Item -Path $testDir -ItemType Directory -Force | Out-Null

                $result = Update-ProjectVersion -Version '1.2.3' -WorkingDirectory $testDir -WarningAction SilentlyContinue

                $result.UpdatedFiles.Count | Should -Be 0
                $result.CommitSha | Should -BeNullOrEmpty
                $result.Version | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Version Format Validation' {
        It 'Should accept valid version format' {
            InModuleScope $script:TestModule.Name {
                $testDir = Join-Path $TestDrive 'ValidVersionTest'
                New-Item -Path $testDir -ItemType Directory -Force | Out-Null

                { Update-ProjectVersion -Version '1.2.3' -WorkingDirectory $testDir -WarningAction SilentlyContinue } |
                    Should -Not -Throw
            }
        }

        It 'Should reject invalid version format' {
            InModuleScope $script:TestModule.Name {
                { Update-ProjectVersion -Version 'invalid' -WorkingDirectory $TestDrive } |
                    Should -Throw
            }
        }

        It 'Should accept valid PreRelease format' {
            InModuleScope $script:TestModule.Name {
                $testDir = Join-Path $TestDrive 'ValidPreReleaseTest'
                New-Item -Path $testDir -ItemType Directory -Force | Out-Null

                { Update-ProjectVersion -Version '1.2.3' -PreRelease 'alpha1' -WorkingDirectory $testDir -WarningAction SilentlyContinue } |
                    Should -Not -Throw
            }
        }

        It 'Should reject invalid PreRelease format' {
            InModuleScope $script:TestModule.Name {
                { Update-ProjectVersion -Version '1.2.3' -PreRelease 'invalid' -WorkingDirectory $TestDrive } |
                    Should -Throw
            }
        }
    }
}
