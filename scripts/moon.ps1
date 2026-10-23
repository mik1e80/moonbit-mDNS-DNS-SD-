# Use the project-local toolchain when present; leave global installation intact.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$localMoon = Join-Path $projectRoot '.tools\moon'
if (Test-Path -LiteralPath (Join-Path $localMoon 'bin\moon.exe')) {
    $env:MOON_HOME = $localMoon
    $env:PATH = (Join-Path $localMoon 'bin') + ';' + $env:PATH
}
& moon @args
exit $LASTEXITCODE
