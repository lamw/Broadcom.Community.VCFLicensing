# Author: William Lam
# Description: PowerShell Module to automate between Broadcom VCF Business Service Console (BSC) and VCF Operations 9.x

# --- Helper Functions for Part Construction ---
Function Get-MultipartFormDataPart {
    param (
        [string] $Name,
        [string] $Value,
        [string] $Boundary
    )
    # The string must be fully formatted before converting to bytes
    $part = ""
    $part += "--$Boundary`r`n"
    $part += "Content-Disposition: form-data; name=`"$Name`"`r`n"
    $part += "`r`n"
    $part += "$Value`r`n"

    # Using ASCII for headers and boundaries is standard/safer than UTF8
    return [System.Text.Encoding]::ASCII.GetBytes($part)
}

Function Get-MultipartFilePart {
    param (
        [string] $Name,
        [string] $FilePath,
        [string] $Boundary
    )

    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $contentBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $contentType = "application/octet-stream"

    $partHeader = ""
    # Add an extra CRLF before the boundary if it's the second part
    $partHeader += "`r`n--$Boundary`r`n"
    $partHeader += "Content-Disposition: form-data; name=`"$Name`"; filename=`"$fileName`"`r`n"
    $partHeader += "Content-Type: $contentType`r`n"
    $partHeader += "`r`n" # Blank line separates headers from content

    # Convert header parts to ASCII bytes
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($partHeader)
    $trailerBytes = [System.Text.Encoding]::ASCII.GetBytes("`r`n") # CRLF after file content

    # Combine: Header Bytes + File Content Bytes + Trailer Bytes
    $combined = New-Object System.Byte[] ($headerBytes.Length + $contentBytes.Length + $trailerBytes.Length)
    [Array]::Copy($headerBytes, 0, $combined, 0, $headerBytes.Length)
    [Array]::Copy($contentBytes, 0, $combined, $headerBytes.Length, $contentBytes.Length)
    [Array]::Copy($trailerBytes, 0, $combined, $headerBytes.Length + $contentBytes.Length, $trailerBytes.Length)

    return $combined
}
# --- End Helper Functions ---

Function Invoke-MultipartUpload {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Uri,

        [Parameter(Mandatory=$true)]
        [Hashtable]$Headers,

        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$false)]
        [string]$NameValue = $null,

        # Optional text field required by license-mgmt V2 registration (e.g. MANUAL)
        [Parameter(Mandatory=$false)]
        [string]$RegistrationMode = $null,

        # multipart form-data name for the binary part (default file; e.g. challenge for verification upload)
        [Parameter(Mandatory=$false)]
        [string]$FileFieldName = 'file',

        [Parameter(Mandatory=$false)]
        [switch]$SkipCertCheck,

        # Return 4xx/5xx responses instead of throwing (PS 6+: Invoke-WebRequest -SkipHttpErrorCheck; PS 5.1: WebException catch)
        [Parameter(Mandatory=$false)]
        [switch]$SkipHttpErrorCheck,

        [Parameter(Mandatory=$false)]
        [boolean]$Troubleshoot=$false
    )

    $NameFieldName = "name"
    $RegistrationModeField = "registration_mode"

    # Input validation
    if (-not (Test-Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        return
    }

    # 1. --- Generate Unique Boundary ---
    $Boundary = "----PowerShellBoundary$([Guid]::NewGuid().ToString().Replace('-', ''))"

    # 2. --- Define Content-Type Header ---
    $ContentType = "multipart/form-data; boundary=$Boundary"
    $Headers["Content-Type"] = $ContentType

    # --- DEBUG INFO ---
    if($Troubleshoot) {
        Write-Host "--- DEBUG INFO ---"
        Write-Host "URI: $Uri"
        Write-Host "Generated Boundary: $Boundary"
        Write-Host "Content-Type Header: $ContentType"
        Write-Host "File Path: $FilePath"
        Write-Host "Name Value: $(if ($NameValue) {"$NameValue (Included)"} else {"N/A (Skipped)"})"
        Write-Host "Registration Mode: $(if ($RegistrationMode) {"$RegistrationMode (Included)"} else {"N/A (Skipped)"})"
        Write-Host "File form-data name: $FileFieldName"
        Write-Host "SkipCertificateCheck: $SkipCertCheck"
        Write-Host "SkipHttpErrorCheck: $SkipHttpErrorCheck"
        Write-Host "------------------"
    }

    # 3. --- Build the full body as a stream of bytes ---
    $bodyStream = New-Object System.IO.MemoryStream

    try {
        # A. Optional registration_mode (before name/file; matches browser multipart order)
        if ($RegistrationMode) {
            $regModeBytes = Get-MultipartFormDataPart -Name $RegistrationModeField -Value $RegistrationMode -Boundary $Boundary
            $bodyStream.Write($regModeBytes, 0, $regModeBytes.Length)
        }

        # B. Conditional: Add the "name" part (Text Field)
        if ($NameValue) {
            $nameBytes = Get-MultipartFormDataPart -Name $NameFieldName -Value $NameValue -Boundary $Boundary
            $bodyStream.Write($nameBytes, 0, $nameBytes.Length)
        }

        # C. Add the binary file part (form name from FileFieldName)
        $filePartBytes = @()
        if ($NameValue -or $RegistrationMode) {
            $filePartBytes = Get-MultipartFilePart -Name $FileFieldName -FilePath $FilePath -Boundary $Boundary
        } else {
            # Manual assembly for file-only upload (first part)
            $fileName = [System.IO.Path]::GetFileName($FilePath)
            $contentType = "application/octet-stream"

            $partHeader = ""
            $partHeader += "--$Boundary`r`n"
            $partHeader += "Content-Disposition: form-data; name=`"$FileFieldName`"; filename=`"$fileName`"`r`n"
            $partHeader += "Content-Type: $contentType`r`n"
            $partHeader += "`r`n" # Blank line separates headers from content

            $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($partHeader)
            $contentBytes = [System.IO.File]::ReadAllBytes($FilePath)
            $trailerBytes = [System.Text.Encoding]::ASCII.GetBytes("`r`n") # CRLF after file content

            $combined = New-Object System.Byte[] ($headerBytes.Length + $contentBytes.Length + $trailerBytes.Length)
            [Array]::Copy($headerBytes, 0, $combined, 0, $headerBytes.Length)
            [Array]::Copy($contentBytes, 0, $combined, $headerBytes.Length, $contentBytes.Length)
            [Array]::Copy($trailerBytes, 0, $combined, $headerBytes.Length + $contentBytes.Length, $trailerBytes.Length)

            $filePartBytes = $combined
        }

        $bodyStream.Write($filePartBytes, 0, $filePartBytes.Length)

        # D. Add the closing boundary
        $closing = "--$Boundary--`r`n"
        $closingBytes = [System.Text.Encoding]::ASCII.GetBytes($closing)
        $bodyStream.Write($closingBytes, 0, $closingBytes.Length)

        # Reset stream position to the beginning for reading by Invoke-WebRequest
        $bodyStream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null

        # 4. --- Execute the Request ---
        # (Splatting logic unchanged)
        $IWRParams = @{
            Uri = $Uri
            Method = 'Post'
            Headers = $Headers
            Body = $bodyStream
        }
        if ($SkipCertCheck) {
            $IWRParams.Add('SkipCertificateCheck', $true)
        }

        $Response = $null
        if ($SkipHttpErrorCheck) {
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                $IWRParams['SkipHttpErrorCheck'] = $true
                $Response = Invoke-WebRequest @IWRParams
            }
            else {
                try {
                    $Response = Invoke-WebRequest @IWRParams
                }
                catch {
                    $ex = $_.Exception
                    if ($ex.Response) {
                        $r = $ex.Response
                        try {
                            $code = [int]$r.StatusCode
                            $sr = New-Object System.IO.StreamReader($r.GetResponseStream())
                            $bodyText = $sr.ReadToEnd()
                            $Response = [pscustomobject]@{ StatusCode = $code; Content = $bodyText }
                        }
                        catch {
                            throw
                        }
                    }
                    else {
                        throw
                    }
                }
            }
        }
        else {
            $Response = Invoke-WebRequest @IWRParams
        }

        if ($Response.StatusCode -ge 200 -and $Response.StatusCode -lt 300) {
            Write-Host "Upload successful. HTTP Status Code: $($Response.StatusCode)"
        }
        return $Response
    }
    catch {
        Write-Error "Upload failed: $($_.Exception.Message)"
        if ($_.Exception.Response -is [System.Net.HttpWebResponse]) {
            $ErrorResponse = $_.Exception.Response
            $StreamReader = New-Object System.IO.StreamReader($ErrorResponse.GetResponseStream())
            $ErrorBody = $StreamReader.ReadToEnd()
            Write-Error "Internal Server Error (500) Body:"
            Write-Error $ErrorBody
        }
        return $_
    }
    finally {
        if ($bodyStream) {
            $bodyStream.Dispose()
        }
    }
}

