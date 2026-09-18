# 开发期辅助：截取指定进程的主窗口，用于人工核对界面效果。
# 用法：powershell -File tool/capture_window.ps1 -ProcessName upbetter -Out shot.png
#
# 使用 PrintWindow(PW_RENDERFULLCONTENT) 而不是屏幕拷贝：
# 后台进程调用 SetForegroundWindow 经常失败，屏幕拷贝会抓到遮挡在
# 上层的其它窗口。PrintWindow 直接向窗口索取重绘结果，与 z-order 无关。
param(
    [string]$ProcessName = 'upbetter',
    [string]$Out = 'shot.png'
)

Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinCap {
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

# PW_RENDERFULLCONTENT：抓取 DWM 合成后的完整内容，
# 对 Flutter 这类 GPU 合成的窗口是必须的。
$PW_RENDERFULLCONTENT = 2

$proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1

if (-not $proc) {
    Write-Error "未找到进程 $ProcessName 的主窗口"
    exit 1
}

$h = $proc.MainWindowHandle
# 先尝试置前（失败也无所谓，PrintWindow 不依赖它），
# 若窗口处于最小化状态则先还原，否则抓到的是 0 尺寸。
[WinCap]::ShowWindow($h, 9) | Out-Null
[WinCap]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 800

$rect = New-Object WinCap+RECT
[WinCap]::GetWindowRect($h, [ref]$rect) | Out-Null
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top

if ($width -le 0 -or $height -le 0) {
    Write-Error "窗口尺寸无效：${width}x${height}"
    exit 1
}

$bitmap = New-Object System.Drawing.Bitmap($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$hdc = $graphics.GetHdc()
$ok = [WinCap]::PrintWindow($h, $hdc, $PW_RENDERFULLCONTENT)
$graphics.ReleaseHdc($hdc)

if (-not $ok) {
    Write-Warning "PrintWindow 返回失败，回退到屏幕拷贝"
    $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
}

$bitmap.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

Write-Host "已保存 $Out (${width}x${height}) printWindow=$ok"
