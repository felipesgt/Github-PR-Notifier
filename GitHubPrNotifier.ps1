param(
    [int]$IntervalSeconds = 0
)

$ErrorActionPreference = "Stop"
$StateDir = Join-Path $env:LOCALAPPDATA "GitHubPrNotifier"
$StateFile = Join-Path $StateDir "state.json"
$ConfigFile = Join-Path $StateDir "config.json"
$LogFile = Join-Path $StateDir "notifier.log"

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "[$ts] $Message"
}

function Get-Config {
    $cfg = @{ intervalSeconds = 60; notifyComments = $true }
    if (Test-Path $ConfigFile) {
        try {
            $raw = Get-Content $ConfigFile -Raw
            if ($raw.Trim()) {
                $json = $raw | ConvertFrom-Json
                if ($json.PSObject.Properties.Name -contains "intervalSeconds") {
                    $cfg.intervalSeconds = [int]$json.intervalSeconds
                }
                if ($json.PSObject.Properties.Name -contains "notifyComments") {
                    $cfg.notifyComments = [bool]$json.notifyComments
                }
            }
        } catch {
            Write-Log "Falha ao ler config.json: $($_.Exception.Message)"
        }
    }
    return $cfg
}

function Get-CurrentInterval {
    $cfg = Get-Config
    $interval = if ($IntervalSeconds -gt 0) { $IntervalSeconds } else { $cfg.intervalSeconds }
    if ($interval -lt 10) { $interval = 10 }
    return $interval
}

function Convert-JsonToHashtable {
    param($InputObject)
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $out = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $out[$prop.Name] = Convert-JsonToHashtable $prop.Value
        }
        return $out
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return @($InputObject | ForEach-Object { Convert-JsonToHashtable $_ })
    }
    return $InputObject
}

function Get-State {
    if (Test-Path $StateFile) {
        try {
            $raw = Get-Content $StateFile -Raw
            if ($raw.Trim()) { return Convert-JsonToHashtable ($raw | ConvertFrom-Json) }
        } catch {
            Write-Log "Falha ao ler estado: $($_.Exception.Message)"
        }
    }
    return @{}
}

function Save-State {
    param([hashtable]$State)
    $State | ConvertTo-Json -Depth 6 | Set-Content -Path $StateFile -Encoding UTF8
}

function Show-ApprovalToast {
    param(
        [string]$Repo,
        [int]$Number,
        [string]$Title,
        [string]$Reviewer,
        [string]$Url
    )

    Import-Module BurntToast -ErrorAction Stop

    $button = New-BTButton -Content "Abrir PR" -Arguments $Url
    New-BurntToastNotification `
        -Text "PR aprovado ✅", "$Repo #$Number", "$Reviewer aprovou: $Title" `
        -Button $button
}

function Show-CommentToast {
    param(
        [string]$Repo,
        [int]$Number,
        [string]$Title,
        [string]$Commenter,
        [string]$Url
    )

    Import-Module BurntToast -ErrorAction Stop

    $button = New-BTButton -Content "Abrir PR" -Arguments $Url
    New-BurntToastNotification `
        -Text "Novo comentário 💬", "$Repo #$Number", "$Commenter comentou em: $Title" `
        -Button $button
}

function Ensure-Gh {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) não encontrado. Instale com: winget install --id GitHub.cli"
    }

    & gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI não está autenticado. Rode: gh auth login"
    }
}

Ensure-Gh

$state = Get-State
$firstRun = ($state.Count -eq 0)
Write-Log "Notifier iniciado. Intervalo: $(Get-CurrentInterval) s. FirstRun=$firstRun"

while ($true) {
    $interval = Get-CurrentInterval
    try {
        # Busca todos os PRs abertos criados pelo usuário autenticado, em qualquer repositório acessível.
        $prsJson = & gh search prs --author "@me" --state open --limit 100 `
            --json number,title,url,repository,updatedAt 2>$null

        if ($LASTEXITCODE -ne 0) {
            throw "gh search prs retornou código $LASTEXITCODE"
        }

        $prs = @()
        if ($prsJson) {
            $prs = $prsJson | ConvertFrom-Json
        }

        foreach ($pr in $prs) {
            $repo = $pr.repository.nameWithOwner
            $prKey = "$repo#$($pr.number)"

            $detailJson = & gh pr view $pr.url --json reviews,comments 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $detailJson) {
                Write-Log "Não foi possível consultar reviews de $prKey"
                continue
            }

            $detail = $detailJson | ConvertFrom-Json
            $approvals = @($detail.reviews | Where-Object { $_.state -eq "APPROVED" })

            foreach ($review in $approvals) {
                $reviewer = if ($review.author.login) { $review.author.login } else { "Reviewer" }
                $submittedAt = if ($review.submittedAt) { $review.submittedAt } else { "unknown" }
                $approvalKey = "$prKey|$reviewer|$submittedAt"

                if (-not $state.ContainsKey($approvalKey)) {
                    # Na primeira execução, apenas memoriza aprovações já existentes.
                    # Assim você não recebe uma enxurrada de notificações antigas.
                    if (-not $firstRun) {
                        Show-ApprovalToast `
                            -Repo $repo `
                            -Number $pr.number `
                            -Title $pr.title `
                            -Reviewer $reviewer `
                            -Url $pr.url

                        Write-Log "Notificado: $approvalKey"
                    }

                    $state[$approvalKey] = @{
                        seenAt = (Get-Date).ToString("o")
                        url = $pr.url
                    }
                }
            }

            $cfg = Get-Config
            if ($cfg.notifyComments) {
                $commentsSeeded = ($state['_meta'].commentsSeeded -eq $true)
                foreach ($comment in @($detail.comments)) {
                    $commenter = if ($comment.author.login) { $comment.author.login } else { "Alguém" }
                    $createdAt = if ($comment.createdAt) { $comment.createdAt } else { "unknown" }
                    $commentKey = "$prKey|comment|$commenter|$createdAt"

                    if (-not $state.ContainsKey($commentKey)) {
                        # Na primeira rotação após ativar esta feature, apenas memoriza.
                        if (-not $firstRun -and $commentsSeeded) {
                            Show-CommentToast `
                                -Repo $repo `
                                -Number $pr.number `
                                -Title $pr.title `
                                -Commenter $commenter `
                                -Url $pr.url

                            Write-Log "Notificado comentário: $commentKey"
                        }

                        $state[$commentKey] = @{
                            seenAt = (Get-Date).ToString("o")
                            url = $pr.url
                        }
                    }
                }

                if (-not $commentsSeeded) {
                    $state['_meta'] = @{ commentsSeeded = $true }
                }
            }
        }

        Save-State $state
        $firstRun = $false
    }
    catch {
        Write-Log "Erro: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds $interval
}