Function Connect-VcfBsc {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Connect to the VCF Business Service Console
        .DESCRIPTION
            This cmdlet creates $global:bscConnection object containing valid access token
        .PARAMETER ClientId
            The OAuth Client ID generated from VCF Business Service Console UI
        .PARAMETER SecretId
            The OAuth Secret ID generated from VCF Business Service Console UI

        .EXAMPLE
            Connect-VcfBsc -ClientID $ClientId -SecretId $SecretId
    #>
    Param (
        [Parameter(Mandatory=$true)][String]$ClientId,
        [Parameter(Mandatory=$true)][String]$SecretId,
        [Switch]$Troubleshoot
    )

    $body = @{
        "grant_type" = "client_credentials"
        "client_id" = $ClientId
        "client_secret" = $SecretId
    }

    $uri = "https://eapi.broadcom.com/vcf/generateToken"
    $method = "POST"

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
        Write-Host -ForegroundColor cyan "[DEBUG]`n$($body | Out-String)`n"
    }

    try {
        $requests = Invoke-WebRequest -Uri $uri -Method $method -Headers @{"Content-Type" = "application/x-www-form-urlencoded"} -Body $body
    } catch {
        Write-Error "Error in requesting Access Token"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if($requests.StatusCode -eq 200) {
        $accessToken=($requests.Content | ConvertFrom-Json).access_token

        $headers = @{
            "Authorization" = "Bearer $accessToken"
        }

        $global:bscConnection = new-object PSObject -Property @{
            'headers' = $headers
        }

        $global:bscConnection | Out-Null
    } else {
        Write-Host "Something went wrong with auth"
    }
}

