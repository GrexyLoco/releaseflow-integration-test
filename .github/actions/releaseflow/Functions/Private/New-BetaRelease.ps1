function New-BetaRelease {
    <#
    .SYNOPSIS
        Creates a beta pre-release.

    .DESCRIPTION
        Creates a beta release with the next available beta number
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

    Write-Verbose "New-BetaRelease: Creating beta release for $($Context.Version)..."

    # Import Smartagr for tagging
    Import-Module K.PSGallery.Smartagr -Force

    # Get next beta number from Smartagr
    $nextNumber = Get-NextPreReleaseNumber -Version $Context.Version -Type 'beta'
    # Use SemVer-compliant format: v1.0.0-beta.1 (with dot before number)
    $betaTag = "$($Context.Version)-beta.$nextNumber"

    Write-Information "Creating beta release: $betaTag"

    # Create tags via Smartagr (creates and pushes tags automatically)
    $tagResult = New-SemanticReleaseTags -TargetVersion $betaTag

    # Update project version files
    Write-Verbose "New-BetaRelease: Updating project version to $betaTag..."
    $versionBase = $Context.Version.TrimStart('v')
    
    # Configure git identity for automated commits (GitHub Actions)
    if ($env:GITHUB_ACTIONS) {
        git config user.name "github-actions[bot]"
        git config user.email "github-actions[bot]@users.noreply.github.com"
    }
    
    $versionUpdate = Update-ProjectVersion -Version $versionBase -PreRelease "beta.$nextNumber"
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
## Beta Release $betaTag

This is an automated beta pre-release from the release branch (frozen).

**Source:** $($Context.SourceBranch)
**Target:** $($Context.TargetBranch)
**PR:** #$($Context.PullRequest)

> 🧪 Beta releases are release candidates for testing.
"@

    $releaseJson = & gh release create $betaTag `
        --repo $Context.Repository `
        --title "Beta: $betaTag" `
        --notes $releaseBody `
        --prerelease `
        --target $Context.TargetBranch

    $releaseUrl = & gh release view $betaTag --repo $Context.Repository --json url -q '.url'

    # Build list of created tags (betaTag plus any smart tags from Smartagr)
    $allTags = @($betaTag)
    if ($tagResult -and $tagResult.PSObject.Properties['CreatedTags']) {
        $allTags += $tagResult.CreatedTags
    }

    [PSCustomObject]@{
        ReleaseUrl  = $releaseUrl
        TagsCreated = $allTags
    }
}
