$ErrorActionPreference = 'Stop'
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $dir 'BgClicker.cs'
$out = Join-Path $dir 'BgClicker.exe'

& $csc /nologo /optimize+ /target:winexe /utf8output `
    /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll `
    "/out:$out" "$src"

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Build OK: $out ($((Get-Item $out).Length) bytes)" -ForegroundColor Green
