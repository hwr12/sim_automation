# ============================================================
# StartupAutomation.ps1 — Sim Automation Framework
# Launches programs in sequence with GUI automation
# Usage: Right-click → "Run with PowerShell" or run from terminal
# ============================================================

# ============================================================
# LAYER 1: WIN32 API BINDINGS (do not edit)
# ============================================================

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Win32 {
    // --- Window Finding ---
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr FindWindowEx(IntPtr hwndParent, IntPtr hwndChildAfter, string lpszClass, string lpszWindow);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hwndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    // --- Window Text ---
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    // --- Window State ---
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    // --- Messages ---
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    // --- Mouse ---
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, IntPtr dwExtraInfo);

    // --- Keyboard ---
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, IntPtr dwExtraInfo);

    // --- Constants ---
    public const uint BM_CLICK        = 0x00F5;
    public const uint WM_CLOSE        = 0x0010;
    public const uint WM_SETTEXT      = 0x000C;
    public const uint WM_GETTEXT      = 0x000D;
    public const int  SW_RESTORE      = 9;
    public const int  SW_SHOW         = 5;
    public const uint MOUSEEVENTF_LEFTDOWN  = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP    = 0x0004;
    public const uint KEYEVENTF_KEYUP       = 0x0002;

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left, Top, Right, Bottom;
    }
}
"@

# ============================================================
# LAYER 2: HELPER FUNCTIONS (do not edit)
# ============================================================

# --- Logging ---
$script:LogPath = "$PSScriptRoot\startup-log.txt"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line -ForegroundColor $(
        switch ($Level) {
            "ERROR"   { "Red" }
            "WARN"    { "Yellow" }
            "SUCCESS" { "Green" }
            default   { "Cyan" }
        }
    )
    $line | Out-File -Append -FilePath $script:LogPath -Encoding UTF8
}

# --- Wait for a window to appear by title (supports partial match) ---
function Wait-ForWindow {
    param(
        [string]$Title,
        [int]$TimeoutSeconds = 30,
        [switch]$Exact
    )
    Write-Log "Waiting for window: '$Title' (timeout: ${TimeoutSeconds}s)"
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        if ($Exact) {
            $hwnd = [Win32]::FindWindow([NullString]::Value, $Title)
            if ($hwnd -ne [IntPtr]::Zero) {
                Write-Log "Found window: '$Title'" "SUCCESS"
                return $hwnd
            }
        } else {
            # Partial match via Get-Process
            $proc = Get-Process | Where-Object { $_.MainWindowTitle -like "*$Title*" } | Select-Object -First 1
            if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
                Write-Log "Found window: '$($proc.MainWindowTitle)'" "SUCCESS"
                return $proc.MainWindowHandle
            }
        }
        Start-Sleep -Milliseconds 500
        $elapsed += 0.5
    }
    Write-Log "Timed out waiting for window: '$Title'" "ERROR"
    return [IntPtr]::Zero
}

# --- Bring a window to the foreground ---
function Focus-Window {
    param([IntPtr]$Handle)
    [Win32]::ShowWindow($Handle, [Win32]::SW_RESTORE) | Out-Null
    [Win32]::SetForegroundWindow($Handle) | Out-Null
    Start-Sleep -Milliseconds 200
}

# --- Find a child control (button, etc.) by its text label ---
function Find-ChildByText {
    param(
        [IntPtr]$ParentHandle,
        [string]$Text,
        [string]$ClassName = $null  # e.g., "Button" to narrow search
    )
    $found = [IntPtr]::Zero
    $callback = [Win32+EnumWindowsProc]{
        param($hWnd, $lParam)
        $len = [Win32]::GetWindowTextLength($hWnd)
        if ($len -gt 0) {
            $sb = New-Object System.Text.StringBuilder ($len + 1)
            [Win32]::GetWindowText($hWnd, $sb, $sb.Capacity) | Out-Null
            $childText = $sb.ToString()
            if ($childText -like "*$Text*") {
                $script:_foundHandle = $hWnd
                return $false  # stop enumerating
            }
        }
        return $true  # continue
    }
    $script:_foundHandle = [IntPtr]::Zero
    [Win32]::EnumChildWindows($ParentHandle, $callback, [IntPtr]::Zero) | Out-Null
    return $script:_foundHandle
}

