# TestModule.psm1
# Placeholder module for ReleaseFlow testing

function Get-TestVersion {
    return '0.0.0'
}

Export-ModuleMember -Function Get-TestVersion


function Get-FirstFeature {
    <#
    .SYNOPSIS
        First feature of v1.0.0
    #>
    return 'Hello from Feature 1!'
}

Export-ModuleMember -Function Get-FirstFeature


function Get-SecondFeature {
    return 'Hello from Feature 2!'
}

Export-ModuleMember -Function Get-SecondFeature


function Get-SecondFeature { return 'Feature 2!' }
function Test-AlphaIncrement { 'Alpha increment test' }
function Test-AlphaIncrement2 { 'Second alpha test' }
