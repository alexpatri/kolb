#!/usr/bin/env sh
# nudge-cycle.sh — Hook UserPromptSubmit do Kolb (NUDGE DE CICLO ABERTO, FR42).
# Em modo aprendizado, quando a sessão tem ESFORÇO NÃO-CONCEITUADO, injeta a cada
# turno (com throttle) um lembrete socrático via additionalContext sugerindo a
# próxima fase do ciclo (RO→AC→AE) — para o aprendizado virar nota AC e não se
# perder. É ADITIVO e NÃO bloqueia (mesmo mecanismo do prompt-steer.sh).
#
# IRMÃO do prompt-steer.sh, NÃO substituto: os dois são hooks UserPromptSubmit
# distintos em hooks.json; o host executa ambos e concatena os additionalContext.
# O caminho constante/jq-free do steer permanece intacto (nenhuma linha dele tocada).
#
# ESFORÇO NÃO-CONCEITUADO = phase_conceptualize AUSENTE E (phase_reflect presente
# OU ≥1 evento commit da sessão). O commit é o proxy determinístico de "o dev
# escreveu código" (no modo a IA não gera; capture-commit.sh só registra commit
# DENTRO do modo ⇒ autoral). FECHAMENTO = ≥1 phase_conceptualize — MESMA regra de
# session-status.sh:110 e session-phase.sh; o nudge silencia EXATAMENTE quando o
# /kolb:help reporta o ciclo fechado (uma verdade só, sem Goodhart de apresentação).
#
# FRONTEIRA (não reinventar a ordem RO→AC→AE): reusa session-phase.sh --sid como
# fonte ÚNICA do `next` (inclui o caso fora-de-ordem ⇒ reflect, decisão do code
# review da 7.1). Este hook só CONSOME o `next` e adiciona a dimensão de commit
# (que o deriver não expõe) para o caso next:none.
#
# ESCREVE estado (diferente da skill read-only da 7.1): o marcador de throttle
# .kolb/runtime/nudge-<sid> guarda o último estado nudgeado (bookkeeping do hook,
# como hook-errors.log). runtime/ é gitignored (toggle-mode.sh:63) ⇒ sem churn.
# Ainda assim fail-open: falha de escrita loga e segue, nunca aborta.
#
# Fail-safe = PASSTHROUGH (como o prompt-steer): erro interno ⇒ exit 0 SEM injetar
# + log (NFR9). O garante DURO de não-geração (block-write.sh) é independente e
# permanece. Caminho ativo 100% JQ-FREE: sid via kolb_gate/sed (sem jq), fase via
# session-phase.sh (jq-free), commit via grep. Não chamar kolb_require_jq.
set -eu

# Sourcing endurecido de _common.sh (idêntico ao prompt-steer.sh/block-write.sh):
# prioriza CLAUDE_PLUGIN_ROOT; cai para o diretório deste script quando a env var
# não está setada (ex.: execução direta em teste). Sob `set -e`, qualquer falha em
# resolver $0 ou sourcear _common.sh ⇒ exit 0 SEM emitir nada (passthrough).
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 0
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
# `.` é builtin ESPECIAL: arquivo ausente/ilegível aborta (status≠0) ANTES de um
# `|| exit 0` colado no dot — por isso guardamos com `[ -r ]` ANTES de sourcear.
[ -r "$_kolb_common" ] || exit 0
# shellcheck source=/dev/null
. "$_kolb_common" 2>/dev/null || exit 0

# 1ª lógica: guard universal. Modo OFF (flag ausente) ou sid irresolvível ⇒ exit 0
# barato, sem jq, SEM ler o índice (AC#4, NFR5). Nenhum caminho abaixo é alcançado
# fora do modo — o off-path é idêntico ao do prompt-steer/block-write.
input=$(cat)
kolb_gate "$input"

# Modo ATIVO a partir daqui. sid do STDIN — este é um HOOK, então o sid vem de
# .session_id (kolb_session_id_from_stdin, já validado p/ [0-9A-Za-z-]), NUNCA de
# CLAUDE_CODE_SESSION_ID (env das skills). É o INVERSO do crux da 7.1 (que era skill).
sid=$(printf '%s' "$input" | kolb_session_id_from_stdin)
[ -n "$sid" ] || exit 0

# Base de estado: fonte única CLAUDE_PROJECT_DIR (presente em HOOK, hot-path ⇒ o
# ramo git de kolb_project_dir nunca dispara aqui). Ausente ⇒ passthrough + log.
base="$(kolb_project_dir)"
[ -n "$base" ] || { kolb_log_error "nudge-cycle: CLAUDE_PROJECT_DIR ausente; passthrough (sem nudge)."; exit 0; }
sessions="$base/.kolb/sessions.jsonl"

