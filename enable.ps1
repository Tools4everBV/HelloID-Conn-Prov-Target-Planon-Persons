#################################################
# HelloID-Conn-Prov-Target-Planon-Persons-Enable
# PowerShell V2
#################################################

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
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $headers = @{
        'Accept'       = 'application/json'
        'Content-Type' = 'application/json'
        Authorization  = "PLANONKEY accesskey=$($actionContext.Configuration.AuthToken)"
    }

    $getUserBody = @{
        filter = @{
            Code = @{
                eq = $actionContext.References.Account
            }
        }
    }

    Write-Information 'Verifying if a Planon-Persons account exists'
    $splatGetUserParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v1/read/HelloIDAPI"
        Method  = 'POST'
        Body    = ($getUserBody | ConvertTo-Json -Depth 10)
        Headers = $headers
    }

    # Determine if a user needs to be [created] or [correlated]
    $correlatedAccount = ((Invoke-RestMethod @splatGetUserParams).records | Select-Object -First 1)

    if ($null -ne $correlatedAccount) {
        $action = 'EnableAccount'
    } else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'EnableAccount' {
            $accountBody = @{
                filter = @{
                    Code = @{
                        eq = $actionContext.References.Account
                    }
                }
                values = @{
                    BeginDate = Get-Date -Format "yyyy-MM-dd"
                    EndDate   = $null
                }
            }

            $splatEnableParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v1/update/HelloIDAPI"
                Method  = 'POST'
                Body    = ($accountBody | ConvertTo-Json -Depth 10)
                Headers = $headers
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Enabling Planon-Persons account with accountReference: [$($actionContext.References.Account)]"
                $null = Invoke-RestMethod @splatEnableParams

            } else {
                Write-Information "[DryRun] Enable Planon-Persons account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Enable account was successful'
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Planon-Persons account: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Planon-Persons account: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
                    IsError = $true
                })
            break
        }
    }

} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Planon-PersonsError -ErrorObject $ex
        $auditMessage = "Could not enable Planon-Persons account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not enable Planon-Persons account. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}