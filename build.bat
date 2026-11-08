@echo off
rem Builds TimeIsnt.exe from clock.asm with the bundled flat assembler.
cd /d "%~dp0"
set "INCLUDE=%~dp0tools\fasm\INCLUDE"
"%~dp0tools\fasm\FASM.EXE" clock.asm TimeIsnt.exe
