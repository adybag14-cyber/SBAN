param(
    [string]$ResultPath = "C:\Users\Ady\work\SBAN\docs\results\v22\longrun_v22_100m.json",
    [string]$StatusPath = "C:\Users\Ady\work\SBAN\docs\results\v22\longrun_v22_100m_watch_status.txt",
    [int]$ReleaseProcessId = 0,
    [int]$PollSeconds = 30,
    [int]$TimeoutHours = 8
)

$ErrorActionPreference = "Stop"

function Write-Status {
    param(
        [string]$Title,
        [string]$Message,
        [int]$PopupType = 64
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $body = @"
[$timestamp] $Title
$Message
"@
    Set-Content -LiteralPath $StatusPath -Value $body -Encoding UTF8

    try {
        $wshell = New-Object -ComObject WScript.Shell
        $null = $wshell.Popup($Message, 0, $Title, $PopupType)
    } catch {
        # Leave the status file behind even if desktop notifications are unavailable.
    }
}

$deadline = (Get-Date).AddHours($TimeoutHours)

while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $ResultPath) {
        try {
            $data = Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json
            if ($null -ne $data.models -and $data.models.Count -gt 0) {
                $model = $data.models[0]
                $predictions = [double]$model.total_predictions
                if ($predictions -gt 0) {
                    $accuracy = 100.0 * ([double]$model.total_correct) / $predictions
                    $message = "Accuracy: {0:N4}%`nPredictions: {1:N0}`nResult file: {2}" -f $accuracy, $predictions, $ResultPath
                    Write-Status -Title "SBAN v22 100M Complete" -Message $message
                    exit 0
                }
            }
        } catch {
            # If the file is mid-write or invalid, keep polling.
        }
    }

    if ($ReleaseProcessId -ne 0) {
        $releaseProc = Get-Process -Id $ReleaseProcessId -ErrorAction SilentlyContinue
        if ($null -eq $releaseProc) {
            $message = "The monitored release process exited before $ResultPath appeared. Check docs\\results\\v22 for partial outputs."
            Write-Status -Title "SBAN v22 100M Watch Ended" -Message $message -PopupType 48
            exit 1
        }
    }

    Start-Sleep -Seconds $PollSeconds
}

$timeoutMessage = "Timed out after $TimeoutHours hour(s) waiting for $ResultPath. The release process may still be running."
Write-Status -Title "SBAN v22 100M Watch Timed Out" -Message $timeoutMessage -PopupType 48
exit 1
