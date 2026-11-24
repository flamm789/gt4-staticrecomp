[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Run,
    [string]$Workspace,
    [ValidateRange(5, 300)]
    [int]$Seconds = 30
)

. "$PSScriptRoot/Common.ps1"

Assert-WindowsX64
$layout = Use-Workspace $Workspace
$runPath = [IO.Path]::GetFullPath($Run)
$receipt = Read-Json (Join-Path $runPath 'run.json')
if ($receipt.mode -eq 'Shaders' -or $receipt.headless -or $receipt.PSObject.Properties['exit_code']) {
    throw 'Select the folder of the currently running windowed game, as printed by Run-GT4.ps1.'
}
$game = Get-Process -Id $receipt.pid
if ($game.ProcessName -notin @('gt4', 'gt4vulkan') -or $game.StartTime.ToUniversalTime().Ticks -ne $receipt.process_start_ticks) {
    throw 'This is not the process that started the selected run.'
}
$presentMon = Join-Path $layout.Downloads 'PresentMon-2.3.1-x64.exe'
$url = 'https://github.com/GameTechDev/PresentMon/releases/download/v2.3.1/PresentMon-2.3.1-x64.exe'
Get-VerifiedDownload $url $presentMon '364e5d98d4d134bd54dd25c22ed2ca2f4883f8bc3ed6502bee0c151e3436d30c'
$session = 'GT4-Reference-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$file = Join-Path $runPath ($session + '.csv')
Invoke-Tool $presentMon @('--process_id', [string]$game.Id, '--session_name', $session,
    '--output_file', $file, '--timed', [string]$Seconds, '--terminate_after_timed',
    '--no_track_input', '--no_console_stats', '--qpc_time_ms')
if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -eq 0) {
    throw 'PresentMon did not create a capture. Check ETW access and that the game was still in the race.'
}
Write-Host "Display capture saved in $file"