Function Register-VcfOperations {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Register VCF Operations 9.0.x instance given a registration file
        .DESCRIPTION
            This cmdlet register VCF Operations instance given a registration file
        .PARAMETER TenantId
            The BSC Tenant ID (retrieved through VCF BSC UI)
        .PARAMETER RegistrationFile
            The filename of the exported registration file from VCF Operations
        .PARAMETER Name
            The human friendly label to use for the registered VCF Operations in VCF BSC
        .PARAMETER RegistrationMode
            Multipart field registration_mode (e.g. MANUAL). Use empty string to omit for legacy APIs.

        .EXAMPLE
            $VCF_OPERATIONS_REGISTRATION_LABEL="vcf01.vcf.lab"
            $VCF_OPERATIONS_REGISTRATION_FILE="Registration-vcf01.vcf.lab-2025-12-16T15_03_43Z.data"

            Register-VcfOperations -TenantId $VCF_BSC_TENANT_ID -RegistrationFile $VCF_OPERATIONS_REGISTRATION_FILE -Name $VCF_OPERATIONS_REGISTRATION_LABEL
    #>
    Param (
        [Parameter(Mandatory=$true)][String]$TenantId,
        [Parameter(Mandatory=$true)][String]$RegistrationFile,
        [Parameter(Mandatory=$true)][String]$Name,
        [Parameter(Mandatory=$false)][String]$RegistrationMode = 'MANUAL',
        [Switch]$Troubleshoot
    )

    $headers = @{
        "Authorization" = $global:bscConnection.Headers.Authorization
    }

    $uri = "https://eapi.broadcom.com/vcf/license-mgmt/api/v1/tenants/${TenantId}/appliance-registration/upload"

    Write-Host "Uploading VCF Operations (${VCF_OPERATIONS_REGISTRATION_LABEL}) Registration File to Broadcom Business Service Console ..."
    try {
        if($Troubleshoot) {
            $requests = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $RegistrationFile -NameValue $Name -RegistrationMode $RegistrationMode -Troubleshoot $true
        } else {
            $requests = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $RegistrationFile -NameValue $Name -RegistrationMode $RegistrationMode
        }
    } catch {
        Write-Error "Error in registering VCF Operations"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if($requests.StatusCode -eq 200) {
        ($requests.Content | ConvertFrom-Json)
    }
}

Function Register-VcfOperations2 {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Register VCF Operations 9.1 instance given a registration file
        .DESCRIPTION
            This cmdlet register VCF Operations 9.1 instance given a registration file. If the API
            returns status DELETED, the same registration file is posted again to the v2 asset
            activate endpoint (multipart file only) and that JSON response is returned.
        .PARAMETER TenantId
            The BSC Tenant ID (retrieved through VCF BSC UI)
        .PARAMETER RegistrationFile
            The filename of the exported registration file from VCF Operations
        .PARAMETER Name
            The human friendly label to use for the registered VCF Operations in VCF BSC
        .PARAMETER RegistrationMode
            Multipart field registration_mode; defaults to MANUAL. Use empty string to omit.

        .EXAMPLE
            $VCF_OPERATIONS_REGISTRATION_LABEL="vcf01.vcf.lab"
            $VCF_OPERATIONS_REGISTRATION_FILE="Registration-vcf01.vcf.lab-2025-12-16T15_03_43Z.data"

            Register-VcfOperations2 -TenantId $VCF_BSC_TENANT_ID -RegistrationFile $VCF_OPERATIONS_REGISTRATION_FILE -Name $VCF_OPERATIONS_REGISTRATION_LABEL
    #>
    Param (
        [Parameter(Mandatory=$true)][String]$TenantId,
        [Parameter(Mandatory=$true)][String]$RegistrationFile,
        [Parameter(Mandatory=$true)][String]$Name,
        [Parameter(Mandatory=$false)][String]$RegistrationMode = 'MANUAL',
        [Switch]$Troubleshoot
    )

    $headers = @{
        "Authorization" = $global:bscConnection.Headers.Authorization
    }

    $uri = "https://eapi.broadcom.com/vcf/license-mgmt/api/v2/tenants/${TenantId}/registrations"

    Write-Host "Uploading VCF Operations (${VCF_OPERATIONS_REGISTRATION_LABEL}) Registration File to Broadcom Business Service Console ..."
    try {
        if($Troubleshoot) {
            $requests = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $RegistrationFile -NameValue $Name -RegistrationMode $RegistrationMode -Troubleshoot $true
        } else {
            $requests = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $RegistrationFile -NameValue $Name -RegistrationMode $RegistrationMode
        }
    } catch {
        Write-Error "Error in registering VCF Operations"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if($requests.StatusCode -eq 200) {
        $result = $requests.Content | ConvertFrom-Json
        if ($result.status -eq 'DELETED' -and $result.asset_id) {
            $activateUri = "https://eapi.broadcom.com/vcf/license-mgmt/api/v2/tenants/${TenantId}/assets/$($result.asset_id)?activate=true"
            Write-Host "Registration returned status DELETED; re-activating asset $($result.asset_id) ..."
            $headersActivate = @{
                "Authorization" = $global:bscConnection.Headers.Authorization
            }
            try {
                if($Troubleshoot) {
                    $activateReq = Invoke-MultipartUpload -Uri $activateUri -Headers $headersActivate -FilePath $RegistrationFile -Troubleshoot $true
                } else {
                    $activateReq = Invoke-MultipartUpload -Uri $activateUri -Headers $headersActivate -FilePath $RegistrationFile
                }
            } catch {
                Write-Error "Error in re-activating VCF Operations asset"
                Write-Error "`n($_.Exception.Message)`n"
                break
            }
            if ($activateReq.StatusCode -eq 200) {
                ($activateReq.Content | ConvertFrom-Json) | Select-Object -Property * -ExcludeProperty id | Out-Host
                return $result.asset_id
            } else {
                $result | Select-Object -Property * -ExcludeProperty id | Out-Host
                return $result.asset_id
            }
        } else {
            $result | Select-Object -Property * -ExcludeProperty id | Out-Host
            return $result.asset_id
        }
    }
}

Function Download-VcfBscVerificationFile  {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Download generated verification file from VCF Business Service Console
        .DESCRIPTION
            This cmdlet downloads generated verification file from VCF Business Service Console
        .PARAMETER TenantId
            The BSC Tenant ID (retrieved through VCF BSC UI)
        .PARAMETER VcfOperationsId
            The registered VCF Operations Id
        .PARAMETER VerificationFile
            The filename where the verification file will be saved

        .EXAMPLE
            $VCF_VERIFICATION_FILE="verification-flt-ops01a.rainpole.io___2026-04-06_18-03-00-948Z.verification"

            Download-VcfBscVerificationFile -TenantId $VCF_BSC_TENANT_ID -VcfOperationsId $VCF_BSC_OPERATIONS_REGISTRATION_ID -VerificationFile $VCF_VERIFICATION_FILE
    #>
    Param (
        [Parameter(Mandatory=$true)][String]$TenantId,
        [Parameter(Mandatory=$true)][String]$VcfOperationsId,
        [Parameter(Mandatory=$true)][String]$VerificationFile,
        [Switch]$Troubleshoot
    )

    $headers = @{
        "Authorization" = $global:bscConnection.Headers.Authorization
        "Content-Type"="application/json"
        "Accept"="application/json"
    }

    $uri = "https://eapi.broadcom.com/vcf/license-mgmt/api/v1/tenants/${TenantId}/assets/${VcfOperationsId}/child-asset-registration/challenges/download"
    $method = "GET"

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
    }

    try {
        Write-Host "Downloading Verification file $VerificationFile ...`n"
        $results = Invoke-WebRequest -Method $method -Uri $uri -Headers $headers -OutFile $VerificationFile

    } catch {
        Write-Error "Error in downloading BSC Verification File"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }
}

Function Upload-VcfBscConfirmationFile {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Upload the confirmation file from VCF Operations to Broadcom Business Service Console
        .DESCRIPTION
            After Import-VcfOperationsVerificationFile, VCF Operations returns a confirmation payload
            (e.g. *.confirmation). That file must be posted for challenges/upload with multipart
            field name "file" — not to the VCF Operations /challenge endpoint.
        .PARAMETER TenantId
            The BSC Tenant ID (retrieved through VCF BSC UI)
        .PARAMETER VcfOperationsId
            The registered VCF Operations / asset Id (same as used for Download-VcfBscVerificationFile)
        .PARAMETER ConfirmationFile
            Path to the confirmation file saved from Download-VcfOperationsConfirmationFile
        .PARAMETER Troubleshoot
            Emit multipart debug details

        .EXAMPLE
            Upload-VcfBscConfirmationFile -TenantId $VCF_BSC_TENANT_ID -VcfOperationsId $VCF_BSC_OPERATIONS_REGISTRATION_ID -ConfirmationFile $VCF_CONFIRMATION_FILE
    #>
    Param (
        [Parameter(Mandatory=$true)][String]$TenantId,
        [Parameter(Mandatory=$true)][String]$VcfOperationsId,
        [Parameter(Mandatory=$true)][String]$ConfirmationFile,
        [Switch]$Troubleshoot
    )

    $headers = @{
        "Authorization" = $global:bscConnection.Headers.Authorization
        "Accept" = "application/json"
    }

    $uri = "https://eapi.broadcom.com/vcf/license-mgmt/api/v1/tenants/${TenantId}/assets/${VcfOperationsId}/child-asset-registration/challenges/upload"

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - POST`n$uri`n"
    }

    try {
        Write-Host "Uploading confirmation file ($ConfirmationFile) to Broadcom Business Service Console ...`n"
        if($Troubleshoot) {
            $requests = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $ConfirmationFile -Troubleshoot $true
        } else {
            $requests = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $ConfirmationFile
        }
    } catch {
        Write-Error "Error uploading confirmation file to BSC"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if ($requests.StatusCode -eq 200) {
        ($requests.Content | ConvertFrom-Json)
    }
}

Function Get-VcfBscLicense {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Returns the list of licenses from VCF Business Service Console
        .DESCRIPTION
            This cmdlet returns the list of licenses from VCF Business Service Console
        .PARAMETER TenantId
            The BSC Tenant ID (retrieved through VCF BSC UI)
        .PARAMETER Name
            The name of the license label to filter results

        .EXAMPLE
            Get-VcfBscLicense -TenantId $VCF_BSC_TENANT_ID

            $VCF_LICENSE_NAME="wlam-vcf"
            Get-VcfBscLicense -TenantId $VCF_BSC_TENANT_ID -Name $VCF_LICENSE_NAME
    #>
    Param (
        [Parameter(Mandatory=$true)][String]$TenantId,
        [Parameter(Mandatory=$false)][String]$Name,
        [Switch]$Troubleshoot
    )

    $headers = @{
        "Authorization" = $global:bscConnection.Headers.Authorization
        "Content-Type"="application/json"
        "Accept"="application/json"
    }

    $uri = "https://eapi.broadcom.com/vcf/license-mgmt/api/v1/tenants/${TenantId}/allocations/search"
    $method = "POST"

    <# TODO Look into server side filtering
    $payload = [ordered]@{
        "filters" = @(
            [ordered]@{
                "key" = "NAME"
                "operator" = "EQUALS"
                "value" = $Name
            }
        )
    }

    $body = $payload | ConvertTo-Json
    #>

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
        Write-Host -ForegroundColor cyan "[DEBUG]`n$($body | Out-String)`n"
    }

    try {
        $results = Invoke-WebRequest -Method $method -Uri $uri -Headers $headers

    } catch {
        Write-Error "Error in retrieving BSC License"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if($results.StatusCode -eq 200) {
        $licenses = ($results.Content | ConvertFrom-Json).results

        if ($PSBoundParameters.ContainsKey("Name")){
            $licenses = $licenses | where {$_.name -eq $Name}
        }

        return $licenses | select id, name, quantity, status, product
    }
}

Function Set-VcfBscLicense {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Associate or Disassociate license to registered VCF Operations instance in VCF Business Service Console
        .DESCRIPTION
            This cmdlet associates or disassociates license to registered VCF Operations instance in VCF Business Service Console
        .PARAMETER TenantId
            The BSC Tenant ID (retrieved through VCF BSC UI)
        .PARAMETER VcfOperationsId
            The Id of the registered VCF Operations (returned from Register-VcfOperations)
        .PARAMETER LicenseIds
            List of license IDs (returned from Get-VcfBscCLicense)
        .PARAMETER Operation
            Associate or Disassociate

        .EXAMPLE
            $VCF_BSC_OPERATIONS_REGISTRATION_ID="f8d3966c-9a82-3cf6-e797-2392b311ed23"
            $VCF_BSC_LICENSE_IDS=@("efaa38b7-08ac-452f-929b-d30f6d37fba5","fc711690-f8d3-4209-a06e-529c39979251")

            Set-VcfBscLicense -TenantId $VCF_BSC_TENANT_ID -VcfOperationsId $VCF_BSC_OPERATIONS_REGISTRATION_ID -LicenseIds $VCF_BSC_LICENSE_IDS -Operation Associate

    #>
    Param (
        [Parameter(Mandatory=$true)][String]$TenantId,
        [Parameter(Mandatory=$true)][String]$VcfOperationsId,
        [Parameter(Mandatory=$true)][String[]]$LicenseIds,
        [Parameter(Mandatory=$true)][ValidateSet("Associate","Dissociate")]$Operation,
        [Switch]$Troubleshoot
    )

    $headers = @{
        "Authorization" = $global:bscConnection.Headers.Authorization
        "Content-Type"="application/json"
        "Accept"="application/json"
    }

    $uri = "https://eapi.broadcom.com/vcf/license-mgmt/api/v1/tenants/${TenantId}/licenses"
    $method = "POST"

    if($Operation -eq "Associate") {
        $payload = [ordered]@{
            operation = "ASSOCIATE"
            license_associate_request = @{
                vcf_ops_id = $VcfOperationsId
                ids = @($LicenseIds)
            }
        }
    } else {
        $payload = [ordered]@{
            operation = "DISSOCIATE"
            license_dissociate_request = @{
                vcf_ops_id = $VcfOperationsId
                ids = @($LicenseIds)
            }
        }
    }

    $body = $payload | ConvertTo-Json

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
        Write-Host -ForegroundColor cyan "[DEBUG]`n$($body | Out-String)`n"
    }

    Write-Host "$Operation license(s) to VCF Operations Id: $VcfOperationsId ...`n"
    try {
        $results = Invoke-WebRequest -Method $method -Uri $uri -Headers $headers -Body $body
    } catch {
        Write-Error "Error in $operation BSC License"
        Write-Error "`n($_.Exception.Message)`n"
        $results
        break
    }

    if($results.StatusCode -eq 200) {
        return ($results.Content | ConvertFrom-Json).results | select id, name, quantity, status, product
    }
}

