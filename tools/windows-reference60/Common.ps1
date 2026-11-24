Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$MainRevision = 'b0008e8a93b05ff0556cb3347204699c225d85bc'
$Task090Revision = 'b987f50ee41a3d2307b3e8ed17e829f380139c21'
$DonorRevision = '1b4808793a12c45125262fd2d5f50a9ec9f7c020'
$BranchName = 'gt4-native-100fps'
$PublicArchive = 'GT4Recomp-1.3.0-rc14-portable.zip'
$PublicArchiveSha = '961047fcc9c254b3adf91fb7990be3a9f5a687afd87ab1fea6cfe7cfcaa0a7d1'
$GlslangSha = 'db832826d73049193882d5572ad76e14fcb7b1cdfc1a6b892ac25217b850b6bc'
$VulkanSdkVersion = '1.4.341.1'
$WindowsSdkVersion = '10.0.26100.0'
$ClangVersion = '22.1.3'

function Use-Workspace {
    param([string]$Path)
    if (-not $Path) {
        if (-not $env:LOCALAPPDATA) { throw 'Specify -Workspace with an absolute path.' }
        $Path = Join-Path $env:LOCALAPPDATA 'GT4-Dev'
    }
    $root = [IO.Path]::GetFullPath($Path)
    if ($root -match '[;\r\n]') { throw "CMake cannot use this workspace path. Choose a simple folder." }
    $assetRoot = Join-Path $root 'assets'
    $privateRoot = Join-Path $assetRoot 'private'
    [pscustomobject]@{
        Root = $root
        Source = Join-Path $root 'source'
        Assets = $assetRoot
        Private = $privateRoot
        Donor = Join-Path $privateRoot 'references/ps2-web-recomp'
        Python = Join-Path $root 'python/Scripts/python.exe'
        Input = Join-Path $privateRoot 'reference60-disc'
        Builds = Join-Path $root 'build'
        Build = Join-Path $root 'build/reference60'
        Published = Join-Path $root "packages/gt4recomp-rc14"
        Downloads = Join-Path $root 'downloads'
        Runs = Join-Path $root 'runs'
    }
}

function Assert-WindowsX64 {
    if ($env:OS -ne 'Windows_NT' -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        throw 'Run this step in a 64-bit PowerShell on Windows x64.'
    }
}

function Invoke-Tool {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$([IO.Path]::GetFileName($Program)) failed (exit $LASTEXITCODE). See the output above."
    }
}

function Read-Json {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Encoding UTF8 -Raw | ConvertFrom-Json
}

function Get-Sha256 {
    param([string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-Sha256 {
    param([string]$Path, [string]$Expected)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
    if ((Get-Sha256 $Path) -ne $Expected) { throw "SHA-256 mismatch: $Path" }
}

function Get-Pins {
    param([string]$Source)
    $inputs = Join-Path $Source 'docs/inputs'
    [pscustomobject]@{
        Disc = Read-Json (Join-Path $inputs 'usa-v2.00.json')
        Elf = Read-Json (Join-Path $inputs 'usa-v2.00-native.json')
        Release = Read-Json (Join-Path $inputs 'slice408-pcsx2.json')
        Aspect = (Read-Json (Join-Path $inputs 'slice217-ee-libraries.json')).profiles.aspect
        Runtime = Read-Json (Join-Path $inputs 'slice262-frame-cost-runtime.json')
        Guard = Read-Json (Join-Path $inputs 'slice376-frame-render-license-guard-runtime.json')
        SDL = Read-Json (Join-Path $inputs 'slice210-sdl3.json')
        Donor = (Read-Json (Join-Path $inputs 'external-recomp-references.json')).references |
            Where-Object { $_.name -eq 'ps2-web-recomp' }
        VulkanHeaders = (Read-Json (Join-Path $inputs 'slice111-native-vulkan.json')).artifacts |
            Where-Object { $_.path -like 'private/tooling/pcsx2-slice101-source/3rdparty/vulkan/include/*' }
    }
}

function Write-Json {
    param([string]$Path, $Data)
    $json = $Data | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

function Get-VerifiedDownload {
    param([string]$Url, [string]$Path, [string]$Sha256, [switch]$PinnedCrlf)
    if (-not (Test-Path -LiteralPath $Path)) {
        $parent = Split-Path -Parent $Path
        $null = New-Item -ItemType Directory -Force -Path $parent
        $temp = Join-Path $parent ('.download-' + [Guid]::NewGuid().ToString('N'))
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $temp
            if ($PinnedCrlf -and (Get-Sha256 $temp) -ne $Sha256) {
                $contents = [IO.File]::ReadAllText($temp, [Text.UTF8Encoding]::new($false, $true))
                $crlf = $contents.Replace("`r`n", "`n").Replace("`n", "`r`n")
                [IO.File]::WriteAllText($temp, $crlf, [Text.UTF8Encoding]::new($false))
            }
            Assert-Sha256 $temp $Sha256
            Move-Item -LiteralPath $temp -Destination $Path
        } finally {
            if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp }
        }
    }
    Assert-Sha256 $Path $Sha256
}

function Copy-VerifiedFile {
    param([string]$From, [string]$To, [string]$Sha256)
    if (-not (Test-Path -LiteralPath $To)) {
        Assert-Sha256 $From $Sha256
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $To)
        Copy-Item -LiteralPath $From -Destination $To
    }
    Assert-Sha256 $To $Sha256
}

function Expand-Package {
    param([string]$Archive, [string]$Destination)
    $parent = Split-Path -Parent $Destination
    $null = New-Item -ItemType Directory -Force -Path $parent
    $temp = Join-Path $parent ('.expand-' + [Guid]::NewGuid().ToString('N'))
    try {
        Expand-Archive -LiteralPath $Archive -DestinationPath $temp
        [IO.Directory]::Move($temp, $Destination)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse }
    }
}

