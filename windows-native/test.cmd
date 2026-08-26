@echo off
setlocal
pushd "%~dp0"

set "VSDEVCMD=%ProgramFiles(x86)%\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEVCMD%" set "VSDEVCMD=%ProgramFiles%\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEVCMD%" set "VSDEVCMD=%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEVCMD%" set "VSDEVCMD=%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"
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
"%CARGO%" test --manifest-path "%~dp0Cargo.toml"
if errorlevel 1 (
    popd
    exit /b 20
)
"%CARGO%" run --manifest-path "%~dp0Cargo.toml" --bin ghostpin-native-core-checks
if errorlevel 1 (
    popd
    exit /b 30
)
popd
exit /b 0
