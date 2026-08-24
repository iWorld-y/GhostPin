@echo off
setlocal
cd /d C:\Users\lance\source\GhostPin-native-win32\windows-native
call "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b 10
set "CMAKE=C:\Users\lance\AppData\Local\Microsoft\WinGet\Links\cmake.exe"
set "CTEST=C:\Users\lance\AppData\Local\Microsoft\WinGet\Links\ctest.exe"
"%CMAKE%" -S . -B build-stage1 -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release
if errorlevel 1 exit /b 20
"%CMAKE%" --build build-stage1
if errorlevel 1 exit /b 30
"%CTEST%" --test-dir build-stage1 --output-on-failure
if errorlevel 1 exit /b 40
exit /b 0
