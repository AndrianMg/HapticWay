# Samples memory (PSS) and CPU usage of the HapticWay app over adb while a
# benchmark run is in progress on the device. One CSV per invocation, tagged
# with the same condition label used by the in-app latency harness, written to
# docs/ alongside the latency CSVs.
#
# Usage (phone connected, USB debugging on, app running):
#   .\tool\record_resources.ps1 -Condition bright_empty
#   ... run the in-app benchmark, then Ctrl+C here to stop sampling.
#
# Notes for the report:
#  - PSS (Proportional Set Size) in kilobytes is Android's standard app-memory
#    figure (shared pages divided among sharers).
#  - %CPU comes from toybox top and is normalised to ONE core: values above
#    100 mean more than one core busy (the S20 Ultra has 8).

param(
    [Parameter(Mandatory = $true)][string]$Condition,
    [int]$IntervalSeconds = 1,
    [string]$AppId = "com.hapticway.hapticway"
)

$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) { throw "adb not found at $adb" }

$state = (& $adb get-state 2>$null)
if ($state -ne "device") { throw "No device attached (adb get-state: '$state'). Connect the phone and enable USB debugging." }

$repoRoot = Split-Path $PSScriptRoot -Parent
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile = Join-Path $repoRoot "docs\resource_usage_${Condition}_$stamp.csv"
"timestamp,elapsed_s,condition,pss_kb,cpu_pct_one_core" | Out-File $outFile -Encoding utf8

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$samples = 0
Write-Host "Sampling $AppId every ${IntervalSeconds}s -> $outFile"
Write-Host "Run the in-app benchmark now. Ctrl+C to stop."

while ($true) {
    $procId = (& $adb shell pidof $AppId).Trim()
    if (-not $procId) {
        Write-Host "  [warn] app not running (waiting)..."
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }

    # Memory: prefer the explicit "TOTAL PSS:" line (newer Android), fall back
    # to the summary table's TOTAL row.
    $mem = & $adb shell dumpsys meminfo $procId
    $pssKb = ""
    $m = [regex]::Match(($mem -join "`n"), 'TOTAL PSS:\s*(\d+)')
    if ($m.Success) { $pssKb = $m.Groups[1].Value }
    else {
        $m = [regex]::Match(($mem -join "`n"), '(?m)^\s*TOTAL\s+(\d+)')
        if ($m.Success) { $pssKb = $m.Groups[1].Value }
    }

    # CPU: toybox top, one iteration, this pid only, %CPU column only.
    $cpuRaw = (& $adb shell top -b -q -n 1 -p $procId -o '%CPU' 2>$null) |
        Where-Object { $_ -match '\d' } | Select-Object -First 1
    $cpuPct = if ($cpuRaw) { $cpuRaw.Trim() } else {
        # Fallback for top builds without -q/-o: parse the process line.
        $line = (& $adb shell top -b -n 1 -p $procId) | Where-Object { $_ -match $procId } | Select-Object -First 1
        if ($line -and $line -match '\s(\d+(\.\d+)?)\s+\d+(\.\d+)?\s') { $Matches[1] } else { "" }
    }

    $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $ts = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    "$ts,$elapsed,$Condition,$pssKb,$cpuPct" | Out-File $outFile -Append -Encoding utf8
    $samples++
    Write-Host ("  {0,6}s  PSS {1,8} kB  CPU {2,6}%" -f $elapsed, $pssKb, $cpuPct)
    Start-Sleep -Seconds $IntervalSeconds
}
