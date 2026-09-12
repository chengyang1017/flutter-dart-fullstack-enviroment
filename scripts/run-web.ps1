$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$WorkbenchRoot = Join-Path $RepoRoot 'apps\workbench'
Set-Location $WorkbenchRoot

$WebHost = 'localhost'
$WebPort = 7357

$RunnerApiUrl = if ($env:RUNNER_API_URL) { $env:RUNNER_API_URL } else { 'http://127.0.0.1:8787' }
$RunnerApiToken = if ($env:RUNNER_API_TOKEN) { $env:RUNNER_API_TOKEN } else { 'dev-runner-token' }
$WorkspaceStorageApiUrl = if ($env:WORKSPACE_STORAGE_API_URL) { $env:WORKSPACE_STORAGE_API_URL } else { 'https://workspace-storage-production.up.railway.app' }
$WorkspaceAccessToken = if ($env:WORKSPACE_ACCESS_TOKEN) { $env:WORKSPACE_ACCESS_TOKEN } else { '' }

$listener = Get-NetTCPConnection -LocalPort $WebPort -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    Write-Error "Fixed Flutter Web port $WebPort is already in use."
    exit 1
}

Write-Host "Flutter Web fixed origin: http://${WebHost}:$WebPort"
Write-Host "Runner API: $RunnerApiUrl"
Write-Host "Workspace cloud: $WorkspaceStorageApiUrl"

flutter run -d chrome `
    "--web-hostname=$WebHost" `
    "--web-port=$WebPort" `
    "--dart-define=RUNNER_API_URL=$RunnerApiUrl" `
    "--dart-define=RUNNER_API_TOKEN=$RunnerApiToken" `
    "--dart-define=WORKSPACE_STORAGE_API_URL=$WorkspaceStorageApiUrl" `
    "--dart-define=WORKSPACE_ACCESS_TOKEN=$WorkspaceAccessToken"
