[CmdletBinding()]
param(
    [ValidateSet('Install', 'Prepare', 'Check', 'Build', 'Hardware', 'StageTask090')]
    [string]$Action = 'Check',
    [string]$Workspace,
    [string]$Iso,
    [string]$VulkanSdk,
    [switch]$PublishedOnly
)

. "$PSScriptRoot/Common.ps1"

function Get-VsInstallation {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        Invoke-Tool $vswhere @('-latest', '-products', '*', '-version', '[17.0,18.0)',
            '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
            'Microsoft.VisualStudio.Component.Windows11SDK.26100', '-property', 'installationPath')
    }
}

function Refresh-ToolPath {
    $env:Path = ($env:Path, [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User')) -join ';'
}

function Get-VulkanSdk {
    if ($VulkanSdk) { return [IO.Path]::GetFullPath($VulkanSdk) }
    if ($env:VULKAN_SDK -and (Split-Path -Leaf ($env:VULKAN_SDK.TrimEnd('\'))) -eq $VulkanSdkVersion) {
        return $env:VULKAN_SDK
    }
    $systemSdk = [Environment]::GetEnvironmentVariable('VULKAN_SDK', 'Machine')
    if ($systemSdk -and (Split-Path -Leaf ($systemSdk.TrimEnd('\'))) -eq $VulkanSdkVersion) {
        return $systemSdk
    }
    Join-Path ([IO.Path]::GetPathRoot($env:ProgramFiles)) "VulkanSDK/$VulkanSdkVersion"
}

function Install-Dependencies {
    $winget = (Get-Command winget.exe -ErrorAction Stop).Source
    $common = @('--exact', '--source', 'winget', '--architecture', 'x64',
        '--accept-package-agreements', '--accept-source-agreements')
    $packages = @(
        @{ Id = 'Git.Git'; Command = 'git.exe'; Version = '' },
        @{ Id = 'Python.Python.3.12'; Command = 'py.exe'; Version = '' }
    )
    if (-not $PublishedOnly) {
        $packages += @(
            @{ Id = 'Kitware.CMake'; Command = 'cmake.exe'; Version = '4.3.1' },
            @{ Id = 'Ninja-build.Ninja'; Command = 'ninja.exe'; Version = '1.13.2' },
            @{ Id = 'LLVM.LLVM'; Command = 'clang-cl.exe'; Version = $ClangVersion }
        )
    }
    foreach ($package in $packages) {
        $installed = Get-Command $package.Command -ErrorAction SilentlyContinue
        if ($package.Id -eq 'Python.Python.3.12' -and $installed) {
            & $installed.Source -3.12 -c 'import sys; print(sys.version.split()[0])'
            if ($LASTEXITCODE -eq 0) { continue }
        } elseif ($installed) {
            if (-not $package.Version) { continue }
            $pattern = '(?<![\d.])' + [regex]::Escape($package.Version) + '(?![\d.])'
            if ((Invoke-Tool $installed.Source @('--version') -join ' ') -match $pattern) { continue }
        }
        $versionArgs = @()
        if ($package.Version) { $versionArgs = @('--version', $package.Version) }
        Invoke-Tool $winget (@('install', '--id', $package.Id) + $common + $versionArgs)
        Refresh-ToolPath
    }
    if (-not $PublishedOnly -and -not (Get-VsInstallation)) {
        $components = '--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --includeRecommended'
        Invoke-Tool $winget (@('install', '--id', 'Microsoft.VisualStudio.2022.BuildTools', '--override', $components) + $common)
    }
    if (-not $PublishedOnly -and -not (Test-Path -LiteralPath (Join-Path (Get-VulkanSdk) 'Bin/glslangValidator.exe') -PathType Leaf)) {
        Invoke-Tool $winget (@('install', '--id', 'KhronosGroup.VulkanSDK', '--version', $VulkanSdkVersion) + $common)
    }
    Write-Host 'Installation finished. Open a new PowerShell for Prepare or Check.'
}

function Enter-BuildShell {
    # Prefer the standalone tools on PATH before VS extends it with its bundled tools.
    $cmake = (Get-Command cmake.exe).Source
    $ctest = Join-Path (Split-Path -Parent $cmake) 'ctest.exe'
    $ninja = (Get-Command ninja.exe).Source
    $clang = (Get-Command clang-cl.exe).Source
    if (((Invoke-Tool $cmake @('--version')) -join ' ') -notmatch 'cmake version 4\.3\.1\b' -or
        (Invoke-Tool $ninja @('--version')) -ne '1.13.2') {
        throw 'Build expects CMake 4.3.1 and Ninja 1.13.2 first on PATH.'
    }
    $vs = Get-VsInstallation
    if (-not $vs) { throw "VS2022 C++ x64 and Windows SDK $WindowsSdkVersion are required. See the installation guide." }
    $shell = Join-Path $vs 'Common7/Tools/Microsoft.VisualStudio.DevShell.dll'
    Import-Module $shell -ErrorAction Stop
    Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments "-arch=amd64 -host_arch=amd64 -winsdk=$WindowsSdkVersion" | Out-Null
    if ($env:WindowsSDKVersion -notmatch ('^' + [regex]::Escape($WindowsSdkVersion) + '[\\/]?$')) {
        throw "VS did not select Windows SDK $WindowsSdkVersion."
    }
    $clangReported = (Invoke-Tool $clang @('--version')) -join ' '
    if ($clangReported -notmatch ('clang version ' + [regex]::Escape($ClangVersion) + '\b')) {
        throw "Build expects clang-cl $ClangVersion. Put that version first on PATH."
    }
    $sdk = Get-VulkanSdk
    $glslang = Join-Path $sdk 'Bin/glslangValidator.exe'
    Assert-Sha256 $glslang $GlslangSha
    foreach ($file in @('Include/vulkan/vulkan.h', 'Lib/vulkan-1.lib')) {
        if (-not (Test-Path -LiteralPath (Join-Path $sdk $file) -PathType Leaf)) { throw "Missing Vulkan SDK file: $file" }
    }
    [pscustomobject]@{ Cmake = $cmake; Ctest = $ctest; Ninja = $ninja; Clang = $clang; Sdk = $sdk; Glslang = $glslang }
}

function Get-PublishedPackage {
    param($Layout, $Pins)
    $publishedExe = Join-Path $Layout.Published 'game/gt4.exe'
    if (-not (Test-Path -LiteralPath $Layout.Published)) {
        $archive = Join-Path $Layout.Downloads $PublicArchive
        Get-VerifiedDownload "https://github.com/moesuito/gt4-staticrecomp/releases/download/v1.3.0-rc14/$PublicArchive" $archive $PublicArchiveSha
        Expand-Package $archive $Layout.Published
    }
    Assert-Sha256 $publishedExe $Pins.Release.runtime.sha256
    foreach ($entry in $Pins.Runtime.inputs.SHADERS.PSObject.Properties) {
        $path = Join-Path $Layout.Published ("game/shaders/" + $entry.Name)
        Copy-VerifiedFile $path (Get-PrivatePath $Layout ('slice153-pacing-shaders/' + $entry.Name)) $entry.Value
    }
}

function Get-SdlPackage {
    param($Layout, $Pins)
    $sdlPath = Get-PrivatePath $Layout "tooling/sdl3-$($Pins.SDL.version)"
    foreach ($entry in $Pins.SDL.downloads.PSObject.Properties) {
        $subfolder = if ($entry.Name -like '*-devel-*') { 'devel' } else { 'runtime' }
        $target = Join-Path $sdlPath $subfolder
        if (-not (Test-Path -LiteralPath $target)) {
            $archive = Join-Path $Layout.Downloads $entry.Name
            Get-VerifiedDownload "https://github.com/libsdl-org/SDL/releases/download/release-$($Pins.SDL.version)/$($entry.Name)" $archive $entry.Value.sha256
            Expand-Package $archive $target
        }
    }
    foreach ($entry in $Pins.SDL.files.PSObject.Properties) {
        Assert-Sha256 (Join-Path $sdlPath $entry.Value.path) $entry.Value.sha256
    }
    foreach ($entry in $Pins.SDL.headers.PSObject.Properties) {
        Assert-Sha256 (Join-Path $sdlPath $entry.Name) $entry.Value.sha256
    }
}

function Prepare-Disc {
    param($Layout, $Pins, [string]$Image)
    if (-not (Test-Path -LiteralPath $Image -PathType Leaf)) { throw "ISO not found: $Image" }
    if ((Get-Item -LiteralPath $Image).Length -ne $Pins.Disc.disc.size_bytes) {
        throw 'This build requires USA v2.00 SCUS-97328 (5314478080 bytes). For SCES-51719, see PAL.fr.md and Inspect-PAL.ps1.'
    }
    if (-not (Test-Path -LiteralPath $Layout.Input)) {
        Invoke-Tool $Layout.Python @((Join-Path $Layout.Source 'scripts/ee_producer.py'), 'prepare',
            '--assets-root', $Layout.Assets, '--output', $Layout.Input, '--iso', $Image)
    } else {
        Assert-Sha256 $Image $Pins.Disc.disc.sha256
    }
    Assert-Sha256 (Join-Path $Layout.Input 'CORE.GT4') $Pins.Disc.files.'/CORE.GT4;1'.sha256
    Assert-Sha256 (Join-Path $Layout.Input 'SCUS_973.28.elf') $Pins.Elf.native_elf_sha256
    Write-Json (Join-Path $Layout.Root 'local-disc.json') @{ iso = $Image; sha256 = $Pins.Disc.disc.sha256 }
}

function Prepare-SourceCapsules {
    param($Layout, $Pins)
    foreach ($recipe in @(
        @{ Folder = 'slice262-frame-cost-runtime'; Script = 'prepare_perf_runtime.py'; Flags = @('--mtvu', '--gs-stream', '--frame-cost') },
        @{ Folder = 'slice376-frame-render-license-guard-runtime'; Script = 'prepare_license_guard.py'; Flags = @('--display-aspect', '--frame-counters', '--frame-skip') },
        @{ Folder = 'slice200-memcard-runtime'; Script = 'prepare_memcard_flush.py'; Flags = @() },
        @{ Folder = 'slice365-ipu-fast-runtime'; Script = 'prepare_ipu_fast.py'; Flags = @() },
        @{ Folder = 'slice396-spu2-runtime'; Script = 'prepare_spu2_runtime.py'; Flags = @() },
        @{ Folder = 'reference60-usb-runtime'; Script = 'prepare_usb_runtime.py'; Flags = @() }
    )) {
        $output = Get-PrivatePath $Layout $recipe.Folder
        if (-not (Test-Path -LiteralPath $output)) {
            $temp = Get-PrivatePath $Layout ('.capsule-' + [Guid]::NewGuid().ToString('N'))
            try {
                $arguments = @((Join-Path $Layout.Source ("scripts/" + $recipe.Script)), $temp,
                    '--assets-root', $Layout.Assets) + $recipe.Flags
                Invoke-Tool $Layout.Python $arguments | Out-Null
                [IO.Directory]::Move($temp, $output)
            } finally {
                if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse }
            }
            Write-Host "Prepared $($recipe.Folder)"
        }
    }
    $port = Get-PrivatePath $Layout 'slice200-port'
    $portNames = @('gpu.cpp', 'gpu.hpp', 'gs.cpp')
    $missingPort = @($portNames | Where-Object { -not (Test-Path -LiteralPath (Join-Path $port $_) -PathType Leaf) })
    if ($missingPort.Count) {
        $temporary = Get-PrivatePath $Layout ('.port-' + [Guid]::NewGuid().ToString('N'))
        try {
            Invoke-Tool $Layout.Python @((Join-Path $Layout.Source 'scripts/prepare_external_vulkan.py'),
                $temporary, '--assets-root', $Layout.Assets, '--gs-stream-hooks') | Out-Null
            foreach ($name in $portNames) {
                Copy-VerifiedFile (Join-Path $temporary $name) (Join-Path $port $name) $Pins.Runtime.inputs.PORT.$name
            }
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse }
        }
    }
}

function Prepare-Workspace {
    param($Layout, [string]$Image)
    $space = Get-Item -LiteralPath ([IO.Path]::GetPathRoot($Layout.Root))
    Write-Host ('Workspace drive free space: {0:N1} GiB' -f ($space.PSDrive.Free / 1GB))
    Get-GitTree 'https://github.com/moesuito/gt4-staticrecomp.git' $Layout.Source $MainRevision $BranchName
    $pins = Get-Pins $Layout.Source
    Get-GitTree 'https://github.com/snuri00/ps2-web-recomp.git' $Layout.Donor $DonorRevision -Crlf
    foreach ($pin in $pins.Donor.source_pins) {
        Assert-Sha256 (Join-Path $Layout.Assets $pin.path) $pin.sha256
    }
    if (-not (Test-Path -LiteralPath $Layout.Python -PathType Leaf)) {
        Invoke-Tool 'py.exe' @('-3.12', '-m', 'venv', (Join-Path $Layout.Root 'python'))
    }
    Invoke-Tool $Layout.Python @('-m', 'pip', 'install', '--disable-pip-version-check', '-r',
        (Join-Path $Layout.Source 'scripts/requirements.txt'))
    if ($Image) { Prepare-Disc $Layout $pins ([IO.Path]::GetFullPath($Image)) }

    Get-PublishedPackage $Layout $pins
    if ($PublishedOnly) {
        Write-Host "Published package prepared in $($Layout.Root)"
        return
    }
    Get-SdlPackage $Layout $pins
    Prepare-SourceCapsules $Layout $pins

    $headerPrefix = 'private/tooling/pcsx2-slice101-source/'
    $headerUrl = 'https://raw.githubusercontent.com/PCSX2/pcsx2/aa7ab4306e269075784c7ac3eb4b45e6e6c53445/'
    foreach ($header in $pins.VulkanHeaders) {
        $url = $headerUrl + $header.path.Substring($headerPrefix.Length)
        Get-VerifiedDownload $url (Join-Path $Layout.Assets $header.path) $header.sha256 -PinnedCrlf
    }
    Write-Host "Preparation saved in $($Layout.Root)"
    Write-Host 'Run Check to see what remains for a local source build.'
}

function Get-SourceBuildIssues {
    param($Layout, $Pins)
    $required = [ordered]@{
        $Layout.Python = ''
        (Join-Path $Layout.Root 'local-disc.json') = ''
        (Join-Path $Layout.Input 'SCUS_973.28.elf') = $Pins.Elf.native_elf_sha256
        (Join-Path $Layout.Assets $Pins.Aspect.path) = $Pins.Aspect.sha256
        (Join-Path (Get-VulkanSdk) 'Bin/glslangValidator.exe') = $GlslangSha
        (Join-Path (Get-VulkanSdk) 'Include/vulkan/vulkan.h') = ''
        (Join-Path (Get-VulkanSdk) 'Lib/vulkan-1.lib') = ''
    }
    foreach ($pin in @($Pins.Donor.source_pins) + @($Pins.VulkanHeaders)) {
        $required[(Join-Path $Layout.Assets $pin.path)] = $pin.sha256
    }
    foreach ($entry in @(
        @{ Path = 'slice200-port'; Files = $Pins.Runtime.inputs.PORT },
        @{ Path = 'slice153-pacing-shaders'; Files = $Pins.Runtime.inputs.SHADERS },
        @{ Path = 'slice262-frame-cost-runtime'; Files = $Pins.Runtime.source_sha256 },
        @{ Path = 'slice376-frame-render-license-guard-runtime'; Files = $Pins.Guard.source_sha256 }
    )) {
        foreach ($file in $entry.Files.PSObject.Properties) {
            $required[(Get-PrivatePath $Layout ($entry.Path + '/' + $file.Name))] = $file.Value
        }
    }
    $required[(Get-PrivatePath $Layout 'slice262-frame-cost-runtime/runtime.json')] = $Pins.Runtime.receipt_sha256
    $required[(Get-PrivatePath $Layout 'slice376-frame-render-license-guard-runtime/runtime.json')] = $Pins.Guard.receipt_sha256
    foreach ($entry in @(
        'slice200-memcard-runtime/sio2.cpp', 'slice200-memcard-runtime/runtime.json',
        'slice365-ipu-fast-runtime/ipu.cpp', 'slice365-ipu-fast-runtime/runtime.json',
        'slice396-spu2-runtime/spu2.cpp', 'slice396-spu2-runtime/runtime.json',
        'reference60-usb-runtime/hw.cpp', 'reference60-usb-runtime/runtime.json'
    )) {
        $required[(Get-PrivatePath $Layout $entry)] = ''
    }
    foreach ($entry in $Pins.SDL.files.PSObject.Properties) {
        $required[(Get-PrivatePath $Layout ("tooling/sdl3-$($Pins.SDL.version)/" + $entry.Value.path))] = $entry.Value.sha256
    }
    foreach ($entry in $Pins.SDL.headers.PSObject.Properties) {
        $required[(Get-PrivatePath $Layout ("tooling/sdl3-$($Pins.SDL.version)/" + $entry.Name))] = $entry.Value.sha256
    }
    foreach ($path in $required.Keys) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            "Missing: $path"
        } elseif ($required[$path] -and (Get-Sha256 $path) -ne $required[$path]) {
            "SHA-256 mismatch: $path"
        }
    }
    foreach ($tool in @('git.exe', 'cmake.exe', 'ninja.exe', 'clang-cl.exe')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { "Missing tool on PATH: $tool" }
    }
    if (-not (Get-VsInstallation)) { "Missing VS2022 C++ x64 tools or Windows SDK $WindowsSdkVersion" }
}

function Prepare-VuTables {
    param($Layout, $Tools)
    $output = Get-PrivatePath $Layout 'reference60-vu'
    $recompiler = Join-Path $Layout.Builds 'vu-emitter/gt4_vu_recomp.exe'
    if (-not (Test-Path -LiteralPath $output)) {
        $emitterBuild = Split-Path -Parent $recompiler
        $null = New-Item -ItemType Directory -Force -Path $emitterBuild
        Push-Location $emitterBuild
        try {
            $emitterSource = Join-Path $Layout.Source 'tools/vu_recomp/src'
            Invoke-Tool $Tools.Clang @('/nologo', '/EHsc', '/O2', '/std:c++20',
                ('/I' + (Join-Path $Layout.Donor 'runtime/include')), ('/I' + (Join-Path $Layout.Donor 'runtime/src')),
                (Join-Path $emitterSource 'vurecomp.cpp'), (Join-Path $emitterSource 'sha256.cpp'),
                (Join-Path $emitterSource 'vurecomp_main.cpp'), '/link', ('/OUT:' + $recompiler))
        } finally {
            Pop-Location
        }
    }
    Invoke-Tool $Layout.Python @((Join-Path $PSScriptRoot 'prepare_vu.py'), $Layout.Source,
        (Join-Path $Layout.Input 'SCUS_973.28.elf'), $recompiler, $output)
    $output
}

function Build-Reference {
    param($Layout, $Pins)
    Assert-CleanTree $Layout.Source $MainRevision
    Assert-CleanTree $Layout.Donor $DonorRevision
    $tools = Enter-BuildShell
    $vu = @(Prepare-VuTables $Layout $tools)[-1]
    $cache = [ordered]@{
        CMAKE_BUILD_TYPE = 'Release'
        CMAKE_MAKE_PROGRAM = $tools.Ninja
        CMAKE_C_COMPILER = $tools.Clang
        CMAKE_CXX_COMPILER = $tools.Clang
        CMAKE_C_FLAGS_RELEASE = '/O2 /Ob2 /DNDEBUG /Z7 -gline-tables-only'
        CMAKE_CXX_FLAGS_RELEASE = '/O2 /Ob2 /DNDEBUG /Z7 -gline-tables-only'
        CMAKE_EXE_LINKER_FLAGS_RELEASE = '/INCREMENTAL:NO /DEBUG /OPT:REF /OPT:ICF'
        GT4_ASSETS_ROOT = $Layout.Assets
        GT4_PYTHON = $Layout.Python
        GT4_EE_PROFILE = 'aspect'
        GT4_TARGET = 'v200'
        GT4_HW_GS = 'ON'
        GT4_HW_VULKAN_SDK = $tools.Sdk
        GT4_HW_GLSLANG = $tools.Glslang
        GT4_RELEASE_DISTRIBUTION = 'ON'
        GT4_SDL3_ROOT = Get-PrivatePath $Layout "tooling/sdl3-$($Pins.SDL.version)"
        GT4_PORT_DIR = Get-PrivatePath $Layout 'slice200-port'
        GT4_SHADER_DIR = Get-PrivatePath $Layout 'slice153-pacing-shaders'
        GT4_PERF_RUNTIME_SOURCE = Get-PrivatePath $Layout 'slice262-frame-cost-runtime'
        GT4_LICENSE_GUARD_SOURCE = Get-PrivatePath $Layout 'slice376-frame-render-license-guard-runtime'
        GT4_MEMCARD_RUNTIME_SOURCE = Get-PrivatePath $Layout 'slice200-memcard-runtime'
        GT4_IPU_RUNTIME_SOURCE = Get-PrivatePath $Layout 'slice365-ipu-fast-runtime'
        GT4_SPU2_RUNTIME_SOURCE = Get-PrivatePath $Layout 'slice396-spu2-runtime'
        GT4_USB_RUNTIME_SOURCE = Get-PrivatePath $Layout 'reference60-usb-runtime'
        GT4_VU1_GENERATED_DIR = Join-Path $vu 'vu1-gen'
        GT4_VU0_GENERATED_DIR = Join-Path $vu 'vu0-gen'
        GT4_VU0_IMAGE_FILE = Join-Path $vu 'vu0-image/vu0_image.bin'
    }
    $configureArgs = @('-S', $Layout.Source, '-B', $Layout.Build, '-G', 'Ninja')
    foreach ($entry in $cache.GetEnumerator()) {
        $configureArgs += ('-D' + $entry.Key + '=' + ([string]$entry.Value).Replace('\', '/'))
    }
    $receipt = @{
        source = $MainRevision
        donor = $DonorRevision
        ee_library_sha256 = $Pins.Aspect.sha256
        clang = (Invoke-Tool $tools.Clang @('--version')) -join "`n"
        cmake = (Invoke-Tool $tools.Cmake @('--version')) -join "`n"
        ninja = (Invoke-Tool $tools.Ninja @('--version')) -join "`n"
        windows_sdk = $WindowsSdkVersion
        glslang_sha256 = $GlslangSha
        configure = $cache
    }
    $null = New-Item -ItemType Directory -Force -Path $Layout.Build
    $buildReceipt = Join-Path $Layout.Build 'reference-build.json'
    # A failed re-build must leave no usable receipt.
    if (Test-Path -LiteralPath $buildReceipt) { Remove-Item -LiteralPath $buildReceipt }
    Invoke-Tool $tools.Cmake $configureArgs
    Invoke-Tool $tools.Cmake @('--build', $Layout.Build, '--parallel', '2', '--target', 'gt4vulkan',
        'pacing_fixture', 'frame_skip_fixture', 'pad_mapping_fixture', 'usb_dfp_fixture', 'wheel_fixture', 'hw_gs_smoke')
    Invoke-Tool $tools.Ctest @('--test-dir', $Layout.Build, '--no-tests=error', '--output-on-failure',
        '-R', '^native_(pacing|frame_skip|pad_mapping|usb_dfp|wheel)$')
    $receipt.executable_sha256 = Get-Sha256 (Join-Path $Layout.Build 'gt4vulkan.exe')
    Write-Json $buildReceipt $receipt
    Write-Host "Build and selected CTest checks finished: $($Layout.Build)"
    Write-Host 'Run Shaders, then test a race on the target PC. No FPS is inferred from compilation.'
}

function Show-Hardware {
    param($Layout)
    $diagnostics = New-RunDirectory $Layout 'hardware'
    $context = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber
    $cpu = Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors
    $video = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, CurrentRefreshRate
    $wheel = @(Get-PnpDevice -PresentOnly | Where-Object {
        $_.InstanceId -like '*VID_046D&PID_C29A*' -or $_.FriendlyName -like '*Driving Force*'
    } | Select-Object Status, FriendlyName)
    Write-Json (Join-Path $diagnostics 'hardware.json') @{ windows = $context; cpu = $cpu; video = @($video); wheel = $wheel }
    $video | Format-Table
    $wheel | Format-Table
    if (-not $wheel.Count) { Write-Warning 'Driving Force GT was not found by name or USB identifier.' }
    $sdk = Get-VulkanSdk
    $vulkanInfo = Join-Path $sdk 'Bin/vulkaninfoSDK.exe'
    if (-not (Test-Path -LiteralPath $vulkanInfo -PathType Leaf)) { $vulkanInfo = Join-Path $sdk 'Bin/vulkaninfo.exe' }
    if (Test-Path -LiteralPath $vulkanInfo -PathType Leaf) {
        Invoke-Tool $vulkanInfo @('--summary') | Tee-Object -FilePath (Join-Path $diagnostics 'vulkan-summary.txt')
        Invoke-Tool $vulkanInfo @() | Set-Content -LiteralPath (Join-Path $diagnostics 'vulkan-full.txt') -Encoding UTF8
    } else {
        Write-Warning 'Vulkan SDK diagnostic utility was not found.'
    }
    Write-Host "Hardware reports: $diagnostics"
    Write-Host 'Confirm the physical GTX 1070 Vulkan API, queue properties, display mode and the wheel tests in the guide.'
}

Assert-WindowsX64
$layout = Use-Workspace $Workspace
switch ($Action) {
    'Install' { Install-Dependencies }
    'Prepare' { Prepare-Workspace $layout $Iso }
    'StageTask090' {
        Get-GitTree 'https://github.com/moesuito/gt4-staticrecomp.git' (Join-Path $layout.Root 'task090-inspection') $Task090Revision
        Write-Host 'Pinned TASK-090 sources prepared separately for inspection.'
    }
    'Hardware' { Show-Hardware $layout }
    default {
        if (-not (Test-Path -LiteralPath (Join-Path $layout.Source '.git') -PathType Container)) { throw 'Run Prepare first.' }
        Assert-CleanTree $layout.Source $MainRevision
        $pins = Get-Pins $layout.Source
        $issues = @(Get-SourceBuildIssues $layout $pins)
        if ($issues.Count) {
            $issues | ForEach-Object { Write-Host $_ }
            throw "Source-build preflight found $($issues.Count) issue(s). See the guide before retrying."
        }
        if ($Action -eq 'Build') { Build-Reference $layout $pins } else {
            Write-Host 'Preflight files verified. Build will check the compiler, generate VU tables and run CTest.'
        }
    }
}
