#!/usr/bin/env sh
# session-status.sh [caminho] [--sid <sid>] — Derivador determinístico do índice.
#
# Lê o índice event-sourced .kolb/sessions.jsonl (append-only, escrito por
# toggle-mode.sh e session-end.sh) e EMITE, por sessão (sid), um registro
# derivado por FOLD: {sid,start,end,mode,status,commits} — um JSON por linha
# (JSONL), ordenado por `start` asc para determinismo (NFR7).
#
# IMPORTANTE: este script só LÊ o índice e DERIVA o status por sessão. NÃO
# calcula sinais de checkpoint (sessões/semana, razão de commits) nem o veredito
# Go/No-Go — isso é da checkpoint.sh (5.2), que consome esta saída. Esta é a
# fronteira determinística (sem relógio, sem aleatoriedade, sem LLM): entrada
# idêntica ⇒ saída byte-a-byte idêntica.
#
# O template templates/sessions.jsonl ilustra o vocabulário de eventos; ele é
# REFERÊNCIA-APENAS e NUNCA é copiado para .kolb/ (injetaria eventos falsos no
# índice real). O sessions.jsonl real nasce dos eventos do `on` (1.2).
#
# Regra de fold por sid (hardcoded, determinística):
#   start   = menor ts entre os eventos do sid (tolera falta de session_start)
#   end     = ts do session_end; senão do último mode_off; senão ts máximo
#   mode    = "learn" (o índice só rastreia sessões de modo nesta fase)
#   commits = [ sha de cada evento event=="commit" ]  (vazio até 5.1)
#   status  = "complete"  se ≥1 evento phase_conceptualize (ciclo fechou)
#             "partial"   senão, se ≥1 evento phase_* (ciclo iniciado, não fechou — FR4)
#             "abandoned" senão (modo ativado, ciclo nunca iniciado)
# O fold é forward-compatible: tolera ausência dos eventos phase_*/commit hoje
# (Epics 3/5) e os consome quando existirem.
set -eu

# Sourcing de _common.sh: prioriza CLAUDE_PLUGIN_ROOT; cai para o diretório deste
# script quando a env var não está setada (ex.: execução direta em teste).
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
# shellcheck source=/dev/null
. "$_kolb_common"

# O fold parseia JSON ⇒ exige jq. Ausente ⇒ erro legível + exit 0 (NFR12).
kolb_require_jq || exit 0

# Argumentos: [caminho] e/ou [--sid <sid>], em qualquer ordem. Sem caminho ⇒
# default .kolb/sessions.jsonl sob CLAUDE_PROJECT_DIR.
sessions=""
filter_sid=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sid)
      shift
      filter_sid="${1:-}"
      ;;
    --sid=*)
      filter_sid="${1#--sid=}"
      ;;
    *)
      sessions="$1"
      ;;
  esac
  # Shift guardado: o ramo `--sid` já pode ter consumido o último token (valor do
  # flag), deixando $#=0; um `shift` cru abortaria sob `set -eu` (NFR9). O AND-list
  # `[ ... ] && shift` nunca dispara o set -e e só desloca se ainda houver token.
  [ $# -gt 0 ] && shift
done
if [ -z "$sessions" ]; then
  base="$(kolb_project_dir)"
  [ -n "$base" ] || { kolb_log_error "session-status: CLAUDE_PROJECT_DIR ausente; índice vazio."; exit 0; }
  sessions="$base/.kolb/sessions.jsonl"
fi

# Arquivo ausente ⇒ índice vazio: saída vazia, exit 0 (AC#4, NFR8).
[ -f "$sessions" ] || exit 0

# Tolerância a malformação (AC#4, NFR8): processa LINHA A LINHA. Cada linha é
# validada com jq como objeto JSON com ts/sid/event (strings). Linha que não
# parseia ou não bate o schema é PULADA e contabilizada — nunca aborta o fold.
# Linhas em branco são ignoradas (não contam como malformadas).
valid=$(mktemp 2>/dev/null) || { kolb_log_error "session-status: falha ao criar tmp; índice vazio."; exit 0; }
trap 'rm -f "$valid"' EXIT INT TERM
skipped=0

# `read || [ -n "$line" ]` garante processar a última linha mesmo sem newline final.
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] || continue
  if printf '%s\n' "$line" | jq -e \
      'type=="object" and (.ts|type=="string") and (.sid|type=="string") and (.event|type=="string")' \
      >/dev/null 2>&1; then
    printf '%s\n' "$line" >> "$valid"
  else
    skipped=$((skipped + 1))
  fi
done < "$sessions"

# Fold determinístico sobre os eventos válidos (jq slurp). Agrupa por sid, deriva
# o registro e ordena por start asc. Comparação de ts é lexicográfica sobre ISO
# 8601 (determinística; o offset de tz é o da máquina, estável dentro da sessão).
# Filtro opcional por --sid aplicado ANTES do agrupamento.
jq -s -c \
  --arg fsid "$filter_sid" \
  '
  ( if $fsid == "" then . else map(select(.sid == $fsid)) end )
  | group_by(.sid)
  | map({
      sid:   .[0].sid,
      start: (map(.ts) | min),
      end:   ( (map(select(.event=="session_end").ts) | max)
               // (map(select(.event=="mode_off").ts) | max)
               // (map(.ts) | max) ),
      mode:  "learn",
      status: (
        if   any(.[]; .event == "phase_conceptualize")  then "complete"
        elif any(.[]; .event | startswith("phase_"))     then "partial"
        else "abandoned" end
      ),
      commits: [ .[] | select(.event == "commit") | .sha? // empty ]
    })
  | sort_by(.start)
  | .[]
  ' "$valid"

# Reporta linhas ignoradas em stderr (legível), sem alterar o exit code de sucesso.
if [ "$skipped" -gt 0 ]; then
  printf 'session-status: %s linha(s) malformada(s) ignorada(s) em %s\n' "$skipped" "$sessions" >&2
fi
exit 0