function Assert-CleanTree {
    param([string]$Path, [string]$Revision)
    $head = Invoke-Tool 'git.exe' @('-C', $Path, 'rev-parse', 'HEAD')
    if ($head -ne $Revision) { throw "Wrong Git revision at $Path. Expected $Revision." }
    $changes = @(Invoke-Tool 'git.exe' @('-C', $Path, 'status', '--porcelain', '--untracked-files=all'))
    if ($changes.Count) { throw "Checkout has local changes: $Path. Use a new workspace to preserve them." }
}

function Get-GitTree {
    param([string]$Url, [string]$Path, [string]$Revision, [string]$NewBranch, [switch]$Crlf)
    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git') -PathType Container)) {
        if ((Test-Path -LiteralPath $Path) -and @(Get-ChildItem -LiteralPath $Path -Force).Count) {
            throw "Folder already contains other data: $Path"
        }
        $null = New-Item -ItemType Directory -Force -Path $Path
        Invoke-Tool 'git.exe' @('init', '--quiet', $Path)
        Invoke-Tool 'git.exe' @('-C', $Path, 'config', '--local', 'core.autocrlf', $Crlf.ToString().ToLowerInvariant())
    }
    & git.exe -C $Path rev-parse --verify --quiet HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Invoke-Tool 'git.exe' @('-C', $Path, 'fetch', '--no-tags', '--depth=1', $Url, $Revision)
        $fetched = Invoke-Tool 'git.exe' @('-C', $Path, 'rev-parse', 'FETCH_HEAD')
        if ($fetched -ne $Revision) { throw "Fetched Git object differs from expected revision $Revision." }
        if ($NewBranch) {
            Invoke-Tool 'git.exe' @('-C', $Path, 'switch', '--create', $NewBranch, $Revision)
        } else {
            Invoke-Tool 'git.exe' @('-C', $Path, 'switch', '--detach', $Revision)
        }
    }
    Assert-CleanTree $Path $Revision
    if ($NewBranch -and (Invoke-Tool 'git.exe' @('-C', $Path, 'branch', '--show-current')) -ne $NewBranch) {
        throw "Expected branch $NewBranch at $Path. Use a new workspace to preserve the existing checkout."
    }
}

function Get-PrivatePath {
    param($Layout, [string]$Relative)
    Join-Path $Layout.Private $Relative
}

function New-RunDirectory {
    param($Layout, [string]$Label)
    $name = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $Label + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
    $directory = Join-Path $Layout.Runs $name
    $null = New-Item -ItemType Directory -Force -Path $Layout.Runs
    (New-Item -ItemType Directory -Path $directory).FullName
}
