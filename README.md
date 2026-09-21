# GitHub PR Notifier (Windows)

Notificador global de aprovações de Pull Requests para Windows.

Monitora **todos** os PRs abertos criados pela sua conta GitHub, em qualquer
repositório acessível, e mostra uma notificação nativa do Windows quando alguém
aprova um PR seu.

## Funcionalidades

- Monitora PRs abertos de todos os seus repositórios (não só os que você tem em
  checkout local)
- Notificação nativa do Windows (toast) com repositório, número, título e autor
  da aprovação, incluindo um botão **Abrir PR**
- Inicia automaticamente e de forma oculta (sem janela de PowerShell) ao fazer
  logon, via Agendador de Tarefas
- Aprovações antigas não geram notificação: só avisa aprovações *novas*
- Logs e estado persistidos em `%LOCALAPPDATA%\GitHubPrNotifier`

## Pré-requisitos

- Windows 10 ou 11
- PowerShell (Windows PowerShell 5.1 ou PowerShell 7+)
- GitHub CLI (`gh`) — o instalador tenta instalar via `winget`
- Autenticado no `gh` — o instalador abre o login se necessário

## Instalação

1. Baixe e extraia a pasta do projeto (ou clone o repositório).
2. Clique com o botão direito em `Install-GitHubPrNotifier.ps1` e escolha
   **Executar com PowerShell**.

Se o Windows bloquear scripts, rode antes:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

O instalador:

- Copia o script para `%LOCALAPPDATA%\GitHubPrNotifier`
- Instala o GitHub CLI, se ainda não existir
- Instala o módulo `BurntToast` (notificações do Windows)
- Registra uma tarefa no **Agendador de Tarefas** que inicia o notifier a cada
  logon
- Inicia o monitoramento na hora

> **Sem janelas!** O notifier roda totalmente oculto: nenhum prompt de
> PowerShell aparece na inicialização do Windows nem durante o uso. Ele fica
> rodando em segundo plano e só se manifesta pelo toast de notificação.

## Configuração

Tudo o que precisa configurar é um único arquivo:
`%LOCALAPPDATA%\GitHubPrNotifier\config.json`

Ele controla a única opção disponível — o intervalo de verificação:

```json
{
    "intervalSeconds": 60
}
```

- O valor é em **segundos** (padrão: `60`).
- Quanto menor, com mais frequência o `gh` é consultado (mínimo de 10s).
- **Não precisa reiniciar nada:** ao salvar o arquivo, o novo intervalo entra em
  vigor no próximo ciclo de verificação (junto com a atualização automática do
  próprio arquivo durante a instalação).

| O que você quer          | O que fazer                                          |
| ------------------------ | ---------------------------------------------------- |
| Checar a cada 2 min      | altere `60` para `120` e salve o arquivo             |
| Voltar ao padrão         | deixe `60` ou recrie o arquivo com o conteúdo acima  |

## Como funciona

- Consulta até 100 PRs abertos criados por você
- Verifica no intervalo definido em `config.json`
- Usa a autenticação já existente do `gh`
- Na primeira execução, aprovações já existentes são apenas memorizadas — você só
  recebe toast para aprovações novas
- Estado e logs ficam em:

```
%LOCALAPPDATA%\GitHubPrNotifier\
├── GitHubPrNotifier.ps1   # script principal
├── run-hidden.vbs         # launcher invisível (usado pelo agendador)
├── config.json            # configuração (intervalo de verificação)
├── state.json             # aprovações já vistas
└── notifier.log           # logs de execução
```

## Teste

Para confirmar que as notificações estão funcionando sem esperar alguém aprovar
um PR, rode:

```powershell
.\Test-Notification.ps1
```

## Desinstalação

Rode `Uninstall-GitHubPrNotifier.ps1` (remove a tarefa agendada e os arquivos
em `%LOCALAPPDATA%\GitHubPrNotifier`).

## Limitações

- Notificações só para **aprovações** (`APPROVED`) — comentários e outras
  revisões não disparam toast
- Depende do GitHub CLI autenticado funcionando
- É um utilitário pessoal simples: sem interface gráfica de configuração

## Licença

MIT — veja [LICENSE](LICENSE).