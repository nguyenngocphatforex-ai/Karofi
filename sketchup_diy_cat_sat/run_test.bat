@echo off
chcp 65001 >nul
rem Chep plugin + test vao C:\diy_test, chay SketchUp 2023, in log.
set "SRC=%~dp0"
if not exist C:\diy_test mkdir C:\diy_test
copy /Y "%SRC%diy_cat_sat.rb" C:\diy_test\ >nul
copy /Y "%SRC%test.rb" C:\diy_test\ >nul
set DIY_AUTOQUIT=1
start "" /wait "C:\Program Files\SketchUp\SketchUp 2023\SketchUp.exe" -RubyStartup C:\diy_test\test.rb
type C:\diy_test\log.txt
pause
