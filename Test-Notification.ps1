$ErrorActionPreference = "Stop"

if (-not (Get-Module -ListAvailable -Name BurntToast)) {
    Write-Host "BurntToast não está instalado. Rode o instalador primeiro." -ForegroundColor Yellow
    exit 1
}

Import-Module BurntToast

$button = New-BTButton -Content "Abrir GitHub" -Arguments "https://github.com"
New-BurntToastNotification `
    -Text "GitHub PR Notifier ✅", "Teste concluído", "As notificações do Windows estão funcionando." `
    -Button $button

Write-Host "Notificação de teste enviada." -ForegroundColor Green
