$ErrorActionPreference = "Stop"

$InstallDir = Join-Path $env:LOCALAPPDATA "GitHubPrNotifier"
$ScriptSource = Join-Path $PSScriptRoot "GitHubPrNotifier.ps1"
$ScriptDest = Join-Path $InstallDir "GitHubPrNotifier.ps1"
$TaskName = "GitHub PR Notifier"

Write-Host ""
Write-Host "=== GitHub PR Notifier ===" -ForegroundColor Cyan
Write-Host ""

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item $ScriptSource $ScriptDest -Force
Copy-Item (Join-Path $PSScriptRoot "config.json") (Join-Path $InstallDir "config.json") -Force

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "GitHub CLI não encontrado." -ForegroundColor Yellow
    Write-Host "Tentando instalar via winget..."
    winget install --id GitHub.cli --exact --accept-source-agreements --accept-package-agreements
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "O GitHub CLI ainda não está disponível neste terminal." -ForegroundColor Red
    Write-Host "Feche e abra o PowerShell e rode este instalador novamente."
    exit 1
}

& gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Você ainda não está autenticado no GitHub CLI." -ForegroundColor Yellow
    Write-Host "Abrindo login..."
    & gh auth login
}

if (-not (Get-Module -ListAvailable -Name BurntToast)) {
    Write-Host ""
    Write-Host "Instalando módulo BurntToast para notificações do Windows..."
    try {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    } catch {}
    Install-Module BurntToast -Scope CurrentUser -Force -AllowClobber
}

Import-Module BurntToast -ErrorAction Stop

# Cria uma tarefa no Agendador para iniciar a cada logon de forma totalmente headless.
# powershell.exe com -WindowStyle Hidden ainda pisca uma janela de console quando é
# lançado pelo Agendador; por isso usamos wscript.exe + um script VBS que inicia o
# PowerShell com a janela oculta (window style 0).
$LauncherPath = Join-Path $InstallDir "run-hidden.vbs"
$vbs = 'Set shell = CreateObject("WScript.Shell")' + "`r`n" + 'shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""' + $ScriptDest + '""", 0, False'
[System.IO.File]::WriteAllText($LauncherPath, $vbs)

$wscriptExe = Join-Path $env:SystemRoot "System32\wscript.exe"
$action = New-ScheduledTaskAction -Execute $wscriptExe -Argument "`"$LauncherPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
} catch {}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Notifica quando um PR criado por você recebe uma nova aprovação no GitHub." `
    -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName

Write-Host ""
Write-Host "Instalação concluída." -ForegroundColor Green
Write-Host "Agora ele monitora PRs abertos criados por você em qualquer repositório acessível pelo seu GitHub."
Write-Host ""
Write-Host "IMPORTANTE: aprovações que já existiam antes da primeira execução são apenas registradas."
Write-Host "Você será notificado somente por novas aprovações."
Write-Host ""
Write-Host "Arquivos:"
Write-Host "  Script: $ScriptDest"
Write-Host "  Estado/logs: $InstallDir"
Write-Host ""
Write-Host "Para remover depois, rode Uninstall-GitHubPrNotifier.ps1."
Write-Host ""
Read-Host "Pressione Enter para fechar"
