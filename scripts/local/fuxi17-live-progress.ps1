$Host.UI.RawUI.WindowTitle = '小米13 iPadOS 17 USB — 本地编译实时进度'
$buildRoot = '\\wsl.localhost\Ubuntu-26.04\home\xiaomi\fuxi17-usb-local-20261102'
$stateFile = 'F:\UniXNU-FUXI-work\fuxi17-live-state.txt'
function Read-LogTail([string]$FilePath) {
    $stream = $null
    try {
        $stream = [IO.File]::Open($FilePath, 'Open', 'Read', 'ReadWrite')
        $offset = [Math]::Max(0, $stream.Length - 16384)
        [void]$stream.Seek($offset, 'Begin')
        $buffer = New-Object byte[] 16384
        $count = $stream.Read($buffer, 0, $buffer.Length)
        $lines = [Text.Encoding]::UTF8.GetString($buffer, 0, $count) -split '\r?\n'
        if ($offset -gt 0 -and $lines.Length -gt 1) { $lines = $lines[1..($lines.Length - 1)] }
        $lines | Select-Object -Last 24 | ForEach-Object {
            $width = [Math]::Max(80, $Host.UI.RawUI.WindowSize.Width - 2)
            if ($_.Length -gt $width) { $_.Substring(0, $width) } else { $_ }
        }
    } catch { '等待日志更新：' + $_.Exception.Message }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}
while ($true) {
    Clear-Host
    Write-Host '小米13 / fuxi / iPadOS 17.7.11 (21H461)' -ForegroundColor Cyan
    Write-Host ('更新时间：' + (Get-Date -Format 'HH:mm:ss'))
    if (Test-Path -LiteralPath $stateFile) {
        Write-Host (Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8) -ForegroundColor Yellow
    }
    Write-Host '已通过：参考内核、根卷策略、USB 模型与六文件集成测试、GPU 归档' -ForegroundColor Green
    if (Test-Path -LiteralPath "$buildRoot\UniXNU\out\fuxi17-usb\linked-usb.json") {
        Write-Host '完整 USB 内核已生成并通过符号检查，实机验证待进行。' -ForegroundColor Green
    } else {
        Write-Host '最终内核未通过完成检查前，请勿把参考内核用于启动。'
    }
    try {
        $candidates = @(
            Get-ChildItem -LiteralPath $buildRoot -Filter '*.log' -File -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath "$buildRoot\UniXNU\out\fuxi\logs" -Filter '*.log' -File -ErrorAction SilentlyContinue
        )
        $latest = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($null -ne $latest) {
            Write-Host ('当前日志：' + $latest.Name + '  /  写入 ' + $latest.LastWriteTime.ToString('HH:mm:ss')) -ForegroundColor Cyan
            Write-Host ('-' * 70)
            Read-LogTail $latest.FullName
        } else { Write-Host '等待日志文件……' }
    } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    Write-Host "`n每 2 秒自动刷新。关闭此窗口不会停止编译。" -ForegroundColor DarkGray
    Start-Sleep -Seconds 2
}
