#!/usr/bin/env sh
# session-phase.sh — Deriver READ-ONLY do estado do CICLO KOLB da sessão atual,
# consumido pela skill /kolb:help (story 7.1). Responde a pergunta que o
# session-status.sh NÃO responde: dado o session_id, QUAL a última fase registrada
# e QUAL a próxima ação canônica (RO→AC→AE). O session-status.sh só emite `status`
# (complete/partial/abandoned), colapsando reflect/conceptualize/experiment — por
# isso este deriver existe (não é reinvenção; responde outra pergunta).
#
# Fronteira determinística (como checkpoint.sh ↔ skills/checkpoint): este script
# DERIVA o `next:` (regra de ordem fixa); a skill /kolb:help apenas NARRA. A skill
# NUNCA recalcula qual é a próxima fase — o script é a fonte de verdade.
#
# READ-ONLY: só LÊ .kolb/ (flag de modo + sessions.jsonl); NUNCA escreve estado,
# NUNCA registra fase (não é log-phase), NUNCA toca o plugin. Sem kolb_gate (é
# deriver de skill explícita, não hook — padrão de pdi-status.sh/checkpoint.sh).
#
# SEM jq (NFR12): o sid é UUID sanitizado [0-9A-Za-z-]; as fases saem por grep/sed
# do JSONL append-only produzido por log-phase.sh (formato fixo). O caminho de modo
# é um único `[ -f ]` (fast-path do kolb_gate, sem jq). Falha graciosa em TUDO
# (NFR8/NFR9): sid/projeto/arquivo ausente ⇒ log + exit 0, nunca aborta.
#
# Uso:   session-phase.sh [--sid <sid>]
#   --sid ausente ⇒ usa $CLAUDE_CODE_SESSION_ID (fonte do sid numa SKILL; hooks
#   pegam de STDIN, skills da env — ver toggle-mode.sh:33/log-phase.sh:41).
#
# Saída (stdout), uma linha por chave, ORDEM FIXA (NFR18):
#   session: <sid>|unknown
#   mode: on|off|unknown
#   phases: <fases presentes em ordem canônica, separadas por espaço>   (pode ser vazio)
#   last-phase: reflect|conceptualize|experiment|none
#   next: reflect|conceptualize|experiment|complete|none
#     - none          → nenhuma fase ainda (narrativa: começar por /kolb:reflect)
#     - reflect       → registrou fase(s) FORA DE ORDEM sem Observação Reflexiva ⇒ RO primeiro
#                       (Kolb não fecha o ciclo sem RO; a conceituação sem reflexão não conta)
#     - conceptualize → refletiu sem conceituar ⇒ FECHAR o ciclo
#     - experiment    → ciclo fechado (RO+AC feitos), consolidação OPCIONAL
#     - complete      → RO→AC→AE completos (reflect E conceptualize E experiment)
set -eu
# Word-splitting determinístico (NFR7): o `for p in $phase_seq` abaixo depende do
# IFS default (space/tab/newline) p/ separar a saída newline-por-fase do sed. `unset
# IFS` garante o default mesmo se o ambiente exportar um IFS não-default (que
# colapsaria todas as fases num token só ⇒ sub-relato silencioso). Idioma de checkpoint.sh.
unset IFS 2>/dev/null || IFS='
	 '

# Sourcing de _common.sh: prioriza CLAUDE_PLUGIN_ROOT; cai para o diretório deste
# script quando a env var não está setada (ex.: execução direta em teste).
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
# shellcheck source=/dev/null
. "$_kolb_common"

