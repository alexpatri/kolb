#!/usr/bin/env sh
# write-note.sh "<topic>" [--pdi-goal <goal>] [--linked <paths CSV>] — Grava UMA
# nota AC atômica (fase AC do ciclo Kolb) em .kolb/notes/<slug>.md. O corpo do
# conceito chega por STDIN (heredoc da skill /kolb:conceptualize).
#
# Por que um script (e não a tool Write): em modo aprendizado o block-write.sh (2.2)
# NEGA Write/Edit/NotebookEdit. A nota é estado durável do PRÓPRIO Kolb (.kolb/notes/)
# — gravá-la por redirection de shell aqui é o canal previsto, igual ao toggle-mode.sh
# escrevendo exit-log.md/sessions.jsonl. NÃO confundir com a "brecha via Bash" de 2.2
# (que é a IA escrever CÓDIGO DE PROJETO contornando o bloqueio).
#
# slug determinístico via kolb_slugify (mesmo tópico ⇒ mesmo slug). NÃO sobrescreve
# uma nota existente (preserva estado do usuário — decisão de escopo B). Sem jq
# (frontmatter montável por printf). Sem kolb_gate (skills são explícitas — o guard
# de modo é dos HOOKS). Falha graciosa (NFR9): qualquer problema ⇒ log + exit 0.
set -eu

# Sourcing de _common.sh: prioriza CLAUDE_PLUGIN_ROOT; cai para o diretório deste
# script quando a env var não está setada (ex.: execução direta em teste).
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
# shellcheck source=/dev/null
. "$_kolb_common"

# Neutraliza caracteres que quebrariam o YAML do frontmatter sem lib de YAML:
# aspas duplas → simples (delimitam os escalares), barra invertida → barra (num
# escalar YAML entre aspas duplas, `\` é introdutor de escape: um valor terminado
# em `\` — ex. `C:\` ou um path Windows em --linked — escaparia a aspa de
# fechamento e quebraria o frontmatter) e CR/LF/TAB → espaço (mantém "uma linha"
# por campo). Mesmo espírito do toggle-mode.sh:118 para o exit-log.
_kolb_yaml_safe() {
  printf '%s' "${1:-}" | tr '\r\n\t"\\' "   '/"
}

# --- Parse de argumentos: 1º posicional = topic; flags --pdi-goal / --linked ---
topic=""
pdi_goal=""
linked_csv=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pdi-goal) shift; pdi_goal="${1:-}" ;;
    --pdi-goal=*) pdi_goal="${1#--pdi-goal=}" ;;
    --linked) shift; linked_csv="${1:-}" ;;
    --linked=*) linked_csv="${1#--linked=}" ;;
    # Sob set -e, um `[ -z "$topic" ] && topic="$1"` abortaria quando topic já
    # estivesse setado (AND-list retorna falso). Usar if explícito.
    *) if [ -z "$topic" ]; then topic="$1"; fi ;;
  esac
  # Shift guardado (set -eu): o ramo de flag pode ter consumido o último token.
  [ $# -gt 0 ] && shift
done

# Título obrigatório.
if [ -z "$topic" ]; then
  kolb_log_error "write-note: título (topic) ausente."
  printf '%s\n' "Kolb: informe um título: /kolb:conceptualize \"<título do conceito>\". Nota não criada."
  exit 0
fi

# Slug determinístico. Vazio (título sem [a-z0-9] ASCII) ⇒ falha graciosa.
slug=$(kolb_slugify "$topic")
if [ -z "$slug" ]; then
  kolb_log_error "write-note: slug vazio para topic='$topic' (sem caractere ASCII utilizável)."
  printf '%s\n' "Kolb: esse título não gera um nome de arquivo válido. Use um título com letras ou números."
  exit 0
fi

# Base de estado: fonte única CLAUDE_PROJECT_DIR. Ausente ⇒ falha graciosa
# (skill e hook precisam concordar na base — sem fallback git/pwd).
base="$(kolb_project_dir)"
if [ -z "$base" ]; then
  kolb_log_error "write-note: CLAUDE_PROJECT_DIR ausente; não foi possível resolver o diretório do projeto."
  printf '%s\n' "Kolb: não consegui localizar o diretório do projeto. Nota não criada."
  exit 0
fi
notes_dir="$base/.kolb/notes"
note="$notes_dir/$slug.md"

# Garante .kolb/notes/ (durável). Sob set -e, falha de FS (read-only, .kolb é
# arquivo regular) abortaria cru; interceptamos com log + exit 0 (NFR9).
if ! mkdir -p "$notes_dir" 2>/dev/null; then
  kolb_log_error "write-note: não foi possível criar $notes_dir (FS não-gravável?)."
  printf '%s\n' "Kolb: não consegui preparar o diretório de notas. Nota não criada."
  exit 0
fi

# NÃO sobrescrever (decisão de escopo B): nota AC é estado durável/versionável do
# usuário. Colisão de slug ⇒ reporta e sai, sem clobber.
if [ -e "$note" ]; then
  printf '%s\n' "Kolb: já existe uma nota para esse tópico em $note — nada foi sobrescrito. Use outro título ou edite a nota."
  exit 0
fi

# Corpo do conceito atômico via stdin. Guardado contra set -e.
body=$(cat) || body=""

# Campos do frontmatter, neutralizados para YAML.
topic_safe=$(_kolb_yaml_safe "$topic")
pdi_safe=$(_kolb_yaml_safe "$pdi_goal")

# linked_files: lista YAML a partir do CSV (vírgula). Vazio ⇒ [].
linked_yaml="[]"
if [ -n "$linked_csv" ]; then
  _items=""
  _oldifs=$IFS
  IFS=','
  # set -f: o split de $linked_csv por vírgula é uma expansão NÃO-citada e, sem
  # desabilitar o globbing, um item com metachar de glob (*/?/[) sofreria pathname
  # expansion contra o FS. Restaurado logo após o laço.
  set -f
  for _f in $linked_csv; do
    _f=$(printf '%s' "$_f" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$_f" ] || continue
    _f=$(_kolb_yaml_safe "$_f")
    if [ -z "$_items" ]; then
      _items="\"$_f\""
    else
      _items="$_items, \"$_f\""
    fi
  done
  set +f
  IFS=$_oldifs
  [ -z "$_items" ] || linked_yaml="[$_items]"
fi

# created == last_review na criação (NFR19, ISO 8601 c/ tz via kolb_ts). O spacing
# do Epic 4 atualiza last_review depois (FR28).
ts="$(kolb_ts)"

# Grava a nota (frontmatter por printf + corpo). Falha de escrita ⇒ log + exit 0,
# limpando arquivo parcial. Mensagem final HONESTA (paridade toggle-mode.sh:176-181).
if {
  printf '%s\n' '---'
  printf 'topic: "%s"\n' "$topic_safe"
  printf 'linked_files: %s\n' "$linked_yaml"
  printf 'created: "%s"\n' "$ts"
  printf 'last_review: "%s"\n' "$ts"
  printf 'pdi_goal: "%s"\n' "$pdi_safe"
  printf '%s\n\n' '---'
  printf '%s\n' "$body"
} > "$note" 2>/dev/null; then
  printf '%s\n' "Kolb: nota AC criada em $note (tópico: \"$topic_safe\")."
else
  kolb_log_error "write-note: falha ao gravar a nota em $note."
  rm -f "$note" 2>/dev/null || true
  printf '%s\n' "Kolb: não consegui gravar a nota (falha de escrita). Nada foi criado."
fi
exit 0
