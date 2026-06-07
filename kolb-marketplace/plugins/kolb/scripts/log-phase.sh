#!/usr/bin/env sh
# log-phase.sh <fase> — Anexa um evento de fase Kolb ao índice event-sourced.
#
# Invocado pelas skills de fase (a 1ª é /kolb:reflect, Story 3.2) quando uma fase
# do ciclo Kolb efetivamente roda. Emite UMA linha em .kolb/sessions.jsonl:
#   {"ts":"<ISO8601>","sid":"<session_id>","event":"phase_<fase>","mode":"learn"}
#
# Por que existe: session-status.sh (1.4) DERIVA o status da sessão a partir
# desses eventos — `phase_conceptualize` ⇒ complete; qualquer outro `phase_*` ⇒
# partial (FR4); nenhum ⇒ abandoned. Sem este evento, uma sessão que reflete mas
# não conceitua seria derivada como `abandoned` em vez de `partial`.
#
# NÃO gateia (skills são invocadas explicitamente; o guard de modo é dos HOOKS,
# não das skills — ver Dev Notes da story). Falha graciosa (NFR9): qualquer
# problema vira log + exit 0, nunca derruba o hospedeiro. Schema fixo {ts,sid,
# event,mode} — montável por printf, sem jq nem escape (como mode_on/mode_off).
# Append-only, sem dedup: o fold usa any()/startswith (idempotente a duplicatas).
set -eu

# Sourcing de _common.sh: prioriza CLAUDE_PLUGIN_ROOT; cai para o diretório deste
# script quando a env var não está setada (ex.: execução direta em teste).
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
# shellcheck source=/dev/null
. "$_kolb_common"

# Valida a fase: só letras minúsculas ASCII (reflect|conceptualize|experiment).
# Qualquer outro caractere é recusado para nunca compor uma linha JSON malformada
# nem um nome de evento inesperado para o fold.
phase="${1:-}"
case "$phase" in
  ""|*[!a-z]*)
    kolb_log_error "log-phase: fase inválida ou ausente (esperado [a-z]+, ex.: reflect)."
    printf '%s\n' "Kolb: fase inválida para registro. Nada foi registrado."
    exit 0
    ;;
esac

# Resolve a sessão. Skill: CLAUDE_CODE_SESSION_ID (UUID). Vazio ⇒ falha graciosa.
sid="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$sid" ]; then
  kolb_log_error "log-phase: CLAUDE_CODE_SESSION_ID vazio; não foi possível resolver a sessão."
  printf '%s\n' "Kolb: não consegui identificar a sessão atual. Fase não registrada."
  exit 0
fi

# Valida o formato do sid: apenas [0-9A-Za-z-] (UUID v4). Defesa idêntica à do
# toggle-mode.sh — não confiar cegamente para nunca compor path/JSON malformado.
case "$sid" in
  ""|*[!0-9A-Za-z-]*)
    kolb_log_error "log-phase: CLAUDE_CODE_SESSION_ID com caractere inesperado; recusado."
    printf '%s\n' "Kolb: identificador de sessão inválido. Fase não registrada."
    exit 0
    ;;
esac

# Base de estado: fonte única CLAUDE_PROJECT_DIR (kolb_project_dir). Ausente ⇒
# falha graciosa — não inventa diretório (skill e hook precisam concordar).
base="$(kolb_project_dir)"
if [ -z "$base" ]; then
  kolb_log_error "log-phase: CLAUDE_PROJECT_DIR ausente; não foi possível resolver o diretório do projeto."
  printf '%s\n' "Kolb: não consegui localizar o diretório do projeto. Fase não registrada."
  exit 0
fi

# Garante .kolb/ (durável). Sob set -e, falha de FS abortaria cru; interceptamos.
if ! mkdir -p "$base/.kolb" 2>/dev/null; then
  kolb_log_error "log-phase: não foi possível criar $base/.kolb (FS não-gravável?)."
  printf '%s\n' "Kolb: não consegui preparar o diretório de estado. Fase não registrada."
  exit 0
fi
sessions="$base/.kolb/sessions.jsonl"

# Append do evento (event-sourced, append-only). Sem jq — sid é UUID e a fase é
# [a-z]+; nenhum caractere precisa de escape. Falha de FS ⇒ log + exit 0 (NFR9).
if printf '{"ts":"%s","sid":"%s","event":"phase_%s","mode":"learn"}\n' "$(kolb_ts)" "$sid" "$phase" >> "$sessions" 2>/dev/null; then
  printf '%s\n' "Kolb: fase '$phase' registrada no índice da sessão."
else
  kolb_log_error "log-phase: falha ao anexar evento phase_$phase em $sessions."
  printf '%s\n' "Kolb: não consegui registrar a fase (falha ao gravar o índice)."
fi
exit 0
