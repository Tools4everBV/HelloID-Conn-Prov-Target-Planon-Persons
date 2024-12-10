#################################################
# HelloID-Conn-Prov-Target-Planon-Persons-Create
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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    $headers = @{
        'Accept'       = 'application/json'
        'Content-Type' = 'application/json'
        Authorization  = "PLANONKEY accesskey=$($actionContext.Configuration.AuthToken)"
    }

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        $getUserBody = @{
            filter = @{
                "$($correlationField)" = @{
                    eq = $correlationValue
                }
            }
        }

        $splatGetUserParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v1/read/HelloIDAPI"
            Method  = 'POST'
            Body    = ($getUserBody | ConvertTo-Json -Depth 10)
            Headers = $headers
        }

        # Determine if a user needs to be [created] or [correlated]
        $correlatedAccount = (Invoke-RestMethod @splatGetUserParams).records
    }

    if ($correlatedAccount.count -eq 1) {
        $action = 'CorrelateAccount'
    } elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple Accounts [$($correlatedAccount.Count)] found with Correlation Value [$correlationField : $correlationValue]"
    } else {
        $action = 'CreateAccount'
    }

    # Process
    switch ($action) {
        'CreateAccount' {
            $actionContext.Data.FreeString41 = $actionContext.References.ManagerAccount

            # Rename properties to include "$" as property name prefix because of API specifications
            $actionContext.Data | Add-Member @{
                "`$DepartmentRef"     = $actionContext.Data.DepartmentRef
                "`$EmploymenttypeRef" = $actionContext.Data.EmploymenttypeRef
                "`$DisplayTypeRef"    = $actionContext.Data.DisplayTypeRef
                "`$FreeString41"      = $actionContext.Data.FreeString41
                "`$PersonPositionRef" = $actionContext.Data.PersonPositionRef
            } -Force

            $actionContext.Data.PSObject.Properties.Remove('DepartmentRef')
            $actionContext.Data.PSObject.Properties.Remove('EmploymenttypeRef')
            $actionContext.Data.PSObject.Properties.Remove('DisplayTypeRef')
            $actionContext.Data.PSObject.Properties.Remove('FreeString41')
            $actionContext.Data.PSObject.Properties.Remove('PersonPositionRef')

            

            $splatCreateParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v1/execute/HelloIDAPI/BomAdd"
                Method  = 'POST'
                Body    = @{
                    values = $actionContext.Data
                } | ConvertTo-Json -Depth 10
                Headers = $headers
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating Planon-Persons account'

                $createdAccount = (Invoke-RestMethod @splatCreateParams).records
                $outputContext.Data = $createdAccount
                $outputContext.AccountReference = $createdAccount.Code
            } else {
                Write-Information '[DryRun] Create and correlate Planon-Persons account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating Planon-Persons account'

            $outputContext.Data = $correlatedAccount
            $outputContext.AccountReference = $correlatedAccount.Code
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $action
            Message = $auditLogMessage
            IsError = $false
        })
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Planon-PersonsError -ErrorObject $ex
        $auditMessage = "Could not create or correlate Planon-Persons account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create or correlate Planon-Persons account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}