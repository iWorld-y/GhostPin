@echo off
setlocal
cd /d "%~dp0"
set "VSDEVCMD="
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%VSWHERE%" (
    for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSINSTALL=%%I"
    if defined VSINSTALL set "VSDEVCMD=%VSINSTALL%\Common7\Tools\VsDevCmd.bat"
)
if not defined VSDEVCMD set "VSDEVCMD=%ProgramFiles(x86)%\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEVCMD%" set "VSDEVCMD=%ProgramFiles%\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEVCMD%" (
    echo 未找到带 C++ 工具链的 Visual Studio。 1>&2
    exit /b 10
)
call "%VSDEVCMD%" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b 10
set "CMAKE=C:\Users\lance\AppData\Local\Microsoft\WinGet\Links\cmake.exe"
set "CTEST=C:\Users\lance\AppData\Local\Microsoft\WinGet\Links\ctest.exe"
if not exist "%CMAKE%" set "CMAKE=cmake"
if not exist "%CTEST%" set "CTEST=ctest"
"%CMAKE%" -S . -B build-stage1 -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release
if errorlevel 1 exit /b 20
"%CMAKE%" --build build-stage1
if errorlevel 1 exit /b 30
"%CTEST%" --test-dir build-stage1 --output-on-failure
if errorlevel 1 exit /b 40
exit /b 0