Function Set-VcfBscLicense2 {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Associate or Disassociate license to registered VCF Operations instance in VCF Business Service Console
        .DESCRIPTION
            This cmdlet associates or disassociates license to registered VCF Operations instance in VCF Business Service Console
        .PARAMETER TenantId
            The BSC Tenant ID (retrieved through VCF BSC UI)
        .PARAMETER LicenseServerId
            The Id of the license server (returned from Import-VcfOperationsConfirmationFile)
        .PARAMETER LicenseIds
            List of license IDs (returned from Get-VcfBscCLicense)
        .PARAMETER Operation
            Associate or Disassociate

        .EXAMPLE
            $VCF_LICENSE_SERVER_BSC_ID="077bf2c4-ddb3-4f2e-a593-a8451909e1b6"
            $VCF_BSC_LICENSE_IDS=@("4088324b-5809-41dd-83f2-e33d0ad8a758","bcc0b0a6-69ba-4f24-95ec-aaf4cf60a557)

            Set-VcfBscLicense2 -TenantId $VCF_BSC_TENANT_ID -LicenseServerId $VCF_LICENSE_SERVER_BSC_ID -LicenseIds $VCF_BSC_LICENSE_IDS -Operation Associate

    #>
    Param (
        [Parameter(Mandatory=$true)][String]$TenantId,
        [Parameter(Mandatory=$true)][String]$LicenseServerId,
        [Parameter(Mandatory=$true)][String[]]$LicenseIds,
        [Parameter(Mandatory=$true)][ValidateSet("Associate","Dissociate")]$Operation,
        [Switch]$Troubleshoot
    )

    $headers = @{
        "Authorization" = $global:bscConnection.Headers.Authorization
        "Content-Type"="application/json"
        "Accept"="application/json"
    }

    $uri = "https://eapi.broadcom.com/vcf/license-mgmt/api/v1/tenants/${TenantId}/assets/${LicenseServerId}/allocations"
    $method = "POST"

    if($Operation -eq "Associate") {
        $payload = [ordered]@{
            allocationIds = $LicenseIds
            action = "ASSOCIATE"
        }
    } else {
        $payload = [ordered]@{
            allocationIds = $LicenseIds
            action = "DISSOCIATE"
        }
    }

    $body = $payload | ConvertTo-Json

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
        Write-Host -ForegroundColor cyan "[DEBUG]`n$($body | Out-String)`n"
    }

    Write-Host "$Operation license(s) to License Server Id: $LicenseServerId ...`n"
    try {
        $results = Invoke-WebRequest -Method $method -Uri $uri -Headers $headers -Body $body
    } catch {
        Write-Error "Error in $operation BSC License"
        Write-Error "`n($_.Exception.Message)`n"
        $results
        break
    }

    if($results.StatusCode -eq 200) {
        return ($results.Content | ConvertFrom-Json).results | select id, name, quantity, status, product
    }
}

