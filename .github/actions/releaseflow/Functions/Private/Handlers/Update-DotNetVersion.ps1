function Update-DotNetVersion {
    <#
    .SYNOPSIS
        Updates version in a .NET project file (Directory.Build.props or .csproj).

    .PARAMETER FilePath
        Path to the project file.

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

    [xml]$xml = Get-Content $FilePath

    # Find or create PropertyGroup
    # Using SelectSingleNode to avoid StrictMode issues
    $propertyGroup = $xml.SelectSingleNode('//PropertyGroup[1]')
    if (-not $propertyGroup) {
        $propertyGroup = $xml.CreateElement('PropertyGroup')
        $projectNode = $xml.SelectSingleNode('//Project')
        if ($projectNode) {
            $projectNode.AppendChild($propertyGroup) | Out-Null
        } else {
            throw "Project element not found in $FilePath"
        }
    }

    # Update VersionPrefix
    $versionPrefixNode = $propertyGroup.SelectSingleNode('VersionPrefix')
    if ($versionPrefixNode) {
        $versionPrefixNode.InnerText = $Version
    }
    else {
        $newNode = $xml.CreateElement('VersionPrefix')
        $newNode.InnerText = $Version
        $propertyGroup.AppendChild($newNode) | Out-Null
    }

    # Update VersionSuffix
    $versionSuffixNode = $propertyGroup.SelectSingleNode('VersionSuffix')
    if ($PreRelease) {
        if ($versionSuffixNode) {
            $versionSuffixNode.InnerText = $PreRelease
        }
        else {
            $newNode = $xml.CreateElement('VersionSuffix')
            $newNode.InnerText = $PreRelease
            $propertyGroup.AppendChild($newNode) | Out-Null
        }
    }
    else {
        # Remove VersionSuffix for stable
        if ($versionSuffixNode) {
            $versionSuffixNode.ParentNode.RemoveChild($versionSuffixNode) | Out-Null
        }
    }

    # Remove old <Version> element if exists (we use Prefix/Suffix)
    $versionNode = $propertyGroup.SelectSingleNode('Version')
    if ($versionNode) {
        $versionNode.ParentNode.RemoveChild($versionNode) | Out-Null
    }

    $xml.Save($FilePath)

    [PSCustomObject]@{
        FilePath   = $FilePath
        FileType   = '.NET'
        Version    = $Version
        PreRelease = $PreRelease
        Updated    = $true
    }
}