# --- Argumentos: [--sid <sid>] (também aceita --sid=<sid>), padrão session-status.sh.
filter_sid=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sid)     shift; filter_sid="${1:-}" ;;
    --sid=*)   filter_sid="${1#--sid=}" ;;
    *)         : ;;   # ignora tokens desconhecidos (deriver tolerante)
  esac
  [ $# -gt 0 ] && shift
done

# Sid: --sid tem precedência; senão a env da skill. Vazio/inválido ⇒ 'unknown'.
sid="$filter_sid"
[ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
case "$sid" in
  ""|*[!0-9A-Za-z-]*)
    kolb_log_error "session-phase: session_id ausente/ inválido; estado indeterminado."
    printf 'session: unknown\n'
    printf 'mode: unknown\n'
    printf 'phases: \n'
    printf 'last-phase: none\n'
    printf 'next: none\n'
    exit 0
    ;;
esac

# Base de estado: fonte única CLAUDE_PROJECT_DIR (kolb_project_dir). Ausente ⇒
# não dá para ler o flag nem o índice ⇒ modo/estado 'unknown' (sid é válido).
base="$(kolb_project_dir)"
if [ -z "$base" ]; then
  kolb_log_error "session-phase: CLAUDE_PROJECT_DIR ausente; não foi possível resolver o projeto."
  printf 'session: %s\n' "$sid"
  printf 'mode: unknown\n'
  printf 'phases: \n'
  printf 'last-phase: none\n'
  printf 'next: none\n'
  exit 0
fi

# --- Modo ON/OFF nesta sessão: mesma verdade do kolb_gate (_common.sh:80). Um
# único stat, sem jq.
if [ -f "$base/.kolb/runtime/mode-$sid" ]; then
  mode="on"
else
  mode="off"
fi

# --- Fases da sessão a partir do índice event-sourced. Sem jq: filtra as linhas
# desta sessão (sid sanitizado ⇒ seguro em grep -F) e extrai o nome da fase dos
# eventos `phase_<fase>` (formato fixo de log-phase.sh:77). Ordem = ordem do arquivo
# (append-only ⇒ ordem cronológica). Arquivo ausente/sem match ⇒ sequência vazia.
sessions="$base/.kolb/sessions.jsonl"
phase_seq=""
if [ -f "$sessions" ]; then
  phase_seq=$(grep -F "\"sid\":\"$sid\"" "$sessions" 2>/dev/null \
    | sed -n 's/.*"event":"phase_\([a-z][a-z]*\)".*/\1/p') || phase_seq=""
fi

# Presença por fase + última fase registrada (percorre em ordem do arquivo).
have_reflect=0
have_conceptualize=0
have_experiment=0
last_phase="none"
for p in $phase_seq; do
  case "$p" in
    reflect)       have_reflect=1 ;;
    conceptualize) have_conceptualize=1 ;;
    experiment)    have_experiment=1 ;;
    *)             continue ;;   # fase fora do vocabulário canônico ⇒ ignora
  esac
  last_phase="$p"
done

# Lista de fases presentes em ORDEM CANÔNICA (não na ordem do arquivo) — leitura estável.
present=""
[ "$have_reflect" = 1 ]       && present="${present}reflect "
[ "$have_conceptualize" = 1 ] && present="${present}conceptualize "
[ "$have_experiment" = 1 ]    && present="${present}experiment "
present="${present% }"

# --- Regra determinística do `next` (ordem canônica RO→AC→AE). O ciclo só está
# COMPLETO com as três fases; a Observação Reflexiva (RO) é a fundação — sem ela a
# conceituação não fecha o ciclo. Por isso qualquer fase registrada FORA DE ORDEM
# (conceptualize/experiment sem reflect) aponta de volta para reflect.
if [ -z "$present" ]; then
  next="none"             # nenhuma fase ainda
elif [ "$have_reflect" = 0 ]; then
  next="reflect"          # registrou fase(s) sem RO ⇒ refletir primeiro (o ciclo não fecha sem RO)
elif [ "$have_conceptualize" = 0 ]; then
  next="conceptualize"    # refletiu mas não conceituou ⇒ fechar o ciclo
elif [ "$have_experiment" = 0 ]; then
  next="experiment"       # ciclo fechado (RO+AC); consolidação opcional (a skill narra como opcional)
else
  next="complete"         # RO→AC→AE completos
fi

# --- Saída (ordem fixa).
printf 'session: %s\n' "$sid"
printf 'mode: %s\n' "$mode"
printf 'phases: %s\n' "$present"
printf 'last-phase: %s\n' "$last_phase"
printf 'next: %s\n' "$next"
exit 0
