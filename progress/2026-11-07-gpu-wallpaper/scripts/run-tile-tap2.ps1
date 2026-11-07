# Scroll until tiles fill, then tap into Pride and Hello, on both grant images, with log capture. Temp boots and reads only; writes no partition. Starts and ends in fastboot on slot b.
$S = 'E:\DSH-Fuxi\dump\wsl'
$Up = 'swipe 180 650 180 150 400'; $Down = 'swipe 180 150 180 650 400'
$Steps = "at 100; press 180 400 1000; wait 6; tap 316 740; wait 12; $Up; wait 25; $Down; wait 15; $Up; wait 25; $Down; wait 15; $Up; wait 25; shot filled; tap 68 740; wait 30; shot pride; tap 45 25; wait 6; shot back; $Up; wait 6; shot scrolled; tap 68 370; wait 30; shot hello; wait 3"
foreach ($n in 't50-auto-g7plugrant', 't50-auto-g7grant') {
  "=== $n  $(Get-Date -Format HH:mm:ss)"
  & "$S\ctl-run.ps1" -Name $n -Steps $Steps -Timeout 420 | Select-Object -Last 6
  $tag = "tap2-$n"
  & "$S\pull-wall.ps1" -Name $tag | Select-Object -Last 1
  wsl.exe -u root -- bash -c "tr -d '\r' < /mnt/e/DSH-Fuxi/dump/wsl/read-stretch.sh > /tmp/rs.sh; bash /tmp/rs.sh $tag"
}
"=== finished $(Get-Date -Format HH:mm:ss)"
