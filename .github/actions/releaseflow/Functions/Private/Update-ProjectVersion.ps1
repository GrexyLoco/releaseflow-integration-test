function Update-ProjectVersion {
    <#
    .SYNOPSIS
        Updates version in project files based on detected project type.

    .DESCRIPTION
        Automatically detects the project type and updates version information:
        - PowerShell: Updates *.psd1 files
        - .NET: Updates Directory.Build.props or *.csproj
        
        Creates a commit with [skip ci] to prevent infinite loops.

    .PARAMETER Version
        The base version (e.g., "1.2.3").

    .PARAMETER PreRelease
        Optional prerelease suffix WITHOUT dot (e.g., "alpha3", "beta1").

    .PARAMETER WorkingDirectory
        The directory to search for project files. Default: current directory.

    .OUTPUTS
        [PSCustomObject] with UpdatedFiles and CommitSha.

    .EXAMPLE
        Update-ProjectVersion -Version "1.2.3" -PreRelease "alpha3"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^\d+\.\d+\.\d+$')]
        [string]$Version,

        # Supports both formats: alpha1 and alpha.1 (SemVer-compliant)
        [ValidatePattern('^(alpha|beta|rc)\.?\d+$')]
        [string]$PreRelease,

        [string]$WorkingDirectory = '.'
    )

    Push-Location $WorkingDirectory
    try {
        $updatedFiles = @()

        # Detect and update PowerShell manifests
        $psd1Files = Get-ChildItem -Recurse -Filter '*.psd1' -File |
            Where-Object { $_.FullName -notmatch '[\\/](bin|obj|node_modules)[\\/]' }
        
        if ($psd1Files) {
            foreach ($file in $psd1Files) {
                $result = Update-PowerShellVersion -FilePath $file.FullName -Version $Version -PreRelease $PreRelease
                if ($result.Updated) { $updatedFiles += $result }
            }
        }

        # Detect and update .NET projects
        $directoryBuildProps = Get-ChildItem -Recurse -Filter 'Directory.Build.props' -File |
            Select-Object -First 1

        if ($directoryBuildProps) {
            # Central versioning via Directory.Build.props
            $result = Update-DotNetVersion -FilePath $directoryBuildProps.FullName -Version $Version -PreRelease $PreRelease
            if ($result.Updated) { $updatedFiles += $result }
        }
        else {
            # Individual csproj files
            $csprojFiles = Get-ChildItem -Recurse -Filter '*.csproj' -File |
                Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' }
            
            foreach ($file in $csprojFiles) {
                $result = Update-DotNetVersion -FilePath $file.FullName -Version $Version -PreRelease $PreRelease
                if ($result.Updated) { $updatedFiles += $result }
            }
        }

        # Create commit if files were updated
        if ($updatedFiles.Count -gt 0 -and $PSCmdlet.ShouldProcess("Commit version update", "git commit")) {
            $fullVersion = if ($PreRelease) { "$Version-$PreRelease" } else { $Version }
            
            # Add only the updated files, not everything (avoids adding embedded repos)
            foreach ($file in $updatedFiles) {
                git add $file.FilePath
            }
            git commit -m "chore(version): update to $fullVersion [skip ci]"
            
            $commitSha = git rev-parse HEAD

            [PSCustomObject]@{
                UpdatedFiles = $updatedFiles
                CommitSha    = $commitSha
                Version      = $fullVersion
            }
        }
        else {
            Write-Warning "No project files found or updated."
            [PSCustomObject]@{
                UpdatedFiles = @()
                CommitSha    = $null
                Version      = $null
            }
        }
    }
    finally {
        Pop-Location
    }
}
