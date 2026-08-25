@echo off
setlocal
pushd "%~dp0"

set "VSDEVCMD=%ProgramFiles(x86)%\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEVCMD%" set "VSDEVCMD=%ProgramFiles%\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEVCMD%" (
    echo 未找到带 MSVC 与 Windows SDK 的 Visual Studio >&2
    popd
    exit /b 10
)
call "%VSDEVCMD%" -arch=x64 -host_arch=x64 >NUL
if errorlevel 1 (
    popd
    exit /b 10
)

set "CARGO=%USERPROFILE%\.cargo\bin\cargo.exe"
if not exist "%CARGO%" set "CARGO=cargo"
"%CARGO%" build --manifest-path "%~dp0Cargo.toml" --release
if errorlevel 1 (
    popd
    exit /b 20
)

if not exist "%~dp0build-stage1" mkdir "%~dp0build-stage1"
copy /Y "%~dp0target\release\ghostpin-native.exe" "%~dp0build-stage1\GhostPin.Native.exe" >NUL
if errorlevel 1 (
    popd
    exit /b 30
)
echo Rust 原生 Release 已生成：%~dp0build-stage1\GhostPin.Native.exe
popd
exit /b 0
