#################################################
# HelloID-Conn-Prov-Target-Planon-Persons-Import
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
    Write-Information 'Starting Planon account entitlement import'

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

    # This filter must be adjusted on customer needs
    $getUserBody = @{
        filter = @{
            FacilityNetUsername = @{
                gt = "1"
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
    $importedAccounts = ((Invoke-RestMethod @splatGetUserParams).records)

    foreach ($importedAccount in $importedAccounts) {
        # Making sure only fieldMapping fields are imported
        $data = @{}
        foreach ($field in $actionContext.ImportFields) {
            $data[$field] = $importedAccount.$field
        }

        # Set Enabled based on importedAccount status"
        $today = Get-Date
        $isEnabled = $false
        if ($importedAccount.EndDate -eq $null -Or $importedAccount.EndDate -lt $today) {
            $isEnabled = $true
        }

        # Make sure the displayName has a value
        $displayName = "$($importedAccount.FirstName) $($importedAccount.LastName)".trim()
        if ([string]::IsNullOrEmpty($displayName)) {
            $displayName = $importedAccount.Code
        }

        # Make sure the userName has a value
        if ([string]::IsNullOrWhiteSpace($importedAccount.FacilityNetUsername)) {
            $importedAccount.FacilityNetUsername = $importedAccount.Code
        }

        # Return the result
        Write-Output @{
            AccountReference = $importedAccount.Code
            displayName      = $displayName
            UserName         = $importedAccount.FacilityNetUsername
            Enabled          = $isEnabled
            Data             = $data
        }
    }
    Write-Information 'Planon account entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Planon-PersonsError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Planon account entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Planon account entitlements. Error: $($ex.Exception.Message)"
    }
}