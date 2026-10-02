[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$toolsDirectory = Join-Path $repositoryRoot '.tools'
$destination = Join-Path $toolsDirectory 'cloudflared.exe'
$download = Join-Path $toolsDirectory 'cloudflared.download.exe'
$source = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'

New-Item -ItemType Directory -Path $toolsDirectory -Force | Out-Null

try {
    Write-Host 'Downloading cloudflared from the official Cloudflare release...'
    Invoke-WebRequest -Uri $source -OutFile $download -UseBasicParsing

    $signature = Get-AuthenticodeSignature -FilePath $download
    $subject = $signature.SignerCertificate.Subject
    if ($signature.Status -ne 'Valid' -or $subject -notmatch 'Cloudflare') {
        throw "The downloaded cloudflared signature is not valid for Cloudflare. Status: $($signature.Status)"
    }

    Move-Item -LiteralPath $download -Destination $destination -Force
    & $destination --version
    Write-Host "cloudflared is ready at $destination"
}
finally {
    if (Test-Path -LiteralPath $download) {
        Remove-Item -LiteralPath $download -Force
    }
}
