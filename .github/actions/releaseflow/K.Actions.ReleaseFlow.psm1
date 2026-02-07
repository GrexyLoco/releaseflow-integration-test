#Requires -Version 7.4

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    K.Actions.ReleaseFlow - GitHub Action for automated release orchestration.

.DESCRIPTION
    This module provides the New-Release function as the single entry point for
    all release operations. It automatically detects the current phase (Alpha,
    Beta, Stable) based on branch context and delegates to internal functions.

    Architecture:
    - New-Release (Public)     → Single entry point, phase detection
    - Get-ReleaseContext       → Detects phase from branches
    - Test-ReleaseGuardrails   → G1-G5 validation
    - New-AlphaRelease         → Alpha tag + GitHub Release
    - New-BetaRelease          → Beta tag + GitHub Release
    - Publish-StableRelease    → Stable tag + Publish Draft
    - New-BackflowPRs          → PRs to open trains
    - Get-DraftIntent          → Intent from GitHub API

    Smartagr (separate module) handles all tagging operations.

.NOTES
    Author: GrexyLoco
    Version: 0.1.0
    Requires: PowerShell 7.4+, GitHub CLI (gh)
#>

# Get module root path
$script:ModuleRoot = $PSScriptRoot

# Dot-source all Handler functions first (from Handlers subdirectory)
$handlerFunctions = @(Get-ChildItem -Path "$script:ModuleRoot/Functions/Private/Handlers" -Filter '*.ps1' -ErrorAction SilentlyContinue)
foreach ($file in $handlerFunctions) {
    try {
        . $file.FullName
        Write-Verbose "Loaded handler function: $($file.BaseName)"
    }
    catch {
        Write-Error "Failed to load handler function '$($file.Name)': $_"
        throw
    }
}

# Dot-source all Private functions
$privateFunctions = @(Get-ChildItem -Path "$script:ModuleRoot/Functions/Private" -Filter '*.ps1' -ErrorAction SilentlyContinue)
foreach ($file in $privateFunctions) {
    try {
        . $file.FullName
        Write-Verbose "Loaded private function: $($file.BaseName)"
    }
    catch {
        Write-Error "Failed to load private function '$($file.Name)': $_"
        throw
    }
}

# Dot-source all Public functions
$publicFunctions = @(Get-ChildItem -Path "$script:ModuleRoot/Functions/Public" -Filter '*.ps1' -ErrorAction SilentlyContinue)
foreach ($file in $publicFunctions) {
    try {
        . $file.FullName
        Write-Verbose "Loaded public function: $($file.BaseName)"
    }
    catch {
        Write-Error "Failed to load public function '$($file.Name)': $_"
        throw
    }
}

Write-Verbose "K.Actions.ReleaseFlow module loaded successfully. Functions: $($publicFunctions.Count) public, $($privateFunctions.Count) private, $($handlerFunctions.Count) handlers."
