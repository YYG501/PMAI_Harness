<######################################################################
Run checkout scripts in a Windows-local Cygwin runtime, without WSL.
Examples:
  ./scripts/windows/run.ps1 -Script tests/run-all.sh
  ./scripts/windows/run.ps1 -Script scripts/repo-kind.py -Arguments --json
######################################################################>
#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Script,
    [string[]]$Arguments = @(),
    [string]$RuntimeRoot = $env:PMAI_WINDOWS_RUNTIME,
    [Parameter(ValueFromPipeline)][AllowNull()][AllowEmptyString()][object]$PipelineInput
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $RuntimeRoot) { $RuntimeRoot = Join-Path $env:LOCALAPPDATA 'PMAI/cygwin' }
$runtimePath = [IO.Path]::GetFullPath($RuntimeRoot)
$bashExe = Join-Path $runtimePath 'bin/bash.exe'
$cygpathExe = Join-Path $runtimePath 'bin/cygpath.exe'
if (-not (Test-Path -LiteralPath $bashExe) -or -not (Test-Path -LiteralPath $cygpathExe)) {
    throw 'Windows runtime missing. Run scripts/windows/setup.ps1 first, or set PMAI_WINDOWS_RUNTIME.'
}
$scriptPath = if ([IO.Path]::IsPathRooted($Script)) { $Script } else { Join-Path $repoRoot $Script }
$scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
$posixScript = & $cygpathExe -u $scriptPath
if ($LASTEXITCODE -ne 0) { throw 'Could not translate script path.' }
$oldPath = $env:PATH
$oldRuntime = $env:PMAI_WINDOWS_RUNTIME
$oldNode = $env:PMAI_WINDOWS_NODE
$oldBridge = $env:PMAI_WINDOWS_BRIDGE
$oldChere = $env:CHERE_INVOKING
try {
    $nodeExe = (Get-Command node.exe -ErrorAction Stop).Source
    $env:PMAI_WINDOWS_RUNTIME = $runtimePath
    # Cygwin login shells otherwise cd to HOME, escaping the selected worktree.
    $env:CHERE_INVOKING = '1'
    $env:PMAI_WINDOWS_NODE = & $cygpathExe -u $nodeExe
    $env:PMAI_WINDOWS_BRIDGE = & $cygpathExe -u $PSScriptRoot
    $env:PATH = (Join-Path $runtimePath 'bin') + ';' + $oldPath
    # Positional arguments are passed as argv, never interpolated into shell code.
    $bashArgs = @('--noprofile', '--norc', '-c', 'export PATH="$PMAI_WINDOWS_BRIDGE:/usr/bin:/bin:$PATH"; script=$1; shift; case "$script" in *.py) exec python3 "$script" "$@";; *.cjs) exec node "$script" "$@";; *) exec bash "$script" "$@";; esac', 'pmai', $posixScript) + $Arguments
    if ($MyInvocation.ExpectingInput) {
        $input | & $bashExe @bashArgs
    } else {
        & $bashExe @bashArgs
    }
    $result = $LASTEXITCODE
} finally {
    $env:PATH = $oldPath
    $env:PMAI_WINDOWS_RUNTIME = $oldRuntime
    $env:PMAI_WINDOWS_NODE = $oldNode
    $env:PMAI_WINDOWS_BRIDGE = $oldBridge
    $env:CHERE_INVOKING = $oldChere
}
exit $result
