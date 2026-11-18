@echo off
rem Removes the "Open cool-retro-term here" entries from the Explorer context
rem menu (folders, folder background, drives) that context-menu-add.bat adds.
rem
rem   context-menu-remove.bat      remove, then wait for a key
rem   context-menu-remove.bat /q   remove, no pause
setlocal
for %%K in (Directory Directory\Background Drive) do reg delete "HKCU\Software\Classes\%%K\shell\cool-retro-term" /f >nul 2>&1
echo Removed "Open cool-retro-term here" from the Explorer context menu.
if /i not "%~1"=="/q" pause
