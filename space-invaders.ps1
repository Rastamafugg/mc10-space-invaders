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

& wsl.exe --cd $linuxRoot --exec bash "$linuxRoot/scripts/build.sh" $Mode
exit $LASTEXITCODE
