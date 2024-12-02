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
    $outputContext.PreviousData = $correlatedAccount

    $actionContext.Data.FreeString41 = $actionContext.References.ManagerAccount

    # Rename properties to include "$" as property name prefix because of API specifications
    # Rename properties for correlatedAccount
    $correlatedAccount | Add-Member @{
        "`$DepartmentRef"     = $correlatedAccount.DepartmentRef
        "`$EmploymenttypeRef" = $correlatedAccount.EmploymenttypeRef
        "`$DisplayTypeRef"    = $correlatedAccount.DisplayTypeRef
    } -Force

    $correlatedAccount.PSObject.Properties.Remove('DepartmentRef')
    $correlatedAccount.PSObject.Properties.Remove('EmploymenttypeRef')
    $correlatedAccount.PSObject.Properties.Remove('DisplayTypeRef')

    # Rename properties for actionContext.Data
    $actionContext.Data | Add-Member @{
        "`$DepartmentRef"     = $actionContext.Data.DepartmentRef
        "`$EmploymenttypeRef" = $actionContext.Data.EmploymenttypeRef
        "`$DisplayTypeRef"    = $actionContext.Data.DisplayTypeRef
    } -Force

    $actionContext.Data.PSObject.Properties.Remove('DepartmentRef')
    $actionContext.Data.PSObject.Properties.Remove('EmploymenttypeRef')
    $actionContext.Data.PSObject.Properties.Remove('DisplayTypeRef')

    # Always compare the account against the current account in target system
    if ($correlatedAccount.count -eq 1) {
        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @($actionContext.Data.PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged) {
            $action = 'UpdateAccount'
        } else {
            $action = 'NoChanges'
        }
    } else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'UpdateAccount' {
            Write-Information "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"

            $changedPropertiesObject = @{}
            foreach ($property in $propertiesChanged) {
                $propertyName = $property.Name
                $propertyValue = $property.value

                $changedPropertiesObject.$propertyName = $propertyValue
            }

            $accountBody = @{
                filter = @{
                    Code = @{
                        eq = $actionContext.References.Account
                    }
                }
                values = $changedPropertiesObject
            }

            $splatUpdateParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/sdk/system/rest/v1/update/HelloIDAPI"
                Method  = 'POST'
                Body    = ($accountBody | ConvertTo-Json -Depth 10)
                Headers = $headers
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating Planon-Persons account with accountReference: [$($actionContext.References.Account)]"
                $null = Invoke-RestMethod @splatUpdateParams
            } else {
                Write-Information "[DryRun] Update Planon-Persons account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to Planon-Persons account with accountReference: [$($actionContext.References.Account)]"

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Planon-Persons account: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Planon-Persons account with accountReference: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
                    IsError = $true
                })
            break
        }
    }
} catch {
    $outputContext.Success  = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Planon-PersonsError -ErrorObject $ex
        $auditMessage = "Could not update Planon-Persons account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update Planon-Persons account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
