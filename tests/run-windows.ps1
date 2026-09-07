# Windows test entry: use isolated fixture identities without editing Git config.
#requires -Version 7.3
[CmdletBinding()]
param(
    [string]$RuntimeRoot = $env:PMAI_WINDOWS_RUNTIME,
    [string]$Suite = 'tests/run-all.sh'
)
$ErrorActionPreference = 'Stop'
$names = @('GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL', 'PYTHONDONTWRITEBYTECODE', 'PMAI_SUITE_TIMEOUT_SECONDS')
$previous = @{}
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:GIT_AUTHOR_NAME = 'PMAI Windows Test'
    $env:GIT_AUTHOR_EMAIL = 'pmai-test@example.invalid'
    $env:GIT_COMMITTER_NAME = $env:GIT_AUTHOR_NAME
    $env:GIT_COMMITTER_EMAIL = $env:GIT_AUTHOR_EMAIL
    $env:PYTHONDONTWRITEBYTECODE = '1'
    # Cygwin process creation makes the large stateful suites slower. Keep a
    # bounded per-suite deadline and honor an explicit caller override.
    if (-not $env:PMAI_SUITE_TIMEOUT_SECONDS) { $env:PMAI_SUITE_TIMEOUT_SECONDS = '900' }
    & (Join-Path $PSScriptRoot '../scripts/windows/run.ps1') -RuntimeRoot $RuntimeRoot -Script scripts/windows/check-runtime.py
    if ($LASTEXITCODE -ne 0) { throw 'Windows runtime preflight failed; tests were not started.' }
    & (Join-Path $PSScriptRoot 'test-windows-entry.ps1') -RuntimeRoot $RuntimeRoot
    if ($LASTEXITCODE -ne 0) { throw 'Windows PowerShell entry test failed; suites were not started.' }
    & (Join-Path $PSScriptRoot '../scripts/windows/run.ps1') -RuntimeRoot $RuntimeRoot -Script $Suite
    $result = $LASTEXITCODE
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
}
exit $result
