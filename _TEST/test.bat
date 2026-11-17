@echo off
setlocal

rem This file is Shift-JIS. Run it under code page 932, then restore the console's code page.
for /f "tokens=2 delims=:." %%A in ('chcp') do set CP=%%A
chcp 932 >nul
call :main %*
set RESULT=%ERRORLEVEL%
chcp %CP% >nul
exit /b %RESULT%

rem 試験（LUX.Tests）を作って走らせる。
rem
rem   test.bat     ソースの文字コードを確かめ、試験を作り（Win64）、走らせ、出力を消す
rem
rem ・出力は、すべて一時フォルダーの下の専用のフォルダーに出し、終わったら消す（ここに dcu・exe を残さない）。
rem ・失敗は、終了コード 1 で返す。
rem ・このファイルは、Shift-JIS・CRLF で保存する。cmd は、バッチを、コンソールのコード ページで読むので、
rem   上で、コード ページを 932 に替えてから、ここから下を読ませている。

:main
rem 開発環境の場所は、その登録から取る
set STUDIO=
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\WOW6432Node\Embarcadero\BDS\37.0" /v RootDir 2^>nul ^| find "RootDir"') do set STUDIO=%%B
if not defined STUDIO echo RAD Studio 37.0 が見つかりません。& exit /b 1
if "%STUDIO:~-1%"=="\" set STUDIO=%STUDIO:~0,-1%
set OUT=%TEMP%\lux-tests
set DCC="%STUDIO%\bin\dcc64.exe" -B -Q "-NSSystem;Winapi;System.Win" "-U%STUDIO%\lib\win64\release" "-E%OUT%" "-NU%OUT%"

cd /d "%~dp0" || goto :fail

if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%" || goto :fail

rem ソースが、UTF-8 の BOM つき・CRLF であることを確かめる
%DCC% SourceCheck.dpr || goto :fail
"%OUT%\SourceCheck.exe" *.dpr *.pas ..\FMX\*.pas ..\Windows\*.pas ..\Thread\*.pas ..\Process\*.pas || goto :fail

rem 試験を作って走らせる
%DCC% LUX.Tests.dpr || goto :fail
"%OUT%\LUX.Tests.exe" || goto :fail

rmdir /s /q "%OUT%"
echo 試験は、すべて通りました。
exit /b 0

:fail
if exist "%OUT%" rmdir /s /q "%OUT%"
echo 失敗しました（理由は、上の出力）。
exit /b 1
