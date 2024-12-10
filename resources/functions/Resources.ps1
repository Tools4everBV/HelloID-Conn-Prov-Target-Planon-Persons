#####################################################
# HelloID-Conn-Prov-Target-Planon-Persons-resources-functions
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

    Write-Information 'Retrieving all functions from Planon'
    $splatGetOrgUnitsParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v1/read/HelloIDAPIFuncties"
        Method  = 'POST'
        Body    = @{} | ConvertTo-Json
        Headers = $headers
    }
    $functions = (Invoke-RestMethod @splatGetOrgUnitsParams).records
    $functionsGrouped = $functions | Group-Object -AsString -AsHashTable -Property Code
    
    $resourceData = $resourceContext.SourceData
    $resourceData = $resourceData | Select-Object -Unique ExternalId, Name

    $resourcesToCreate = [System.Collections.Generic.List[object]]::new()
    $resourcesToRename = [System.Collections.Generic.List[object]]::new()
    foreach ($resource in $resourceData) {
        if($resource.Name.Length -gt 50)
        {
            $resource.Name = $resource.Name.substring(0,50)
        }
        if(-not([string]::IsNullOrEmpty($resource.ExternalId))){
            $exists = $functionsGrouped["$($resource.ExternalId)"]
            if ($null -eq $exists) {
                $resourcesToCreate.Add($resource)
            }
             else {
                if($resource.Name.trim() -ne $exists.Function) {
                    $resourcesToRename.Add($resource)
                }
            }
        }
    }

    Write-Information "Creating [$($resourcesToCreate.Count)] resources"
    foreach ($resource in $resourcesToCreate) {
        if($resource.Name.Length -gt 50)
        {
            $resource.Name = $resource.Name.substring(0,50)
        }
        try {
            if (-not ($actionContext.DryRun -eq $True)) {
                $splatCreateResourceParams = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v1/execute/HelloIDAPIFuncties/BomAdd"
                    Method  = 'POST'
                    Body    = @{
                        values = @{
                            Code     = $resource.ExternalId
                            Function = $resource.Name.trim()
                        }
                    } | ConvertTo-Json
                    Headers = $headers
                }
                $null = Invoke-RestMethod @splatCreateResourceParams -Verbose:$false

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Created Planon-Persons function resource with name: [$($resource.Name)] and function: [$($resource.ExternalId)]"
                        IsError = $false
                    })
            } else {
                Write-Warning "[DryRun] Create Planon-Persons function resource with name: [$($resource.Name)]  and function: [$($resource.ExternalId)] will be executed during enforcement"
            }
        } catch {
            $outputContext.Success = $false
            $ex = $PSItem
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorObj = Resolve-Planon-PersonsError  -ErrorObject $ex
                $auditMessage = "Could not create Planon-Persons function resource [$($resource.Name)]. Error: $($errorObj.FriendlyMessage)"
                Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
            } else {
                $auditMessage = "Could not create Planon-Persons function resource [$($resource)]. Error: $($ex.Exception.Message)"
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
            if($resource.Name.Length -gt 50)
            {
                $resource.Name = $resource.Name.trim().substring(0,50)
            }
            try {
                $currentResource = $functionsGrouped["$($resource.ExternalId)"]
                if (-not ($actionContext.DryRun -eq $True)) {
                    $splatRenameResourceParams = @{
                        Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v2/update/HelloIDAPIFuncties"
                        Method  = 'POST'
                        Body    = @{
                            filter = @{
                                Code = @{
                                    eq = $resource.ExternalId
                                }
                            }
                            values = @{
                                Function = $resource.Name.trim()
                            }
                        } | ConvertTo-Json
                        Headers = $headers
                    }
                    $null = Invoke-RestMethod @splatRenameResourceParams -Verbose:$false

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = "Renamed Planon-Persons function resource from [$($currentResource.Function)] to [$($resource.Name)] with code: [$($resource.ExternalId)]"
                            IsError = $false
                        })
                } else {
                    Write-Warning "[DryRun] Rename Planon-Persons function resource from [$($currentResource.Function)] to [$($resource.Name)] with code: [$($resource.ExternalId)] will be executed during enforcement"
                }
            } catch {
                $outputContext.Success = $false
                $ex = $PSItem
                if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                    $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                    $errorObj = Resolve-Planon-PersonsError  -ErrorObject $ex
                    $auditMessage = "Could not rename Planon-Persons function resource [$($resource.Name)]. Error: $($errorObj.FriendlyMessage)"
                    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
                } else {
                    $auditMessage = "Could not rename Planon-Persons function resource [$($resource)]. Error: $($ex.Exception.Message)"
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
        $auditMessage = "Could not create Planon-Persons function resource. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create Planon-Persons function resource. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}