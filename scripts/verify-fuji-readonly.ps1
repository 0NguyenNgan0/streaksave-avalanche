param([string]$Rpc = 'https://api.avax-test.network/ext/bc/C/rpc')
$ErrorActionPreference='Stop'
$Token='0x1aaB5693678b18753dCFD5096f497031c1A1f126'
$Streak='0xE71Ae741c3bEe9f7F21057d825FE7dA8984406f9'
$ExpectedProvider='0x8986EC1B5E6Ca6Ceeb5ea608E8BA718b72D7Fd67'
$i=0
function Rpc([string]$method, [object[]]$args) {
  $script:i++
  $json=@{jsonrpc='2.0'; id=$script:i; method=$method; params=$args}|ConvertTo-Json -Depth 8 -Compress
  $r=Invoke-RestMethod -Uri $Rpc -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 20
  if ($r.error){throw "$method RPC error: $($r.error.message)"}
  return [string]$r.result
}
function ReadCall([string]$to,[string]$selector) {return Rpc 'eth_call' @(@{to=$to;data=$selector},'latest')}
function DecodeAddress([string]$hex) {if ($hex.Length -lt 42){throw "bad address output: $hex"}; return '0x'+$hex.Substring($hex.Length-40)}
function AssertEq([string]$label,[string]$actual,[string]$expected) {
 if ($actual.ToLowerInvariant() -ne $expected.ToLowerInvariant()){throw "FAIL $label actual=$actual expected=$expected"}
 Write-Host "PASS: $label = $actual" -ForegroundColor Green
}
Write-Host '=== Fuji Read-Only Verification ===' -ForegroundColor Cyan
AssertEq 'chain ID' (Rpc 'eth_chainId' @()) '0xa869'
foreach($contract in @(@('MockUSDC',$Token),@('StreakSavings',$Streak))){
 $code=Rpc 'eth_getCode' @($contract[1],'latest')
 if (!$code -or $code -eq '0x'){throw "FAIL $($contract[0]) has no bytecode"}
 Write-Host "PASS: $($contract[0]) deployed code length $($code.Length)" -ForegroundColor Green
}
# Only the standardized decimals() selector is used here.
AssertEq 'MockUSDC decimals' ([Convert]::ToInt64((ReadCall $Token '0x313ce567').Substring(2),16)).ToString() '6'
# Additional constructor relation / provider / duration should be checked with cast or ABI-aware tooling by tester.
Write-Host 'NOT CHECKED by this script: usdc() linkage, yieldProvider(), epochDuration(), tx receipts or E2E.' -ForegroundColor Yellow
Write-Host 'Read-only verification finished; no transactions submitted.'
