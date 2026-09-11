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
    $cassette = "$linuxRoot/build/space-invaders.c10"
    $emulatorArgs = @('-machine', 'mc10', '-cart', 'mcx128')

    if ($env:MC10_MCX_ROM) {
        $mcxRom = $env:MC10_MCX_ROM
        if ($mcxRom -match '^[A-Za-z]:[\\/]') {
            $mcxRom = (& wsl.exe --exec wslpath -a -u $mcxRom).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $mcxRom) {
                throw 'WSL could not resolve MC10_MCX_ROM.'
            }
        }
        $emulatorArgs += @('-cart-rom', $mcxRom, '-load-tape', $cassette)
    } else {
        $emulatorArgs += @('-run', $cassette)
    }

    & wsl.exe --cd $linuxRoot --exec $emulator @emulatorArgs
    exit $LASTEXITCODE
}

& wsl.exe --cd $linuxRoot --exec bash "$linuxRoot/scripts/build.sh" $Mode
exit $LASTEXITCODE
