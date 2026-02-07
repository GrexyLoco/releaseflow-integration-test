function Update-PowerShellVersion {
    <#
    .SYNOPSIS
        Updates version in a PowerShell module manifest (.psd1).

    .PARAMETER FilePath
        Path to the .psd1 file.

    .PARAMETER Version
        The base version (e.g., "1.2.3").

    .PARAMETER PreRelease
        Optional prerelease suffix (e.g., "alpha3").
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Version,

        [string]$PreRelease
    )

    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }

    $content = Get-Content $FilePath -Raw

    # Update ModuleVersion
    $content = $content -replace "ModuleVersion\s*=\s*['""][\d\.]+['""]", "ModuleVersion = '$Version'"

    # Update or add Prerelease in PrivateData.PSData
    if ($PreRelease) {
        if ($content -match 'Prerelease\s*=') {
            $content = $content -replace "Prerelease\s*=\s*['""][^'""]*['""]", "Prerelease = '$PreRelease'"
        }
        else {
            # Add Prerelease if PSData block exists
            $content = $content -replace '(PSData\s*=\s*@\{)', "`$1`n            Prerelease = '$PreRelease'"
        }
    }
    else {
        # Remove Prerelease for stable
        $content = $content -replace "Prerelease\s*=\s*['""][^'""]*['""]\s*\n?", ""
    }

    Set-Content -Path $FilePath -Value $content -NoNewline

    [PSCustomObject]@{
        FilePath   = $FilePath
        FileType   = 'PowerShell'
        Version    = $Version
        PreRelease = $PreRelease
        Updated    = $true
    }
}
