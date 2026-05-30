#!/usr/bin/env sh
# toggle-mode.sh on|off — Liga/desliga o modo aprendizado do Kolb na sessão atual.
#
# Determinístico e idempotente (NFR6): `on` numa sessão já ativa e `off` numa
# inativa são no-ops sem efeito colateral (nenhum evento duplicado). Falha
# graciosa (NFR9). Zero dependências além de POSIX.
#
# Estado por sessão (isolamento, FR3): o flag é nomeado pelo session_id, então
# uma 2ª janela (outro id) nunca vê o flag da 1ª.
set -eu

# Sourcing de _common.sh: prioriza CLAUDE_PLUGIN_ROOT; cai para o diretório deste
# script quando a env var não está setada (ex.: execução direta em teste).
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
# shellcheck source=/dev/null
. "$_kolb_common"

# Valida o argumento: exatamente on|off; qualquer outro ⇒ uso legível + exit 0.
action="${1:-}"
case "$action" in
  on|off) ;;
  *)
    printf '%s\n' "uso: toggle-mode.sh on|off"
    exit 0
    ;;
esac

# Resolve a sessão. Skill: CLAUDE_CODE_SESSION_ID (UUID). Vazio ⇒ falha graciosa.
sid="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$sid" ]; then
  kolb_log_error "toggle-mode: CLAUDE_CODE_SESSION_ID vazio; não foi possível resolver a sessão."
  printf '%s\n' "Kolb: não consegui identificar a sessão atual (CLAUDE_CODE_SESSION_ID ausente). Nada foi alterado."
  exit 0
fi

# Valida o formato do sid: apenas [0-9A-Za-z-] (UUID v4). Qualquer outro caractere
# (barra, aspas, espaço, newline) é recusado para nunca compor um path ou uma
# linha JSON malformados. Defesa: a plataforma entrega um UUID, mas não confiamos.
case "$sid" in
  ""|*[!0-9A-Za-z-]*)
    kolb_log_error "toggle-mode: CLAUDE_CODE_SESSION_ID com caractere inesperado; recusado."
    printf '%s\n' "Kolb: identificador de sessão inválido. Nada foi alterado."
    exit 0
    ;;
esac

# Base de estado: fonte única CLAUDE_PROJECT_DIR (kolb_project_dir). Ausente ⇒
# falha graciosa — não inventa diretório (skill e hook precisam concordar).
base="$(kolb_project_dir)"
if [ -z "$base" ]; then
  kolb_log_error "toggle-mode: CLAUDE_PROJECT_DIR ausente; não foi possível resolver o diretório do projeto."
  printf '%s\n' "Kolb: não consegui localizar o diretório do projeto (CLAUDE_PROJECT_DIR ausente). Nada foi alterado."
  exit 0
fi
rt="$base/.kolb/runtime"
flag="$rt/mode-$sid"
sessions="$base/.kolb/sessions.jsonl"

# Estrutura idempotente: cria runtime/ e o .gitignore (=*) só se ausente.
# Sob set -e, uma falha de FS (read-only, sem permissão, .kolb é arquivo) abortaria
# cru; aqui interceptamos com log + exit 0 (NFR9 — nunca derruba o hospedeiro).
if ! mkdir -p "$rt" 2>/dev/null; then
  kolb_log_error "toggle-mode: não foi possível criar $rt (FS não-gravável?)."
  printf '%s\n' "Kolb: não consegui preparar o diretório de estado. Nada foi alterado."
  exit 0
fi
# .gitignore é best-effort: se a escrita falhar, loga e segue (não é crítico).
if [ ! -f "$rt/.gitignore" ]; then
  printf '%s\n' '*' > "$rt/.gitignore" 2>/dev/null || \
    kolb_log_error "toggle-mode: não foi possível escrever $rt/.gitignore (seguindo mesmo assim)."
fi

if [ "$action" = "on" ]; then
  if [ -f "$flag" ]; then
    printf '%s\n' "Kolb: modo aprendizado já está ativo nesta sessão."
    exit 0
  fi
  if ! touch "$flag" 2>/dev/null; then
    kolb_log_error "toggle-mode: não foi possível criar o flag $flag."
    printf '%s\n' "Kolb: não consegui ativar o modo (falha ao gravar o estado). Nada foi alterado."
    exit 0
  fi
  # Evento append-only em .kolb/sessions.jsonl (durável). Sem jq — sid é UUID.
  # Se o append falhar, o flag (fonte de verdade do gating) já está posto e o modo
  # funciona; registramos a lacuna de auditoria em vez de abortar sob set -e.
  printf '{"ts":"%s","sid":"%s","event":"mode_on","mode":"learn"}\n' "$(kolb_ts)" "$sid" >> "$sessions" 2>/dev/null || \
    kolb_log_error "toggle-mode: flag criado, mas falha ao anexar evento mode_on em $sessions."
  printf '%s\n' "Kolb: modo aprendizado ATIVADO nesta sessão."
  exit 0
fi

# action = off — remove o flag se existir; senão, no-op silencioso (sem erro).
# NÃO escreve exit-log nem emite evento mode_off aqui: isso é da história 1.3.
if [ -f "$flag" ]; then
  if rm -f "$flag" 2>/dev/null; then
    printf '%s\n' "Kolb: modo aprendizado DESATIVADO nesta sessão."
  else
    kolb_log_error "toggle-mode: falha ao remover o flag $flag."
    printf '%s\n' "Kolb: não consegui desativar o modo (falha ao remover o estado)."
  fi
else
  printf '%s\n' "Kolb: modo aprendizado já estava inativo nesta sessão."
fi
exit 0
