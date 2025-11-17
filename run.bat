@echo off
setlocal
set LUAJIT=lib\luajit.exe
set SCRIPT=src\main.lua
set LUA_PATH=src\?.lua;%LUA_PATH%
%LUAJIT% %SCRIPT%
endlocal
