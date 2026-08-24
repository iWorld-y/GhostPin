$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$exePath = Join-Path $scriptRoot "..\build-stage1\GhostPin.Native.PlatformChecks.exe"
$exePath = (Resolve-Path -LiteralPath $exePath).Path
$tempRoot = Join-Path $env:TEMP ("GhostPin.Native.PlatformChecks-" + [guid]::NewGuid().ToString("N"))
$stdoutPath = Join-Path $tempRoot "stdout.txt"
$stderrPath = Join-Path $tempRoot "stderr.txt"
$exitCodePath = Join-Path $tempRoot "exitcode.txt"
$runnerPath = Join-Path $tempRoot "run.cmd"
$taskName = "GhostPin.Native.PlatformChecks." + [guid]::NewGuid().ToString("N")
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$runnerText = "@echo off" + [Environment]::NewLine
$runnerText += '"' + $exePath + '" 1>"' + $stdoutPath + '" 2>"' + $stderrPath + '"' + [Environment]::NewLine
$runnerText += 'echo %ERRORLEVEL%>"' + $exitCodePath + '"' + [Environment]::NewLine
Set-Content -LiteralPath $runnerPath -Value $runnerText -Encoding ASCII

try {
    $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument ('/d /c "{0}"' -f $runnerPath)
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(3)
    $principal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName

    $deadline = (Get-Date).AddSeconds(45)
    while (-not (Test-Path -LiteralPath $exitCodePath) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }
    if (-not (Test-Path -LiteralPath $exitCodePath)) {
        throw "Interactive PlatformChecks did not finish before timeout"
    }

    $exitCode = [int](Get-Content -LiteralPath $exitCodePath | Select-Object -First 1)
    Write-Output "stdout:"
    if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath }
    Write-Output "stderr:"
    if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath }
    Write-Output ("exitcode: {0}" -f $exitCode)
    exit $exitCode
}
finally {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
