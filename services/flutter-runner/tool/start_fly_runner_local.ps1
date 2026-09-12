$ErrorActionPreference = 'Stop'

$secretPath = Join-Path $env:USERPROFILE '.flutter-runner-secrets\fly-runtime.env'
if (-not (Test-Path $secretPath)) {
    throw "Fly runtime environment file not found: $secretPath"
}

Get-Content $secretPath | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
}

$env:FLYCTL_EXECUTABLE = Join-Path $env:USERPROFILE '.fly\bin\flyctl.exe'
$env:RUNNER_EXECUTION_MODE = 'fly'
$env:RUNNER_AUTH_MODE = 'static'
$env:RUNNER_AUTH_TOKENS = '{"local-fly-preview-test":"local-user"}'
$env:RUNNER_HOST = '127.0.0.1'
$env:RUNNER_PORT = '8787'
$env:RUNNER_PUBLIC_BASE_URL = 'http://127.0.0.1:8787'
$env:RUNNER_ALLOWED_ORIGIN = '*'
$env:RUNNER_IDLE_MINUTES = '10'

Write-Host 'Starting real Fly-backed Runner on http://127.0.0.1:8787'
Write-Host 'Execution: one Fly Machine per Runner session; Preview: machine-specific WireGuard tunnel.'

dart run bin/server.dart