# --- Click a named button in a window ---
function Click-Button {
    param(
        [IntPtr]$WindowHandle,
        [string]$ButtonText
    )
    Write-Log "Looking for button: '$ButtonText'"
    $btn = Find-ChildByText -ParentHandle $WindowHandle -Text $ButtonText
    if ($btn -ne [IntPtr]::Zero) {
        [Win32]::SendMessage($btn, [Win32]::BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Write-Log "Clicked button: '$ButtonText'" "SUCCESS"
        return $true
    }
    Write-Log "Button '$ButtonText' not found" "ERROR"
    return $false
}

# --- Click at absolute screen coordinates (fallback) ---
function Click-At {
    param([int]$X, [int]$Y)
    Write-Log "Clicking at coordinates ($X, $Y)"
    [Win32]::SetCursorPos($X, $Y) | Out-Null
    Start-Sleep -Milliseconds 50
    [Win32]::mouse_event([Win32]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
    [Win32]::mouse_event([Win32]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 100
}

# --- Click relative to a window's top-left corner ---
function Click-RelativeTo {
    param(
        [IntPtr]$WindowHandle,
        [int]$OffsetX,
        [int]$OffsetY
    )
    $rect = New-Object Win32+RECT
    [Win32]::GetWindowRect($WindowHandle, [ref]$rect) | Out-Null
    $absX = $rect.Left + $OffsetX
    $absY = $rect.Top + $OffsetY
    Write-Log "Clicking relative ($OffsetX, $OffsetY) → absolute ($absX, $absY)"
    Click-At -X $absX -Y $absY
}

# --- Type text into the focused field ---
function Send-Text {
    param([string]$Text)
    Write-Log "Typing text: '$Text'"
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait($Text)
    Start-Sleep -Milliseconds 100
}

# --- Send keyboard shortcuts (e.g., "^s" for Ctrl+S) ---
# Uses SendKeys syntax: ^ = Ctrl, % = Alt, + = Shift
# See: https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.sendkeys
function Send-Keys {
    param([string]$Keys)
    Write-Log "Sending keys: '$Keys'"
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
    Start-Sleep -Milliseconds 100
}

# --- Launch a program and return its process ---
function Launch-Program {
    param(
        [string]$Path,
        [string]$Arguments = "",
        [string]$WorkingDir = ""
    )
    $params = @{ FilePath = $Path; PassThru = $true }
    if ($Arguments -ne "")  { $params.ArgumentList    = $Arguments }
    if ($WorkingDir -ne "") { $params.WorkingDirectory = $WorkingDir }
    return Start-Process @params
}

# ============================================================
# LAYER 3: YOUR AUTOMATION SEQUENCE (edit this)
# ============================================================
#
# Available commands:
#   Launch-Program   -Path "app.exe" -Arguments "args" -WorkingDir "C:\dir"
#   Wait-ForWindow   -Title "Window Name" -TimeoutSeconds 30 [-Exact]
#   Focus-Window     -Handle $hwnd
#   Click-Button     -WindowHandle $hwnd -ButtonText "OK"
#   Click-At         -X 500 -Y 300
#   Click-RelativeTo -WindowHandle $hwnd -OffsetX 100 -OffsetY 50
#   Send-Text        -Text "hello world"
#   Send-Keys        -Keys "^s"           # Ctrl+S
#   Send-Keys        -Keys "%{F4}"        # Alt+F4
#   Send-Keys        -Keys "{ENTER}"      # Enter key
#   Start-Sleep      -Seconds 3
#   Write-Log        -Message "step done" -Level "SUCCESS"
#
# SendKeys syntax reference:
#   ^  = Ctrl      %  = Alt      +  = Shift
#   {ENTER} {TAB} {ESC} {DELETE} {BACKSPACE}
#   {UP} {DOWN} {LEFT} {RIGHT}
#   {F1}..{F12}
# ============================================================

function Run-Automation {
    Write-Log "=== Automation sequence started ==="

    # ---- Step 1: ImmersiveDisplayPRO ----
    Write-Log "--- Step 1: ImmersiveDisplayPRO ---"
    Launch-Program -Path "C:\Users\Public\Desktop\ImmersiveDisplayPRO.lnk"
    $hwnd = Wait-ForWindow -Title "ImmersiveDisplayPRO" -TimeoutSeconds 30
    if ($hwnd -ne [IntPtr]::Zero) {
        Focus-Window -Handle $hwnd
        Start-Sleep -Seconds 2
        # TODO: Add button clicks or interactions here
    }

    Write-Log "=== Automation sequence complete ===" "SUCCESS"
}

# ============================================================
# MAIN
# ============================================================

# Run the automation
Run-Automation

# Keep window open (remove this line if running as startup task)
Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
