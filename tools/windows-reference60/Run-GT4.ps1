[CmdletBinding()]
param(
    [ValidateSet('Published', 'Source')]
    [string]$Profile = 'Published',
    [ValidateSet('Play', 'Performance', 'Record', 'Replay', 'Wheel', 'Shaders')]
    [string]$Mode = 'Play',
    [string]$Workspace,
    [string]$Card,
    [string]$ReplayFrom,
    [string]$WheelConfig,
    [string]$Adapter = 'NVIDIA GeForce GTX 1070',
    [ValidateRange(1, 3)]
    [int]$Scale = 1,
    [ValidateRange(0, 10000000)]
    [long]$Frames = 0,
    [switch]$Headless
)

. "$PSScriptRoot/Common.ps1"

function Get-Seed {
    param([string]$Path, [string]$Run)
    if (-not $Path) { return $null }
    $seed = Join-Path $Run 'card-before.ps2'
    Copy-Item -LiteralPath $Path -Destination $seed
    Copy-Item -LiteralPath $seed -Destination (Join-Path $Run 'card.ps2')
    Get-Sha256 $seed
}

function Start-RecordedGame {
    param([string]$Exe, [string[]]$Arguments, [string]$Directory, [hashtable]$Variables, [hashtable]$Receipt)
    $saved = @{}
    foreach ($variable in Get-ChildItem Env:) {
        if ($variable.Name -like 'GT4_*' -or $variable.Name -like 'PS2_*') {
            $saved[$variable.Name] = $variable.Value
            [Environment]::SetEnvironmentVariable($variable.Name, $null, 'Process')
        }
    }
    try {
        foreach ($entry in $Variables.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
        }
        $commandLine = ($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
        $process = Start-Process -FilePath $Exe -ArgumentList $commandLine -WorkingDirectory $Directory -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $Directory 'stdout.log') -RedirectStandardError (Join-Path $Directory 'game.log')
        $Receipt.pid = $process.Id
        if ($Receipt.mode -in @('Play', 'Performance', 'Record', 'Replay', 'Wheel') -and -not $process.HasExited) {
            $Receipt.process_start_ticks = $process.StartTime.ToUniversalTime().Ticks
        }
        Write-Json (Join-Path $Directory 'run.json') $Receipt
        Write-Host "Game PID: $($process.Id)"
        Write-Host "Logs: $Directory"
        $process.WaitForExit()
        $Receipt.exit_code = $process.ExitCode
    } finally {
        foreach ($name in $Variables.Keys) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    }
    Write-Json (Join-Path $Directory 'run.json') $Receipt
    if ($Receipt.exit_code -ne 0) { throw "Game exit code $($Receipt.exit_code). Read game.log in $Directory." }
}

Assert-WindowsX64
$layout = Use-Workspace $Workspace
Assert-CleanTree $layout.Source $MainRevision
$pins = Get-Pins $layout.Source
if ($Profile -eq 'Published') {
    if ($Mode -eq 'Wheel') { throw 'Native DFP requires the Source build with the USB capsule.' }
    $exe = Join-Path $layout.Published 'game/gt4.exe'
    $exeSha = $pins.Release.runtime.sha256
} else {
    $exe = Join-Path $layout.Build 'gt4vulkan.exe'
    $build = Read-Json (Join-Path $layout.Build 'reference-build.json')
    if ($build.source -ne $MainRevision) { throw 'Build does not have the expected reference revision.' }
    $exeSha = $build.executable_sha256
}
Assert-Sha256 $exe $exeSha
$binDir = Split-Path -Parent $exe
Assert-Sha256 (Join-Path $binDir 'SDL3.dll') $pins.SDL.files.runtime.sha256
foreach ($entry in $pins.Runtime.inputs.SHADERS.PSObject.Properties) {
    Assert-Sha256 (Join-Path $binDir ('shaders/' + $entry.Name)) $entry.Value
}
if (Get-Process -Name 'gt4', 'gt4vulkan' -ErrorAction SilentlyContinue) {
    throw 'Close the other GT4 game session normally before starting this test.'
}

