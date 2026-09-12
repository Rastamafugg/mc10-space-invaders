[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('build', 'run', 'utility', 'utility-run', 'test', 'check', 'clean')]
    [string]$Mode = 'build'
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$linuxRoot = (& wsl.exe --exec wslpath -a -u $projectRoot).Trim()
if ($LASTEXITCODE -ne 0 -or -not $linuxRoot) {
    throw 'WSL could not resolve the project directory.'
}

if ($Mode -in @('run', 'utility-run')) {
    $buildTarget = if ($Mode -eq 'utility-run') { 'utility' } else { 'build' }
    $cassetteName = if ($Mode -eq 'utility-run') { 'environment-test.c10' } else { 'space-invaders.c10' }
    & wsl.exe --cd $linuxRoot --exec bash "$linuxRoot/scripts/build.sh" $buildTarget
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    $emulator = if ($env:MC10_XROAR) { $env:MC10_XROAR } else { '/usr/local/bin/xroar' }
    $cassette = "$linuxRoot/build/$cassetteName"
    if ($env:MC10_MCX_DIRECT_ROM -or $env:MC10_MCX_ROM) {
        $emulatorArgs = @('-machine', 'mc10', '-cart', 'mcx128')
        $mcxRom = if ($env:MC10_MCX_DIRECT_ROM) { $env:MC10_MCX_DIRECT_ROM } else { $env:MC10_MCX_ROM }
        if ($mcxRom -match '^[A-Za-z]:[\\/]') {
            $mcxRom = (& wsl.exe --exec wslpath -a -u $mcxRom).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $mcxRom) {
                throw 'WSL could not resolve the MCX ROM path.'
            }
        }
        $directMode = if ($env:MC10_MCX_DIRECT_MODE) { $env:MC10_MCX_DIRECT_MODE } else { 'large' }
        if ($directMode -notin @('large', 'stock')) {
            throw "MC10_MCX_DIRECT_MODE must be 'large' or 'stock'."
        }
        if ($env:MC10_MCX_DIRECT_ROM -and $directMode -eq 'stock') {
            if ($env:MC10_XROAR_MC10_CART_PATCHED -eq '1') {
                # The patched XRoar build routes its synthetic RTS stack reads
                # through the MCX cartridge, so its -run autorun path is safe.
                $emulatorArgs += @('-cart-rom', $mcxRom, '-run', $cassette)
            } else {
                # Keep the stock BASIC prompt usable. An unpatched XRoar
                # bypasses the MCX cartridge during its auto-keyboard RTS.
                $emulatorArgs += @('-cart-rom', $mcxRom, '-load-tape', $cassette)
            }
        } elseif ($env:MC10_MCX_DIRECT_ROM) {
            # MCX BASIC does not accept XRoar's generic CLOADM:EXEC syntax.
            # Queue CLOADM only; the cassette Play control and EXEC remain
            # explicit so the direct path follows the MCX BASIC sequence.
            $emulatorArgs += @('-cart-rom', $mcxRom, '-load-tape', $cassette, '-type', 'CLOADM\r')
        } else {
            $emulatorArgs += @('-cart-rom', $mcxRom, '-load-tape', $cassette)
        }
    } else {
        # An MCX-128 cartridge without its EPROM maps an empty ROM at reset.
        # Use the stock machine as a loader control instead of showing a bad
        # reverse-@ screen. The MCX test requires MC10_MCX_ROM.
        $emulatorArgs = @('-machine', 'mc10', '-run', $cassette)
    }

    & wsl.exe --cd $linuxRoot --exec $emulator @emulatorArgs
    exit $LASTEXITCODE
}

if ($Mode -eq 'test') {
    & wsl.exe --cd $linuxRoot --exec bash "$linuxRoot/scripts/build.sh" build
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    & wsl.exe --cd $linuxRoot --exec bash "$linuxRoot/scripts/build.sh" utility
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $testArgs = @()
    if ($env:MC10_XROAR) {
        $testEmulator = $env:MC10_XROAR
        if ($testEmulator -match '^[A-Za-z]:[\\/]') {
            $testEmulator = (& wsl.exe --exec wslpath -a -u $testEmulator).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $testEmulator) {
                throw 'WSL could not resolve the XRoar path.'
            }
        }
        $testArgs += @('--xroar', $testEmulator)
    }

    $testRom = if ($env:MC10_MCX_DIRECT_ROM) { $env:MC10_MCX_DIRECT_ROM } else { $env:MC10_MCX_ROM }
    if ($testRom) {
        if ($testRom -match '^[A-Za-z]:[\\/]') {
            $testRom = (& wsl.exe --exec wslpath -a -u $testRom).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $testRom) {
                throw 'WSL could not resolve the MCX ROM path.'
            }
        }
        $testArgs += @('--rom', $testRom)
    }

    & wsl.exe --cd $linuxRoot --exec python3 "$linuxRoot/scripts/regression.py" @testArgs
    exit $LASTEXITCODE
}

if ($Mode -eq 'utility') {
    & wsl.exe --cd $linuxRoot --exec bash "$linuxRoot/scripts/build.sh" utility
} else {
    & wsl.exe --cd $linuxRoot --exec bash "$linuxRoot/scripts/build.sh" $Mode
}
exit $LASTEXITCODE