# --- Estado do ciclo: REUSA session-phase.sh (fonte única da ordem RO→AC→AE).
# Só extrai a linha `next:`; qualquer falha do deriver ⇒ next vazio ⇒ silêncio.
_phase_script="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/session-phase.sh"
[ -f "$_phase_script" ] || _phase_script="$_kolb_self_dir/session-phase.sh"
next=$("$_phase_script" --sid "$sid" 2>/dev/null | sed -n 's/^next: //p') || next=""

# --- Dimensão de commit (proxy de "escreveu código"): ≥1 evento commit desta
# sessão no índice. jq-free (sid sanitizado ⇒ seguro em grep -F). Ausente ⇒ 0.
has_commit=0
if [ -f "$sessions" ]; then
  if grep -F '"event":"commit"' "$sessions" 2>/dev/null | grep -qF "\"sid\":\"$sid\""; then
    has_commit=1
  fi
fi

# --- Regra de decisão: (next[, commit]) → token de estado + mensagem socrática.
# Silêncio (token vazio) quando o ciclo está FECHADO (experiment|complete ⇒
# conceptualize presente) ou VAZIO (none sem commit) — zero ruído (AC#2).
token=""
msg=""
case "$next" in
  conceptualize)
    token="conceptualize"
    msg="Modo aprendizado: você refletiu (RO) mas ainda não conceituou. O aprendizado só vira nota AC reutilizável com /kolb:conceptualize.\nQuer extrair agora o conceito atômico do que aprendeu?"
    ;;
  reflect)
    token="reflect"
    msg="Modo aprendizado: há fase do ciclo registrada sem a Observação Reflexiva que a sustenta — o ciclo Kolb não fecha sem RO.\nQuer começar por /kolb:reflect sobre o que você escreveu?"
    ;;
  none)
    if [ "$has_commit" = 1 ]; then
      token="effort"
      msg="Modo aprendizado: você escreveu código nesta sessão mas ainda não refletiu sobre ele; o aprendizado se perde se o ciclo não fechar.\nQuer rodar /kolb:reflect antes de seguir?"
    fi
    ;;
  *)
    # experiment | complete (ciclo fechado) | vazio (falha do deriver) ⇒ silêncio.
    : ;;
esac

# Nada a nudgear ⇒ passthrough silencioso (AC#2).
[ -n "$token" ] || exit 0

# --- Throttle por ESTADO (AC#3): marcador em runtime/ (gitignored). Se o último
# estado nudgeado nesta sessão é o mesmo ⇒ silêncio (não repete a cada turno).
marker="$base/.kolb/runtime/nudge-$sid"
if [ -f "$marker" ]; then
  last=$(cat "$marker" 2>/dev/null) || last=""
  [ "$last" = "$token" ] && exit 0
fi

# --- Emite o nudge (ADITIVO) PRIMEIRO; grava o throttle SÓ após emissão OK.
# Ordem deliberada: o marcador nunca deve registrar como "nudgeado" um turno cuja
# injeção falhou (EPIPE/stdout fechado) — senão, enquanto o estado do ciclo não
# mudasse, o nudge ficaria silenciado sem NUNCA ter sido entregue. Forma JSON =
# prompt-steer.sh:50; a mensagem varia por estado mas NÃO tem aspas duplas internas
# ⇒ JSON montável sem escape; o \n (literal na string) vira quebra de linha no valor
# JSON, mantendo UMA linha no stdout. Tom honra o CLAUDE.md (≤3 linhas · termina em
# ação · não revela solução).
if printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"$msg\"}}"; then
  # Emissão OK ⇒ grava o estado nudgeado (bookkeeping; fail-open — falha de FS loga
  # e segue). runtime/ é durável-mas-gitignored. Caso "emit OK + marcador falha" ⇒
  # re-nudge no próximo turno (repetição rara sob falha persistente de FS, já aceita
  # na AC#5), nunca abort.
  if mkdir -p "$base/.kolb/runtime" 2>/dev/null; then
    printf '%s\n' "$token" > "$marker" 2>/dev/null \
      || kolb_log_error "nudge-cycle: falha ao gravar marcador de throttle ($marker)."
  else
    kolb_log_error "nudge-cycle: falha ao criar runtime/ para o throttle."
  fi
else
  # Fail-open (NFR9): emissão falha (EPIPE/stdout fechado) ⇒ log + exit 0 SEM
  # persistir o throttle ⇒ o nudge é re-tentado no próximo turno (enquanto o estado
  # não mudar), em vez de ficar silenciado por um estado que nunca foi entregue.
  kolb_log_error "nudge-cycle: falha ao emitir additionalContext; passthrough (sem injetar)."
fi
exit 0
