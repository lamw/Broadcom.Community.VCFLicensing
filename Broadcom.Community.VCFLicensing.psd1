#
# Module manifest for module 'Broadcom.Community.VCFLicensing'
#
# Generated on: 12/17/25
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'Broadcom.Community.VCFLicensing.psm1'

# Version number of this module.
ModuleVersion = '1.0.1'

# Supported PSEditions
# CompatiblePSEditions = @()

# ID used to uniquely identify this module
GUID = '76c6b875-1902-4334-8e04-c77e664564cd'

# Author of this module
Author = 'William Lam'

# Company or vendor of this module
CompanyName = 'Broadcom'

# Copyright statement for this module
Copyright = '(c) 2025 Broadcom. All rights reserved.'

# Description of the functionality provided by this module
Description = 'PowerShell Module for automating license entitlement between VCF Business Service Console and VCF Operations'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '7.0'

RequiredModules = @()

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = 'Connect-VcfBsc','Register-VcfOperations','Get-VcfBscCLicense','Set-VcfBscCLicense','Download-VcfBscLicense','Connect-VcfOperations','Download-VcfOperationsRegistrationFile','Import-VcfOperationsLicenseFile','Download-VcfOperationsUsageFile','Import-VcfOperationsUsageFile','Get-VcfOperationsEntitlements','Get-VcfOperationsVcenters','Set-VcfOperationsLicenseAssignment'

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = '*'

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @()

# DSC resources to export from this module
# DscResourcesToExport = @()

# List of all modules packaged with this module
ModuleList = @()

# List of all files packaged with this module
# FileList = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @('Broadcom','VCF')

        # A URL to the license for this module.
        # LicenseUri = ''

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/lamw/Broadcom.Community.VCFLicensing'

        # A URL to an icon representing this module.
        IconUri = 'https://github.com/lamw/Broadcom.Community.VCFLicensing/raw/master/icon.png'

        # ReleaseNotes of this module
        # ReleaseNotes = ''

    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}