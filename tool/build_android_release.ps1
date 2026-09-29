[CmdletBinding()]
param(
    [ValidateSet('arm64', 'arm32', 'x64')]
    [string[]]$Architectures = @('arm64'),
    [string]$Flutter = 'flutter',
    [string[]]$DartDefine = @(),
    [string]$DartDefineFromFile
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$platforms = @{ arm64 = 'android-arm64'; arm32 = 'android-arm'; x64 = 'android-x64' }
$abis = @{ arm64 = 'arm64-v8a'; arm32 = 'armeabi-v7a'; x64 = 'x86_64' }
$selected = @($Architectures | Select-Object -Unique)
if ($selected.Count -eq 0) { throw 'Select at least one architecture.' }
$targets = ($selected | ForEach-Object { $platforms[$_] }) -join ','
$buildArguments = @('build', 'apk', '--release', '--split-per-abi', "--target-platform=$targets")
foreach ($define in $DartDefine) { $buildArguments += "--dart-define=$define" }
if ($DartDefineFromFile) {
    $defineFile = (Resolve-Path -LiteralPath $DartDefineFromFile).Path
    $buildArguments += "--dart-define-from-file=$defineFile"
}

Push-Location $projectRoot
try {
    & $Flutter @buildArguments
    if ($LASTEXITCODE -ne 0) { throw "Flutter release build failed (exit $LASTEXITCODE)." }

    $version = [regex]::Match((Get-Content -Raw -LiteralPath 'pubspec.yaml'), '(?m)^version:\s*([^+\s]+)\+(\d+)\s*$')
    if (-not $version.Success) { throw 'Expected version: name+build in pubspec.yaml.' }
    $metadata = Get-Content -Raw -LiteralPath 'build/app/outputs/apk/release/output-metadata.json' | ConvertFrom-Json
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($architecture in $selected) {
        $abi = $abis[$architecture]
        $apkPath = Join-Path $projectRoot "build/app/outputs/flutter-apk/app-$abi-release.apk"
        $apk = Get-Item -LiteralPath $apkPath
        $output = @($metadata.elements | Where-Object { $_.outputFile -eq $apk.Name })
        if ($output.Count -ne 1 -or $output[0].versionName -ne $version.Groups[1].Value -or
            $output[0].versionCode -ne [int]$version.Groups[2].Value) {
            throw "APK version does not match pubspec.yaml: $apkPath"
        }
        $archive = [IO.Compression.ZipFile]::OpenRead($apk.FullName)
        try {
            $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
            $actualAbis = @($entryNames | Where-Object { $_ -match '^lib/[^/]+/[^/]+\.so$' } |
                ForEach-Object { $_.Split('/')[1] } | Sort-Object -Unique)
            if ($actualAbis.Count -ne 1 -or $actualAbis[0] -ne $abi) {
                throw "Unexpected architectures in ${apkPath}: $($actualAbis -join ', ')"
            }
            foreach ($library in @('libapp.so', 'libflutter.so')) {
                if ($entryNames -notcontains "lib/$abi/$library") {
                    throw "Missing $library for $abi in $apkPath"
                }
            }
            if ($entryNames -contains 'assets/flutter_assets/assets/fonts/NotoSansSC-Variable.ttf') {
                throw "Unused variable font is bundled again: $apkPath"
            }
        } finally {
            $archive.Dispose()
        }
        [PSCustomObject]@{
            Architecture = $abi
            Version = "$($version.Groups[1].Value)+$($version.Groups[2].Value)"
            MiB = [Math]::Round($apk.Length / 1MB, 2)
            Apk = $apk.FullName
        }
    }
} finally {
    Pop-Location
}
