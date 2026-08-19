[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$versionPath = Join-Path $root "script/VERSION"
$projectPath = Join-Path $root "windows/src/GhostPin.Windows.App/GhostPin.Windows.App.csproj"
$iconPath = Join-Path $root "windows/src/GhostPin.Windows.App/Assets/GhostPin.ico"
$distPath = Join-Path $root "dist"
$publishPath = Join-Path ([System.IO.Path]::GetTempPath()) ("GhostPin-Windows-Publish-" + [Guid]::NewGuid().ToString("N"))
$finalName = ""
$finalPath = ""

try {
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
        throw "Version file not found: $versionPath"
    }
    if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
        throw "Windows project not found: $projectPath"
    }
    if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
        throw "Windows application icon not found: $iconPath"
    }

    $version = (Get-Content -Raw -LiteralPath $versionPath).Trim()
    if ($version -notmatch '^\d+\.\d+\.\d+$') {
        throw "script/VERSION must contain a three-part numeric version; actual: $version"
    }

    $assemblyVersion = "$version.0"
    $finalName = "GhostPin-$version-windows-x64.exe"
    $finalPath = Join-Path $distPath $finalName

    if (Test-Path -LiteralPath $distPath) {
        Remove-Item -LiteralPath $distPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $distPath -Force | Out-Null
    New-Item -ItemType Directory -Path $publishPath -Force | Out-Null

    $publishArguments = @(
        $projectPath,
        "--configuration", $Configuration,
        "--runtime", "win-x64",
        "--self-contained", "true",
        "--output", $publishPath,
        "-p:PublishSingleFile=true",
        "-p:IncludeNativeLibrariesForSelfExtract=true",
        "-p:EnableCompressionInSingleFile=true",
        "-p:PublishTrimmed=false",
        "-p:DebugType=None",
        "-p:DebugSymbols=false",
        "-p:NuGetAudit=false",
        "-p:Version=$version",
        "-p:VersionPrefix=$version",
        "-p:AssemblyVersion=$assemblyVersion",
        "-p:FileVersion=$assemblyVersion",
        "-p:InformationalVersion=$version",
        "-p:IncludeSourceRevisionInInformationalVersion=false",
        "-p:Product=GhostPin"
    )

    Write-Host "Publishing GhostPin Windows $version ($Configuration)..."
    & dotnet publish @publishArguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE"
    }

    $publishedExecutables = @(Get-ChildItem -LiteralPath $publishPath -Filter "GhostPin.Windows.App.exe" -File -Recurse)
    if ($publishedExecutables.Count -ne 1) {
        throw "Expected one GhostPin.Windows.App.exe in publish output; actual: $($publishedExecutables.Count)"
    }
    if (@(Get-ChildItem -LiteralPath $publishPath -Filter "*.pdb" -File -Recurse).Count -ne 0) {
        throw "Publish output must not contain debug symbol files."
    }

    Copy-Item -LiteralPath $publishedExecutables[0].FullName -Destination $finalPath -Force

    $distEntries = @(Get-ChildItem -LiteralPath $distPath -Force)
    if ($distEntries.Count -ne 1 -or $distEntries[0].PSIsContainer -or $distEntries[0].Name -ne $finalName) {
        throw "dist must contain only $finalName"
    }

    $stream = [System.IO.File]::OpenRead($finalPath)
    try {
        if ($stream.ReadByte() -ne 0x4D -or $stream.ReadByte() -ne 0x5A) {
            throw "Artifact is not a valid PE executable: $finalName"
        }
    }
    finally {
        $stream.Dispose()
    }

    Add-Type -AssemblyName System.Drawing
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($finalPath)
    if ($null -eq $icon) {
        throw "Unable to read the application icon from: $finalName"
    }
    $icon.Dispose()

    $versionInfo = (Get-Item -LiteralPath $finalPath).VersionInfo
    $versionPattern = "^$([regex]::Escape($version))(\.0)?$"
    if ($versionInfo.FileVersion -notmatch $versionPattern) {
        throw "File version mismatch: $($versionInfo.FileVersion); expected $version"
    }
    if ($versionInfo.ProductVersion -notmatch $versionPattern) {
        throw "Product version mismatch: $($versionInfo.ProductVersion); expected $version"
    }
    if ($versionInfo.ProductName -ne "GhostPin") {
        throw "Product name mismatch: $($versionInfo.ProductName)"
    }

    Remove-Item -LiteralPath $publishPath -Recurse -Force
    Write-Host "Created $finalPath"
    Write-Host "Version: $($versionInfo.ProductVersion)"
    Write-Host "Icon: $iconPath"
}
catch {
    if ($finalPath -and (Test-Path -LiteralPath $finalPath)) {
        Remove-Item -LiteralPath $finalPath -Force -ErrorAction SilentlyContinue
    }
    if ($publishPath -and (Test-Path -LiteralPath $publishPath)) {
        Remove-Item -LiteralPath $publishPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Error $_.Exception.Message
    exit 1
}