if ($Headless -and $Mode -ne 'Replay') { throw '-Headless is for the fixed input replay only.' }
if ($ReplayFrom -and $Mode -ne 'Replay') { throw '-ReplayFrom is for Replay only.' }
if ($WheelConfig -and $Mode -ne 'Wheel') { throw '-WheelConfig is for Wheel only.' }
if ($Card -and $Mode -in @('Replay', 'Shaders')) { throw 'Replay uses the original recording seed. Shaders uses no card.' }
$run = New-RunDirectory $layout ($Profile.ToLowerInvariant() + '-' + $Mode.ToLowerInvariant())
$variables = @{
    GT4_RENDERER = 'hw'
    GT4_HW_CORE = '2'
    GT4_FORCE_480P = '1'
    GT4_FORCE_WIDESCREEN = '1'
    GT4_DISPLAY_ASPECT = '16:9'
    GT4_PACING = 'paced'
    GT4_PRESENT_MODE = 'fifo'
    GT4_HW_ADAPTER = $Adapter
    GT4_HW_SCALE = [string]$Scale
    GT4_HW_SHADER_CACHE = Join-Path $layout.Root "shader-cache/$exeSha"
}
$receipt = @{
    profile = $Profile
    mode = $Mode
    exe_sha256 = $exeSha
    version = if ($Profile -eq 'Published') { '1.3.0-rc14' } else { $MainRevision }
    headless = [bool]$Headless
    settings = $variables
    started_utc = [DateTime]::UtcNow.ToString('o')
}
$playing = $Mode -ne 'Shaders'
if ($playing) {
    $disc = Read-Json (Join-Path $layout.Root 'local-disc.json')
    $elf = Join-Path $layout.Input 'SCUS_973.28.elf'
    Assert-Sha256 $disc.iso $pins.Disc.disc.sha256
    Assert-Sha256 $elf $pins.Elf.native_elf_sha256
    $receipt.disc_sha256 = $pins.Disc.disc.sha256
    $receipt.elf_sha256 = $pins.Elf.native_elf_sha256

    if ($Mode -eq 'Replay') {
        if (-not $ReplayFrom) { throw 'Replay needs -ReplayFrom with a completed Record folder.' }
        $prior = [IO.Path]::GetFullPath($ReplayFrom)
        $record = Read-Json (Join-Path $prior 'run.json')
        if ($record.mode -ne 'Record' -or $record.exit_code -ne 0 -or $record.disc_sha256 -ne $receipt.disc_sha256 -or $record.elf_sha256 -ne $receipt.elf_sha256) {
            throw 'Replay source must be a completed recording of the same USA v2.00 disc and ELF.'
        }
        if ($record.card_seed_sha256) {
            $Card = Join-Path $prior 'card-before.ps2'
            Assert-Sha256 $Card $record.card_seed_sha256
        }
        $inputFile = Join-Path $prior 'pad-input.txt'
        Assert-Sha256 $inputFile $record.pad_input_sha256
        $variables.GT4_INPUT_REPLAY = $inputFile
        $variables.GT4_FRAME_SKIP_FORCE = '1'
        $variables.GT4_FRAME_SKIP_LOG = Join-Path $run 'physics.csv'
        if ($Frames -eq 0) { $Frames = $record.recorded_vblanks }
        if ($Frames -gt $record.recorded_vblanks) { throw 'Replay frame count exceeds the recorded duration.' }
        $receipt.pad_input_sha256 = $record.pad_input_sha256
    }
    if ($Mode -eq 'Record') {
        $variables.GT4_INPUT_RECORD = Join-Path $run 'pad-input.txt'
        Write-Host 'Play with keyboard or pad. F9 finishes the recording and closes the game.'
    }
    if ($Mode -eq 'Wheel') {
        $sourceConfig = if ($WheelConfig) { $WheelConfig } else { Join-Path $PSScriptRoot 'wheel-dfgt.toml' }
        $targetConfig = Join-Path $run 'wheel.toml'
        Copy-Item -LiteralPath $sourceConfig -Destination $targetConfig
        $variables.GT4_WHEEL_FILE = $targetConfig
        $variables.GT4_DFP_PORT = '2'
        $variables.GT4_DFP_TRACE = '1'
        Write-Host 'Test with low force first and check axes, gears and physical feedback. See the guide.'
    }
    if ($Mode -eq 'Performance') {
        $variables.GT4_PERF = '1'
        $variables.GT4_HW_PROFILE_EVERY = '600'
        $variables.GT4_HW_FRAMETIME_LOG = Join-Path $run 'frametime.csv'
        $variables.GT4_HW_GPU_TIMING = '1'
        Write-Host 'Press F7 at the start of a stable race segment and F8 at its end. Close the game normally.'
    }
    $receipt.card_seed_sha256 = Get-Seed $Card $run
    $receipt.frames_requested = $Frames
    $gameArgs = @($elf, '--ntsc', '--disc', $disc.iso, '--frames', [string]$Frames,
        '--memcard', (Join-Path $run 'card.ps2'), '--misses', (Join-Path $run 'misses.txt'))
    if (-not $Headless) { $gameArgs += '--window' }
} else {
    $gameArgs = @('--prepare-shaders')
}
Start-RecordedGame $exe $gameArgs $run $variables $receipt
if ($Mode -eq 'Shaders') {
    $output = Get-Content -LiteralPath (Join-Path $run 'stdout.log') -Raw
    if ($output -notmatch '(?m)^shaders ready\r?$') { throw "Shader preparation did not report readiness. See $run." }
    if ($Profile -eq 'Source') {
        $smoke = Join-Path $binDir 'hw_gs_smoke.exe'
        $smokeRun = New-RunDirectory $layout 'source-vulkan'
        Start-RecordedGame $smoke @('--frames', '2', '--window', '--display') $smokeRun $variables @{
            mode = 'VulkanSmoke'; headless = $false
        }
        $selection = Get-Content -LiteralPath (Join-Path $smokeRun 'stdout.log') -Raw
        if ($selection -notmatch ('(?m)^device=' + [regex]::Escape($Adapter) + ' vendor=')) {
            throw "The Vulkan smoke test selected a different adapter. See $smokeRun/stdout.log."
        }
        Write-Host "Confirmed the requested device in $smokeRun/stdout.log"
    }
    Write-Host 'Shader check passed. Measure the actual race separately.'
}
if ($Mode -eq 'Record') {
    $inputFile = Join-Path $run 'pad-input.txt'
    $ending = Get-Content -LiteralPath $inputFile -Tail 1
    if ($ending -notmatch '^end ([1-9][0-9]*)$') { throw "The recording did not finish. Use F9. Logs: $run" }
    $receipt.recorded_vblanks = [long]$Matches[1]
    $receipt.pad_input_sha256 = Get-Sha256 $inputFile
    Write-Json (Join-Path $run 'run.json') $receipt
}
if ($Mode -eq 'Replay' -and -not (Test-Path -LiteralPath (Join-Path $run 'physics.csv'))) {
    throw 'Replay did not produce the reference physics trace. Check whether the requested capsule is enabled.'
}
Write-Host "Run finished. Local results: $run"
