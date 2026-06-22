# Instalação do Kolb

O Kolb é instalado como **plugin via marketplace local** do Claude Code. Não há
cópia manual de diretórios nem merge de `settings.json`: os hooks são declarados
pelo próprio plugin e o estado do projeto (`.kolb/`) nasce **automaticamente no
primeiro uso**.

## Pré-requisitos

- **Claude Code** com suporte a plugins/marketplace.
- **`jq`** instalado e no `PATH`. Os scripts do Kolb usam `jq` para ler os
  eventos dos hooks; se ele estiver ausente, reportam um erro legível e não
  derrubam a sessão (NFR12 — fail-open), mas as features de runtime não operam
  até instalá-lo.

## Passos (marketplace local)

No Claude Code, a partir da raiz do projeto que contém `kolb/`:

```
/plugin marketplace add ./kolb
/plugin install kolb@kolb-local
```

1. `/plugin marketplace add ./kolb` — registra o marketplace local
   (`name: kolb-local`).
2. `/plugin install kolb@kolb-local` — instala o plugin `kolb` a partir desse
   marketplace.

Use exatamente estas formas — não há flags nem variações adicionais.

## Verificação pós-instalação

- Os slash commands `/kolb:*` ficam disponíveis na sessão. Confirme, por
  exemplo, com `/kolb:learn-mode on` (ativa o modo aprendizado) e
  `/kolb:learn-mode off "<motivo>"` (desativa com justificativa).
- **Opcional:** validar o pacote localmente —
  `claude plugin validate ./kolb-marketplace/plugins/kolb`. Um warning sobre o
  `CLAUDE.md` do plugin não ser auto-carregado é **conhecido e esperado** (não é
  falha).

## Criação inicial de `.kolb/` (estado do projeto)

O estado do Kolb vive em `.kolb/` na raiz do projeto e é criado
**automaticamente no primeiro uso de cada feature** — você não precisa criar
nada à mão:

- `.kolb/runtime/` e `.kolb/runtime/.gitignore` (conteúdo `*`) são criados no
  **primeiro** `/kolb:learn-mode on`, de forma idempotente (só se ainda não
  existirem).
- `.kolb/notes/` é criado na **primeira** nota AC (`/kolb:conceptualize`).
- `pdi.md` e `exit-log.md` nascem no primeiro uso de cada feature, copiados dos
  `templates/*` do plugin.
- `sessions.jsonl` é **event-sourced**: nasce dos eventos do `/kolb:learn-mode on`
  (anexados linha a linha), **não** é copiado de nenhum template. O
  `templates/sessions.jsonl` é referência-apenas e nunca é copiado para `.kolb/`
  (semeá-lo manualmente injetaria eventos falsos no índice).

Depois de algum uso, a árvore esperada é:

```
.kolb/
├── notes/              # notas AC (durável, versionável)
├── pdi.md              # Plano de Desenvolvimento Individual (durável)
├── exit-log.md         # registro de saídas do modo (durável)
├── sessions.jsonl      # índice de sessões event-sourced (durável)
└── runtime/
    └── .gitignore      # conteúdo: *  (efêmero, ignorado pelo git)
```

**Split durável vs. runtime (AR-StateSplit):** tudo em `.kolb/*` é versionável e
deve ser commitado — **exceto** `.kolb/runtime/*`, que é efêmero e fica fora do
versionamento (o `.gitignore = *` garante isso). **Não** commite `runtime/`.

> **Atalho opcional (não obrigatório):** se preferir, você pode pré-criar
> `.kolb/notes/` e `.kolb/runtime/.gitignore` (com o conteúdo `*`) manualmente
> antes do primeiro uso. É apenas conveniência — o caminho normal é automático,
> e pular este atalho não muda nada.
