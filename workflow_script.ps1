param()
$ErrorActionPreference = "Continue"

Write-Host "`n====== COMPREHENSIVE WORKFLOW SCRIPT ======`n" -ForegroundColor Green

# Step 1-2: Kill Python
Write-Host "[1] Killing Python processes..." -ForegroundColor Yellow
taskkill /F /IM python.exe 2>&1 | Where-Object { $_ -notmatch "ERROR" } | Select-Object -Last 1
Start-Sleep -Seconds 1

# Step 3: Environment
Write-Host "`n[3] Setting environment..." -ForegroundColor Yellow
$env:TMP = "D:\TempJunk"
$env:TEMP = "D:\TempJunk"
Write-Host "  TMP=$env:TMP, TEMP=$env:TEMP"

# Step 4: Sync
Write-Host "`n[4] Running sync-blog.ps1..." -ForegroundColor Yellow
Push-Location D:\Quarto\Foxmir_blog
$syncOut = @()
& powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\sync-blog.ps1" 2>&1 | ForEach-Object { $syncOut += $_ }
Write-Host "  Last 5 lines of sync output:"
$syncOut[-5..-1] | ForEach-Object { Write-Host "    $_" }

# Step 5: Check for errors
$syncErrors = $syncOut | Where-Object { $_ -match "error|exception" }
if ($syncErrors) {
    Write-Host "  ⚠ Errors detected:" -ForegroundColor Red
    $syncErrors | ForEach-Object { Write-Host "    $_" }
}

# Step 6: Quarto render
Write-Host "`n[6] Running Quarto render..." -ForegroundColor Yellow
$quartoOut = @()
& D:\Quarto\bin\quarto.exe render 2>&1 | ForEach-Object { $quartoOut += $_ }
Write-Host "  Last 10 lines of Quarto output:"
$quartoOut[-10..-1] | ForEach-Object { Write-Host "    $_" }

# Step 7: Check HTML
Write-Host "`n[7] Checking output files..." -ForegroundColor Yellow
if (Test-Path "docs\index.html") {
    $size = (Get-Item "docs\index.html").Length
    Write-Host "  ✓ index.html: $size bytes"
} else {
    Write-Host "  ✗ index.html not found"
}

Pop-Location
Write-Host "`n====== WORKFLOW COMPLETE ======`n" -ForegroundColor Green
