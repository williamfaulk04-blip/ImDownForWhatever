[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8000,

    [string]$DatabasePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$python = Join-Path $repositoryRoot '.venv\Scripts\python.exe'
$localCloudflared = Join-Path $repositoryRoot '.tools\cloudflared.exe'
$serverProcess = $null
$tunnelProcess = $null
$stdoutLog = Join-Path ([System.IO.Path]::GetTempPath()) "imdownforwhatever-cloudflared-$([guid]::NewGuid()).out.log"
$stderrLog = Join-Path ([System.IO.Path]::GetTempPath()) "imdownforwhatever-cloudflared-$([guid]::NewGuid()).err.log"

if (-not (Test-Path -LiteralPath $python)) {
    throw 'Python environment not found. Create .venv and install server/requirements-dev.txt first.'
}

$cloudflaredCommand = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($null -ne $cloudflaredCommand) {
    $cloudflared = $cloudflaredCommand.Source
}
elseif (Test-Path -LiteralPath $localCloudflared) {
    $cloudflared = $localCloudflared
}
else {
    throw 'cloudflared not found. Run scripts/install-cloudflared.ps1 first.'
}

if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
    $databaseDirectory = Join-Path $env:LOCALAPPDATA 'ImDownForWhatever'
    $DatabasePath = Join-Path $databaseDirectory 'rooms.sqlite3'
}
elseif (-not [System.IO.Path]::IsPathRooted($DatabasePath)) {
    $DatabasePath = Join-Path $repositoryRoot $DatabasePath
}
$DatabasePath = [System.IO.Path]::GetFullPath($DatabasePath)
$localUrl = "http://127.0.0.1:$Port"
$previousDatabasePath = $env:FASTPOLL_DB_PATH

try {
    $portProbe = [System.Net.Sockets.TcpClient]::new()
    try {
        $connected = $portProbe.ConnectAsync('127.0.0.1', $Port).Wait(250)
        if ($connected -and $portProbe.Connected) {
            throw "Port $Port is already in use. Stop the existing service or choose another port with -Port."
        }
    }
    finally {
        $portProbe.Dispose()
    }

    $env:FASTPOLL_DB_PATH = $DatabasePath
    Write-Host "Starting the API with database $DatabasePath"
    $serverProcess = Start-Process -FilePath $python -WorkingDirectory $repositoryRoot -PassThru -NoNewWindow -ArgumentList @(
        '-m', 'uvicorn', 'server.main:app',
        '--host', '127.0.0.1',
        '--port', $Port,
        '--workers', '1'
    )

    $healthy = $false
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        if ($serverProcess.HasExited) {
            throw "The API exited before becoming healthy (exit code $($serverProcess.ExitCode))."
        }
        try {
            $health = Invoke-RestMethod -Uri "$localUrl/health" -TimeoutSec 2
            if ($health.status -eq 'healthy') {
                if ($serverProcess.HasExited) {
                    throw "The API exited after answering its health check (exit code $($serverProcess.ExitCode))."
                }
                $healthy = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $healthy) {
        throw "The API did not become healthy at $localUrl/health."
    }

    Write-Host 'Starting a temporary Cloudflare Quick Tunnel...'
    $tunnelProcess = Start-Process -FilePath $cloudflared -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog `
        -ArgumentList @('tunnel', '--url', $localUrl, '--no-autoupdate')

    $publicUrl = $null
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if ($tunnelProcess.HasExited) {
            $details = (Get-Content -LiteralPath $stdoutLog, $stderrLog -ErrorAction SilentlyContinue) -join [Environment]::NewLine
            throw "cloudflared exited before creating a tunnel.`n$details"
        }
        $details = (Get-Content -LiteralPath $stdoutLog, $stderrLog -ErrorAction SilentlyContinue) -join [Environment]::NewLine
        $match = [regex]::Match($details, 'https://[a-z0-9-]+\.trycloudflare\.com')
        if ($match.Success) {
            $publicUrl = $match.Value
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $publicUrl) {
        throw 'Cloudflare did not provide a Quick Tunnel URL within 30 seconds.'
    }

    Write-Host ''
    Write-Host 'Cross-network API is ready:' -ForegroundColor Green
    Write-Host $publicUrl -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'On each emulator, open Settings and paste this URL under Server address.'
    Write-Host 'Existing command-line builds can also use:'
    Write-Host "flutter run -d YOUR_DEVICE_ID --dart-define=FASTPOLL_API_BASE=$publicUrl"
    Write-Host ''
    Write-Host 'Keep this window open for the entire test. Press Ctrl+C when finished.'

    while (-not $tunnelProcess.HasExited) {
        Start-Sleep -Seconds 1
    }
}
finally {
    if ($null -ne $tunnelProcess -and -not $tunnelProcess.HasExited) {
        Stop-Process -Id $tunnelProcess.Id -Force
    }
    if ($null -ne $serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -Force
    }
    $env:FASTPOLL_DB_PATH = $previousDatabasePath
    foreach ($log in @($stdoutLog, $stderrLog)) {
        if (Test-Path -LiteralPath $log) {
            Remove-Item -LiteralPath $log -Force
        }
    }
    Write-Host 'API and tunnel stopped.'
}
