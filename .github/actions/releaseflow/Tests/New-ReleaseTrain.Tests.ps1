#Requires -Version 7.4
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for New-ReleaseTrain function.

.DESCRIPTION
    Tests all guardrails (PD-1 to PD-4) for the New-ReleaseTrain function.
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

Describe 'New-ReleaseTrain' {
    Context 'Guardrail PD-1: Existing Intent' {
        It 'Should throw when Draft Intent exists' {
            InModuleScope $script:TestModule.Name {
                # Mock gh release list to return existing intent
                Mock gh { '[{"tagName":"v2.0.0","isDraft":true}]' }
                # Mock git commands - need to mock git describe for latest-stable resolution
                Mock git { 
                    if ($args[0] -eq 'describe') {
                        return 'v1.0.0'
                    }
                    if ($args[0] -eq 'rev-parse') {
                        $global:LASTEXITCODE = 0
                        return 'abc123'
                    }
                    if ($args[0] -eq 'tag') {
                        return ''
                    }
                    if ($args[0] -eq 'branch') {
                        return ''
                    }
                    return ''
                }
                
                { New-ReleaseTrain -TargetVersion '2.0.0' } | Should -Throw '*PD-1*existiert bereits*'
            }
        }
    }

    Context 'Guardrail PD-2: Existing Tag' {
        It 'Should throw when Git tag exists' {
            InModuleScope $script:TestModule.Name {
                Mock gh { '[]' }
                # Mock git commands with unified mock
                Mock git { 
                    if ($args[0] -eq 'describe') {
                        return 'v1.0.0'
                    }
                    if ($args[0] -eq 'rev-parse') {
                        $global:LASTEXITCODE = 0
                        return 'abc123'
                    }
                    if ($args[0] -eq 'tag') {
                        return 'v2.0.0'  # Tag exists
                    }
                    if ($args[0] -eq 'branch') {
                        return ''
                    }
                    return ''
                }
                
                { New-ReleaseTrain -TargetVersion '2.0.0' } | Should -Throw '*PD-2*existiert bereits*'
            }
        }
    }

    Context 'Guardrail PD-3: Existing Branch' {
        It 'Should throw when branch exists' {
            InModuleScope $script:TestModule.Name {
                Mock gh { '[]' }
                # Mock git commands with unified mock
                Mock git { 
                    if ($args[0] -eq 'describe') {
                        return 'v1.0.0'
                    }
                    if ($args[0] -eq 'rev-parse') {
                        $global:LASTEXITCODE = 0
                        return 'abc123'
                    }
                    if ($args[0] -eq 'tag') {
                        return ''
                    }
                    if ($args[0] -eq 'branch') {
                        return 'origin/dev/v2.0.0'  # Branch exists
                    }
                    return ''
                }
                
                { New-ReleaseTrain -TargetVersion '2.0.0' } | Should -Throw '*PD-3*existiert bereits*'
            }
        }
    }

    Context 'Guardrail PD-4: Invalid Base' {
        It 'Should throw when base not found' {
            InModuleScope $script:TestModule.Name {
                Mock gh { '[]' }
                # Mock git commands with unified mock
                Mock git { 
                    if ($args[0] -eq 'tag') {
                        return ''
                    }
                    if ($args[0] -eq 'branch') {
                        return ''
                    }
                    if ($args[0] -eq 'rev-parse') {
                        $global:LASTEXITCODE = 1
                        return $null
                    }
                    return ''
                }
                
                { New-ReleaseTrain -TargetVersion '2.0.0' -Base 'nonexistent' } | Should -Throw '*PD-4*nicht gefunden*'
            }
        }
    }
}