Function Download-VcfBscLicense  {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Download generated license from VCF Business Service Console
        .DESCRIPTION
            This cmdlet downloads generated license from VCF Business Service Console
        .PARAMETER TenantId
            The BSC Tenant ID (retrieved through VCF BSC UI)
        .PARAMETER VcfOperationsId
            The registered VCF Operations Id
        .PARAMETER LicenseFile
            The filename where the license file will be saved

        .EXAMPLE
            $VCF_LICENSE_FILE="vcf01.vcf.lab.lic"

            Download-VcfBscLicense -TenantId $VCF_BSC_TENANT_ID -VcfOperationsId $VCF_BSC_OPERATIONS_REGISTRATION_ID -LicenseFile $VCF_LICENSE_FILE
    #>
    Param (
        [Parameter(Mandatory=$true)][String]$TenantId,
        [Parameter(Mandatory=$true)][String]$VcfOperationsId,
        [Parameter(Mandatory=$true)][String]$LicenseFile,
        [Switch]$Troubleshoot
    )

    $headers = @{
        "Authorization" = $global:bscConnection.Headers.Authorization
        "Content-Type"="application/json"
        "Accept"="application/json"
    }

    $uri = "https://eapi.broadcom.com/vcf/license-mgmt/api/v1/tenants/${TenantId}/vcf-ops/${VcfOperationsId}/licenses/download"
    $method = "GET"

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
    }

    try {
        Write-Host "Downloading license file $LicenseFile ...`n"
        $results = Invoke-WebRequest -Method $method -Uri $uri -Headers $headers -OutFile $LicenseFile

        return $LicenseFile

    } catch {
        Write-Error "Error in downloading BSC License"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }
}

Function Connect-VcfOperations {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Connect to VCF Operations
        .DESCRIPTION
            This cmdlet creates $global:vcfOpsConnection object containing valid access token
        .PARAMETER Fqdn
            IP Address/Hostname of VCF Operations
        .PARAMETER User
            The username to login to VCF Operations
        .PARAMETER Password
            The password to login to VCF Operations

        .EXAMPLE
            $VCF_OPERATIONS_HOSTNAME="vcf01.vcf.lab"
            $VCF_OPERATIONS_USERNAME="admin"
            $VCF_OPERATIONS_PASSWORD=''

            Connect-VcfOperations -Fqdn $VCF_OPERATIONS_HOSTNAME -User $VCF_OPERATIONS_USERNAME -Password $VCF_OPERATIONS_PASSWORD
    #>
    Param (
        [Parameter(Mandatory=$true)][String]$Fqdn,
        [Parameter(Mandatory=$true)][String]$User,
        [Parameter(Mandatory=$true)][String]$Password,
        [Switch]$Troubleshoot
    )

    $payload = @{
        username = $User
        password = $Password
        authSource = "local"
    }

    $body = $payload | ConvertTo-Json

    $uri = "https://${Fqdn}/suite-api/api/auth/token/acquire"
    $method = "POST"

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
        Write-Host -ForegroundColor cyan "[DEBUG]`n$($body | Out-String)`n"
    }

    try {
        $requests = Invoke-WebRequest -Uri $uri -Method $method -Headers @{"Content-Type" = "application/json";"Accept" = "application/json"} -Body $body -SkipCertificateCheck
    } catch {
        Write-Error "Error in requesting Access Token"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if($requests.StatusCode -eq 200) {
        $accessToken=($requests.Content | ConvertFrom-Json).token

        $headers = @{
            "Authorization" = "OpsToken $accessToken"
            "Content-Type" = "application/json"
            "Accept" = "application/json"
            "X-Ops-API-use-unsupported" = "true"
        }

        $global:vcfOpsConnection = new-object PSObject -Property @{
            'Server' = $Fqdn
            'headers' = $headers
        }

        $global:vcfOpsConnection | Out-Null
    } else {
        Write-Host "Something went wrong with auth"
    }
}

