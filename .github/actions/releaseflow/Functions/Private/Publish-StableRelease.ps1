function Publish-StableRelease {
    <#
    .SYNOPSIS
        Publishes a stable release by promoting the draft intent.

    .DESCRIPTION
        Publishes the draft release intent as a stable release.
        The stable tag (e.g., v1.0.0) is automatically created by GitHub when publishing.
        Then creates/updates smart tags (v1, v1.2, latest) via Smartagr.

    .PARAMETER Context
        Release context from Get-ReleaseContext.

    .OUTPUTS
        [PSCustomObject] with ReleaseUrl and TagsCreated.

    .NOTES
        Internal function - not exported.
        Order is important: Publish release first (creates stable tag),
        then update smart tags via Smartagr.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Context
    )

    Write-Verbose "Publish-StableRelease: Publishing stable release $($Context.Version)..."

    # Import Smartagr for tagging
    Import-Module K.PSGallery.Smartagr -Force

    # Create stable tag via Smartagr (includes smart tags: v1, v1.2, latest)
    Write-Information "Creating stable release: $($Context.Version)"
    $tagResult = New-SemanticReleaseTags -TargetVersion $Context.Version

    # Update project version files (stable, no PreRelease)
    Write-Verbose "Publish-StableRelease: Updating project version to $($Context.Version)..."
    $versionBase = $Context.Version.TrimStart('v')
    
    # Configure git identity for automated commits (GitHub Actions)
    if ($env:GITHUB_ACTIONS) {
        git config user.name "github-actions[bot]"
        git config user.email "github-actions[bot]@users.noreply.github.com"
    }
    
    $versionUpdate = Update-ProjectVersion -Version $versionBase
    # Use PSObject.Properties for strict-mode-safe property access
    $commitSha = $null
    if ($versionUpdate -and $versionUpdate.PSObject.Properties['CommitSha']) {
        $commitSha = $versionUpdate.CommitSha
    }
    if ($commitSha) {
        Write-Information "Version updated and committed: $commitSha"
        git push origin main
    }

    # Publish the draft release (convert from draft to published)
    # IMPORTANT: This must happen FIRST before creating tags
    # GitHub will automatically create the stable tag (e.g., v1.0.0) when publishing
    if ($Context.Intent) {
        Write-Verbose "Publish-StableRelease: Publishing draft release ID $($Context.Intent.Id)..."

        # Update the draft release to published
        # This will cause GitHub to automatically create the stable tag
        & gh api --method PATCH "repos/$($Context.Repository)/releases/$($Context.Intent.Id)" `
            -f draft=false `
            -f tag_name=$($Context.Version) `
            -f target_commitish='main'

        $releaseUrl = $Context.Intent.Url
    }
    else {
        # Create new release if no draft exists
        $releaseBody = @"
## Release $($Context.Version)

This is an automated stable release.

**Source:** $($Context.SourceBranch)
**Target:** $($Context.TargetBranch)
**PR:** #$($Context.PullRequest)

> ✅ This is a production-ready stable release.
"@

        & gh release create $Context.Version `
            --repo $Context.Repository `
            --title "Release: $($Context.Version)" `
            --notes $releaseBody `
            --target 'main'

        $releaseUrl = & gh release view $Context.Version --repo $Context.Repository --json url -q '.url'
    }

    # Import Smartagr for tagging
    Import-Module K.PSGallery.Smartagr -Force

    # Create smart tags via Smartagr (v1, v1.2, latest)
    # The stable tag (e.g., v1.0.0) was already created by GitHub above
    # Smartagr will skip it if it already exists and only create/update smart tags
    Write-Information "Creating smart tags for: $($Context.Version)"
    $tagResult = New-SemanticReleaseTags -TargetVersion $Context.Version -PushToRemote

    # Create backflow PRs to all open dev trains
    Write-Verbose "Publish-StableRelease: Creating backflow PRs..."
    $backflowPRs = @(New-BackflowPRs -Version $Context.Version)

    if ($backflowPRs.Count -gt 0) {
        Write-Information "Created $($backflowPRs.Count) backflow PR(s)"
    }
    else {
        Write-Verbose "Publish-StableRelease: No backflow PRs needed (no open dev intents)"
    }

    [PSCustomObject]@{
        ReleaseUrl   = $releaseUrl
        TagsCreated  = @($Context.Version) + $tagResult.SmartTags
        BackflowPRs  = $backflowPRs
    }
}
