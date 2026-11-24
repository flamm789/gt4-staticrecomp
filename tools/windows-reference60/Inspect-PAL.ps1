[CmdletBinding()]
param(
    [string]$Iso,
    [string]$Workspace
)

. "$PSScriptRoot/Common.ps1"

Assert-WindowsX64
if (-not $Iso) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    try {
        $dialog.Title = 'Choisir votre ISO de Gran Turismo 4'
        $dialog.Filter = 'Image ISO (*.iso)|*.iso'
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $Iso = $dialog.FileName
    } finally {
        $dialog.Dispose()
    }
}
if (-not (Test-Path -LiteralPath $Iso -PathType Leaf)) { throw "ISO introuvable : $Iso" }
$image = (Get-Item -LiteralPath $Iso).FullName
$requirements = Join-Path $PSScriptRoot '../../scripts/requirements.txt'
if (-not (Test-Path -LiteralPath $requirements -PathType Leaf)) {
    throw 'Extraire le ZIP GitHub complet. Le fichier scripts/requirements.txt manque.'
}

$layout = Use-Workspace $Workspace
$venv = Join-Path $layout.Root 'pal-python'
$python = Join-Path $venv 'Scripts/python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if (-not $launcher) { throw 'Python 3.12 est requis. Voir PAL.fr.md.' }
    Invoke-Tool $launcher.Source @('-3.12', '-m', 'venv', $venv)
}
Invoke-Tool $python @('-m', 'pip', 'install', '--disable-pip-version-check', '--no-input', '-r', $requirements)
Write-Host 'Lecture de votre ISO. Le calcul des empreintes peut prendre quelques minutes.'
$json = Invoke-Tool $python @('-I', '-B', (Join-Path $PSScriptRoot 'inspect_pal.py'), $image)
$result = ($json -join "`n") | ConvertFrom-Json
$report = Join-Path (New-RunDirectory $layout 'pal-inspection') 'pal-report.json'
Write-Json $report $result
Write-Host "Disque : $($result.system.serial), $($result.system.video_mode), CRC $($result.pcsx2_disc_crc)"
if (-not $result.matches_reported_pcsx2_id) {
    Write-Warning 'Le disque inspecte ne correspond pas au couple SCES-51719 / 44A61C8F.'
}
Write-Host "Rapport local : $report"
