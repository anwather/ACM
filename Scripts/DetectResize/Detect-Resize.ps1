param (
    [object]$WebhookData
)

if ($null -ne $WebhookData) {
    $webhookbody = convertfrom-json $webhookdata.RequestBody
}
else {
    Write-Warning -Message 'Webhook data is `$null'
    exit
}

$OperationName = $webhookbody.data.OperationName

Write-Output "OperationName: $OperationName"

if ([string]::IsNullOrWhiteSpace($OperationName)) {
    throw "Operation is null. Not sure why this runbook was called."
}

$connectionName = "AzureRunAsConnection"
try {
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection) {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    }
    else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

#$tenantId = (Get-AzContext).Tenant.Id
$tokenCache = Get-AzContext | Select-Object -ExpandProperty TokenCache
$cachedTokens = $tokenCache.ReadItems()
$accessToken = $cachedTokens[0].AccessToken

$resourceId = $webhookbody.data.ResourceUri

$uri = "https://management.azure.com/providers/Microsoft.ResourceGraph/resourceChanges?api-version=2018-09-01-preview"
$changeURI = "https://management.azure.com/providers/Microsoft.ResourceGraph/resourceChangeDetails?api-version=2018-09-01-preview"

$endTime = (Get-Date (Get-Date).ToUniversalTime() -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
$startTime = (Get-Date (Get-Date).AddMinutes(-5).ToUniversalTime() -Format "yyyy-MM-ddTHH:mm:ss.fffZ")

Write-Output $startTime
Write-Output $endTime

$json = @{
    resourceId = $resourceId
    interval   = @{
        start = $startTime
        end   = $endTime
    }
} | ConvertTo-Json -Depth 5

$response = Invoke-WebRequest -Method POST `
    -Uri $uri `
    -Body $json `
    -Headers @{ "Authorization" = "Bearer " + $accessToken; 'Content-Type' = 'application/json' } -UseBasicParsing

$jsonObj = ConvertFrom-Json $([String]::new($response.Content))

foreach ($changeID in $jsonObj.changes.changeId ) { 
    $json2 = @{
        resourceId = $resourceId
        changeId   = $changeID
    } | ConvertTo-Json -Depth 5
    
    Write-Output "Getting changes for $changeID"

    $response = Invoke-RestMethod -Method POST `
        -Uri $changeURI `
        -Body $json2 `
        -Headers @{ "Authorization" = "Bearer " + $accessToken; 'Content-Type' = 'application/json' } 
    
    if ($OperationName -match "database") {
        Write-Output "Checking database changes"
        $pre = $response.beforeSnapshot.content.properties.currentServiceObjectiveName
        $post = $response.afterSnapshot.content.properties.currentServiceObjectiveName
        if ($pre -ne $post) {
            Write-Output "Resource $($response.beforeSnapshot.content.Name) scaled from capacity $pre to $post"
            $obj = @{
                ResourceId = $resourceId
                OldValue   = $pre
                NewValue   = $post
            }
        }
    }

    if ($OperationName -match "virtualmachine") {
        $pre = $response.beforeSnapshot.content.properties.hardwareprofile.vmsize
        $post = $response.afterSnapshot.content.properties.hardwareprofile.vmsize
        if ($pre -ne $post) {
            Write-Output "Resource $($response.beforeSnapshot.content.Name) scaled from size $pre to $post"
            $obj = @{
                ResourceId = $resourceId
                OldValue   = $pre
                NewValue   = $post
            }
        }
    }

    if ($OperationName -match "Microsoft.Web/serverFarms/write") {
        $pre = $response.beforeSnapshot.content.sku.name
        $post = $response.afterSnapshot.content.sku.name
        if ($pre -ne $post) {
            Write-Output "Resource $($response.beforeSnapshot.content.Name) scaled from size $pre to $post"
            $obj = @{
                ResourceId = $resourceId
                OldValue   = $pre
                NewValue   = $post
            }
        }
    }
}

# Send Info

if ($null -ne $obj) {
    $jsonBody = $obj | ConvertTo-Json
    Write-Output $jsonBody
    $uri = Get-AutomationVariable -Name 'AppURI'
    Invoke-WebRequest -Method POST -Uri $uri -Body $jsonBody -ContentType "application/json"
}

