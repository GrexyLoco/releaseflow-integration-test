function Get-DraftIntent {
    <#
    .SYNOPSIS
        Retrieves the draft release intent for a given version.

    .DESCRIPTION
        Queries GitHub API to find a draft release matching the specified version.
        The draft release serves as the "intent" for a future release.

    .PARAMETER Version
        The version to look for (e.g., v1.2.0).

    .OUTPUTS
        [PSCustomObject] with draft release details, or $null if not found.

    .NOTES
        Internal function - not exported.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    Write-Verbose "Get-DraftIntent: Looking for draft release with tag '$Version'..."

    # Normalize version (ensure v prefix)
    if ($Version -notmatch '^v') {
        $Version = "v$Version"
    }

    # Get repository from environment
    $repository = $env:GITHUB_REPOSITORY
    if (-not $repository) {
        throw [System.InvalidOperationException]::new(
            "GITHUB_REPOSITORY environment variable is not set."
        )
    }

    # Query GitHub API for releases
    $releasesJson = & gh api "repos/$repository/releases" --paginate 2>$null
    if (-not $releasesJson) {
        Write-Verbose "Get-DraftIntent: No releases found in repository."
        return $null
    }

    $releases = $releasesJson | ConvertFrom-Json

    # Find draft release matching version
    $draftIntent = $releases | Where-Object {
        $_.draft -eq $true -and $_.tag_name -eq $Version
    } | Select-Object -First 1

    if (-not $draftIntent) {
        Write-Verbose "Get-DraftIntent: No draft intent found for version '$Version'."
        return $null
    }

    Write-Verbose "Get-DraftIntent: Found draft intent ID $($draftIntent.id)"

    [PSCustomObject]@{
        Id              = $draftIntent.id
        TagName         = $draftIntent.tag_name
        Name            = $draftIntent.name
        Body            = $draftIntent.body
        TargetCommitish = $draftIntent.target_commitish
        Prerelease      = $draftIntent.prerelease
        Url             = $draftIntent.html_url
        CreatedAt       = $draftIntent.created_at
    }
}
