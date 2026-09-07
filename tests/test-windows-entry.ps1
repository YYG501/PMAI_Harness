#requires -Version 7.3
[CmdletBinding()]
param([string]$RuntimeRoot = $env:PMAI_WINDOWS_RUNTIME)
$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Legacy'
$runner = Join-Path $PSScriptRoot '../scripts/windows/run.ps1'
$expected = @('中文路径 with spaces', '', '"quoted"', '$(literal); & | >', '/pmai-design', 'C:\path with spaces\target')
$beforePath = $env:PATH
$beforeRuntime = $env:PMAI_WINDOWS_RUNTIME
$beforeChere = $env:CHERE_INVOKING
$beforeEncoding = $OutputEncoding
$previousExit = $env:PMAI_TEST_ARGV_EXIT
try {
    $env:PMAI_TEST_ARGV_EXIT = '13'
    $output = & $runner -RuntimeRoot $RuntimeRoot -Script tests/helpers/windows-argv.py -Arguments $expected
    if ($LASTEXITCODE -ne 13) { throw 'Child exit code was not preserved.' }
    $actual = @($output | ConvertFrom-Json)
    if ($actual.Count -ne $expected.Count) { throw 'Argument count changed.' }
    for ($index = 0; $index -lt $expected.Count; $index++) {
        if ($actual[$index] -cne $expected[$index]) { throw "Argument $index changed." }
    }
    $OutputEncoding = [Text.ASCIIEncoding]::new()
    $stdinLines = @('{"prompt":"中文 $(literal); & | >"}', '', 'second line')
    $pipeOutput = $stdinLines | & $runner -RuntimeRoot $RuntimeRoot -Script tests/helpers/windows-argv.py -Arguments @('--stdin-json', '正文参数')
    if ($LASTEXITCODE -ne 13) { throw 'Piped child exit code was not preserved.' }
    $pipeActual = $pipeOutput | ConvertFrom-Json
    if ($pipeActual.stdin.Replace("`r`n", "`n") -cne (($stdinLines -join "`n") + "`n") -or $pipeActual.argv[0] -cne '正文参数') {
        throw 'UTF-8 pipeline input, empty lines or accompanying argv changed.'
    }
    if ($OutputEncoding.CodePage -ne 20127) { throw 'Runner changed caller output encoding.' }
    if ($env:PATH -cne $beforePath -or $env:PMAI_WINDOWS_RUNTIME -cne $beforeRuntime -or $env:CHERE_INVOKING -cne $beforeChere) {
        throw 'Runner leaked environment changes into the caller.'
    }
    'Windows PowerShell argv, UTF-8 stdin, exit code and environment passed.'
} finally {
    $env:PMAI_TEST_ARGV_EXIT = $previousExit
    $OutputEncoding = $beforeEncoding
}
exit 0
