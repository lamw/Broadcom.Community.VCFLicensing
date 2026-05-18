# PowerShell Module for Automating License Entitlement between VCF Business Service Console & VCF Operations

![](icon.png)

## Summary

PowerShell Module to automate license entitlement between [VCF Business Service Console APIs](https://developer.broadcom.com/xapis/vcf-business-services-console-apis/latest/) & [VCF Operations Licensing API](https://williamlam.com/2025/09/automating-vcf-9-0-operations-license-registration-import-for-air-gapped-environments.html).

For detail usage, please refer to these blog posts:
* [VCF 9.1.x](https://williamlam.com/2026/05/vcf-9-1-automating-new-license-entitlement-workflow-between-vcf-operations-vcf-business-service-console-bsc.html)
* [VCF 9.0.x](https://williamlam.com/2025/12/automating-license-entitlement-workflows-between-vcf-operations-vcf-business-service-console-bsc.html)

## Prerequisites
* PowerShell Core 7.x or later
* VCF Business Service Console OAuth API Client ID/Secret
* VCF Operations 9.x

## Functions

* Connect-VcfBsc
* Connect-VcfOperations
* Download-VcfBscLicense
* Download-VcfBscVerificationFile (**🆕 for VCF 9.1**)
* Download-VcfOperationsRegistrationFile
* Download-VcfOperationsUsageFile
* Get-VcfBscCLicense
* Get-VcfOperationsEntitlements
* Get-VcfOperationsVcenters
* Get-VcfOperationsVcenters2 (**🆕 for VCF 9.1**)
* Import-VcfOperationsConfirmationFile (**🆕 for VCF 9.1**)
* Import-VcfOperationsLicenseFile
* Import-VcfOperationsUsageFile
* Import-VcfOperationsVerificationFile (**🆕 for VCF 9.1**)
* Register-VcfOperations
* Register-VcfOperations2 (**🆕 for VCF 9.1**)
* Set-VcfBscCLicense
* Set-VcfBscLicense2 (**🆕 for VCF 9.1**)
* Set-VcfOperationsLicenseAssignment
* Set-VcfOperationsLicenseAssignment2 (**🆕 for VCF 9.1**)
* Upload-VcfBscConfirmationFile (**🆕 for VCF 9.1**)