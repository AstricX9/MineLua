param(
  [string]$Version = "1.0.0",
  # Ships loose assets and readable Lua source, the way releases were built
  # before the container existed. Useful when a packaged build misbehaves and
  # you need to bisect against an unobfuscated one.
  [switch]$PlainAssets
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$logsRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "logs"))
$buildLogsRoot = [System.IO.Path]::GetFullPath((Join-Path $logsRoot "build"))
New-Item -ItemType Directory -Force -Path $logsRoot,$buildLogsRoot | Out-Null

$logVersion = $Version -replace '[^A-Za-z0-9._-]', '_'
$logTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$buildLogPath = Join-Path $buildLogsRoot "release-$logVersion-$logTimestamp.log"
Start-Transcript -LiteralPath $buildLogPath -Force | Out-Null
$transcriptStarted = $true
Write-Host "Build log: $buildLogPath"

try {
$publicRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "build\public"))

# Number successful release archives consecutively. Failed builds do not
# consume a number because only completed .zip files are considered.
$buildNumber = 1
if (Test-Path -LiteralPath $publicRoot) {
  $previousBuildNumbers = Get-ChildItem -LiteralPath $publicRoot -File -Filter "MineLua-*-build*-windows-x64.zip" |
    ForEach-Object {
      if ($_.Name -match '^MineLua-.+-build(?<number>\d+)-windows-x64\.zip$') {
        [int]$Matches.number
      }
  }
  if ($previousBuildNumbers) {
    $buildNumber = 1 + [int](($previousBuildNumbers | Measure-Object -Maximum).Maximum)
  }
}

$packageName = "MineLua-$Version-build$buildNumber-windows-x64"
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
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "lib"),(Join-Path $packageRoot "saves") | Out-Null

