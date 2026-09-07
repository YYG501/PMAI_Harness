# Install a verified, locally downloaded official Cygwin installer.
# Download setup-x86_64.exe and sha512.sum from https://cygwin.com/ first.
#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Installer,
    [Parameter(Mandatory)][string]$ChecksumFile,
    [string]$RuntimeRoot = $env:PMAI_WINDOWS_RUNTIME
)
$ErrorActionPreference = 'Stop'
if (-not $RuntimeRoot) { $RuntimeRoot = Join-Path $env:LOCALAPPDATA 'PMAI/cygwin' }
$runtimePath = [IO.Path]::GetFullPath($RuntimeRoot)
if ($runtimePath -eq [IO.Path]::GetPathRoot($runtimePath)) { throw 'Runtime root must not be a drive root.' }
$setupExe = (Resolve-Path -LiteralPath $Installer).Path
$match = [regex]::Match((Get-Content -Raw -LiteralPath $ChecksumFile), '(?im)^([a-f0-9]{128})\s+\*?setup-x86_64\.exe\s*$')
if (-not $match.Success -or (Get-FileHash -LiteralPath $setupExe -Algorithm SHA512).Hash -ine $match.Groups[1].Value) {
    throw 'Official installer SHA512 verification failed.'
}
$cachePath = Join-Path (Split-Path $runtimePath -Parent) 'cygwin-downloads'
$setupArgs = @('--no-admin', '--quiet-mode', '--no-shortcuts',
    '--root', ('"' + $runtimePath + '"'), '--local-package-dir', ('"' + $cachePath + '"'),
    '--site', 'https://mirrors.kernel.org/sourceware/cygwin/',
    '--packages', 'bash,python3,git,diffutils,findutils,grep,sed,which,patch,perl,jq')
$process = Start-Process -FilePath $setupExe -ArgumentList $setupArgs -WindowStyle Hidden -PassThru -Wait
if ($process.ExitCode -ne 0) { throw "Cygwin setup failed: $($process.ExitCode). See runtime var/log/setup.log.full." }
& (Join-Path $PSScriptRoot 'run.ps1') -RuntimeRoot $runtimePath -Script (Join-Path $PSScriptRoot 'check-runtime.py')
if ($LASTEXITCODE -ne 0) { throw 'Windows runtime capability probe failed.' }
Write-Output "Windows runtime ready: $runtimePath"
Write-Output 'Set PMAI_WINDOWS_RUNTIME to this directory when using a custom root.'
