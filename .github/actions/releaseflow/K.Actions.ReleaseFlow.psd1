@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'K.Actions.ReleaseFlow.psm1'

    # Version number of this module.
    ModuleVersion = '1.2.3'

    # ID used to uniquely identify this module
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

    # Author of this module
    Author            = 'GrexyLoco'

    # Company or vendor of this module
    CompanyName       = 'GrexyLoco'

    # Copyright statement for this module
    Copyright         = '(c) 2026 GrexyLoco. All rights reserved.'

    # Description of the functionality provided by this module
    Description       = 'GitHub Action for automated release orchestration with guardrails, backflow PRs, and semantic versioning. Works with K.PSGallery.Smartagr for tagging.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.4'

    # Supported PSEditions
    CompatiblePSEditions = @('Core')

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @()

    # Functions to export from this module
    FunctionsToExport = @(
        'New-Release'
        'New-ReleaseTrain'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport   = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData       = @{
        PSData = @{
            # Tags applied to this module for discoverability
            Tags         = @(
                'GitHub'
                'Actions'
                'Release'
                'SemVer'
                'SemanticVersioning'
                'CI'
                'CD'
                'Automation'
                'Backflow'
                'Guardrails'
            )

            # A URL to the license for this module.
            LicenseUri   = 'https://github.com/GrexyLoco/K.Actions.ReleaseFlow/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/GrexyLoco/K.Actions.ReleaseFlow'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = 'Initial release - Release orchestration for GitHub Actions'

            # Prerelease string of this module
            # # Flag to indicate whether the module requires explicit user acceptance
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        }
    }
}
