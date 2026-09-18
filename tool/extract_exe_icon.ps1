# 开发期辅助：从可执行文件中提取指定尺寸的图标，用于核对图标是否真的打进去了。
# 用法：powershell -File tool/extract_exe_icon.ps1 -Exe <exe路径> -Size 32 -Out icon32.png
#
# 用 PrivateExtractIcons 而不是 ExtractAssociatedIcon：
# 后者只能拿到系统默认尺寸（通常是 32px），无法验证多尺寸 ICO 的每一档。
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [int]$Size = 32,
    [string]$Out = "icon_$Size.png"
)

Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class IconExtract {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int PrivateExtractIcons(
        string lpszFile, int nIconIndex, int cxIcon, int cyIcon,
        IntPtr[] phicon, int[] piconid, int nIcons, int flags);
    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
"@

$handles = New-Object IntPtr[] 1
$ids = New-Object int[] 1
$count = [IconExtract]::PrivateExtractIcons($Exe, 0, $Size, $Size, $handles, $ids, 1, 0)

if ($count -le 0 -or $handles[0] -eq [IntPtr]::Zero) {
    Write-Error "无法从 $Exe 提取 ${Size}px 图标"
    exit 1
}

$icon = [System.Drawing.Icon]::FromHandle($handles[0])
$bitmap = $icon.ToBitmap()
$bitmap.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()
$icon.Dispose()
[IconExtract]::DestroyIcon($handles[0]) | Out-Null

Write-Host "已提取 ${Size}x${Size} -> $Out"
