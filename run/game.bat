@echo off
setlocal
pushd "%~dp0.."
set LUAJIT=lib\luajit.exe
set SCRIPT=src\main.lua
set LUA_PATH=src\?.lua;%LUA_PATH%
%LUAJIT% %SCRIPT% %*
set EXIT_CODE=%ERRORLEVEL%
popd
endlocal & exit /b %EXIT_CODE%
