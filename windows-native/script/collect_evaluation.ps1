param(
    [Parameter(Mandatory = $true)]
    [string]$NativeExe,
    [Parameter(Mandatory = $true)]
    [string]$WpfExe,
    [string]$WpfPublishDir,
    [ValidateRange(1, 20)]
    [int]$Samples = 3,
    [ValidateRange(1, 60)]
    [int]$WarmupSeconds = 2,
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\docs\windows-native-evaluation-samples.json")
)

$ErrorActionPreference = "Stop"

function Resolve-ExistingPath([string]$Path) {
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-ArtifactSummary([string]$ExePath, [string]$PublishDir) {
    $exe = Get-Item -LiteralPath $ExePath
    $directory = if ($PublishDir) {
        Get-Item -LiteralPath $PublishDir
    } else {
        $exe.Directory
    }
    $files = @(Get-ChildItem -LiteralPath $directory.FullName -File)
    return [ordered]@{
        executable = $exe.FullName
        bytes = [int64]$exe.Length
        publishDirectory = $directory.FullName
        fileCount = $files.Count
    }
}

function Measure-Launch([string]$ExePath, [int]$Warmup) {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $ExePath -PassThru
    $ready = $false
    $readyMs = $null
    $deadline = (Get-Date).AddSeconds(15)
    try {
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 100
            $process.Refresh()
            if ($process.HasExited) {
                break
            }
            if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
                $ready = $true
                $readyMs = $watch.ElapsedMilliseconds
                break
            }
        }
        if (-not $ready -and -not $process.HasExited) {
            # Tray-only windows may not expose MainWindowHandle; record the fallback explicitly.
            $readyMs = $watch.ElapsedMilliseconds
        }
        if (-not $process.HasExited) {
            Start-Sleep -Seconds $Warmup
            $process.Refresh()
        }
        $workingSet = if ($process.HasExited) { $null } else { [int64]$process.WorkingSet64 }
        return [ordered]@{
            pid = $process.Id
            exitedDuringStartup = $process.HasExited
            readyWindowDetected = $ready
            startupMs = $readyMs
            workingSetBytes = $workingSet
        }
    }
    finally {
        if (-not $process.HasExited) {
            $process.CloseMainWindow() | Out-Null
            if (-not $process.WaitForExit(2000)) {
                $process.Kill()
                $process.WaitForExit()
            }
        }
        $process.Dispose()
    }
}

$nativePath = Resolve-ExistingPath $NativeExe
$wpfPath = Resolve-ExistingPath $WpfExe
$nativeSummary = Get-ArtifactSummary $nativePath $null
$wpfSummary = Get-ArtifactSummary $wpfPath $WpfPublishDir
$samples = @()
for ($index = 1; $index -le $Samples; $index++) {
    $samples += [ordered]@{
        index = $index
        native = Measure-Launch $nativePath $WarmupSeconds
        wpf = Measure-Launch $wpfPath $WarmupSeconds
    }
}

$result = [ordered]@{
    collectedAt = (Get-Date).ToUniversalTime().ToString("o")
    computer = $env:COMPUTERNAME
    os = (Get-CimInstance Win32_OperatingSystem).Caption
    powershell = $PSVersionTable.PSVersion.ToString()
    samples = $Samples
    warmupSeconds = $WarmupSeconds
    native = $nativeSummary
    wpf = $wpfSummary
    launches = $samples
}
$parent = Split-Path -Parent $OutputPath
if ($parent) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output (ConvertTo-Json $result -Depth 6)
