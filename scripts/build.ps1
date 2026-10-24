$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
$projectRoot = Split-Path $PSScriptRoot -Parent
$manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'manifest.json') -Raw | ConvertFrom-Json
$compilerCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (!$compiler) { throw 'The .NET Framework C# compiler (csc.exe) was not found.' }
$helperSource = Join-Path $projectRoot 'helper\TrayHelper.cs'
$helperExecutable = Join-Path $projectRoot 'helper\tray-helper.exe'
& $compiler /nologo /target:winexe /optimize+ /out:$helperExecutable /reference:System.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll $helperSource
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile tray-helper.exe.' }
$outputDirectory = Join-Path $projectRoot 'dist'
[void][System.IO.Directory]::CreateDirectory($outputDirectory)
$output = Join-Path $outputDirectory "zotero-mini-tray-$($manifest.version).xpi"
$stream = [System.IO.File]::Open($output, [System.IO.FileMode]::Create)
$archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($relativePath in @('manifest.json', 'bootstrap.js', 'helper/tray-helper.exe', 'helper/TrayHelper.cs')) {
        $entry = $archive.CreateEntry($relativePath)
        $destination = $entry.Open()
        $source = [System.IO.File]::OpenRead((Join-Path $projectRoot $relativePath))
        try { $source.CopyTo($destination) } finally { $source.Dispose(); $destination.Dispose() }
    }
} finally { $archive.Dispose(); $stream.Dispose() }
Write-Output $output
