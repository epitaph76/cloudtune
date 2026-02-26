param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$BuildArgs
)

$pubspecPath = Join-Path $PSScriptRoot "..\pubspec.yaml"
$pubspecPath = [System.IO.Path]::GetFullPath($pubspecPath)
$content = Get-Content -Path $pubspecPath -Raw
$versionPattern = '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$'
$match = [regex]::Match($content, $versionPattern)

if (-not $match.Success) {
    throw "version not found in $pubspecPath"
}

$major = [int]$match.Groups[1].Value
$minor = [int]$match.Groups[2].Value
$patch = [int]$match.Groups[3].Value + 1
$build = [int]$match.Groups[4].Value
$newVersion = "$major.$minor.$patch+$build"
$updated = [regex]::Replace($content, $versionPattern, "version: $newVersion", 1)
[System.IO.File]::WriteAllText($pubspecPath, $updated, [System.Text.UTF8Encoding]::new($false))

if ($BuildArgs.Count -eq 0) {
    throw "Usage: ./tool/flutter_build.ps1 <flutter build args>, example: ./tool/flutter_build.ps1 apk --release"
}

Write-Host "Version bumped to $newVersion"
& flutter build @BuildArgs
exit $LASTEXITCODE
