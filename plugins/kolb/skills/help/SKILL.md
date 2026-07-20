---
description: Mostra a ajuda do Kolb — lista os comandos e as 4 fases do ciclo (CE→RO→AC→AE) E situa você na sessão atual (modo on/off, fase mais recente e a próxima ação sugerida). Acione com "/kolb:help" quando quiser lembrar os comandos ou saber qual o próximo passo para não perder o fluxo.
allowed-tools: [Bash]
---

# /kolb:help — Ajuda do Kolb (ciente do estado)

Ajuda o dev a **descobrir os comandos** e a **saber a próxima ação** sem sair para
a documentação. Duas partes: (1) uma **listagem** fixa do fluxo, sempre exibida; e
(2) o **estado da sessão atual** (modo on/off + fase do ciclo + próxima ação),
quando ele puder ser resolvido.

Esta skill é de **apresentação e só-leitura**: não gera nem edita código, não
registra fase do ciclo (help não é fase RO/AC/AE — não há `log-phase` aqui), não
escreve nada em `.kolb/`. Ela **narra** o que o deriver determinístico calcula —
**não recalcula** a lógica de próxima fase (o script é a fonte de verdade).

## O que fazer

### 1. Sempre: exibir o fluxo

Liste, de forma compacta (registro de tom do `CLAUDE.md`: direto, sem discurso),
os comandos e as 4 fases. Não invente comandos além destes:

**Comandos**
- `/kolb:learn-mode on` · `/kolb:learn-mode off "<motivo>"` — liga/desliga o modo aprendizado na sessão.
- `/kolb:reflect` — **RO**: verbalize as decisões do seu código; o tutor isolado questiona.
- `/kolb:conceptualize "<título>"` — **AC**: destila UM conceito atômico numa nota reutilizável.
- `/kolb:experiment` — **AE**: recebe uma variação não-trivial para resolver sem IA.
- `/kolb:checkpoint [4|8]` — veredito Go/No-Go determinístico das últimas 4/8 semanas.
- `/kolb:create-pdi` — **cria** o PDI por elicitação socrática (metas na sua formulação).
- `/kolb:pdi-checkin` — revisa o PDI (metas · evidência · próxima ação) e o mantém vivo.
- `/kolb:help` — esta ajuda.

**As 4 fases do ciclo Kolb**
`CE` (Experiência Concreta — você escreve o código; estado default do modo) →
`RO` (`/kolb:reflect`) → `AC` (`/kolb:conceptualize`) → `AE` (`/kolb:experiment`).

### 2. Situar na sessão atual (estado)

Rode o **deriver read-only** para obter o estado do ciclo na sessão corrente:

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/session-phase.sh" --sid "$CLAUDE_CODE_SESSION_ID"
```

A saída é chave-por-linha:

```
session: <sid>|unknown
mode: on|off|unknown
phases: <fases já registradas nesta sessão>
last-phase: reflect|conceptualize|experiment|none
next: reflect|conceptualize|experiment|complete|none
```

Narre o estado em ≤3 linhas, no registro de tom, mapeando **`next`** para a próxima
ação (a skill só traduz o `next` — **não** decide a ordem por conta própria):

- **`session: unknown`** ou **`mode: unknown`** → não foi possível resolver a
  sessão/o projeto. Diga isso em uma linha honesta e **pare no fluxo acima** — não
  invente fase nem modo.
- **`mode: off`** → "Modo aprendizado **off** nesta sessão. Ligue com
  `/kolb:learn-mode on` para começar o ciclo." (Não narre fase — fora do modo não há ciclo.)
- **`mode: on`**, conforme `next`:
  - **`none`** → "Modo **on**, nenhuma fase ainda. Escreva seu código (CE) e, quando
    quiser destrinchar as decisões, rode `/kolb:reflect`."
  - **`reflect`** → "Você registrou `<last-phase>` mas **pulou a Observação Reflexiva**.
    O ciclo não fecha sem RO — rode `/kolb:reflect` para verbalizar as decisões deste
    código antes de conceituar. O que você decidiu aqui e por quê?"
  - **`conceptualize`** → "Você registrou `<last-phase>` mas ainda **não conceituou**.
    Rode `/kolb:conceptualize \"<título>\"` para fechar o ciclo e não perder o
    aprendizado — qual é a ideia única desta sessão?"
  - **`experiment`** → "Ciclo fechado ✓ (você conceituou). Opcional: consolide por
    transferência com `/kolb:experiment`. Quer testar o conceito num contexto novo?"
  - **`complete`** → "Ciclo completo ✓ (RO→AC→AE nesta sessão). Nada pendente — siga
    para o próximo problema quando quiser."

Encerre devolvendo a bola quando houver uma próxima ação (pergunta ou prompt de ação).

---

Esta skill **pode ser sugerida pelo modelo** quando o dev parecer perdido no fluxo
ou perguntar "o que eu faço agora?". Ela **não** liga/desliga o modo, **não** chama
o tutor, **não** registra fase e **não** grava estado. Respostas em **streaming**
natural do hospedeiro — sem barras de progresso nem "processando…".