Function Download-VcfOperationsRegistrationFile {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Download registration file from VCF Operations
        .DESCRIPTION
            This cmdlet downloads registration file from VCF Operations

        .EXAMPLE
            Download-VcfOperationsRegistrationFile
    #>
    Param (
        [Switch]$Troubleshoot
    )

    $uri = "https://$($global:vcfOpsConnection.server)/suite-api/internal/extension/vcf-license-cloud-integration/registration/offline/request"
    $method = "POST"

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
    }

    try {
        $requests = Invoke-WebRequest -Method $method -Uri $uri -Headers $global:vcfOpsConnection.headers -SkipCertificateCheck
    } catch {
        Write-Error "Error in downloading registration file"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if($requests.StatusCode -eq 200) {
        $result = ($requests.Content | ConvertFrom-Json)

        $RegistrationFile = $result.fileName
        $RegistrationData = $result.jwsEncodedData

        Write-Host "Successfully downloaded registration file $RegistrationFile`n"
        $RegistrationData | Out-File -FilePath $RegistrationFile

        return $RegistrationFile
    }
}

Function Import-VcfOperationsVerificationFile {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Import the BSC verification (*.verification) file into VCF Operations
        .DESCRIPTION
            Mirrors licensing_utils.import_verification_file_to_vcfops: POSTs the verification file to
            license-servers/challenge, then treats a 200 body as a
            confirmation JWT (plain text, not JSON) to ConfirmationOutFile.

            HTTP 400 with body containing "Invalid/Empty Challenge file" means the verification was already
            imported previously; a message is shown and the cmdlet returns without writing a file.

            Do not use the confirmation file (*.confirmation) from Download-VcfOperationsConfirmationFile
            here — that file must be uploaded to BSC with Upload-VcfBscConfirmationFile instead.
        .PARAMETER VerificationFile
            Path to the *.verification file from BSC (not *.confirmation)
        .PARAMETER FileFieldName
            Multipart form field name for the upload (default challenge).
        .PARAMETER ConfirmationOutFile
            Path to write the confirmation JWT. If omitted, defaults to
            confirmation-<VCF Ops FQDN>__<UTC timestamp>.confirmation in the same folder as the verification file
            (e.g. confirmation-flt-ops01a.rainpole.io__2026-04-06T21_09_01.257Z.confirmation).

        .EXAMPLE
            $VCF_VERIFICATION_FILE="verification-flt-ops01a.rainpole.io___2026-04-06_18-03-00-948Z.verification"

            Import-VcfOperationsVerificationFile -VerificationFile $VCF_VERIFICATION_FILE
    #>
    Param (
        [Parameter(Mandatory=$true)][String]$VerificationFile,
        [Parameter(Mandatory=$false)][String]$FileFieldName = 'challenge',
        [Parameter(Mandatory=$false)][String]$ConfirmationOutFile = $null,
        [Switch]$Troubleshoot
    )

    if ($VerificationFile -like '*.confirmation') {
        Write-Warning "This path looks like a confirmation file (*.confirmation). Import-VcfOperationsVerificationFile expects the BSC verification file (*.verification). To complete the handshake, use Upload-VcfBscConfirmationFile for the confirmation file."
    }

    if (-not $ConfirmationOutFile) {
        $vfDir = Split-Path -Parent $VerificationFile
        if ([string]::IsNullOrEmpty($vfDir)) { $vfDir = '.' }
        $hostPart = $global:vcfOpsConnection.server
        if ([string]::IsNullOrWhiteSpace($hostPart)) {
            $hostPart = 'vcf-operations'
        }
        $ts = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH_mm_ss.fff') + 'Z'
        $confirmName = "confirmation-${hostPart}__${ts}.confirmation"
        $ConfirmationOutFile = Join-Path $vfDir $confirmName
    }

    $uri = "https://$($global:vcfOpsConnection.server)/suite-api/internal/extension/vcf-license-cloud-integration/license-servers/challenge"
    $method = "POST"

    $headers = @{
        "Authorization" = $global:vcfOpsConnection.headers.authorization
        "X-Ops-API-use-unsupported" = "true"
        "Accept" = "application/json, text/plain, */*"
    }

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
    }

    try {
        Write-Host "Importing Verification File ($VerificationFile) to VCF Operations ...`n"
        if($Troubleshoot) {
            $results = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $VerificationFile -FileFieldName $FileFieldName -SkipCertCheck -SkipHttpErrorCheck -Troubleshoot $true
        } else {
            $results = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $VerificationFile -FileFieldName $FileFieldName -SkipCertCheck -SkipHttpErrorCheck -Troubleshoot $false
        }
    } catch {
        Write-Error "Error in importing verification file"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if ($results -is [System.Management.Automation.ErrorRecord]) {
        Write-Error "Verification import failed: $($results.Exception.Message)"
        break
    }

    if ($null -eq $results.StatusCode) {
        Write-Error "Verification import failed: no HTTP response."
        break
    }

    if ($results.StatusCode -eq 400 -and $results.Content -like '*Invalid/Empty Challenge file*') {
        Write-Host "Verification file was already imported in a previous attempt (Invalid/Empty Challenge file).`n"
        return
    }

    if ($results.StatusCode -ne 200) {
        Write-Error "Verification import failed: HTTP $($results.StatusCode). Response: $($results.Content)"
        break
    }

    $confirmationJwt = $results.Content.Trim()
    if ([string]::IsNullOrWhiteSpace($confirmationJwt)) {
        Write-Error "Verification import returned empty confirmation JWT."
        break
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($ConfirmationOutFile, $confirmationJwt, $utf8NoBom)
    Write-Host "Confirmation file saved to $ConfirmationOutFile`n"

    return $ConfirmationOutFile
}

Function Import-VcfOperationsConfirmationFile  {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Import generated confirmation file from VCF Operations into VCF Business Service Console
        .DESCRIPTION
            This cmdlet imports generated confirmation file from VCF Operations into VCF Business Service Console
        .PARAMETER TenantId
            The BSC Tenant ID (retrieved through VCF BSC UI)
        .PARAMETER ConfirmationFile
            The name of the confirmation file to import

        .EXAMPLE
            $VCF_OPERATIONS_CONFIRMATION_FILE="confirmation-flt-ops01a.rainpole.io___2026-04-06T21_09_01.257Z.confirmation"

            Import-VcfOperationsConfirmationFile -TenantId $VCF_BSC_TENANT_ID -VcfOperationsId $VCF_BSC_OPERATIONS_REGISTRATION_ID -ConfirmationFile $VCF_OPERATIONS_CONFIRMATION_FILE
    #>
    Param (
        [Parameter(Mandatory=$true)][String]$TenantId,
        [Parameter(Mandatory=$true)][String]$VcfOperationsId,
        [Parameter(Mandatory=$true)][String]$ConfirmationFile,
        [Switch]$Troubleshoot
    )

    $uri = "https://eapi.broadcom.com/vcf/license-mgmt/api/v1/tenants/${TenantId}/assets/${VcfOperationsId}/child-asset-registration/challenges/upload"
    $method = "POST"

    $headers = @{
        "Authorization" = $global:bscConnection.Headers.Authorization
        "Accept"        = "application/json"
    }

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
    }

    try {
        Write-Host "Uploading confirmation file ($ConfirmationFile) to Broadcom Business Service Console ...`n"
        if($Troubleshoot) {
            $results = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $ConfirmationFile -Troubleshoot $true
        } else {
            $results = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $ConfirmationFile
        }
    } catch {
        Write-Error "Error in importing confirmation file"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if ($results.StatusCode -eq 200) {
        ($results.Content | ConvertFrom-Json).child_assets | select asset_type, asset_id | Out-Host
        return (($results.Content | ConvertFrom-Json).child_assets).asset_id
    }
}

Function Import-VcfOperationsLicenseFile {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Import generated license file from VCF Business Service Console into VCF Operations
        .DESCRIPTION
            This cmdlet imports generated license file from VCF Business Service Console into VCF Operations
        .PARAMETER LicenseFile
            The name of the license file to import

        .EXAMPLE
            $VCF_LICENSE_FILE="/Users/wlam/Documents/cursor/ops-license/flt-ops01a.rainpole.io.lic"

            Import-VcfOperationsLicenseFile -LicenseFile $VCF_LICENSE_FILE
    #>
    Param (
        [Parameter(Mandatory=$true)][String]$LicenseFile,
        [Switch]$Troubleshoot
    )

    $uri = "https://$($global:vcfOpsConnection.server)/suite-api/internal/extension/vcf-license-cloud-integration/registration/offline/response"
    $method = "POST"

    $headers = @{
        "Authorization" = $global:vcfOpsConnection.headers.authorization
        "X-Ops-API-use-unsupported" = "true"
        "Accept" = "application/json, text/plain, */*"
    }

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
    }

    try {
        Write-Host "Importing License File ($LicenseFile) to VCF Operations ...`n"
        if($Troubleshoot) {
            $results = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $LicenseFile -SkipCertCheck -Troubleshoot $true
        } else {
            $results = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $LicenseFile -SkipCertCheck
        }
    } catch {
        Write-Error "Error in importing license file"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }
}

