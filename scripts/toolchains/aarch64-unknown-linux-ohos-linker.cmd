@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ohos-clang-linker.ps1" -Abi arm64-v8a -- %*
