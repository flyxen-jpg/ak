# Erzeugt lab\ha\secrets.env (einmalig). Alle Knoten muessen identische Werte haben.
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'secrets.env'
if (Test-Path $out) { Write-Host "secrets.env existiert bereits - nichts zu tun"; exit 0 }
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
function B64([int]$n) { $b = New-Object byte[] $n; $rng.GetBytes($b); [Convert]::ToBase64String($b) }
function Hex([int]$n) { $b = New-Object byte[] $n; $rng.GetBytes($b); -join ($b | ForEach-Object { $_.ToString('x2') }) }
function Pw([int]$n)  { (B64 $n) -replace '[/+=]', '' }
$lines = @(
  "# Generiert $(Get-Date -Format s) - NICHT einchecken"
  "PG_SUPERUSER_PASSWORD=$(Pw 24)"
  "PG_REPLICATION_PASSWORD=$(Pw 24)"
  "PG_REGISTRY_PASSWORD=$(Pw 24)"
  "JWT_SECRET=$(B64 48)"
  "AK_WEBHOOK_SECRET_KEY=$(B64 32)"
  "MIGRATION_ENCRYPTION_KEY=$(B64 32)"
  "SSO_ENCRYPTION_KEY=$(B64 32)"
  "ADMIN_PASSWORD=Ak-$(Pw 18)!"
  "GARAGE_RPC_SECRET=$(Hex 32)"
  "GARAGE_ADMIN_TOKEN=$(Pw 32)"
  "KEEPALIVED_AUTH_PASS=$((Pw 12).Substring(0,8))"
)
[IO.File]::WriteAllText($out, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
Write-Host "secrets.env erzeugt"