Function Download-VcfOperationsUsageFile {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Download usage file from VCF Operations
        .DESCRIPTION
            This cmdlet downloads usage file from VCF Operations

        .EXAMPLE
            Download-VcfOperationsUsageFile
    #>
    Param (
        [Switch]$Troubleshoot
    )

    # Get the current date/time as a DateTimeOffset object
    $NowOffset = [DateTimeOffset]::Now

    # STARTDATE: Tomorrow's date in Unix milliseconds
    $StartTimeMilliseconds = $NowOffset.AddDays(1).ToUnixTimeMilliseconds()

    # ENDDATE: One month from now in Unix milliseconds
    $EndTimeMilliseconds = $NowOffset.AddMonths(1).ToUnixTimeMilliseconds()

    $uri = "https://$($global:vcfOpsConnection.server)/suite-api/internal/extension/vcf-license-cloud-integration/usage/offline/report?startDate=${StartTimeMilliseconds}&endDate=${EndTimeMilliseconds}"
    $method = "POST"

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
    }

    try {
        Write-Host "Downloading Usage File ..."
        $requests = Invoke-WebRequest -Method $method -Uri $uri -Headers $global:vcfOpsConnection.headers -SkipCertificateCheck
    } catch {
        Write-Error "Error in downloading usage file"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if($requests.StatusCode -eq 200) {
        $result = ($requests.Content | ConvertFrom-Json)

        $UsageFile = $result.fileName.Replace(" ", "")
        $UsageData = $result.gzipJwsEncodedData

        Write-Host "Successfully downloaded usage file $UsageFile`n"
        $ContentBytes = [System.Convert]::FromBase64String($UsageData)
        [System.IO.File]::WriteAllBytes($UsageFile, $ContentBytes)
    }
}

Function Import-VcfOperationsUsageFile  {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Import generated usage file from VCF Operations into VCF Business Service Console
        .DESCRIPTION
            This cmdlet imports generated usage file from VCF Operations into VCF Business Service Console
        .PARAMETER TenantId
            The BSC Tenant ID (retrieved through VCF BSC UI)
        .PARAMETER UsageFile
            The name of the usage file to import

        .EXAMPLE
            $VCF_OPERATIONS_USAGE_FILE="Usage-vcf01.vcf.lab-2025-12-16T21_09_14Z.gzip"

            Import-VcfOperationsUsageFile -TenantId $VCF_BSC_TENANT_ID -UsageFile $VCF_OPERATIONS_USAGE_FILE
    #>
    Param (
        [Parameter(Mandatory=$true)][String]$TenantId,
        [Parameter(Mandatory=$true)][String]$UsageFile,
        [Switch]$Troubleshoot
    )

    $uri = "https://eapi.broadcom.com/vcf/license-usage/api/v1/tenants/${TenantId}/license-usage/upload"
    $method = "POST"

    $headers = @{
        "Authorization" = $global:bscConnection.Headers.Authorization
    }

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
    }

    try {
        Write-Host "Importing Usage File ($UsageFile) to VCF Operations ...`n"
        if($Troubleshoot) {
            $results = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $UsageFile -Troubleshoot $true
        } else {
            $results = Invoke-MultipartUpload -Uri $uri -Headers $headers -FilePath $UsageFile
        }
    } catch {
        Write-Error "Error in importing usage file"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }
}

Function Get-VcfOperationsEntitlements {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            List license entitlements that have been imported into VCF Operations
        .DESCRIPTION
            This cmdlet lists license entitlements that have been imported into VCF Operations

        .EXAMPLE
            Get-VcfOperationsEntitlements
    #>
    Param (
        [Switch]$Troubleshoot
    )

    $uri = "https://$($global:vcfOpsConnection.server)/suite-api/internal/extension/vcf-entitlement/entitlements/query"
    $method = "POST"

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
    }

    try {
        $requests = Invoke-WebRequest -Uri $uri -Method $method -Headers $global:vcfOpsConnection.headers -SkipCertificateCheck
    } catch {
        Write-Error "Error in retrieving license entitlements"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if($requests.StatusCode -eq 200) {
        $entitlements = (($requests.Content | ConvertFrom-Json).entitlementWithVcentersDetails).entitlementInfo

        $results = @()
        foreach($entitlement in $entitlements) {
            $tmp = [pscustomobject] [ordered]@{
                Name = $entitlement.name
                Id = $entitlement.id
                Product = $entitlement.productDisplayName
                Type = $entitlement.type
                UsedCapacity = $entitlement.usage
                AllocatedCapacity = $entitlement.capacity
            }
            $results+=$tmp
        }
    }
    return $results | Sort-Object -Property Name
}

