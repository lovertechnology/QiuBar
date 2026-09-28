@echo off
rem pack script: stage temp on same drive (cross-volume rename is blocked), electron binary via npmmirror
set TMP=%~dp0.tmp
set TEMP=%~dp0.tmp
set ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
call npx electron-packager . QiuBar --platform=win32 --arch=x64 --out=dist --overwrite --icon=icon.ico --no-asar --ignore=^/data --ignore=^/make-icon.ps1 --ignore=^/\.npmrc --ignore=^/\.tmp
rem NOTE: do NOT add --ignore for the out dir. cmd eats the "^", turning ^/dist into an
rem unanchored /dist regex that also deletes node_modules/**/dist (broke gsap.min.js once).
rem electron-packager already auto-ignores the resolved --out directory.
