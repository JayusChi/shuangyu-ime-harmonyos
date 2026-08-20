@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ohos-clang-linker.ps1" -Abi x86_64 -- %*
