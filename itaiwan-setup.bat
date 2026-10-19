@echo off
chcp 65001 >nul
set "SELF=%~f0"
echo Installing iTaiwan auto-connect...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$c=[IO.File]::ReadAllText($env:SELF,[Text.Encoding]::UTF8); $i=$c.IndexOf('#'+'#PS_START'); Invoke-Expression $c.Substring($i)"
if errorlevel 1 (
  echo.
  echo If you see red error text above, take a screenshot and send it to Claude.
  pause
)
exit /b
##PS_START
# 以下是 PowerShell 安裝程式（上面的批次指令會讀取並執行這一段）

Add-Type -AssemblyName System.Windows.Forms

function Show-Box([string]$text, $icon) {
    [System.Windows.Forms.MessageBox]::Show($text, 'iTaiwan自動連線',
        [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
}

$Worker = @'
# iTaiwan auto-agree
# When connected to the "iTaiwan" Wi-Fi, find the captive portal's agree form and submit it.
# Log and the last portal page are saved under %LOCALAPPDATA%\iTaiwanAutoAgree

param([string]$TargetSsid = 'iTaiwan')

$ErrorActionPreference = 'Continue'
$Dir = Join-Path $env:LOCALAPPDATA 'iTaiwanAutoAgree'
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$Log = Join-Path $Dir 'log.txt'
function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Add-Content -Path $Log -Encoding UTF8 }

# "同意" written as char codes so the file works regardless of encoding
$AgreeZh = "$([char]0x540C)$([char]0x610F)"
$AgreePattern = "$AgreeZh|agree|accept|confirm"

function Get-Ssid {
    $line = netsh wlan show interfaces | Select-String '^\s*SSID\s*:\s*(.+)$' | Select-Object -First 1
    if ($line) { return $line.Matches[0].Groups[1].Value.Trim() }
    return $null
}

function Test-Online {
    try {
        $r = Invoke-WebRequest 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 6 -MaximumRedirection 0 -ErrorAction Stop
        return ($r.Content -eq 'Microsoft Connect Test')
    } catch { return $false }
}

function Get-ResponseUri($r) {
    try { if ($r.BaseResponse.ResponseUri) { return $r.BaseResponse.ResponseUri } } catch {}
    try { if ($r.BaseResponse.RequestMessage.RequestUri) { return $r.BaseResponse.RequestMessage.RequestUri } } catch {}
    return $null
}

function Find-Redirect([string]$html) {
    if ($html -match '(?is)http-equiv\s*=\s*["'']?refresh["'']?[^>]*?url\s*=\s*["'']?([^"''>\s]+)') { return $matches[1] }
    if ($html -match '(?is)(?:window\.|document\.)?location(?:\.href)?\s*=\s*["'']([^"'']+)["'']') { return $matches[1] }
    if ($html -match '(?is)location\.replace\(\s*["'']([^"'']+)["'']') { return $matches[1] }
    return $null
}

function Get-PortalUrl {
    $probe = 'http://www.msftconnecttest.com/redirect'
    try {
        $r = Invoke-WebRequest $probe -UseBasicParsing -TimeoutSec 8 -MaximumRedirection 0 -ErrorAction Stop
        if ($r.Headers.Location) { return [string]$r.Headers.Location }
        $u = Find-Redirect $r.Content
        if ($u) { return $u }
        $ru = Get-ResponseUri $r
        if ($ru -and $ru.Host -notmatch 'msftconnecttest|msn\.com|microsoft') { return $ru.AbsoluteUri }
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            try { $loc = $resp.Headers['Location']; if ($loc) { return [string]$loc } } catch {}
            try { if ($resp.Headers.Location) { return [string]$resp.Headers.Location } } catch {}
        }
    }
    return $null
}

function Get-Attr([string]$tag, [string]$name) {
    $m = [regex]::Match($tag, "(?is)\b$name\s*=\s*(?:""([^""]*)""|'([^']*)'|([^\s>]+))")
    if (-not $m.Success) { return $null }
    foreach ($g in 1..3) { if ($m.Groups[$g].Success) { return [System.Net.WebUtility]::HtmlDecode($m.Groups[$g].Value) } }
    return $null
}

