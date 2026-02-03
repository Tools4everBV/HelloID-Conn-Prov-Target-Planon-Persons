#################################################
# HelloID-Conn-Prov-Target-Planon-Persons-Update
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
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
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
        }
        catch {
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

    # Requesting authorization token
    $splatRetrieveTokenParams = @{
        Uri         = "$($actionContext.Configuration.AuthURL)/auth/realms/planon/protocol/openid-connect/token"
        Method      = 'POST'
        ContentType = 'application/x-www-form-urlencoded'
        Body        = @{
            client_id     = $($actionContext.Configuration.ClientId)
            client_secret = $($actionContext.Configuration.ClientSecret)
            grant_type    = "client_credentials"
        }
    }
    $responseToken = Invoke-RestMethod @splatRetrieveTokenParams

    #create headers
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($responseToken.access_token)")
    $headers.Add("Content-Type", "application/json")

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
    $outputContext.PreviousData = $correlatedAccount

    # Rename properties to include "$" as property name prefix because of API specifications
    # Rename properties for correlatedAccount
    $correlatedAccount | Add-Member @{
        "`$RefBOStateUserDefined" = $actionContext.Data.RefBOStateUserDefined
    } -Force

    $correlatedAccount.PSObject.Properties.Remove('RefBOStateUserDefined')

    # Rename properties for actionContext.Data
    $actionContext.Data | Add-Member @{
        "`$RefBOStateUserDefined" = $actionContext.Data.RefBOStateUserDefined
    } -Force

    $actionContext.Data.PSObject.Properties.Remove('RefBOStateUserDefined')


    # Process
    $accountBody = @{
        filter = @{
            Code = @{
                eq = $actionContext.References.Account
            }
        }
        values = $actionContext.Data
    }

    $splatUpdateParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v2/update/HelloIDAPI"
        Method  = 'POST'
        Body    = ($accountBody | ConvertTo-Json -Depth 10)
        Headers = $headers
    }

    if (-not($actionContext.DryRun -eq $true)) {
        Write-Information "Enable Planon account with accountReference: [$($actionContext.References.Account)]"
        $null = Invoke-RestMethod @splatUpdateParams
    }
    else {
        Write-Information "[DryRun] Enable Planon account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
    }

    $outputContext.Success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = "Enable account was successful, Account property(s) updated: [$($actionContext.Data -join ',')]"
            IsError = $false
        })
    break


    $outputContext.Data = $actionContext.Data
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Planon-PersonsError -ErrorObject $ex
        $auditMessage = "Could not enable Planon account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not enable Planon account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}