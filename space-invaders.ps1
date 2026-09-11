[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('build', 'run', 'check', 'clean')]
    [string]$Mode = 'build'
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$linuxRoot = (& wsl.exe --exec wslpath -a -u $projectRoot).Trim()
if ($LASTEXITCODE -ne 0 -or -not $linuxRoot) {
    throw 'WSL could not resolve the project directory.'
}

if ($Mode -eq 'run') {
    & wsl.exe --cd $linuxRoot --exec bash "$linuxRoot/scripts/build.sh" build
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    $emulator = if ($env:MC10_XROAR) { $env:MC10_XROAR } else { '/usr/local/bin/xroar' }
    & wsl.exe --cd $linuxRoot --exec $emulator `
        -machine mc10 `
        -cart mcx128 `
        -run "$linuxRoot/build/space-invaders.c10"
    exit $LASTEXITCODE
}

& wsl.exe --cd $linuxRoot --exec bash "$linuxRoot/scripts/build.sh" $Mode
exit $LASTEXITCODE
