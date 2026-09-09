$ErrorActionPreference = 'Stop'

# Keep the Flutter Web origin stable so Hive/IndexedDB remains a reusable cache.
$WebHost = 'localhost'
$WebPort = 7357

$RunnerApiUrl = if ($env:RUNNER_API_URL) {
    $env:RUNNER_API_URL
} else {
    'http://127.0.0.1:8787'
}

$RunnerApiToken = if ($env:RUNNER_API_TOKEN) {
    $env:RUNNER_API_TOKEN
} else {
    'dev-runner-token'
}

$WorkspaceStorageApiUrl = if ($env:WORKSPACE_STORAGE_API_URL) {
    $env:WORKSPACE_STORAGE_API_URL
} else {
    'https://workspace-storage-production.up.railway.app'
}

# Optional development auto-login token. Leave empty to use the real
# register/login screen and a browser-persisted account session.
$WorkspaceAccessToken = if ($env:WORKSPACE_ACCESS_TOKEN) {
    $env:WORKSPACE_ACCESS_TOKEN
} else {
    ''
}

$listener = Get-NetTCPConnection -LocalPort $WebPort -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    Write-Error "Fixed Flutter Web port $WebPort is already in use. Stop the existing process and run this script again. The app will not fall back to a random port because that would create a different browser storage origin."
    exit 1
}

Write-Host "Flutter Web fixed origin: http://${WebHost}:$WebPort"
Write-Host "Runner API: $RunnerApiUrl"
if ($WorkspaceStorageApiUrl) {
    Write-Host "Workspace cloud: $WorkspaceStorageApiUrl (cloud is authoritative; browser Hive is per-account cache)"
    if ($WorkspaceAccessToken) {
        Write-Host 'Workspace auth: development bearer auto-login enabled'
    } else {
        Write-Host 'Workspace auth: interactive register/login enabled'
    }
} else {
    Write-Host 'Workspace cloud: disabled (set WORKSPACE_STORAGE_API_URL to enable cloud accounts)'
}

flutter run -d chrome `
    "--web-hostname=$WebHost" `
    "--web-port=$WebPort" `
    "--dart-define=RUNNER_API_URL=$RunnerApiUrl" `
    "--dart-define=RUNNER_API_TOKEN=$RunnerApiToken" `
    "--dart-define=WORKSPACE_STORAGE_API_URL=$WorkspaceStorageApiUrl" `
    "--dart-define=WORKSPACE_ACCESS_TOKEN=$WorkspaceAccessToken"