function Submit-AgreeForm([string]$html, [Uri]$baseUri, $session) {
    $forms = [regex]::Matches($html, '(?is)<form\b([^>]*)>(.*?)</form>')
    if ($forms.Count -eq 0) { Log 'No <form> found on portal page.'; return $false }

    $form = $forms | Where-Object { $_.Groups[2].Value -match $AgreePattern } | Select-Object -First 1
    if (-not $form) { $form = $forms[0] }

    $formTag = "<form $($form.Groups[1].Value)>"
    $body = $form.Groups[2].Value
    $action = Get-Attr $formTag 'action'
    $method = Get-Attr $formTag 'method'
    if (-not $method) { $method = 'GET' }
    $target = if ($action) { [Uri]::new($baseUri, $action) } else { $baseUri }

    $fields = [ordered]@{}
    $submitAdded = $false
    foreach ($tag in [regex]::Matches($body, '(?is)<input\b[^>]*>|<button\b[^>]*>.*?</button>')) {
        $t = $tag.Value
        $name = Get-Attr $t 'name'
        if (-not $name) { continue }
        $type = (Get-Attr $t 'type'); if (-not $type) { $type = if ($t -match '^(?i)<button') { 'submit' } else { 'text' } }
        $value = Get-Attr $t 'value'
        switch -regex ($type.ToLower()) {
            '^(submit|image|button)$' {
                # include only the agree button (or the first submit if nothing matches)
                if (-not $submitAdded -and ($t -match $AgreePattern)) {
                    $fields[$name] = if ($null -ne $value) { $value } else { '' }; $submitAdded = $true
                }
            }
            '^(checkbox|radio)$' {
                # tick agree checkboxes; keep other boxes only if pre-checked
                if ($t -match $AgreePattern -or $name -match 'agree|accept|terms|policy|rule' -or $t -match '(?i)\bchecked\b') {
                    $fields[$name] = if ($null -ne $value) { $value } else { 'on' }
                }
            }
            default { $fields[$name] = if ($null -ne $value) { $value } else { '' } }
        }
    }

    Log "Submitting $($method.ToUpper()) $target with fields: $($fields.Keys -join ', ')"
    try {
        if ($method -match '(?i)post') {
            $r = Invoke-WebRequest $target -Method Post -Body $fields -WebSession $session -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        } else {
            $r = Invoke-WebRequest $target -Method Get -Body $fields -WebSession $session -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        }
        $r.Content | Set-Content -Path (Join-Path $Dir 'after-submit.html') -Encoding UTF8
        return $true
    } catch {
        Log "Submit failed: $($_.Exception.Message)"
        return $false
    }
}

# ---- main ----
Start-Sleep -Seconds 3   # give DHCP a moment
$ssid = Get-Ssid
if ($ssid -ne $TargetSsid) { exit 0 }
Log "Connected to $ssid"

for ($i = 1; $i -le 5; $i++) {
    if (Test-Online) { Log 'Internet is reachable. Done.'; exit 0 }

    $portal = Get-PortalUrl
    if (-not $portal) { Log "Attempt ${i}: portal URL not found yet."; Start-Sleep -Seconds 3; continue }
    Log "Attempt ${i}: portal = $portal"

    try {
        $page = Invoke-WebRequest $portal -UseBasicParsing -SessionVariable sess -TimeoutSec 10 -ErrorAction Stop
        $html = $page.Content
        $base = Get-ResponseUri $page; if (-not $base) { $base = [Uri]$portal }
        # follow one level of meta/JS redirect if the page has no form
        if ($html -notmatch '(?i)<form') {
            $next = Find-Redirect $html
            if ($next) {
                $nextUri = [Uri]::new($base, $next)
                $page = Invoke-WebRequest $nextUri -UseBasicParsing -WebSession $sess -TimeoutSec 10 -ErrorAction Stop
                $html = $page.Content
                $base = Get-ResponseUri $page; if (-not $base) { $base = $nextUri }
            }
        }
        $html | Set-Content -Path (Join-Path $Dir 'portal.html') -Encoding UTF8
        Submit-AgreeForm $html $base $sess | Out-Null
    } catch {
        Log "Attempt ${i}: error loading portal: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 3
}

if (Test-Online) { Log 'Internet is reachable. Done.' } else { Log 'Still offline after 5 attempts. See portal.html.' }
'@

try {
    $ErrorActionPreference = 'Stop'
    $Dir  = Join-Path $env:LOCALAPPDATA 'iTaiwanAutoAgree'
    $Dest = Join-Path $Dir 'itaiwan-auto-agree.ps1'

    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    [IO.File]::WriteAllText($Dest, $Worker, (New-Object System.Text.UTF8Encoding $true))

    # 觸發條件：NetworkProfile 事件 10000 =「已連上網路」
    $class = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
    $trigger = New-CimInstance -CimClass $class -ClientOnly
    $trigger.Enabled = $true
    $trigger.Subscription = '<QueryList><Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"><Select Path="Microsoft-Windows-NetworkProfile/Operational">*[System[(EventID=10000)]]</Select></Query></QueryList>'

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Dest`""

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    Register-ScheduledTask -TaskName 'iTaiwanAutoAgree' -Trigger $trigger -Action $action `
        -Settings $settings -Description 'Auto-accept the iTaiwan Wi-Fi terms page' -Force | Out-Null

    $task = Get-ScheduledTask -TaskName 'iTaiwanAutoAgree' -ErrorAction Stop

    Show-Box ("安裝完成！`n`n" +
              "之後每次連上 iTaiwan，都會在背景自動按下「同意」。`n`n" +
              "排程狀態：$($task.State)`n" +
              "紀錄檔位置：$Dir\log.txt`n`n" +
              "若要移除，請在 PowerShell 執行：`n" +
              'Unregister-ScheduledTask -TaskName iTaiwanAutoAgree -Confirm:$false') `
             ([System.Windows.Forms.MessageBoxIcon]::Information)
}
catch {
    Show-Box ("安裝失敗：`n`n$($_.Exception.Message)`n`n" +
              "如果訊息提到「存取被拒」，請在檔案上按右鍵，選「以系統管理員身分執行」。") `
             ([System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}
