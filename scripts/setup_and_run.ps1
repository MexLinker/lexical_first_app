Param(
  [string]$ApiUrl,
  [int]$ExpoPort = 8083,
  [int]$BackendPort = 3001,
  [int]$BackendWaitSeconds = 60,
  [switch]$SkipInstall,
  [switch]$InstallOnly,
  [switch]$BackendOnly,
  [switch]$ExpoOnly
)

<#
  Lexical bootstrap script (Windows PowerShell)
  - Installs dependencies on demand
  - Starts backend and/or Expo dev server
  - Performs health checks when possible

  Usage:
    powershell -ExecutionPolicy Bypass -File scripts/setup_and_run.ps1 [options]

  Key options:
    -ApiUrl <url>        Override API base URL exposed to Expo.
    -ExpoPort <port>     Override Expo dev server port (default 8083).
    -BackendPort <port>  Override backend port (default 3001).
    -BackendWaitSeconds  Health check timeout seconds (default 60).
    -SkipInstall         Skip npm install steps.
    -InstallOnly         Install dependencies then exit.
    -BackendOnly         Only run the backend (foreground job).
    -ExpoOnly            Only run Expo (requires running backend).
#>

if ($BackendOnly -and $ExpoOnly) {
  Write-Error "Cannot specify both -BackendOnly and -ExpoOnly."
  exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $ScriptDir "..")).Path

function Require-Command {
  param([string]$CommandName)
  if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
    Write-Error "Required command '$CommandName' is not available. Please install the necessary tooling (Node.js 18+)."
    exit 1
  }
}

Require-Command npm
if (-not $ExpoOnly) {
  Require-Command node
}
if (-not $BackendOnly) {
  Require-Command npx
}

function Get-HostIP {
  try {
    $ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
      $_.IPAddress -notlike "169.254.*" -and $_.InterfaceAlias -notlike "*Virtual*"
    } | Select-Object -ExpandProperty IPAddress
    if ($ips -and $ips.Count -gt 0) { return $ips[0] }
  } catch {}
  return $null
}

if (-not $ApiUrl) {
  if (-not $BackendOnly) {
    $ApiUrl = "http://localhost:$BackendPort"
  } else {
    $ip = Get-HostIP
    if (-not $ip) {
      Write-Error "Could not detect host IP. Provide -ApiUrl 'http://IP:PORT'."
      exit 1
    }
    $ApiUrl = "http://${ip}:$BackendPort"
  }
}

Write-Host ("Root: {0}" -f $Root)
Write-Host ("Backend port: {0}" -f $BackendPort)
Write-Host ("Expo port: {0}" -f $ExpoPort)
Write-Host ("API URL: {0}" -f $ApiUrl)
Write-Host ""

if (-not $SkipInstall) {
  Write-Host "Installing backend dependencies..."
  Push-Location (Join-Path $Root 'backend')
  npm install
  Pop-Location

  Write-Host "Installing Expo app dependencies..."
  Push-Location (Join-Path $Root 'lexical-expo-app')
  npm install
  Pop-Location
} else {
  Write-Host "Skipping dependency installation (per -SkipInstall)."
}

if ($InstallOnly) {
  Write-Host "Installation complete. Re-run without -InstallOnly to start services."
  exit 0
}

$backendJob = $null

if (-not $ExpoOnly) {
  Write-Host "Starting backend..."
  if ($BackendOnly) {
    $env:PORT = $BackendPort
    Set-Location (Join-Path $Root 'backend')
    node server.js
    exit $LASTEXITCODE
  } else {
    $backendJob = Start-Job -ScriptBlock {
      param($rootPath, $port)
      $env:PORT = $port
      Set-Location (Join-Path $rootPath 'backend')
      node server.js
    } -ArgumentList $Root, $BackendPort

    Write-Host "Waiting for backend health at $ApiUrl/api/health..."
    $healthy = $false
    $attempts = [Math]::Max([Math]::Ceiling($BackendWaitSeconds), 1)
    for ($i = 0; $i -lt $attempts; $i++) {
      try {
        $resp = Invoke-WebRequest -Uri "$ApiUrl/api/health" -TimeoutSec 3
        if ($resp.StatusCode -eq 200) {
          $healthy = $true
          break
        }
      } catch {}
      Start-Sleep -Seconds 1
    }
    if ($healthy) {
      Write-Host "Backend is healthy."
    } else {
      Write-Warning "Health check did not succeed at $ApiUrl/api/health (continuing)."
    }
  }
}

if (-not $BackendOnly) {
  $env:EXPO_PUBLIC_API_URL = $ApiUrl
  Set-Location (Join-Path $Root 'lexical-expo-app')
  try {
    Write-Host "Starting Expo dev server..."
    npx expo start --port $ExpoPort
  } finally {
    if ($backendJob) {
      try { Stop-Job $backendJob -Force } catch {}
      try { Receive-Job $backendJob | Out-Host } catch {}
      try { Remove-Job $backendJob } catch {}
    }
  }
} elseif ($backendJob) {
  try { Receive-Job $backendJob | Out-Host } catch {}
  try { Remove-Job $backendJob } catch {}
}
