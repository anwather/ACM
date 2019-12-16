$policies = Get-ChildItem -Path .\Policies -Directory

$managementGroupName = "awinternalmg"

Write-Output "Discovered Policy Definitions"
$policies | ForEach-Object {
    Write-Output $_.BaseName
}

$deploy = @("AuditNonHubLicence", "AuditOrphanedDisks", "AuditOrphanedNIC", "AuditOrphanedPublicIp")

Write-Output "Deploying Policies as per release variable"

$deploy | ForEach-Object {
    Write-Output $_
}

Push-Location

Copy-Item .\Initiatives\AzureCostOptimization\azurecostoptimization.json .\inittemp.json -Force
Copy-Item .\Initiatives\AzureCostOptimization\azurecostoptimization.definitions.json .\inittempdefs.json -Force

foreach ($policyFolder in $policies) {
    Push-Location
    if ($policyFolder.Name -in $deploy) {
        Write-Output "Deploy policy $($policyFolder.Name)"
        $policyParameters = $null
        $params = $null
        Set-Location $policyFolder.FullName

        $policyRules = Get-ChildItem | Where-Object Name -match "rules" | Get-Content -Raw
        $policyParameters = Get-ChildItem | Where-Object Name -match "parameters" | Get-Content -Raw

        if (!($null -eq $policyParameters)) {
            $params = @{
                Verbose   = $true
                Parameter = $policyParameters
            }
        }
        else {
            $params = @{
                Verbose = $true
            }
        }

        Write-Output $policyRules
        Write-Output $policyParameters

        $policyDefinition = Get-ChildItem | Where-Object Name -notmatch "parameters|rules" | Get-Content | ConvertFrom-Json

        $pol = New-AzPolicyDefinition -Name ($policyDefinition.properties.displayName).Replace(" ", "-") `
            -DisplayName $policyDefinition.properties.displayName `
            -Description $policyDefinition.properties.description `
            -Policy $policyRules `
            -Mode $policyDefinition.properties.mode `
            -ManagementGroupName $managementGroupName  `
            @params

        (Get-Content ..\..\inittempdefs.json) -replace $policyDefinition.properties.displayName, $pol.PolicyDefinitionId | Set-Content -Path ..\..\inittempdefs.json
        
        

    }
    Pop-Location
}

$iDef = Get-Content .\inittemp.json | ConvertFrom-Json
$policyDefinitions = Get-ChildItem | Where-Object Name -match "defs" | Get-Content -Raw

New-AzPolicySetDefinition -ManagementGroupName $managementGroupName -Name $idef.name `
    -DisplayName $idef.properties.displayName `
    -Description $idef.properties.description `
    -PolicyDefinition $policyDefinitions `
    -Verbose

if (Test-Path .\Policies) {
    Remove-Item *.json -Force
}