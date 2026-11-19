$ErrorActionPreference = "Stop"

$Repo = "C:\StreakSave"
Set-Location $Repo

Write-Host "=== StreakSave Integration Gate ===" -ForegroundColor Cyan
Write-Host ("Branch: " + (git branch --show-current))

# 1) Git hygiene
$status = git status --porcelain
if ($status) {
    Write-Host ""
    Write-Host "FAIL: working tree is not clean." -ForegroundColor Red
    git status
    exit 1
}
Write-Host "PASS: working tree clean" -ForegroundColor Green

# 2) Shared ABI compatibility
Write-Host ""
Write-Host "[1/5] Shared ABI compatibility" -ForegroundColor Cyan
node .\scripts\check-abi-compat.mjs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 3) Frontend-local ABI compatibility
Write-Host ""
Write-Host "[2/5] Frontend ABI compatibility" -ForegroundColor Cyan
Set-Location "$Repo\apps\web"
node .\scripts\check-abi.mjs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 4) Frontend gates
Write-Host ""
Write-Host "[3/5] Frontend typecheck" -ForegroundColor Cyan
npm run typecheck
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "[4/5] Frontend production build" -ForegroundColor Cyan
npm run build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 5) Contract tests when Foundry is available
Write-Host ""
Write-Host "[5/5] Contract tests" -ForegroundColor Cyan
$forge = Get-Command forge -ErrorAction SilentlyContinue

if ($forge) {
    Set-Location "$Repo\contracts"
    forge test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "PASS: forge test" -ForegroundColor Green
} else {
    Write-Host "SKIP: forge is not installed in this PowerShell environment." -ForegroundColor Yellow
    Write-Host "Contract branch was merged; use Contracts CI as the contract test gate." -ForegroundColor Yellow
}

# Deployment readiness check
Set-Location "$Repo\apps\web"
$envFile = Join-Path (Get-Location) ".env.local"

Write-Host ""
if (Test-Path $envFile) {
    $envText = Get-Content $envFile -Raw
    $hasStreak = $envText -match 'NEXT_PUBLIC_STREAK_CONTRACT=0x[a-fA-F0-9]{40}'
    $hasUsdc = $envText -match 'NEXT_PUBLIC_USDC_CONTRACT=0x[a-fA-F0-9]{40}'

    if ($hasStreak -and $hasUsdc) {
        Write-Host "DEPLOYMENT CONFIG: contract addresses detected." -ForegroundColor Green
        Write-Host "Next gate: manual Fuji E2E (connect -> approve -> deposit -> reward -> claim -> withdraw)." -ForegroundColor Cyan
    } else {
        Write-Host "DEPLOYMENT CONFIG: .env.local exists but Fuji addresses are incomplete." -ForegroundColor Yellow
        Write-Host "Full E2E remains pending until Member A deploys and provides both addresses." -ForegroundColor Yellow
    }
} else {
    Write-Host "DEPLOYMENT CONFIG: no apps/web/.env.local yet." -ForegroundColor Yellow
    Write-Host "Full Fuji E2E remains pending until deployment addresses are available." -ForegroundColor Yellow
}

Set-Location $Repo
Write-Host ""
Write-Host "=== LOCAL INTEGRATION GATE PASS ===" -ForegroundColor Green
Write-Host "ABI + frontend integration are locally healthy."
