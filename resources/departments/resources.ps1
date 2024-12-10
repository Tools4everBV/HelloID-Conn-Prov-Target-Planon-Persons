#####################################################
# HelloID-Conn-Prov-Target-Planon-Persons-Departments
# PowerShell V2
#####################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-Planon-PersonsError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            $httpErrorObj.FriendlyMessage = $errorDetailsObject.errors.description
        } catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    Write-Information 'Setting authorization header'
    $headers = @{
        'Accept'       = 'application/json'
        'Content-Type' = 'application/json'
        Authorization  = "PLANONKEY accesskey=$($actionContext.Configuration.AuthToken)"
    }

    Write-Information 'Retrieving all organizational units from Planon'
    $splatGetOrgUnitsParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v1/read/HelloIDAPIEenheden"
        Method  = 'POST'
        Body    = @{} | ConvertTo-Json
        Headers = $headers
    }
    $organizationalUnits = (Invoke-RestMethod @splatGetOrgUnitsParams).records
    $organizationalUnitsGrouped = $organizationalUnits | Group-Object -AsString -AsHashTable -Property CompositeCode

    $resourceData = $resourceContext.SourceData
    $resourceData = $resourceData | Select-Object -Unique ExternalId, DisplayName

    $resourcesToCreate = [System.Collections.Generic.List[object]]::new()
    $resourcesToRename = [System.Collections.Generic.List[object]]::new()
    foreach ($resource in $resourceData) {
        if(-not([string]::IsNullOrEmpty($resource.ExternalId))){
            $exists = $organizationalUnitsGrouped["$($resource.ExternalId)"]
            if ($null -eq $exists) {
                $resourcesToCreate.Add($resource)
            }
            else {
                if($resource.DisplayName.trim() -ne $exists.Name -or $resource.InternePostcode -ne $exists.FreeString2) {
                    $resourcesToRename.Add($resource)
                }
            }
        }
    }

    Write-Information "Creating [$($resourcesToCreate.Count)] resources"
    foreach ($resource in $resourcesToCreate) {
        try {
            if (-not ($actionContext.DryRun -eq $True)) {
                $splatCreateResourceParams = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v1/execute/HelloIDAPIEenheden/BomAdd"
                    Method  = 'POST'
                    Body    = @{
                        values = @{
                            Code = $resource.ExternalId
                            Name = $resource.DisplayName
                            #FreeString2 = $resource.ExternalId
                        }
                    } | ConvertTo-Json
                    Headers = $headers
                }
                $null = Invoke-RestMethod @splatCreateResourceParams -Verbose:$false
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Created Planon-Persons department resource with code: [$($resource.ExternalId)] and name: [$($resource.DisplayName)]"
                        IsError = $false
                    })
            } else {
                Write-Warning "[DryRun] Create Planon-Persons department resource with code: [$($resource.ExternalId)] and name: [$($resource.DisplayName)]  will be executed during enforcement"
            }
        } catch {
            $outputContext.Success = $false
            $ex = $PSItem
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorObj = Resolve-Planon-PersonsError  -ErrorObject $ex
                $auditMessage = "Could not create Planon-Persons department resource with code: [$($resource.ExternalId)] and name: [$($resource.DisplayName)]. Error: $($errorObj.FriendlyMessage)"
                Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
            } else {
                $auditMessage = "Could not create Planon-Persons department resource with code: [$($resource.ExternalId)] and name: [$($resource.DisplayName)]. Error: $($ex.Exception.Message)"
                Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            }
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $auditMessage
                    IsError = $true
                })
        }
    }

    if($actionContext.Configuration.RenameResources) {

        Write-Information "Renaming [$($resourcesToRename.Count)] resources"
        foreach ($resource in $resourcesToRename) {
            try {
                $currentResource = $organizationalUnitsGrouped["$($resource.ExternalId)"]
                if (-not ($actionContext.DryRun -eq $True)) {
                    Write-Warning "Rename Planon-Persons department resource from [$($currentResource.Name)] to [$($resource.DisplayName)] and from [$($currentResource.FreeString2)] to [$($resource.InternePostcode)]  with code: [$($resource.ExternalId)] will be executed during enforcement"
                    
                    $splatRenameResourceParams = @{
                        Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v2/update/HelloIDAPIEenheden"
                        Method  = 'POST'
                        Body    = @{
                            filter = @{
                                CompositeCode = @{
                                    eq = $resource.ExternalId
                                }
                            }
                            values = @{
                                Name = $resource.DisplayName.trim()
                                FreeString2 = $resource.InternePostcode
                            }
                        } | ConvertTo-Json
                        Headers = $headers
                    }
                    $null = Invoke-RestMethod @splatRenameResourceParams -Verbose:$false

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = "Renamed Planon-Persons department resource resource from [$($currentResource.Name)] to [$($resource.DisplayName)] and from [$($currentResource.FreeString2)] to [$($resource.InternePostcode)]  with code: [$($resource.ExternalId)]"
                            IsError = $false
                        })
                } else {
                    Write-Warning "[DryRun] Rename Planon-Persons department resource from [$($currentResource.Name)] to [$($resource.DisplayName)] and from [$($currentResource.FreeString2)] to [$($resource.InternePostcode)]  with code: [$($resource.ExternalId)] will be executed during enforcement"
                }
            } catch {
                $outputContext.Success = $false
                $ex = $PSItem
                if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                    $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                    $errorObj = Resolve-Planon-PersonsError  -ErrorObject $ex
                    $auditMessage = "Could not rename Planon-Persons department resource [$($resource.DisplayName)]. Error: $($errorObj.FriendlyMessage)"
                    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
                } else {
                    $auditMessage = "Could not rename Planon-Persons department resource [$($resource.DisplayName)]. Error: $($ex.Exception.Message)"
                    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
                }
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = $auditMessage
                        IsError = $true
                    })
            }
        }
    }

    $outputContext.Success = $true
} catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Planon-PersonsError  -ErrorObject $ex
        $auditMessage = "Could not create Planon-Persons department resource. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create Planon-Persons department resource. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}