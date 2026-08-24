param(
  [string]$Version = "1.0.0"
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$publicRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "build\public"))
$packageName = "MineLua-$Version-windows-x64"
$packageRoot = [System.IO.Path]::GetFullPath((Join-Path $publicRoot $packageName))
$launcherBuild = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "build\release-launcher"))
$archivePath = Join-Path $publicRoot "$packageName.zip"

if (-not $publicRoot.StartsWith((Join-Path $projectRoot "build"), [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to package outside the project build directory."
}
if (-not $packageRoot.StartsWith($publicRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Invalid package output path."
}

New-Item -ItemType Directory -Force -Path $publicRoot | Out-Null
if (Test-Path -LiteralPath $packageRoot) { Remove-Item -LiteralPath $packageRoot -Recurse -Force }
if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
New-Item -ItemType Directory -Force -Path $packageRoot,$launcherBuild | Out-Null

$vsRoot = "C:\Program Files\Microsoft Visual Studio\18\Community"
$vcvars = Join-Path $vsRoot "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path -LiteralPath $vcvars)) {
  throw "Visual Studio x64 build tools were not found at $vcvars"
}

$launcherSource = Join-Path $projectRoot "native\release_launcher.c"
$launcherExe = Join-Path $launcherBuild "MineLua.exe"
$compileCommand = 'call "{0}" >nul && cl /nologo /O2 /MT /W4 /WX /Fe:"{1}" "{2}" /link /SUBSYSTEM:WINDOWS shell32.lib user32.lib' -f $vcvars,$launcherExe,$launcherSource
& cmd.exe /d /s /c $compileCommand
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $launcherExe)) {
  throw "MineLua release launcher compilation failed."
}

Copy-Item -LiteralPath $launcherExe -Destination (Join-Path $packageRoot "MineLua.exe")
foreach ($directory in @("assets", "data", "src")) {
  Copy-Item -LiteralPath (Join-Path $projectRoot $directory) -Destination $packageRoot -Recurse
}
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "lib"),(Join-Path $packageRoot "saves") | Out-Null

$runtimeFiles = @(
  "glfw3.dll",
  "lua51.dll",
  "luajit.exe",
  "luajit.exe.manifest",
  "minelua_imgui_tools_v2.dll",
  "stb_image.dll"
)
foreach ($file in $runtimeFiles) {
  $source = Join-Path $projectRoot "lib\$file"
  if (-not (Test-Path -LiteralPath $source)) { throw "Missing runtime dependency: $source" }
  Copy-Item -LiteralPath $source -Destination (Join-Path $packageRoot "lib\$file")
}

$redistRoot = Join-Path $vsRoot "VC\Redist\MSVC"
$redistVersion = Get-ChildItem -LiteralPath $redistRoot -Directory |
  Where-Object { $_.Name -match '^\d+\.\d+' } |
  Sort-Object { [version]$_.Name } -Descending |
  Select-Object -First 1
if ($redistVersion) {
  $crt = Get-ChildItem -LiteralPath (Join-Path $redistVersion.FullName "x64") -Directory |
    Where-Object { $_.Name -like "Microsoft.VC*.CRT" } |
    Select-Object -First 1
  if ($crt) {
    Get-ChildItem -LiteralPath $crt.FullName -Filter "*.dll" -File | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $packageRoot "lib")
    }
  }
}

Copy-Item -LiteralPath (Join-Path $projectRoot "release\README.md") -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $projectRoot "release\RELEASE_NOTES.md") -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $projectRoot "THIRD_PARTY_NOTICES.md") -Destination $packageRoot

$commit = (& git -C $projectRoot rev-parse --short HEAD 2>$null)
$dirty = [bool](& git -C $projectRoot status --porcelain 2>$null)
$manifest = [ordered]@{
  product = "MineLua"
  version = $Version
  platform = "windows-x64"
  builtUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  sourceCommit = "$commit"
  includesWorkingTreeChanges = $dirty
  launcher = "MineLua.exe"
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $packageRoot "BUILD_MANIFEST.json") -Encoding utf8

$checksums = Get-ChildItem -LiteralPath $packageRoot -File -Recurse |
  Where-Object { $_.Name -ne "SHA256SUMS.txt" } |
  Sort-Object FullName |
  ForEach-Object {
    $relative = [System.IO.Path]::GetRelativePath($packageRoot, $_.FullName).Replace('\','/')
    "{0}  {1}" -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(),$relative
  }
$checksums | Set-Content -LiteralPath (Join-Path $packageRoot "SHA256SUMS.txt") -Encoding ascii

Compress-Archive -LiteralPath $packageRoot -DestinationPath $archivePath -CompressionLevel Optimal
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$archivePath.sha256" -Value "$archiveHash  $packageName.zip" -Encoding ascii

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
  if ($zip.Entries.Count -lt 100) { throw "Release archive is unexpectedly incomplete." }
  if (-not ($zip.Entries | Where-Object { $_.FullName -eq "$packageName/MineLua.exe" })) {
    throw "Release archive does not contain MineLua.exe."
  }
  $entryCount = $zip.Entries.Count
} finally {
  $zip.Dispose()
}

[pscustomobject]@{
  Package = $packageRoot
  Archive = $archivePath
  Sha256 = $archiveHash
  Entries = $entryCount
  Bytes = (Get-Item -LiteralPath $archivePath).Length
}
