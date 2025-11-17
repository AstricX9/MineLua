@echo off
setlocal
set LUAJIT=lib\luajit.exe
set SCRIPT=src\main.lua
set LUA_PATH=src\?.lua
%LUAJIT% %SCRIPT%
endlocal
