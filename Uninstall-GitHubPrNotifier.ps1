$ErrorActionPreference = "SilentlyContinue"

$TaskName = "GitHub PR Notifier"
$InstallDir = Join-Path $env:LOCALAPPDATA "GitHubPrNotifier"

Stop-ScheduledTask -TaskName $TaskName
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Remove-Item $InstallDir -Recurse -Force

Write-Host "GitHub PR Notifier removido." -ForegroundColor Green
Read-Host "Pressione Enter para fechar"
