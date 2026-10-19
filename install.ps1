# 安裝 iTaiwan 自動同意腳本，並建立「每次連上網路就執行」的排程工作。
# 使用方式：在此檔案上按右鍵 -> 「用 PowerShell 執行」

Add-Type -AssemblyName System.Windows.Forms

function Show-Box([string]$text, [string]$title, $icon) {
    [System.Windows.Forms.MessageBox]::Show($text, $title,
        [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
}

try {
    $ErrorActionPreference = 'Stop'
    $Dir  = Join-Path $env:LOCALAPPDATA 'iTaiwanAutoAgree'
    $Dest = Join-Path $Dir 'itaiwan-auto-agree.ps1'
    $Src  = Join-Path $PSScriptRoot 'itaiwan-auto-agree.ps1'

    if (-not (Test-Path $Src)) {
        throw "找不到 itaiwan-auto-agree.ps1。請確認它和 install.ps1 放在同一個資料夾。`n（目前資料夾：$PSScriptRoot）"
    }

    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    Copy-Item -Path $Src -Destination $Dest -Force
    Unblock-File -Path $Dest -ErrorAction SilentlyContinue

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

    # 確認排程真的建立了
    $task = Get-ScheduledTask -TaskName 'iTaiwanAutoAgree' -ErrorAction Stop

    Show-Box ("安裝完成！`n`n" +
              "之後每次連上 iTaiwan，都會在背景自動按下「同意」。`n`n" +
              "排程狀態：$($task.State)`n" +
              "紀錄檔位置：$Dir\log.txt`n`n" +
              "若要移除，請在 PowerShell 執行：`n" +
              'Unregister-ScheduledTask -TaskName iTaiwanAutoAgree -Confirm:$false') `
             'iTaiwan 自動同意' ([System.Windows.Forms.MessageBoxIcon]::Information)
}
catch {
    Show-Box ("安裝失敗：`n`n$($_.Exception.Message)`n`n" +
              "如果訊息提到「存取被拒」，請改用系統管理員身分開啟 PowerShell 再執行一次。") `
             'iTaiwan 自動同意' ([System.Windows.Forms.MessageBoxIcon]::Error)
}
