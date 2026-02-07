function Get-NextPreReleaseNumber {
    <#
    .SYNOPSIS
        Calculates the next pre-release number for alpha or beta releases.

    .DESCRIPTION
        Queries existing tags to determine the next sequential pre-release number.
        For example, if v1.0.0-alpha1 exists, returns 2 for the next alpha.

    .PARAMETER Version
        The base version (e.g., v1.0.0).

    .PARAMETER Type
        The pre-release type: 'alpha' or 'beta'.

    .OUTPUTS
        [int] The next pre-release number.

    .EXAMPLE
        Get-NextPreReleaseNumber -Version 'v1.0.0' -Type 'alpha'
        # Returns 1 if no alpha tags exist, or the next number if they do.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [ValidateSet('alpha', 'beta')]
        [string]$Type
    )

    # Normalize version (ensure v prefix)
    if ($Version -notmatch '^v') {
        $Version = "v$Version"
    }

    Write-Verbose "Get-NextPreReleaseNumber: Looking for existing $Type tags for $Version..."

    # Get all tags matching the pattern
    $pattern = "$Version-$Type*"
    $existingTags = git tag -l $pattern 2>$null

    if (-not $existingTags) {
        Write-Verbose "Get-NextPreReleaseNumber: No existing $Type tags found. Starting at 1."
        return 1
    }

    # Parse existing numbers (supports both v1.0.0-alpha.1 and v1.0.0-alpha1 formats)
    $numbers = $existingTags | ForEach-Object {
        if ($_ -match "$Version-$Type\.?(\d+)$") {
            [int]$Matches[1]
        }
    } | Where-Object { $_ -ne $null }

    if (-not $numbers) {
        Write-Verbose "Get-NextPreReleaseNumber: Could not parse existing tags. Starting at 1."
        return 1
    }

    $maxNumber = ($numbers | Measure-Object -Maximum).Maximum
    $nextNumber = $maxNumber + 1

    Write-Verbose "Get-NextPreReleaseNumber: Found max $Type number $maxNumber. Next is $nextNumber."
    
    return $nextNumber
}
