[CmdletBinding()]
param(
    [string]$MamePath,
    [string]$RomPath,
    [ValidateRange(10, 600)]
    [int]$SecondsToRun = 120,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot

if (-not $MamePath) {
    $MamePath = $env:MC10_MAME
}
if (-not $MamePath) {
    $MamePath = 'E:\tools\mame0289-bin\mame.exe'
}
if (Test-Path -LiteralPath $MamePath -PathType Leaf) {
    $MamePath = (Resolve-Path -LiteralPath $MamePath).Path
} else {
    $mameCommand = Get-Command $MamePath -ErrorAction SilentlyContinue
    if (-not $mameCommand) {
        throw "MAME executable was not found: $MamePath. Set MC10_MAME or pass -MamePath."
    }
    $MamePath = $mameCommand.Source
}

$mameDirectory = Split-Path -Parent $MamePath
if (-not $RomPath) {
    $RomPath = $env:MC10_MAME_ROMPATH
}
if (-not $RomPath) {
    $romCandidates = @(
        'E:\projects\ladybug\web\docker\roms',
        (Join-Path $mameDirectory 'roms')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }
    $RomPath = [string]::Join(';', $romCandidates)
}
if (-not $RomPath) {
    throw 'MAME ROM path was not found. Set MC10_MAME_ROMPATH or pass -RomPath.'
}

if (-not $SkipBuild) {
    $linuxRoot = (& wsl.exe --exec wslpath -a -u $projectRoot).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $linuxRoot) {
        throw 'WSL could not resolve the project directory.'
    }
    & wsl.exe --cd $linuxRoot --exec bash "$linuxRoot/scripts/build.sh" irq1
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

$cassette = Join-Path $projectRoot 'build\irq1-sanity.c10'
$luaScript = Join-Path $projectRoot 'scripts\mame-irq1-regression.lua'
if (-not (Test-Path -LiteralPath $cassette -PathType Leaf)) {
    throw "IRQ1 cassette was not found: $cassette. Run the build or omit -SkipBuild."
}

$arguments = @(
    'mc10',
    '-noreadconfig',
    '-skip_gameinfo',
    '-ramsize', '20K',
    '-rompath', $RomPath,
    '-cass', $cassette,
    '-autoboot_delay', '2',
    '-autoboot_script', $luaScript,
    '-seconds_to_run', $SecondsToRun,
    '-snapshot_directory', (Join-Path $projectRoot 'build\mame-snapshots'),
    '-window',
    '-nothrottle'
)

Write-Host 'Launching MAME IRQ1 sanity harness.'
& $MamePath @arguments
exit $LASTEXITCODE
