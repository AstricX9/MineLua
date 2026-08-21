@echo off
setlocal
set VSWHERE=C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe

if not exist "%VSWHERE%" (
  echo Visual Studio Installer was not found.
  exit /b 1
)

for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set VSROOT=%%i
if not defined VSROOT (
  echo Visual C++ build tools were not found.
  exit /b 1
)

call "%VSROOT%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1

cmake -S native\imgui_bridge -B build\imgui_bridge -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release
if errorlevel 1 exit /b 1
cmake --build build\imgui_bridge --config Release
exit /b %errorlevel%
