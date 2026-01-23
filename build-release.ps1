# ============================================================================
# LanmarkTekFix Release Builder
# ============================================================================
# This script builds the installer, generates SHA256 hash, and prepares
# the winget manifest for submission.
#
# Prerequisites:
#   - .NET 8 SDK installed
#   - Inno Setup 6 installed (default path or set $InnoSetupPath)
#   - gh CLI installed and authenticated (for publishing release)
#
# Usage:
#   .\build-release.ps1 -Version "3.1.2"
#   .\build-release.ps1 -Version "3.1.2" -Publish
# ============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,

    [switch]$Publish,

    [string]$SourcePath = "Y:\Lanmark\LanmarkTekFix-Windows",
    [string]$InnoSetupPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    [string]$OutputDir = "Y:\Lanmark\tekfix-releases"
)

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " LanmarkTekFix Release Builder v$Version" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Build the .NET project
Write-Host "[1/5] Building .NET project..." -ForegroundColor Yellow
$publishDir = Join-Path $SourcePath "publish"

# Clean previous publish
if (Test-Path $publishDir) {
    Remove-Item $publishDir -Recurse -Force
}

Push-Location $SourcePath
dotnet publish -c Release -r win-x64 --self-contained true -o $publishDir
if ($LASTEXITCODE -ne 0) {
    Write-Error "dotnet publish failed!"
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "  Build complete." -ForegroundColor Green

# Step 2: Compile Inno Setup installer (silent version)
Write-Host "[2/5] Compiling silent installer..." -ForegroundColor Yellow
$issFile = Join-Path $SourcePath "TekFixTrayAgent-Silent.iss"

if (-not (Test-Path $InnoSetupPath)) {
    Write-Error "Inno Setup not found at: $InnoSetupPath"
    Write-Host "Install from: https://jrsoftware.org/isdl.php"
    exit 1
}

& $InnoSetupPath $issFile
if ($LASTEXITCODE -ne 0) {
    Write-Error "Inno Setup compilation failed!"
    exit 1
}
Write-Host "  Installer compiled." -ForegroundColor Green

# Step 3: Calculate SHA256
Write-Host "[3/5] Calculating SHA256 hash..." -ForegroundColor Yellow
$installerPath = Join-Path $SourcePath "installer\LanmarkTekFixSetup_v${Version}_Silent.exe"

if (-not (Test-Path $installerPath)) {
    Write-Error "Installer not found at: $installerPath"
    exit 1
}

$hash = (Get-FileHash $installerPath -Algorithm SHA256).Hash
Write-Host "  SHA256: $hash" -ForegroundColor Green

# Step 4: Update winget manifest with correct hash
Write-Host "[4/5] Updating winget manifest..." -ForegroundColor Yellow
$manifestDir = Join-Path $OutputDir "winget\manifests\l\Lanmark\TekFixSupportAgent\$Version"

if (-not (Test-Path $manifestDir)) {
    New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
}

$installerYaml = Join-Path $manifestDir "Lanmark.TekFixSupportAgent.installer.yaml"
if (Test-Path $installerYaml) {
    $content = Get-Content $installerYaml -Raw
    $content = $content -replace "REPLACE_WITH_ACTUAL_SHA256", $hash
    $content = $content -replace "InstallerSha256: [A-Fa-f0-9]{64}", "InstallerSha256: $hash"
    Set-Content $installerYaml $content
    Write-Host "  Manifest updated with SHA256." -ForegroundColor Green
} else {
    Write-Warning "Manifest file not found: $installerYaml"
}

# Step 5: Publish to GitHub (if -Publish flag set)
if ($Publish) {
    Write-Host "[5/5] Publishing to GitHub..." -ForegroundColor Yellow

    # Copy installer to releases folder
    $releasesDir = Join-Path $OutputDir "releases"
    if (-not (Test-Path $releasesDir)) {
        New-Item -ItemType Directory -Path $releasesDir -Force | Out-Null
    }
    Copy-Item $installerPath $releasesDir

    # Create GitHub release
    Push-Location $OutputDir
    gh release create "v$Version" `
        "$installerPath" `
        --title "LanmarkTekFix Support Agent v$Version" `
        --notes "## LanmarkTekFix Support Agent v$Version`n`nSilent installer for RMM/winget deployment.`n`n### Install`n```````nwinget install Lanmark.TekFixSupportAgent`n```````n`n### Silent Install (RMM)`n``````powershell`nLanmarkTekFixSetup_v${Version}_Silent.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART`n```````n`nSHA256: ``$hash``"

    if ($LASTEXITCODE -ne 0) {
        Write-Error "GitHub release creation failed! Make sure gh is authenticated."
        Pop-Location
        exit 1
    }
    Pop-Location
    Write-Host "  Release published!" -ForegroundColor Green
} else {
    Write-Host "[5/5] Skipping publish (use -Publish flag to upload to GitHub)" -ForegroundColor Gray
}

# Summary
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Release Build Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Installer: $installerPath" -ForegroundColor White
Write-Host "  SHA256:    $hash" -ForegroundColor White
Write-Host "  Manifest:  $manifestDir" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Create release:  .\build-release.ps1 -Version $Version -Publish" -ForegroundColor White
Write-Host "  2. Submit to winget: Fork microsoft/winget-pkgs, copy manifest, submit PR" -ForegroundColor White
Write-Host "  3. Or use wingetcreate:" -ForegroundColor White
Write-Host "     wingetcreate update Lanmark.TekFixSupportAgent -u <installer-url> -v $Version" -ForegroundColor White