$containerKey = $null
if ($PlainAssets) {
  foreach ($directory in @("assets", "data", "src")) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $directory) -Destination $packageRoot -Recurse
  }
} else {
  # Every module becomes stripped bytecode and every asset moves into one
  # encrypted container, leaving the package with no readable source and no
  # loose textures, sounds, models or definitions. See docs/obfuscation.md.
  $luajit = Join-Path $projectRoot "lib\luajit.exe"
  $packer = Join-Path $projectRoot "scripts\obfuscate\pack.lua"
  $packOutput = & $luajit $packer --root $projectRoot --out $packageRoot
  if ($LASTEXITCODE -ne 0) { throw "Asset obfuscation failed:`n$($packOutput -join "`n")" }
  $packOutput | ForEach-Object { Write-Host "  $_" }

  $containerKey = ($packOutput | Select-String -Pattern '^container key (\w+) salt (\w+)$' |
    Select-Object -First 1)
  if (-not $containerKey) { throw "The packer did not report a container key." }

  # Settings stay loose so players can still edit them; the packed copy is
  # deliberately excluded from the container.
  New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "data\config") | Out-Null
  Copy-Item -LiteralPath (Join-Path $projectRoot "data\config\settings.json") `
    -Destination (Join-Path $packageRoot "data\config\settings.json")

  $container = Join-Path $packageRoot "lib\minelua.pak"
  if (-not (Test-Path -LiteralPath $container)) { throw "The asset container was not produced." }
  if ((Get-Item -LiteralPath $container).Length -lt 1MB) { throw "The asset container is implausibly small." }

  # Nothing that reads as Lua source may reach the package: every .lua file in
  # it has to be a LuaJIT bytecode stub.
  $sourceLeaks = Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter *.lua |
    Where-Object {
      $head = [byte[]]::new(3)
      $stream = [System.IO.File]::OpenRead($_.FullName)
      try { $read = $stream.Read($head, 0, 3) } finally { $stream.Dispose() }
      -not ($read -eq 3 -and $head[0] -eq 0x1B -and $head[1] -eq 0x4C -and $head[2] -eq 0x4A)
    }
  if ($sourceLeaks) {
    throw "Readable Lua source reached the package: $($sourceLeaks.FullName -join ', ')"
  }
  foreach ($directory in @("assets", "src\worldgen")) {
    if (Test-Path -LiteralPath (Join-Path $packageRoot $directory)) {
      throw "Loose $directory survived obfuscation."
    }
  }
}

$runtimeFiles = @(
  "glfw3.dll",
  "lua51.dll",
  "luajit.exe",
  "luajit.exe.manifest",
  "minelua_imgui_tools_v5.dll",
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
  buildNumber = $buildNumber
  platform = "windows-x64"
  builtUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  sourceCommit = "$commit"
  includesWorkingTreeChanges = $dirty
  launcher = "MineLua.exe"
  obfuscated = (-not $PlainAssets)
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $packageRoot "BUILD_MANIFEST.json") -Encoding utf8

$packageRootPrefix = "$packageRoot\"
$checksums = Get-ChildItem -LiteralPath $packageRoot -File -Recurse |
  Where-Object { $_.Name -ne "SHA256SUMS.txt" } |
  Sort-Object FullName |
  ForEach-Object {
    if (-not $_.FullName.StartsWith($packageRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to checksum a file outside the package root: $($_.FullName)"
    }
    # System.IO.Path.GetRelativePath is unavailable in Windows PowerShell 5.1's
    # .NET Framework runtime. Every input was recursively enumerated beneath
    # packageRoot, so removing the already-validated prefix is equivalent and
    # works on both Windows PowerShell 5.1 and modern PowerShell.
    $relative = $_.FullName.Substring($packageRootPrefix.Length).Replace('\','/')
    "{0}  {1}" -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(),$relative
  }
$checksums | Set-Content -LiteralPath (Join-Path $packageRoot "SHA256SUMS.txt") -Encoding ascii

Compress-Archive -LiteralPath $packageRoot -DestinationPath $archivePath -CompressionLevel Optimal
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$archivePath.sha256" -Value "$archiveHash  $packageName.zip" -Encoding ascii

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
  # Windows PowerShell 5.1's Compress-Archive stores directory separators as
  # backslashes. Normalize once so archive validation is independent of the
  # PowerShell/.NET version that created the zip.
  $archiveNames = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
  # An obfuscated package is a handful of files, so the old "at least a hundred
  # entries" sanity check only applies to a loose one. What stands in for it is
  # the container: it carries everything those entries used to be.
  $minimumEntries = if ($PlainAssets) { 100 } else { 12 }
  if ($zip.Entries.Count -lt $minimumEntries) { throw "Release archive is unexpectedly incomplete." }
  if ($archiveNames -notcontains "$packageName/MineLua.exe") {
    throw "Release archive does not contain MineLua.exe."
  }
  if (-not $PlainAssets) {
    if ($archiveNames -notcontains "$packageName/lib/minelua.pak") {
      throw "Release archive does not contain the asset container."
    }
    $strayAssets = $archiveNames | Where-Object { $_ -match '\.(png|wav|json|vsh|fsh|glsl)$' } |
      Where-Object { $_ -ne "$packageName/data/config/settings.json" -and
                     $_ -ne "$packageName/BUILD_MANIFEST.json" }
    if ($strayAssets) {
      throw "Loose assets reached the archive: $($strayAssets -join ', ')"
    }
  }
  $entryCount = $zip.Entries.Count
} finally {
  $zip.Dispose()
}

# The container key is what a future build would need to open this package
# again. It is deliberately kept beside the archive instead of inside it.
if ($containerKey) {
  $keyPath = Join-Path $publicRoot "$packageName.container-key.txt"
  Set-Content -LiteralPath $keyPath -Encoding ascii -Value @(
    "MineLua $Version build $buildNumber container key -- do not ship this file.",
    $containerKey.Line
  )
}

[pscustomobject]@{
  BuildNumber = $buildNumber
  Package = $packageRoot
  Archive = $archivePath
  Sha256 = $archiveHash
  Entries = $entryCount
  Bytes = (Get-Item -LiteralPath $archivePath).Length
  Obfuscated = (-not $PlainAssets)
}
} catch {
  Write-Host "BUILD FAILED" -ForegroundColor Red
  Write-Host ($_ | Out-String) -ForegroundColor Red
  # A zip is not a successful release until all validation above has passed.
  # Remove failed archives so they do not consume the next build number.
  if ($archivePath -and (Test-Path -LiteralPath $archivePath)) {
    Remove-Item -LiteralPath $archivePath -Force
  }
  if ($archivePath -and (Test-Path -LiteralPath "$archivePath.sha256")) {
    Remove-Item -LiteralPath "$archivePath.sha256" -Force
  }
  throw
} finally {
  if ($transcriptStarted) {
    try { Stop-Transcript | Out-Null } catch { }
  }
}
