# Walkthrough de prontidão da V1 — as 6 jornadas do PRD (Story 6.3, AC#3/AC#4)

**Data:** 2026-06-21 · **Escopo:** validação de **prontidão** (readiness) da V1
completa (Epics 1–5 entregues; 6.1/6.2 done). **Fonte das jornadas:** `prd.md:153-243`.

## Método (e por que NÃO é um live-install)

O projeto **consistentemente** verificou por **inspeção estática + smoke test efêmero
em `/tmp`**, sem tocar `~/.claude` (decisão mantida de 1.1 a 6.2). Este walkthrough
segue a mesma régua: rastreia cada jornada → componentes que a realizam → evidência
acumulada → veredito, **executa headless** o que é exercitável por cadeia de script,
e **lista explicitamente** o que só fecha **ao vivo num host instalado** (disparo real
de hooks/skills pelo Claude Code). O passo ao-vivo é do **Alex** — não é executado aqui.

Vereditos possíveis:
- **`pronto (headless)`** — cadeia de script verificada end-to-end nesta análise e/ou por smoke test de story.
- **`pronto, falta confirmação ao vivo`** — lógica verificada headless; resta só o disparo real pelo host (item ao-vivo, listado abaixo).

---

## Evidência integrada desta análise (fold E2E headless)

Cadeia real rodada em diretório efêmero (`CLAUDE_PROJECT_DIR` em `mktemp -d`, sids UUID
de teste), exercitando os scripts REAIS do plugin (não mocks). Resultado — todos PASS:

| Passo | Componente | Resultado observado |
|---|---|---|
| Gate barato, modo OFF | `block-write.sh` + `kolb_gate` | sem flag `mode-<sid>` ⇒ **passthrough silencioso** (rc=0, zero saída) — **J6** |
| CE — ligar o modo | `toggle-mode.sh on` | `Kolb: modo aprendizado ATIVADO nesta sessão.` + flag `mode-<sid>` criado |
| Bloqueio de geração | `block-write.sh` (modo ON) | emite o **deny socrático verbatim** (`permissionDecision:"deny"`) — **J1/J2** |
| RO + AC — registrar fases | `log-phase.sh reflect` / `conceptualize` | `Kolb: fase '…' registrada no índice da sessão.` |
| Fold do índice | `session-status.sh --sid` | `status:"complete"` (≥1 `phase_conceptualize`) — **J1** |
| Sessão só-reflect | `log-phase.sh reflect` + fold | `status:"partial"` (FR4 — ciclo iniciado, não fechou) — **J2** |
| Spacing contextual | `spacing-read.sh` (Read casando `linked_files`) | injeta `additionalContext` "Spacing contextual (ciclo Kolb)…" — **J4** |

Estado pós-execução: **árvore git limpa** (tudo em `/tmp`, nada tocado no repo).

---

## Rastreio por jornada

### J1 — Happy Path (ciclo Kolb completo CE→RO→AC→AE) — `prd.md:153`
| Componente | Papel | Evidência | Veredito |
|---|---|---|---|
| `block-write.sh` | bloqueia geração na CE | fold E2E (deny verbatim) + smoke 2.2 | `pronto (headless)` |
| `prompt-steer.sh` | injeta contrato/anti-cola a cada turno | smoke 2.3 + convergência P1/P2/P5 (snapshot) | `pronto (headless)` |
| `/kolb:reflect` + `agents/tutor.md` | RO: verbalização + tutor isolado | smoke 3.1/3.2; `log-phase reflect` no fold | `pronto, falta confirmação ao vivo` (invocação da skill/Task pelo host) |
| `/kolb:conceptualize` + `write-note.sh` | AC: nota atômica | smoke 3.3; `log-phase conceptualize`⇒`complete` no fold | `pronto, falta confirmação ao vivo` |
| `/kolb:experiment` | AE: variação não-trivial | smoke 3.4 | `pronto, falta confirmação ao vivo` |
| `templates/sample-run.md` | transcrição canônica das 4 fases | snapshot P2–P8 (7 citações verbatim convergem) | `pronto (headless)` |

### J2 — Edge "escreva o código" — `prd.md` (geração negada + parcial)
| Componente | Papel | Evidência | Veredito |
|---|---|---|---|
| `prompt-steer.sh` | reorienta para a abordagem | smoke 2.3 | `pronto (headless)` |
| `block-write.sh` | deny duro da escrita | fold E2E (deny) + smoke 2.2 | `pronto (headless)` |
| `session-end.sh` / `session-status.sh` | modo parcial + descarte de partial/abandoned | fold E2E (`partial`) + smoke 1.3/1.4 | `pronto (headless)` |

