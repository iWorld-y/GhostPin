[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$versionPath = Join-Path $root "script/VERSION"
$buildScript = Join-Path $root "windows-native/build_stage1.cmd"
$nativeExe = Join-Path $root "windows-native/build-stage1/GhostPin.Native.exe"
$distPath = Join-Path $root "dist"

if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
    throw "Version file not found: $versionPath"
}
if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
    throw "Native build script not found: $buildScript"
}

$version = (Get-Content -Raw -LiteralPath $versionPath).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "script/VERSION must contain a three-part numeric version; actual: $version"
}

& $buildScript
if ($LASTEXITCODE -ne 0) {
    throw "Rust native build failed with exit code $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $nativeExe -PathType Leaf)) {
    throw "Native executable not found: $nativeExe"
}

$finalName = "GhostPin-$version-windows-x64.exe"
$finalPath = Join-Path $distPath $finalName
if (Test-Path -LiteralPath $distPath) {
    Remove-Item -LiteralPath $distPath -Recurse -Force
}
New-Item -ItemType Directory -Path $distPath -Force | Out-Null
Copy-Item -LiteralPath $nativeExe -Destination $finalPath -Force

$stream = [System.IO.File]::OpenRead($finalPath)
try {
    if ($stream.ReadByte() -ne 0x4D -or $stream.ReadByte() -ne 0x5A) {
        throw "Artifact is not a valid PE executable: $finalName"
    }
}
finally {
    $stream.Dispose()
}

$distEntries = @(Get-ChildItem -LiteralPath $distPath -Force)
if ($distEntries.Count -ne 1 -or $distEntries[0].PSIsContainer -or $distEntries[0].Name -ne $finalName) {
    throw "dist must contain only $finalName"
}
Write-Host "Created $finalPath"
