$ErrorActionPreference = 'Stop'

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

$WorkspaceAccessToken = if ($env:WORKSPACE_ACCESS_TOKEN) {
    $env:WORKSPACE_ACCESS_TOKEN
} else {
    ''
}

Write-Host 'Looking for Android device...'

$devicesJson = flutter devices --machine | ConvertFrom-Json

$androidDevices = @(
    $devicesJson | Where-Object {
        $_.targetPlatform -like 'android-*'
    }
)

if ($androidDevices.Count -eq 0) {
    Write-Error 'No Android device found. Connect Xiaomi Pad 6 and enable USB/Wireless debugging.'
    exit 1
}

if ($env:FLUTTER_ANDROID_DEVICE) {
    $device = $androidDevices |
        Where-Object { $_.id -eq $env:FLUTTER_ANDROID_DEVICE } |
        Select-Object -First 1

    if (-not $device) {
        Write-Error "Android device '$env:FLUTTER_ANDROID_DEVICE' was not found."
        exit 1
    }
} else {
    $device = $androidDevices | Select-Object -First 1
}

$DeviceId = $device.id

Write-Host "Android device: $($device.name) [$DeviceId]"
Write-Host "Runner API: $RunnerApiUrl"
Write-Host "Workspace cloud: $WorkspaceStorageApiUrl"

# When using the local Runner on this PC, Android's 127.0.0.1 normally
# points back to the tablet itself. adb reverse makes tablet localhost:8787
# forward to this computer's localhost:8787.
if ($RunnerApiUrl -eq 'http://127.0.0.1:8787') {
    Write-Host 'Forwarding tablet localhost:8787 -> PC localhost:8787...'
    adb -s $DeviceId reverse tcp:8787 tcp:8787
}

flutter run -d $DeviceId `
    "--dart-define=RUNNER_API_URL=$RunnerApiUrl" `
    "--dart-define=RUNNER_API_TOKEN=$RunnerApiToken" `
    "--dart-define=WORKSPACE_STORAGE_API_URL=$WorkspaceStorageApiUrl" `
    "--dart-define=WORKSPACE_ACCESS_TOKEN=$WorkspaceAccessToken"