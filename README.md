# PowerShell Module for Automating License Entitlement between VCF Business Service Console & VCF Operations

![](icon.png)

## Summary

PowerShell Module to automate license entitlement between [VCF Business Service Console APIs](https://developer.broadcom.com/xapis/vcf-business-services-console-apis/latest/) & [VCF Operations Licensing API](https://williamlam.com/2025/09/automating-vcf-9-0-operations-license-registration-import-for-air-gapped-environments.html). More details can be found in this blog post [here](https://williamlam.com/2025/12/automating-license-entitlement-workflows-between-vcf-operations-vcf-business-service-console-bsc.html).

## Prerequisites
* PowerShell Core 7.x or later
* VCF Business Service Console OAuth API Client ID/Secret
* VCF Operations 9.x

## Functions

* Connect-VcfBsc
* Connect-VcfOperations
* Download-VcfBscLicense
* Download-VcfOperationsRegistrationFile
* Download-VcfOperationsUsageFile
* Get-VcfBscCLicense
* Get-VcfOperationsEntitlements
* Get-VcfOperationsVcenters
* Import-VcfOperationsLicenseFile
* Import-VcfOperationsUsageFile
* Register-VcfOperations
* Set-VcfBscCLicense
* Set-VcfOperationsLicenseAssignment