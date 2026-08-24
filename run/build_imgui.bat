@echo off
setlocal
pushd "%~dp0.."
set VSWHERE=C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe

if not exist "%VSWHERE%" (
  echo Visual Studio Installer was not found.
  set EXIT_CODE=1
  goto :finish
)

for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set VSROOT=%%i
if not defined VSROOT (
  echo Visual C++ build tools were not found.
  set EXIT_CODE=1
  goto :finish
)

call "%VSROOT%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 (
  set EXIT_CODE=1
  goto :finish
)

cmake -S native\imgui_bridge -B build\imgui_bridge -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release
if errorlevel 1 (
  set EXIT_CODE=1
  goto :finish
)
cmake --build build\imgui_bridge --config Release
set EXIT_CODE=%ERRORLEVEL%

:finish
popd
endlocal & exit /b %EXIT_CODE%
