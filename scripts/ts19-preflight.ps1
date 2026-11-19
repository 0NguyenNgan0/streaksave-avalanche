# Read-only TS-19 environment preflight. Does not sign, deploy or submit transactions.
param([string]$Repo = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
Set-Location $Repo
Write-Host '=== TS-19 Preflight (READ-ONLY) ===' -ForegroundColor Cyan
$branch = (git branch --show-current).Trim()
$sha = (git rev-parse HEAD).Trim()
Write-Host "Branch: $branch"
Write-Host "Commit: $sha"
$dirty = git status --porcelain
if ($dirty) { Write-Warning 'Working tree is not clean. Inspect diff before any merge; this is not a blocker for read-only preflight.' }
node .\scripts\check-abi-compat.mjs
if ($LASTEXITCODE -ne 0) { throw 'Shared ABI compatibility failed' }
Push-Location .\apps\web
try {
  node .\scripts\check-abi.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Frontend ABI compatibility failed' }
  $envPath = Join-Path (Get-Location) '.env.local'
  if (-not (Test-Path $envPath)) {
    Write-Host 'BLOCKED: apps/web/.env.local not present (Fuji addresses not configured).' -ForegroundColor Yellow
  } else {
    $values = @{}
    foreach ($line in Get-Content $envPath) {
      if ($line -match '^\s*(NEXT_PUBLIC_STREAK_CONTRACT|NEXT_PUBLIC_USDC_CONTRACT|NEXT_PUBLIC_FUJI_RPC_URL)\s*=\s*(.*?)\s*$') {
        $values[$matches[1]] = $matches[2]
      }
    }
    foreach ($key in @('NEXT_PUBLIC_STREAK_CONTRACT','NEXT_PUBLIC_USDC_CONTRACT')) {
      $address = $values[$key]
      if ($address -match '^0x[a-fA-F0-9]{40}$' -and $address -notmatch '^0x0{40}$') {
        Write-Host "$key : public address has valid syntax" -ForegroundColor Green
      } else {
        Write-Host "$key : missing/invalid (requires Fuji deployment)" -ForegroundColor Yellow
      }
    }
    Write-Host 'NOTE: address syntax is not contract bytecode or chain verification.' -ForegroundColor Yellow
  }
} finally { Pop-Location }
Write-Host 'PRE-FLIGHT COMPLETE. This is NOT a Fuji E2E PASS.' -ForegroundColor Cyan
Write-Host 'Execute docs/TS-19-FRESH-WALLET-QA.md; fill docs/TS-19-EVIDENCE.md after real transactions.'
