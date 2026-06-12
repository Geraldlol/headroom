@echo off
REM Launch Claude Code through the local Headroom compression proxy WITH
REM /remote-control still working (forward proxy via HTTPS_PROXY).
REM Plain `claude` and `headroom-claude` are both unaffected.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0headroom-claude-rc.ps1" %*
