param(
    [string]$Godot = (Join-Path $PSScriptRoot '../Godot_v4.7.2-stable_win64.exe')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$outputDirectory = Join-Path $projectRoot 'export'
New-Item -ItemType Directory -Force $outputDirectory | Out-Null
$exportProcess = Start-Process -FilePath $Godot -ArgumentList @(
    '--headless', '--path', "`"$projectRoot`"", '--export-release', 'Web',
    "`"$(Join-Path $outputDirectory 'index.html')`""
) -WindowStyle Hidden -Wait -PassThru
if ($exportProcess.ExitCode -ne 0) { throw "Godot export failed with exit code $($exportProcess.ExitCode)" }

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'embed.html') -Destination (Join-Path $outputDirectory 'embed.html')
# Include only runtime files, with index.html at the ZIP root for itch.io.
$runtimeFiles = @(
    'index.html', 'index.js', 'index.wasm', 'index.pck', 'index.png',
    'index.icon.png', 'index.apple-touch-icon.png',
    'index.audio.worklet.js', 'index.audio.position.worklet.js', 'embed.html'
) | ForEach-Object { Join-Path $outputDirectory $_ }
Compress-Archive -LiteralPath $runtimeFiles -DestinationPath (Join-Path $outputDirectory 'index.zip') -Force
Write-Output "Upload package: $(Join-Path $outputDirectory 'index.zip')"
