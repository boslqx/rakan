Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public struct RECT { public int L, T, R, B; }
}
"@
$out = Join-Path $PSScriptRoot 'move_log.txt'
"==== $(Get-Date)" | Out-File $out
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "screen: $($_.DeviceName) $($_.Bounds) primary=$($_.Primary)" } | Out-File $out -Append
$pids = @(Get-Process qemu-system-x86_64, emulator -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
"pids: $pids" | Out-File $out -Append
$prim = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$cb = [W+EnumProc]{ param($h, $l)
  $p = 0; [void][W]::GetWindowThreadProcessId($h, [ref]$p)
  if ($pids -contains [int]$p -and [W]::IsWindowVisible($h)) {
    $r = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r)
    if ($r.L -le -20000) { [void][W]::ShowWindow($h, 9); Start-Sleep -Milliseconds 400; [void][W]::GetWindowRect($h, [ref]$r) }
    $sb = New-Object System.Text.StringBuilder 256; [void][W]::GetWindowText($h, $sb, 256)
    "window pid=$p title='$($sb.ToString())' rect=$($r.L),$($r.T),$($r.R),$($r.B)" | Out-File $out -Append
    $w = $r.R - $r.L; $hgt = $r.B - $r.T
    if ($w -gt 40 -and $hgt -gt 40) {
      [void][W]::ShowWindow($h, 9)
      # keep size, but cap height to the screen so the whole phone is visible
      $nh = [Math]::Min($hgt, $prim.Height - 20)
      $nw = [int]($w * $nh / $hgt)
      [void][W]::SetWindowPos($h, [IntPtr]::Zero, $prim.X + 40, $prim.Y + 10, $nw, $nh, 0x0040)
      [void][W]::SetForegroundWindow($h)
      $r2 = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r2)
      "  moved to $($r2.L),$($r2.T),$($r2.R),$($r2.B)" | Out-File $out -Append
    }
  }
  return $true }
[void][W]::EnumWindows($cb, [IntPtr]::Zero)
"END" | Out-File $out -Append