Function Get-VcfOperationsVcenters {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            List vCenter Servers managed by VCF Operations
        .DESCRIPTION
            This cmdlet lists vCenter Servers managed by VCF Operations

        .EXAMPLE
            Get-VcfOperationsVcenters
    #>
    Param (
        [Switch]$Troubleshoot
    )

    $uri = "https://$($global:vcfOpsConnection.server)/suite-api/internal/extension/vcf-entitlement/vcenter-systems/query?page=0&pageSize=10"
    $method = "POST"

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
    }

    try {
        $requests = Invoke-WebRequest -Uri $uri -Method $method -Headers $global:vcfOpsConnection.headers -SkipCertificateCheck
    } catch {
        Write-Error "Error in retrieving license entitlements"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if($requests.StatusCode -eq 200) {
        $vcenters = ($requests.Content | ConvertFrom-Json).vcenterSystems

        $results = @()
        foreach($vcenter in $vcenters) {
            $tmp = [pscustomobject] [ordered]@{
                "vCenter" = $vcenter.vcenterInfo.host
                "Id" = $vcenter.vcenterInfo.id
                "ManagedByVCFInstance" = $vcenter.vcenterInfo.vcfAdapterName
                "PrimaryLicenseName" = $vcenter.entitlementName
                "PrimaryLicenseProduct" = $vcenter.entitlementProduct
                "PrimaryLicenseUsedCapacity" = $vcenter.licensedUsage
                "AddOnLicenseName" = $vcenter.addOns
                "FullyLicensed" = $vcenter.unlicensedUsage -eq 0 ? $true : $false
            }
            $results+=$tmp
        }
    }
    return $results | Sort-Object -Property Name
}

Function Get-VcfOperationsVcenters2 {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            List vCenter Servers managed by VCF Operations
        .DESCRIPTION
            This cmdlet lists vCenter Servers managed by VCF Operations

        .EXAMPLE
            Get-VcfOperationsVcenters2
    #>
    Param (
        [Switch]$Troubleshoot
    )

    $uri = "https://$($global:vcfOpsConnection.server)/suite-api/internal/extension/vcf-entitlement/vcenter-systems/query?page=0&pageSize=10"
    $method = "POST"

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
    }

    try {
        $requests = Invoke-WebRequest -Uri $uri -Method $method -Headers $global:vcfOpsConnection.headers -SkipCertificateCheck
    } catch {
        Write-Error "Error in retrieving license entitlements"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if($requests.StatusCode -eq 200) {
        $vcenters = ($requests.Content | ConvertFrom-Json).vcenterSystems

        $results = @()
        foreach($vcenter in $vcenters) {
            $licenseProductFamilies = $vcenters.productFamilies

            $licenseInfo = @()
            foreach($licenseProductFamily in $licenseProductFamilies) {
                $license = [pscustomobject] [ordered]@{
                    "Family" = $licenseProductFamily.productFamily
                    "Type" = $licenseProductFamily.type
                    "LicensedUsage" = $licenseProductFamily.licensedUsage
                    "UnlicensedUsage" = $licenseProductFamily.unlicensedUsage
                    "AllocationId" = $licenseProductFamily.licenses.allocationId
                    "LicenseName" = $licenseProductFamily.licenses.name
                }
                $licenseInfo+=$license
            }

            $tmp = [pscustomobject] [ordered]@{
                "vCenter" = $vcenter.host
                "Id" = $vcenter.id
                "ManagedByVCFInstance" = $vcenter.vcfAdapterName
                "Version" = $vcenter.version
                "Expiration" = $vcenter.expirationTimestamp
                "FullyLicensed" = $vcenter.state -eq "LICENSED"? $true : $false
                "Licenses" = $licenseInfo
            }
            $results+=$tmp
        }
    }
    return $results | Sort-Object -Property Name
}

Function Set-VcfOperationsLicenseAssignment2 {
    <#
        .NOTES
        ===========================================================================
        Created by:    William Lam
        Organization:  Broadcom
        Blog:          http://www.williamlam.com
        Twitter:       @lamw
        ===========================================================================
        .SYNOPSIS
            Assign license entitlement(s) to a vCenter Server managed by VCF Operations
        .DESCRIPTION
            This cmdlet assigns license entitlement(s) to a vCenter Server managed by VCF Operations
        .PARAMETER VcenterId
            vCenter Server ID (returned from Get-VcfOperationsVcenters)
        .PARAMETER LicenseIds

        .EXAMPLE
            $VCENTER_ID="abc6b4a7-2d61-4da0-9338-e1193148be7b"
            $VCF_LICENSE_ID="4088324b-5809-41dd-83f2-e33d0ad8a758"
            $VSAN_LICENSE_ID="bcc0b0a6-69ba-4f24-95ec-aaf4cf60a557"

            Set-VcfOperationsLicenseAssignment2 -VcenterId $VCENTER_ID -LicenseId $VCF_LICENSE_ID
            Set-VcfOperationsLicenseAssignment2 -VcenterId $VCENTER_ID -LicenseId $VSAN_LICENSE_ID
    #>
    Param (
        [Parameter(Mandatory=$true)][String]$VcenterId,
        [Parameter(Mandatory=$true)][String]$LicenseId,
        [Switch]$Troubleshoot
    )

    $uri = "https://$($global:vcfOpsConnection.server)/suite-api/internal/extension/vcf-entitlement/assign"
    $method = "POST"

    $vc = Get-VcfOperationsVcenters2 | where {$_.id -eq $VcenterId}

    $payload = @(
        [ordered]@{
            vcenter = [ordered]@{
                id          = $VcenterId
                adapterName = $vc.vCenter
                host        = $vc.vCenter
            }
            allocationIds = @($LicenseId)
        }
    )

    $body = ConvertTo-Json -InputObject @($payload)

    if($Troubleshoot) {
        Write-Host -ForegroundColor cyan "`n[DEBUG] - $method`n$uri`n"
        Write-Host -ForegroundColor cyan "[DEBUG]`n$($body | Out-String)`n"
    }

    try {
        $requests = Invoke-WebRequest -Uri $uri -Method $method -Headers $global:vcfOpsConnection.headers -Body $body -SkipCertificateCheck
    } catch {
        Write-Error "Error in assigning license entitlements"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if($requests.StatusCode -eq 200) {
        ($requests.Content | ConvertFrom-Json)

    }
}

