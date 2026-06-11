@echo off
REM Launch Claude Code through the local hardened Headroom compression proxy.
REM Plain `claude` is unaffected; use `headroom-claude` for the compressed path.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0headroom-claude.ps1" %*
