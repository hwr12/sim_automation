# Sim Automation — Startup Script Design

**Date:** 2026-03-02
**Approach:** Pure PowerShell + Win32 API (no external dependencies)

## Goal

A single PowerShell script that runs on Windows startup, launches simulation tools in sequence, and automates GUI interactions (clicking buttons, typing text, sending keystrokes).

## Architecture

Three layers in a single `.ps1` file:

### 1. Win32 API Layer
P/Invoke bindings to `user32.dll`:
- `FindWindow` / `FindWindowEx` — locate windows and child controls
- `SendMessage` — click buttons, read text
- `SetForegroundWindow` — bring windows to front
- `SetCursorPos` / `mouse_event` — coordinate-based mouse clicks
- `keybd_event` — keyboard input

### 2. Helper Functions
User-friendly wrappers:
- `Wait-ForWindow "Title"` — polls until a window appears (with timeout)
- `Click-Button "ButtonName"` — finds and clicks a named button in active window
- `Click-At X Y` — clicks at screen coordinates (fallback)
- `Send-Text "text"` — types a string into the focused field
- `Send-Keys "shortcut"` — sends keyboard shortcuts (e.g., Ctrl+S)
- `Write-Log "message"` — timestamped logging

### 3. Automation Sequence
Config-driven step list. Each step is one of:
- `Launch` — start a program with optional args
- `WaitWindow` — wait for a window title to appear
- `ClickButton` — click a named button
- `ClickAt` — click at coordinates
- `SendText` — type text
- `SendKeys` — keyboard shortcut
- `Delay` — wait N seconds

## Startup Registration

Uses Windows Task Scheduler (`Register-ScheduledTask`) to run at user logon. Included as a helper function in the script, run once to register.

## File Structure

```
sim_automation/
  StartupAutomation.ps1   — main script
  startup-log.txt          — runtime log (auto-generated)
  docs/plans/
    2026-03-02-sim-automation-design.md
```

## Trade-offs

- Win32 API works well for standard Windows controls; Electron/web-based UIs may need coordinate-based fallback
- Single file keeps it simple but means all config is inline (acceptable for personal automation)
- Task Scheduler is more reliable than Startup folder for logon triggers
