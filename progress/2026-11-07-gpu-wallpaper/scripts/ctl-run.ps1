# One unattended test: boots an image, runs a list of steps over USB, sends REBOOT, decodes the screenshots.
# Steps, separated by ';', with x y in screen points (360 x 800):
#   at <sec after boot> | wait <sec> | shot <name> | tap <x> <y> | swipe <x0> <y0> <x1> <y1> [ms] | press <x> <y> [ms] | home
# 'home' is an up swipe starting just below the home bar: from the lock screen it unlocks, from an app it returns to the desktop.
# Needs a kernel with touch-cave2. A step's failure is reported and the REBOOT still goes out.
# -Attach skips the boot and uses the running system. -NoReboot leaves it running.
# A boot that fell through to boot_b is recalled and retried up to -Retries times.
param([string]$Name, [string]$Steps, [int]$Timeout = 300, [switch]$Attach, [switch]$NoReboot, [int]$Retries = 2)
$f = 'E:\DSH-Fuxi\tools\platform-tools\fastboot.exe'
$start = Get-Date; $stamp = $start.ToString('HHmmss')
$label = if ($Name) { $Name } else { 'attach' }
$out = "E:\DSH-Fuxi\logs\run-$label-$stamp.txt"; $ser = "E:\DSH-Fuxi\logs\com3-$label-$stamp.log"
New-Item -ItemType File -Force $out | Out-Null
function W([string]$s) { $line = ('{0,6:N1}s {1}' -f ((Get-Date) - $start).TotalSeconds, $s); Add-Content -Path $out -Value $line; Write-Output $line }
function Get-Crc([string]$text) {
  [long]$crc = 4294967295
  foreach ($b in [Text.Encoding]::ASCII.GetBytes($text)) {
    $crc = $crc -bxor [long]$b
    for ($i = 0; $i -lt 8; $i++) { if ($crc -band 1) { $crc = ($crc -shr 1) -bxor 3988292384 } else { $crc = $crc -shr 1 } }
  }
  return ($crc -bxor 4294967295)
}
function Frame([string]$verb, [string]$session, [long]$seq) {
  $body = 'SXNU1 {0} {1:x8} {2}' -f $session, $seq, $verb
  return ('{0} {1:x8}' -f $body, (Get-Crc $body)) + "`n"
}
# touchAction clamps x at 30479 and scales it to 32767; y uses 20319. A grid of taps fits x_pt = raw * 360 / 30480.
# A kernel with the first touch-cave2 refuses raw x above 20319, which is 240 pt: it cannot reach the right-hand third.
$AxisX = 30480 / 360; $AxisY = 20320 / 800
function Hex-X([double]$v) { return '{0:x4}' -f [int][Math]::Min(30479, [Math]::Max(0, $v * $AxisX)) }
# The cave mirrors y (20319 - y), so its input runs from the screen's bottom. The user saw "up" swipes go down.
function Hex-Y([double]$v) { return '{0:x4}' -f [int][Math]::Min(20319, [Math]::Max(0, (800 - $v) * $AxisY)) }
if (-not $Attach) {
  $img = "E:\DSH-Fuxi\$Name.img"
  if (-not (Test-Path $img)) { W "no $img"; exit 1 }
  if (-not (& $f devices)) { W 'phone not in fastboot'; exit 1 }
  $null = cmd /c "`"$f`" set_active b 2>&1"
  W "boot $Name"
  & $f boot $img 2>&1 | Select-Object -Last 1 | ForEach-Object { W "$_" }
}
$end = $start.AddSeconds($Timeout); $port = $null
while (-not $port -and (Get-Date) -lt $end) {
  if ([IO.Ports.SerialPort]::GetPortNames() -contains 'COM3') {
    try {
      $port = New-Object IO.Ports.SerialPort 'COM3', 115200, 'None', 8, 'One'
      $port.DtrEnable = $true; $port.ReadTimeout = 200; $port.WriteTimeout = 2000; $port.Open()
      W ('COM3 open after ' + [int]((Get-Date) - $start).TotalSeconds + ' s')
    } catch { $port = $null; Start-Sleep 1 }
  } else { Start-Sleep 1 }
}
if (-not $port) { W "NO COM3 within $Timeout s"; exit 2 }
$script:buf = ''
function Pump([int]$ms) {
  $until = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $until) {
    $c = $port.ReadExisting()
    if ($c) { [IO.File]::AppendAllText($ser, $c); $script:buf += $c
      if ($script:buf.Length -gt 200000) { $script:buf = $script:buf.Substring($script:buf.Length - 4000) } }
    Start-Sleep -Milliseconds 50
  }
}
function Wait-Reply([string]$verb, [long]$seq, [int]$ms) {
  $until = (Get-Date).AddMilliseconds($ms)
  $pattern = 'SXNU1R \w{16} ' + ('{0:x8}' -f $seq) + ' ' + $verb + ' [^\r\n]*\n'
  while ((Get-Date) -lt $until) {
    $m = [regex]::Match($script:buf, $pattern)
    if ($m.Success) { $script:buf = $script:buf.Substring($m.Index + $m.Length); return $m.Value.Trim() }
    $c = $port.ReadExisting()
    if ($c) { [IO.File]::AppendAllText($ser, $c); $script:buf += $c } else { Start-Sleep -Milliseconds 30 }
  }
  return $null
}
$session = $null; [long]$seq = 0
function Say-Hello {
  for ($i = 1; $i -le 10 -and -not $script:session; $i++) {
    $port.Write((Frame 'HELLO' '0000000000000000' 0))
    $r = Wait-Reply 'HELLO' 0 4000
    if ($r -match 'session=(\w{16}) last_seq=(\w+)') { $script:session = $Matches[1]; $script:seq = [Convert]::ToInt64($Matches[2], 16) }
  }
  return [bool]$script:session
}
function Send-Gesture([string]$verb) {
  if (-not $script:session -and -not (Say-Hello)) { W 'HELLO never answered'; return }
  $script:seq++
  $port.Write((Frame $verb $script:session $script:seq))
  # A gesture is answered as SCREENSHOT, after it has been performed.
  $r = Wait-Reply 'SCREENSHOT' $script:seq 15000
  W ("  $verb -> " + $(if ($r -match 'state=ready') { 'ok' } elseif ($r) { $r } else { 'NO REPLY' }))
  # A refused frame does not advance the kernel's sequence, so the next one would be refused too.
  if (-not $r) { $script:session = $null }
}
function Take-Shot([string]$tag) {
  if (-not $script:session -and -not (Say-Hello)) { W 'HELLO never answered'; return }
  $script:seq++
  $port.Write((Frame 'SCREENSHOT' $script:session $script:seq))
  $meta = Wait-Reply 'SCREENSHOT' $script:seq 30000
  if ($meta -notmatch 'encoded=(\d+)') { W "  shot ${tag}: $meta"; $script:session = $null; return }
  $total = [int]$Matches[1]; $ms = New-Object IO.MemoryStream; $bad = $null
  while ($ms.Length -lt $total) {
    $script:seq++
    $port.Write((Frame 'SHOTNEXT' $script:session $script:seq))
    $r = Wait-Reply 'SHOTNEXT' $script:seq 8000
    if ($r -notmatch ('offset=' + $ms.Length + ' data=([0-9a-fA-F]+)')) { $bad = "at $($ms.Length) of ${total}: $r"; break }
    $hex = $Matches[1]
    for ($i = 0; $i -lt $hex.Length; $i += 2) { $ms.WriteByte([Convert]::ToByte($hex.Substring($i, 2), 16)) }
  }
  if ($bad) { W "  shot $tag stopped $bad"; $script:session = $null; return }
  $base = "E:\DSH-Fuxi\logs\shot-$label-$stamp-$tag"
  [IO.File]::WriteAllBytes("$base.bin", $ms.ToArray()); [IO.File]::WriteAllText("$base.txt", $meta)
  W "  shot $tag $total bytes"
}
function Send-Reboot {
  # A fresh HELLO, so an earlier refused frame cannot leave REBOOT with a stale sequence.
  $script:session = $null
  if (-not (Say-Hello)) { W 'HELLO never answered, REBOOT not sent'; return }
  # Soon after boot the kernel answers state=nohook, because its reset hook is not installed yet (seen at 95 s; fine later).
  foreach ($try in 1..18) {
    $script:seq++; $port.Write((Frame 'REBOOT' $script:session $script:seq))
    $r = Wait-Reply 'REBOOT' $script:seq 4000
    W ('REBOOT reply: ' + $r)
    if ($r -notmatch 'nohook') { break }
    Pump 10000
    $script:session = $null
    if (-not (Say-Hello)) { W 'HELLO never answered'; return }
  }
  $t = Get-Date
  try { while ($port.IsOpen -and ([IO.Ports.SerialPort]::GetPortNames() -contains 'COM3') -and ((Get-Date) - $t).TotalSeconds -lt 30) { $c = $port.ReadExisting(); if ($c) { [IO.File]::AppendAllText($ser, $c) }; Start-Sleep -Milliseconds 100 } } catch {}
  try { $port.Close() } catch {}
  $back = $false
  for ($i = 0; $i -lt 60; $i++) { if (& $f devices) { $back = $true; W ('back in fastboot, ' + [int]((Get-Date) - $t).TotalSeconds + ' s after REBOOT'); break }; Start-Sleep 1 }
  if (-not $back) { W 'NOT back in fastboot' }
  $null = cmd /c "`"$f`" set_active b 2>&1"
  $script:backOk = $back
}
# A Mi-logo hang falls through to boot_b, which also opens COM3. Only a kernel with touch-cave2 answers a TAP at all, even
# before its screenshot provider is registered, so a tap in the top-left corner tells the two apart. Reading boot-args from
# the log alone is not reliable: the line may not have arrived yet.
if (-not $Attach) {
  $cave = $false
  foreach ($try in 1..3) {
    $script:session = $null
    if (-not (Say-Hello)) { continue }
    $script:seq++
    $port.Write((Frame 'TAP-0000-0000' $script:session $script:seq))
    if (Wait-Reply 'SCREENSHOT' $script:seq 6000) { $cave = $true; break }
  }
  # The daily image now answers TAP too, so a reply is not enough. Only make-t50-auto images carry sheng-autoreset.
  if ($cave) {
    $argsUntil = (Get-Date).AddSeconds(60); $bootArgs = $null
    while (-not $bootArgs -and (Get-Date) -lt $argsUntil) {
      Pump 500
      if (Test-Path $ser) {
        $m = [regex]::Match([IO.File]::ReadAllText($ser), 'boot-args = (\S+)')
        if ($m.Success) { $bootArgs = $m.Groups[1].Value }
      }
    }
    if (-not $bootArgs) { W 'boot-args not seen within 60 s: cannot rule out a fallback' }
    elseif ($bootArgs -notmatch '^sheng-autoreset=') { W "first boot arg is $bootArgs"; $cave = $false }
  }
  if (-not $cave) { $script:session = $null }
  if (-not $cave) {
    W 'FALLBACK: this is boot_b, not the test image; the run does not count'
    $script:backOk = $false
    Send-Reboot
    if ($script:backOk -and $Retries -gt 0) {
      W "retrying, $Retries left"
      & $PSCommandPath -Name $Name -Steps $Steps -Timeout $Timeout -Retries ($Retries - 1)
      exit $LASTEXITCODE
    }
    exit 5
  }
}
foreach ($step in ($Steps -split ';')) {
  $a = @($step.Trim() -split '\s+'); if (-not $a[0]) { continue }
  W ("step: " + $step.Trim())
  switch ($a[0]) {
    'at'    { while (((Get-Date) - $start).TotalSeconds -lt [double]$a[1]) { Pump 300 } }
    'wait'  { Pump ([int]([double]$a[1] * 1000)) }
    'shot'  { Take-Shot $a[1] }
    # A capture without the 24 s transfer: the encoded size and CRC show whether the screen changed.
    'probe' {
      if (-not $script:session) { $null = Say-Hello }
      $script:seq++; $port.Write((Frame 'SCREENSHOT' $script:session $script:seq))
      $r = Wait-Reply 'SCREENSHOT' $script:seq 15000
      if ($r -match 'encoded=(\d+) crc32=(\w+)') { W ("  probe $($a[1]) encoded=$($Matches[1]) crc=$($Matches[2])") } else { W "  probe $($a[1]): $r"; $script:session = $null }
    }
    # Waits until the screen shows real content: the test pattern and boot logo encode far below the lock screen's 60 KB. Boot time varies by a minute.
    'ready' {
      $limit = (Get-Date).AddSeconds([double]$a[1]); $isReady = $false
      while (-not $isReady -and (Get-Date) -lt $limit) {
        if (-not $script:session) { $null = Say-Hello }
        $script:seq++; $port.Write((Frame 'SCREENSHOT' $script:session $script:seq))
        $r = Wait-Reply 'SCREENSHOT' $script:seq 15000
        if ($r -match 'encoded=(\d+)') { if ([int]$Matches[1] -gt 20000) { $isReady = $true } } else { $script:session = $null }
        if (-not $isReady) { Pump 3000 }
      }
      W ("  ready=$isReady after " + [int]((Get-Date) - $start).TotalSeconds + ' s')
    }
    'tap'   { Send-Gesture ('TAP-{0}-{1}' -f (Hex-X $a[1]), (Hex-Y $a[2])) }
    'press' { $d = if ($a.Count -gt 3) { [int]$a[3] } else { 800 }; Send-Gesture ('SWP-{0}-{1}-{0}-{1}-{2:x4}' -f (Hex-X $a[1]), (Hex-Y $a[2]), $d) }
    'swipe' { $d = if ($a.Count -gt 5) { [int]$a[5] } else { 150 }; Send-Gesture ('SWP-{0}-{1}-{2}-{3}-{4:x4}' -f (Hex-X $a[1]), (Hex-Y $a[2]), (Hex-X $a[3]), (Hex-Y $a[4]), $d) }
    'home'  { Send-Gesture ('SWP-{0}-{1}-{0}-{2}-{3:x4}' -f (Hex-X 180), (Hex-Y 792), (Hex-Y 300), 150) }
    default { W "  unknown step $($a[0])" }
  }
}
Pump 500
if ($NoReboot) { try { $port.Close() } catch {} } else { Send-Reboot }
Get-ChildItem "E:\DSH-Fuxi\logs\shot-$label-$stamp-*.bin" -ErrorAction SilentlyContinue | ForEach-Object {
  $p = ($_.FullName -replace '\.bin$', '') -replace '\\', '/' -replace '^E:', '/mnt/e'
  wsl.exe -u root -- python3 -I /mnt/e/DSH-Fuxi/dump/wsl/decode-shot.py $p 2>&1 | ForEach-Object { W "  $_" }
}
if (Test-Path $ser) { Select-String -Path $ser -Pattern 'FUXI120S' | ForEach-Object { W ('  ' + $_.Line.Trim()) } }
W 'done'
