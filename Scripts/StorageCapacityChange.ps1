#Requires -Version 7.0.0
Param([ValidateRange(1, 30)]
    [int]$Days = 30)

$storageAccountIDs = (Get-AzStorageAccount).Id

$resultArray = $storageAccountIDs | ForEach-Object -Parallel {
    $m = get-azmetric -ResourceId $_ -TimeGrain 01:00:00 -EndTime (Get-Date) -StartTime (Get-Date).AddDays(-$using:Days) -WarningAction SilentlyContinue
    $startCounter = 0
    $endCounter = $m.Data.Count
    do {
    
        $exit = $false
        if ($m.Data[$startCounter].Average -ne 0) {
            $startVal = @{
                StartTime = $m.Data[$startCounter].TimeStamp
                Average   = $m.Data[$startCounter].Average
            }
            $startVal.Average++
            $exit = $true
        }
        else {
            $startCounter++
        }
    
    } while ($exit -eq $false)

    do {
    
        $exit = $false
        if ($null -ne $m.Data[$endCounter].Average) {
            $endVal = @{
                EndTime = $m.Data[$endCounter].TimeStamp
                Average = $m.Data[$endCounter].Average
            }
            $exit = $true
        }
        else {
            $endCounter--
        }
    
    } while ($exit -eq $false)

    $percentChange = "{0:p5}" -f [double](($endVal.Average - $startVal.Average) / $startVal.Average)

    $outputObj = [PSCustomObject]@{
        StorageAccountName = $_.Split("/")[-1]
        StartTime          = $startVal.StartTime
        EndTime            = $endVal.EndTime
        StartValue         = "$([math]::Round(($startVal.Average)/1KB))KB"
        EndValue           = "$([math]::Round(($endVal.Average)/1KB))KB"
        PercentageChange   = $percentChange
        
    }
    return $outputObj
} -ThrottleLimit 2

$resultArray | Out-GridView



