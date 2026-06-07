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
# A justificativa (2º arg) só é usada no `off`, onde é obrigatória (FR2); `on` a ignora.
action="${1:-}"
justification="${2:-}"
case "$action" in
  on|off) ;;
  *)
    printf '%s\n' 'uso: toggle-mode.sh on | off "<justificativa de uma linha>"'
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
  # Eventos append-only em .kolb/sessions.jsonl (durável). Sem jq — sid é UUID.
  # Se um append falhar, o flag (fonte de verdade do gating) já está posto e o modo
  # funciona; registramos a lacuna de auditoria em vez de abortar sob set -e.
  #
  # session_start ANTES de mode_on: este é o único ponto que sabe que o modo está
  # sendo *entrado* numa sessão genuína (o hook SessionStart é gated e, numa sessão
  # nova, o flag ainda não existe). Sem dedup: numa sessão on→off→on o 2º on emite
  # outro session_start, e o fold (session-status.sh) toma o ts mínimo por sid —
  # tolerar multiplicidade é mais barato que pagar um grep no hot-path (NFR3).
  printf '{"ts":"%s","sid":"%s","event":"session_start","mode":"learn"}\n' "$(kolb_ts)" "$sid" >> "$sessions" 2>/dev/null || \
    kolb_log_error "toggle-mode: flag criado, mas falha ao anexar evento session_start em $sessions."
  printf '{"ts":"%s","sid":"%s","event":"mode_on","mode":"learn"}\n' "$(kolb_ts)" "$sid" >> "$sessions" 2>/dev/null || \
    kolb_log_error "toggle-mode: flag criado, mas falha ao anexar evento mode_on em $sessions."
  printf '%s\n' "Kolb: modo aprendizado ATIVADO nesta sessão."
  exit 0
fi

# action = off — desativação auditada com justificativa obrigatória (FR2).
#
# Idempotência (AC#5, NFR6): flag ausente ⇒ no-op silencioso, SEM exigir
# justificativa — não há modo a encerrar.
if [ ! -f "$flag" ]; then
  printf '%s\n' "Kolb: modo aprendizado já estava inativo nesta sessão."
  exit 0
fi

# Flag presente: exige justificativa de uma linha. Normaliza CR/LF em espaço para
# garantir "uma linha" no exit-log (NFR18) e detecta justificativa só-branca. Também
# neutraliza os delimitadores do formato auditável — `|` (separador de colunas) vira
# `/` e `"` (aspas do campo) vira `'` — para que texto livre do usuário não quebre a
# linha `<ts> | session <sid> | off | "<just>"` nem forje colunas/aspas.
justification=$(printf '%s' "$justification" | tr '\r\n|"' "  /'")
_just_trimmed=$(printf '%s' "$justification" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
if [ -z "$_just_trimmed" ]; then
  # Tom socrático (NFR23): ≤3 linhas, termina pedindo ação. O modo permanece ATIVO.
  printf '%s\n' "Kolb: a desativação exige um motivo de uma linha. Por que sair do modo agora?"
  printf '%s\n' 'Use: /kolb:learn-mode off "<seu motivo>" — o modo continua ATIVO até registrá-lo.'
  exit 0
fi

# Desativação efetiva: remove o flag PRIMEIRO. Invariante de auditoria (resolve a
# verificação aberta #1 da story): uma linha no exit-log existe se e somente se a
# desativação ocorreu — evita "log fantasma" caso o rm falhe. A janela "off sem
# motivo gravado" é desprezível (script sequencial, single-user).
if ! rm -f "$flag" 2>/dev/null; then
  kolb_log_error "toggle-mode: falha ao remover o flag $flag."
  printf '%s\n' "Kolb: não consegui desativar o modo (falha ao remover o estado). Nada foi registrado."
  exit 0
fi

# A partir daqui o modo está OFF. A auditoria abaixo é best-effort (NFR9): qualquer
# falha de FS é registrada em hook-errors.log e o script segue/sai com exit 0.
exitlog="$base/.kolb/exit-log.md"

# Cria o exit-log do template pré-preenchido se ausente (FR40). O template é
# read-only no plugin; copiamos para .kolb/ (durável). Fallback: cabeçalho mínimo.
if [ ! -f "$exitlog" ]; then
  _kolb_tpl="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/templates/exit-log.md"
  [ -f "$_kolb_tpl" ] || _kolb_tpl="$_kolb_self_dir/../templates/exit-log.md"
  if [ -f "$_kolb_tpl" ]; then
    cp "$_kolb_tpl" "$exitlog" 2>/dev/null || \
      kolb_log_error "toggle-mode: falha ao copiar template exit-log para $exitlog."
  fi
  # Se ainda não existe (template ausente ou cp falhou), grava um cabeçalho mínimo.
  if [ ! -f "$exitlog" ]; then
    {
      printf '%s\n\n' "# Kolb — Exit Log"
      printf '%s\n' "Registro auditável das desativações do modo aprendizado (uma linha por saída)."
      printf '%s\n\n' 'Formato: `<timestamp ISO 8601> | session <session_id> | off | "<justificativa de uma linha>"`'
    } > "$exitlog" 2>/dev/null || \
      kolb_log_error "toggle-mode: falha ao criar exit-log mínimo em $exitlog."
  fi
fi

# Anexa a linha de auditoria (append puro, legível a olho nu — NFR18/NFR19).
# Rastreia o sucesso do append para não superdeclarar o registro na mensagem final.
if printf '%s | session %s | off | "%s"\n' "$(kolb_ts)" "$sid" "$justification" >> "$exitlog" 2>/dev/null; then
  _exitlog_ok=1
else
  _exitlog_ok=0
  kolb_log_error "toggle-mode: modo desativado, mas falha ao anexar linha em $exitlog."
fi

# Evento mode_off em sessions.jsonl (event-sourced, append-only). A justificativa
# NÃO entra aqui: o schema de evento é fixo {ts,sid,event,mode} e o motivo legível
# vive no exit-log — mantém o JSONL montável por printf, sem jq nem escape.
printf '{"ts":"%s","sid":"%s","event":"mode_off","mode":"learn"}\n' "$(kolb_ts)" "$sid" >> "$sessions" 2>/dev/null || \
  kolb_log_error "toggle-mode: modo desativado, mas falha ao anexar evento mode_off em $sessions."

# Mensagem final honesta: só afirma "registrado" se o append ao exit-log teve êxito.
if [ "$_exitlog_ok" = 1 ]; then
  printf '%s\n' "Kolb: modo aprendizado DESATIVADO nesta sessão. Motivo registrado no exit-log."
else
  printf '%s\n' "Kolb: modo aprendizado DESATIVADO nesta sessão (falha ao registrar o motivo — ver .kolb/runtime/hook-errors.log)."
fi
exit 0
