param([string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path $Repo).Path
Push-Location $repo
try {
  $isRepo = (& git rev-parse --is-inside-work-tree 2>$null)
  if ($LASTEXITCODE -ne 0 -or $isRepo -ne 'true') { throw 'Not a git repository' }
  $report=Join-Path $env:TEMP ('streaksave-security-audit-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.txt')
  $lines=New-Object 'System.Collections.Generic.List[string]'
  $issues=0
  $lines.Add('StreakSave local working-tree security review')
  $lines.Add('Date: '+(Get-Date -Format o));$lines.Add('Repo: '+$repo)
  $lines.Add('HEAD: '+(& git rev-parse HEAD))
  $tracked=@(& git ls-files --cached --full-name)
  $lines.Add('Tracked files: '+$tracked.Count)
  $dangerousName='(?i)(^|/)(\.env(\.|$)|id_rsa|id_ed25519|[^/]*\.(pem|key|p12|pfx|keystore)$|secret[-_]?recovery|mnemonic|private[-_]?key)'
  $patterns=@(
    @{name='Private key PEM header';regex='-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'},
    @{name='Possible mnemonic assignment';regex='(?i)\b(mnemonic|seed_phrase|secret_recovery_phrase)\b\s*[:=]\s*["\x27][a-z]+\s+[a-z]+\s+[a-z]+'},
    @{name='Possible private-key literal';regex='(?i)\b(private[_-]?key|DEPLOYER_PRIVATE_KEY)\b\s*[:=]\s*["\x27]?0x[0-9a-f]{64}\b'},
    @{name='GitHub classic token';regex='\bghp_[A-Za-z0-9]{30,}\b'}
  )
  foreach ($file in $tracked) {
    if ($file -match $dangerousName) { $issues++; $lines.Add('FLAG FILE PATH: '+$file) }
    if ($file -eq 'scripts/audit-repo-security.ps1') { continue } # self contains detection regex literals
    if ([IO.Path]::GetExtension($file) -match '(?i)^\.(png|jpg|jpeg|webp|gif|pdf|zip|gz|woff2|map|lock)$') { continue }
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { continue }
    try {
      $info=Get-Item -LiteralPath $file
      if ($info.Length -gt 1048576) { continue }
      $content=[IO.File]::ReadAllText($info.FullName)
      foreach ($p in $patterns) {
        if ([regex]::IsMatch($content,$p.regex)) {
          $issues++; $lines.Add('FLAG CONTENT: '+$file+' ['+$p.name+']')
        }
      }
    } catch { $lines.Add('UNREADABLE: '+$file+' (manual review)'); $issues++ }
  }
  foreach($name in @('apps/web/.env.local','.env','.env.local')) {
    $present=Test-Path $name
    $listed=@(& git ls-files --cached -- $name)
    $lines.Add(('Local '+$name+': '+$(if($present){'present'}else{'absent'})+'; tracked='+($listed.Count -gt 0)))
    if ($listed.Count -gt 0) { $issues++; $lines.Add('FLAG TRACKED ENV: '+$name) }
  }
  $lines.Add('Potential findings: '+$issues)
  $lines.Add('Limit: current tracked tree only; review Git history, collaborator access, branch protection and remote secrets separately.')
  [IO.File]::WriteAllLines($report,$lines,[Text.UTF8Encoding]::new($false))
  Write-Host "Report: $report"
  if ($issues -eq 0) { Write-Host 'LOCAL SECRET HEURISTIC SCAN: NO FLAGS (not a full audit)' -ForegroundColor Green }
  else { Write-Host "REVIEW REQUIRED: $issues possible findings; no secret values printed" -ForegroundColor Yellow; exit 2 }
} finally { Pop-Location }
