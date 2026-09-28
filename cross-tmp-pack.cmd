@echo off
rem pack script: electron binary via npmmirror.
rem Temp dir must be on the SAME VOLUME as the project (cross-volume rename -> EPERM) but OUTSIDE the
rem project tree: file watchers (editor / antivirus / agent sandbox) keep handles on files inside the
rem project, which makes the rename of the freshly extracted Electron template fail with EPERM.
set TMP=%~dp0..\qiubar-packtmp
set TEMP=%~dp0..\qiubar-packtmp
if not exist "%~dp0..\qiubar-packtmp" mkdir "%~dp0..\qiubar-packtmp"
set ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
call npx electron-packager . QiuBar --platform=win32 --arch=x64 --out=dist --overwrite --icon=icon.ico --no-asar --ignore=^/data --ignore=^/make-icon.ps1 --ignore=^/\.npmrc --ignore=^/\.tmp
rem fail loudly: silently continuing left a stale dist with a half-applied prune once
if errorlevel 1 echo [ERROR] electron-packager failed - is a QiuBar.exe still running and locking dist ?
if errorlevel 1 exit /b 1
rem NOTE: do NOT add --ignore for the out dir. cmd eats the "^", turning ^/dist into an
rem unanchored /dist regex that also deletes node_modules/**/dist (broke gsap.min.js once).
rem electron-packager already auto-ignores the resolved --out directory.

rem prune locales: keep only zh-CN + en-US, saves ~46MB (Electron's official recommendation)
rem single-line for / pushd form on purpose: multi-line parenthesised blocks are fragile under LF endings
@pushd "%~dp0dist\QiuBar-win32-x64\locales"
for %%f in (*.pak) do @if /i not "%%~nxf"=="zh-CN.pak" if /i not "%%~nxf"=="en-US.pak" del /q "%%f"
@popd

rem tidy up: packager leaves the extracted Electron template behind, ~500MB per run
if exist "%~dp0..\qiubar-packtmp" rd /s /q "%~dp0..\qiubar-packtmp" >nul 2>&1
