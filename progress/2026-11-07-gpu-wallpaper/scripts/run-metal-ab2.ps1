# Poster gallery workload on the old then the new plugin, with a fresh baseline capture first. Temp boots and reads only; writes no partition.
# Starts and ends in fastboot on slot b. The baseline's large text is removed; the two test captures keep theirs for reading.
$S = 'E:\DSH-Fuxi\dump\wsl'; $W = '/mnt/e/DSH-Fuxi/dump/wsl'; $L = '/mnt/e/DSH-Fuxi/logs'
$Steps = 'at 100; press 180 400 1000; wait 5; tap 316 740; wait 10; shot gallery; swipe 180 650 180 150 400; wait 15; shot gallery2; swipe 180 650 180 150 400; wait 15; shot gallery3'
function Count([string]$dir) { wsl.exe -u root -- python3 -I "$W/metal-kinds.py" count "$L/carve-$dir/lscan.txt" "$L/carve-$dir/kinds.json" }
& "$S\pull-wall.ps1" -Name 'ab2-base' | Select-Object -Last 1
Count 'ab2-base'
Remove-Item -LiteralPath 'E:\DSH-Fuxi\logs\carve-ab2-base\lscan.txt' -Confirm:$false
$prev = 'ab2-base'
foreach ($n in 't50-auto-gpu7tap', 't50-auto-g7plug') {
  "=== $n  $(Get-Date -Format HH:mm:ss)"
  & "$S\ctl-run.ps1" -Name $n -Steps $Steps -Timeout 400 | Select-Object -Last 11
  $tag = "ab2-$n"
  & "$S\pull-wall.ps1" -Name $tag | Select-Object -Last 1
  Count $tag
  "--- growth during $n"
  wsl.exe -u root -- python3 -I "$W/metal-kinds.py" diff "$L/carve-$prev/kinds.json" "$L/carve-$tag/kinds.json"
  $prev = $tag
}
"=== finished $(Get-Date -Format HH:mm:ss)"
