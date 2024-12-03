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

    Write-Information 'Retrieving all organizational units from Planon'
    $splatGetOrgUnitsParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v1/read/HelloIDAPIFuncties"
        Method  = 'POST'
        Body    = @{} | ConvertTo-Json
        Headers = $headers
    }
    $functions = (Invoke-RestMethod @splatGetOrgUnitsParams).records

    $functionsGrouped = $functions | Group-Object -AsString -AsHashTable -Property code
    $resourcesToCreate = [System.Collections.Generic.List[object]]::new()
    foreach ($resource in $resourceContext.SourceData) {
        if(-not([string]::IsNullOrEmpty($resource))){
            $exists = $functionsGrouped["$($resource.Code)"]
            if ($null -eq $exists) {
                $resourcesToCreate.Add($resource)
            }
        }
    }

    Write-Information "Creating [$($resourcesToCreate.Count)] resources"
    foreach ($resource in $resourcesToCreate) {
        try {
            if (-not ($actionContext.DryRun -eq $True)) {
                $splatCreateResourceParams = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v1/execute/HelloIDAPIFuncties/BomAdd"
                    Method  = 'POST'
                    Body    = @{
                        values = @{
                            Code     = $resource.Code
                            Function = $resource.Name
                        }
                    } | ConvertTo-Json
                    Headers = $headers
                }
                $null = Invoke-RestMethod @splatCreateResourceParams -Verbose:$false

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Created Planon-Persons function resource with name: [$($resource.name)] and function: [$($resource.Code)]"
                        IsError = $false
                    })
            } else {
                Write-Information "[DryRun] Create Planon-Persons function resource with name: [$($resource.name)]  and function: [$($resource.Code)] will be executed during enforcement"
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