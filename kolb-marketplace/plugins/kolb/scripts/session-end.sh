#!/usr/bin/env sh
# session-end.sh — Hook SessionEnd do Kolb. Anexa um evento `session_end` a
# .kolb/sessions.jsonl quando a sessão termina AINDA EM MODO (flag presente).
#
# Captura o caso em que o usuário fecha a janela sem `/kolb:learn-mode off`:
# o `mode_off` nunca foi emitido, e este é o único anchor de término. Sessões
# que já fizeram `off` não têm flag → o guard faz passthrough e nada é anexado
# (o `mode_off` da 1.3 já é o terminal nesse caso).
#
# Estrutura canônica de hook: gating barato PRIMEIRO (NFR5), nunca derruba o
# hospedeiro (NFR9 — erro interno ⇒ hook-errors.log + exit 0).
set -eu

# Sourcing de _common.sh: prioriza CLAUDE_PLUGIN_ROOT; cai para o diretório deste
# script quando a env var não está setada (ex.: execução direta em teste).
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
# shellcheck source=/dev/null
. "$_kolb_common"

# 1ª lógica: guard universal. Modo OFF (flag ausente) ⇒ exit 0 barato, sem jq.
input=$(cat)
kolb_gate "$input"

# Modo ATIVO a partir daqui. Re-extrai o sid do stdin para compor o evento
# (redundante com o guard, mas barato e claro — sem jq; sid é UUID validado).
sid=$(printf '%s' "$input" | kolb_session_id_from_stdin)

# Base de estado: fonte única CLAUDE_PROJECT_DIR. Ausente ⇒ falha graciosa.
base="$(kolb_project_dir)"
[ -n "$base" ] || { kolb_log_error "session-end: CLAUDE_PROJECT_DIR ausente; nada anexado."; exit 0; }
sessions="$base/.kolb/sessions.jsonl"

# Append best-effort do evento terminal (append-only, sem jq — schema fixo).
printf '{"ts":"%s","sid":"%s","event":"session_end","mode":"learn"}\n' "$(kolb_ts)" "$sid" >> "$sessions" 2>/dev/null \
  || kolb_log_error "session-end: falha ao anexar session_end em $sessions."
exit 0
