# Build a self-contained static offline replay page with the fixed project toolchain.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    & (Join-Path $PSScriptRoot 'moon.ps1') build examples/browser_replay --target js --frozen
    if ($LASTEXITCODE -ne 0) { throw 'MoonBit browser replay build failed.' }
    $outputDir = Join-Path $projectRoot '.tools\browser-replay'
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $builtJs = Join-Path $projectRoot '_build\js\debug\build\examples\browser_replay\browser_replay.js'
    Copy-Item -LiteralPath $builtJs -Destination (Join-Path $outputDir 'browser_replay.js')
    $sourceMap = $builtJs + '.map'
    if (Test-Path -LiteralPath $sourceMap) {
        Copy-Item -LiteralPath $sourceMap -Destination (Join-Path $outputDir 'browser_replay.js.map')
    }
    foreach ($asset in @('index.html', 'style.css', 'ui.js')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot "examples\browser_replay\$asset") -Destination (Join-Path $outputDir $asset)
    }
    Write-Output "Built offline replay page: $outputDir\index.html"
    Write-Output 'Serve: python -m http.server 8000 --bind 127.0.0.1 --directory .tools/browser-replay'
} finally {
    Pop-Location
}