### J3 — Friction: bypass por sessão paralela — `prd.md`
| Componente | Papel | Evidência | Veredito |
|---|---|---|---|
| gating por sessão (`mode-<sid>`) | o modo é por-sessão; sessão paralela sem flag não é gateada | fold E2E (sid sem flag ⇒ passthrough) + smoke 1.2 | `pronto (headless)` |
| `capture-commit.sh` + `checkpoint.sh` | sinal **indireto** de bypass (proveniência de commits → razão; limiar 2 semanas ⇒ retrospectiva) | smoke 5.1/5.2 | `pronto (headless)` (lógica); disparo real do hook PostToolUse/Bash = item ao-vivo |

> Nota: a J3 é, por design, **não-coercitiva** — o plugin não impede o bypass; ele o
> torna **visível** no checkpoint (erosão/Goodhart). Isso é prontidão de **sinal**, não de bloqueio.

### J4 — Retrieval: spacing passivo — `prd.md`
| Componente | Papel | Evidência | Veredito |
|---|---|---|---|
| `spacing-start.sh` (SessionStart) | 1–2 notas antigas para retrieval ativo | smoke 4.3 + convergência P9 | `pronto, falta confirmação ao vivo` (disparo SessionStart pelo host) |
| `spacing-read.sh` (PostToolUse Read) | nota associada ao arquivo aberto | fold E2E (additionalContext injetado) + smoke 4.4 | `pronto, falta confirmação ao vivo` |

### J5 — Checkpoint Go/No-Go — `prd.md`
| Componente | Papel | Evidência | Veredito |
|---|---|---|---|
| `checkpoint.sh` | deriver determinístico (alvos hardcoded, lê sessões/notas, veredito categórico) | smoke 5.2 (42 PASS) | `pronto (headless)` |
| `/kolb:checkpoint` (SKILL) | narra a saída SEM recálculo por LLM | smoke 5.3 (43 PASS) | `pronto, falta confirmação ao vivo` (invocação da skill pelo host) |

### J6 — Default: modo off (não-interferência) — `prd.md`
| Componente | Papel | Evidência | Veredito |
|---|---|---|---|
| `kolb_gate` em todos os hooks | `exit 0` barato quando modo off; zero overhead | fold E2E (passthrough silencioso, jq-free na off-path) + smoke 1.2/2.2 | `pronto (headless)` |

---

## Itens que só fecham AO VIVO (passo final do Alex — host instalado)

Consolidação das pendências "verificação ao vivo" deferidas em 1.2/1.4/3.1–3.4/4.1–4.4/5.3.
**Nenhum** exige tocar `~/.claude` nesta story; o live-install é o passo do Alex.

1. **Disparo real dos hooks pelo host** (PreToolUse/PostToolUse/UserPromptSubmit/SessionStart/SessionEnd) — a lógica está verificada headless; resta o host invocar os scripts via `hooks.json` com o STDIN real.
2. **Invocação das skills pelo host** (`/kolb:learn-mode`, `/reflect`, `/conceptualize`, `/experiment`, `/checkpoint`, `/pdi-checkin`) — incluindo `disable-model-invocation` honrado (learn-mode/checkpoint).
3. **Subagent `kolb:tutor` via Task** — isolamento de nível 1 (só {código+verbalização} repassado) no fluxo real.
4. **NFR11 — `/reload-plugins`** (ver seção abaixo): editar → recarregar → próxima sessão usa a versão nova.

---

## AC#4 / NFR11 — edição sem rebuild (`architecture.md:112,424`)

**Verificável headless (e verificado): ausência de build step / artefato gerado.**
- Não há tooling de build no pacote: **nenhum** `package.json`, `Makefile`, `tsconfig`,
  passo de compilação ou artefato gerado sob `kolb-marketplace/`.
- Os hooks referenciam scripts por `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh` em `hooks/hooks.json`
  — **lidos do disco a cada disparo**, sem etapa intermediária.
- Skills (`skills/*/SKILL.md`), agente (`agents/tutor.md`), contrato (`CLAUDE.md`) e
  templates (`templates/*`) são **arquivos-fonte `.md` lidos diretamente**.
- ⇒ NFR11 é verdadeiro **por construção**: editar um arquivo do plugin altera o
  comportamento sem rebuild/re-deploy.

**Procedimento de confirmação ao vivo (passo do Alex):**
1. Editar uma skill / um script de hook / o `CLAUDE.md`.
2. Rodar `/reload-plugins` no Claude Code.
3. Abrir/continuar uma sessão → a mudança já está em vigor (sem build, sem re-deploy).

Item da mesma categoria "só-fecha-ao-vivo" da AC#3.

---

## Veredito de prontidão

**A V1 está pronta para ship (headless GREEN).** Todas as 6 jornadas têm seus
componentes rastreados, com lógica verificada por cadeia de script (fold E2E desta
análise + smoke tests por story). Os itens remanescentes são **exclusivamente** de
**confirmação ao vivo** num host instalado (disparo real de hooks/skills + `/reload-plugins`),
coerentes com a decisão consistente do projeto de não tocar `~/.claude`. O gate de
validação (Opção A) passa e o snapshot do contrato (NFR22) está GREEN.
