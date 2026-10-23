param([switch]$Offline)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectRoot = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $projectRoot 'toolchain.json') -Raw | ConvertFrom-Json
$toolsDir = Join-Path $projectRoot '.tools'
$localMoon = Join-Path $toolsDir 'moon'
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
$versionPath = $config.release.Replace('+', '%2B')

function Get-VerifiedArchive($url, $path, $expected) {
    if (-not (Test-Path -LiteralPath $path)) {
        if ($Offline) { throw "Missing archive in offline mode: $path" }
        Invoke-WebRequest -Uri $url -OutFile $path
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Archive checksum mismatch: $path" }
}

if (-not (Test-Path -LiteralPath (Join-Path $localMoon 'bin\moon.exe'))) {
    $binaryZip = Join-Path $toolsDir 'moonbit.zip'
    $coreZip = Join-Path $toolsDir 'core.zip'
    Get-VerifiedArchive "https://cli.moonbitlang.com/binaries/$versionPath/moonbit-windows-x86_64.zip" $binaryZip $config.windows_archive_sha256
    Get-VerifiedArchive "https://cli.moonbitlang.com/cores/core-$versionPath.zip" $coreZip $config.core_archive_sha256
    Expand-Archive -LiteralPath $binaryZip -DestinationPath $localMoon
    Expand-Archive -LiteralPath $coreZip -DestinationPath (Join-Path $localMoon 'lib')
}
$env:MOON_HOME = $localMoon
$env:PATH = (Join-Path $localMoon 'bin') + ';' + $env:PATH
$versions = (& moon version --all) -join "`n"
if ($LASTEXITCODE -ne 0 -or -not $versions.Contains($config.moonc)) { throw 'Unexpected toolchain version' }
Write-Output $versions
Push-Location (Join-Path $localMoon 'lib\core')
try {
    foreach ($target in @('js', 'native', 'wasm', 'wasm-gc')) {
        & moon bundle --target $target --quiet
        if ($LASTEXITCODE -ne 0) { throw "Core bundle failed: $target" }
    }
} finally { Pop-Location }
if (-not $Offline) {
    Push-Location $projectRoot
    try {
        & moon update
        if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed' }
    } finally { Pop-Location }
}
Write-Output 'Project toolchain ready. Use scripts/moon.ps1 for project commands.'
