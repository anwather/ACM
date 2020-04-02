Param(
    [Parameter(Mandatory = $true, ParameterSetName = "mg")]
    [string]$ManagementGroupName,
    [Parameter(Mandatory = $true, ParameterSetName = "sub")]
    [string]$SubscriptionId
)

$policies = Get-ChildItem -Path .\Policies -Recurse -File

foreach ($policy in $policies) {

    if ($policy.BaseName) {
        Write-Output "Deploying policy $($policy.BaseName)"
        $policyParameters = $null
        $params = $null

        $policyObj = Get-Content $policy | ConvertFrom-Json | Select-Object -ExpandProperty properties

        (Get-Content $policy | ConvertFrom-Json | Select-Object -ExpandProperty properties).policyRule `
        | ConvertTo-Json -Depth 100 | Out-File tmp_$($policyObj.Name).json

        $policyRules = Get-Content tmp_$($policyObj.Name).json -Raw && Remove-Item tmp_$($policyObj.Name).json -Force

        (Get-Content $policy | ConvertFrom-Json | Select-Object -ExpandProperty properties).parameters `
        | ConvertTo-Json -Depth 100 | Out-File tmp_$($policyObj.Name).json

        if ((Get-Content tmp_$($policyObj.Name).json | Measure-Object -Line).Lines -gt 1 ) {
            $policyParameters = Get-Content tmp_$($policyObj.Name).json -Raw
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

        switch ($PSBoundParameters) {
            { $_.ContainsKey("ManagementGroupName") } { $params.Add("ManagementGroupName", $ManagementGroupName) }
            { $_.ContainsKey("SubscriptionId") } { $params.Add("SubscriptionId", $SubscriptionId) }
        }

        Remove-Item tmp_$($policyObj.Name).json -Force

        New-AzPolicyDefinition -Name $policyObj.name `
            -DisplayName $policyObj.displayName `
            -Description $policyObj.description `
            -Policy $policyRules `
            -Mode $policyObj.mode `
            -Metadata ($policyObj.metadata | ConvertTo-Json) `
            @params

        $params = $null
    }
    
}
$params = @{ }
switch ($PSBoundParameters) {
    { $_.ContainsKey("ManagementGroupName") } { $params.Add("ManagementGroupName", $ManagementGroupName) }
    { $_.ContainsKey("SubscriptionId") } { $params.Add("SubscriptionId", $SubscriptionId) }
}

$policyMap = @{ }
Get-AzPolicyDefinition @params | Select-Object Name, PolicyDefinitionId | ForEach-Object {
    if (!($policyMap.ContainsKey($_.Name))) {
        $policyMap.Add($_.Name, $_.PolicyDefinitionId)
    }
}

$initiatives = Get-ChildItem -Path .\Initiatives -Recurse -File

foreach ($initiative in $initiatives) {
    Write-Output "Deploy initiative $($initiative.Name)"
    $initiativeParameters = $null
    $params = $null

    $initiativeObj = Get-Content $initiative | ConvertFrom-Json | Select-Object -ExpandProperty properties

    $obj = (Get-Content $initiative | ConvertFrom-Json | Select-Object -ExpandProperty properties).policyDefinitions
    $obj | ForEach-Object { $_.policyDefinitionId = $policyMap[$_.policyDefinitionId] }
    if ($obj.Count -eq 1) {
        $obj | ConvertTo-Json -Depth 100 -AsArray | Out-File tmp_$($initiativeObj.Name).json
    }
    else {
        $obj | ConvertTo-Json -Depth 100 | Out-File tmp_$($initiativeObj.Name).json
    }
    

    $initiativeDefinition = Get-Content tmp_$($initiativeObj.Name).json -Raw && Remove-Item tmp_$($initiativeObj.Name).json -Force

    (Get-Content $initiative | ConvertFrom-Json | Select-Object -ExpandProperty properties).parameters `
    | ConvertTo-Json -Depth 100 | Out-File tmp_$($initiativeObj.Name).json

    if ((Get-Content tmp_$($initiativeObj.Name).json | Measure-Object -Line).Lines -gt 1 ) {
        $initiativeParameters = Get-Content tmp_$($initiativeObj.Name).json -Raw
        $params = @{
            Verbose   = $true
            Parameter = $initiativeParameters
        }
    }
    else {
        $params = @{
            Verbose = $true
        }
    }

    switch ($PSBoundParameters) {
        { $_.ContainsKey("ManagementGroupName") } { $params.Add("ManagementGroupName", $ManagementGroupName) }
        { $_.ContainsKey("SubscriptionId") } { $params.Add("SubscriptionId", $SubscriptionId) }
    }

    Remove-Item tmp_$($initiativeObj.Name).json -Force

    New-AzPolicySetDefinition -Name $initiativeObj.name `
        -DisplayName $initiativeObj.displayName `
        -Description $initiativeObj.description `
        -PolicyDefinition $initiativeDefinition `
        -Metadata ($initiativeObj.metadata | ConvertTo-Json) `
        @params

    $params = $null

}



