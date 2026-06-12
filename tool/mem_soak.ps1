$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$out = "d:\University Project\HapticWay\mem_soak.log"
"start $(Get-Date -Format o)" | Out-File -Encoding utf8 $out
for ($i = 0; $i -le 30; $i++) {
  $line = & $adb shell dumpsys meminfo com.hapticway.hapticway | Select-String "TOTAL PSS:" | Select-Object -First 1
  if ($line) {
    "$(Get-Date -Format HH:mm:ss)  $($line.Line.Trim())" | Out-File -Append -Encoding utf8 $out
  } else {
    "$(Get-Date -Format HH:mm:ss)  NO DATA (app not running?)" | Out-File -Append -Encoding utf8 $out
  }
  if ($i -lt 30) { Start-Sleep -Seconds 60 }
}
"end $(Get-Date -Format o)" | Out-File -Append -Encoding utf8 $out
