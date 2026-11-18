@echo off
rem Adds "Open cool-retro-term here" to the Explorer context menu: right-click
rem on a folder, on empty space inside a folder, or on a drive.  It opens a
rem window of wezterm-gui.exe from this folder in the clicked folder.
rem
rem Per user (HKCU): no administrator rights needed.  Run it again after
rem moving this folder.  context-menu-remove.bat takes the entries away.
rem An existing "cool-retro-term" entry (the Qt version) is replaced.
rem
rem   context-menu-add.bat      add, then wait for a key
rem   context-menu-add.bat /q   add, no pause
setlocal
set "EXE=%~dp0wezterm-gui.exe"
set "ICON=%~dp0cool-retro-term.ico"
set "LABEL=Open cool-retro-term here"
if not exist "%EXE%" goto missing

rem %V is the clicked folder.  "%V." keeps a drive root ("C:\") from ending
rem in \" (an escaped quote); Windows drops the trailing dot.
set "CMD=\"%EXE%\" start --cwd \"%%V.\""

call :entry "HKCU\Software\Classes\Directory\shell\cool-retro-term" || goto failed
call :entry "HKCU\Software\Classes\Directory\Background\shell\cool-retro-term" || goto failed
call :entry "HKCU\Software\Classes\Drive\shell\cool-retro-term" || goto failed

echo Added "%LABEL%" to the Explorer context menu:
echo   "%EXE%" start --cwd "%%V."
goto done

:entry
reg add "%~1" /ve /d "%LABEL%" /f >nul || exit /b 1
reg add "%~1" /v Icon /d "\"%ICON%\"" /f >nul || exit /b 1
reg add "%~1\command" /ve /d "%CMD%" /f >nul || exit /b 1
exit /b 0

:missing
echo wezterm-gui.exe was not found next to this file:
echo   %EXE%
goto done

:failed
echo Could not write the registry entries.

:done
if /i not "%~1"=="/q" pause
