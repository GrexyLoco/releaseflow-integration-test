function New-AlphaRelease {
    <#
    .SYNOPSIS
        Creates an alpha pre-release.

    .DESCRIPTION
        Creates an alpha release with the next available alpha number
        based on existing tags. Uses Smartagr for tagging.

    .PARAMETER Context
        Release context from Get-ReleaseContext.

    .OUTPUTS
        [PSCustomObject] with ReleaseUrl and TagsCreated.

    .NOTES
        Internal function - not exported.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Context
    )

    Write-Verbose "New-AlphaRelease: Creating alpha release for $($Context.Version)..."

    # Import Smartagr for tagging
    Import-Module K.PSGallery.Smartagr -Force

    # Get next alpha number from Smartagr
    $nextNumber = Get-NextPreReleaseNumber -Version $Context.Version -Type 'alpha'
    # Use SemVer-compliant format: v1.0.0-alpha.1 (with dot before number)
    $alphaTag = "$($Context.Version)-alpha.$nextNumber"

    Write-Information "Creating alpha release: $alphaTag"

    # Create tags via Smartagr (creates and pushes tags automatically)
    $tagResult = New-SemanticReleaseTags -TargetVersion $alphaTag

    # Update project version files
    Write-Verbose "New-AlphaRelease: Updating project version to $alphaTag..."
    $versionBase = $Context.Version.TrimStart('v')
    
    # Configure git identity for automated commits (GitHub Actions)
    if ($env:GITHUB_ACTIONS) {
        git config user.name "github-actions[bot]"
        git config user.email "github-actions[bot]@users.noreply.github.com"
    }
    
    $versionUpdate = Update-ProjectVersion -Version $versionBase -PreRelease "alpha.$nextNumber"
    # Use PSObject.Properties for strict-mode-safe property access
    $commitSha = $null
    if ($versionUpdate -and $versionUpdate.PSObject.Properties['CommitSha']) {
        $commitSha = $versionUpdate.CommitSha
    }
    if ($commitSha) {
        Write-Information "Version updated and committed: $commitSha"
        git push origin $Context.TargetBranch 2>&1
    }

    # Create GitHub release (pre-release)
    $releaseBody = @"
## Alpha Release $alphaTag

This is an automated alpha pre-release from the development branch.

**Source:** $($Context.SourceBranch)
**Target:** $($Context.TargetBranch)
**PR:** #$($Context.PullRequest)

> ⚠️ Alpha releases are for testing purposes only.
"@

    $releaseJson = & gh release create $alphaTag `
        --repo $Context.Repository `
        --title "Alpha: $alphaTag" `
        --notes $releaseBody `
        --prerelease `
        --target $Context.TargetBranch

    $releaseUrl = & gh release view $alphaTag --repo $Context.Repository --json url -q '.url'

    # Build list of created tags (alphaTag plus any smart tags from Smartagr)
    $allTags = @($alphaTag)
    if ($tagResult -and $tagResult.PSObject.Properties['CreatedTags']) {
        $allTags += $tagResult.CreatedTags
    }

    [PSCustomObject]@{
        ReleaseUrl  = $releaseUrl
        TagsCreated = $allTags
    }
}
