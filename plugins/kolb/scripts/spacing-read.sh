#!/usr/bin/env sh
# PostToolUse(Read): nota AC associada — FR26,27
# spacing-read.sh — Hook PostToolUse/Read do Kolb (SPACING CONTEXTUAL). Em modo
# aprendizado, ao LER um arquivo do projeto, se existir uma nota AC cujo
# `linked_files` casa o arquivo lido, injeta um additionalContext que ORDENA à IA
# pedir a verbalização do conceito ANTES de revelar o conteúdo da nota (a IA
# primeiro elicita o que o dev lembra; só depois confronta com a nota).
#
# É o 1º hook PostToolUse do plugin. Par contextual do spacing-start.sh (4.3):
# mesma estrutura canônica de hook aditivo, com seleção por `linked_files` em vez
# de janela temporal, e — CRUX (D1) — ESTRITAMENTE READ-ONLY: NÃO avança
# last_review, NÃO escreve em nenhuma nota nem em $CLAUDE_PLUGIN_ROOT. PostToolUse/
# Read é alta-frequência; avançar a janela aqui suprimiria o retrieval inicial da
# 4.3 e geraria churn de git. FR26 (contextual) é ORTOGONAL a FR28 (janela).
#
# Fail-safe = PASSTHROUGH/fail-open (igual a spacing-start.sh/prompt-steer.sh): hook
# ADITIVO, então qualquer erro interno ⇒ exit 0 SEM injetar additionalContext + log
# best-effort (NFR9). Nunca exit≠0, nunca aborta o hospedeiro.
#
# jq: necessário no caminho ATIVO tanto na ENTRADA (tool_input.file_path é um path
# arbitrário, lido por jq -r — não pelo sed restrito do session_id) quanto no JSON
# de SAÍDA (corpo da nota é texto arbitrário ⇒ escape). O off-path (gate) é 100%
# jq-free (NFR5). O frontmatter das notas é YAML e é lido por awk (idioma de
# pdi-status.sh/spacing-start.sh) — NUNCA jq.
#
# Matching abs×rel (D3): Read entrega file_path ABSOLUTO; linked_files são tipicamente
# project-relative. Normaliza o path lido p/ relativo (remove o prefixo
# "$CLAUDE_PROJECT_DIR/") e casa quando uma entrada igualar o rel OU o abs OU o abs
# terminar em "/<entrada>" (sufixo forgiving). Sem realpath/readlink -f (GNU-only/NFR12).
set -eu

# Sourcing endurecido de _common.sh (idêntico a spacing-start.sh/prompt-steer.sh):
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
# barato, sem jq (FR5/NFR5). Nada abaixo do gate executa fora do modo.
input=$(cat)
kolb_gate "$input"

# Modo ATIVO a partir daqui. jq é necessário também p/ LER a entrada (file_path é
# path arbitrário) ⇒ require_jq logo APÓS o gate (off-path permanece jq-free).
kolb_require_jq || exit 0

# Path lido (absoluto, contrato do Read). Ausente/null ⇒ silencioso (FR29/AC#6).
read_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -n "$read_path" ] || exit 0

# Base de estado: fonte única CLAUDE_PROJECT_DIR.
base="$(kolb_project_dir)"
[ -n "$base" ] || { kolb_log_error "spacing-read: CLAUDE_PROJECT_DIR ausente; nada injetado."; exit 0; }
notes_dir="$base/.kolb/notes"

# Normaliza o path lido p/ project-relative removendo o prefixo "$base/" (D3). Se
# não começa por "$base/", rel == read_path (payload já-relativo / fora da base).
rel=${read_path#"$base"/}

# notes/ ausente ⇒ silencioso (FR29).
[ -d "$notes_dir" ] || exit 0

# notes/ sem *.md ⇒ silencioso (FR29). `set --` é seguro: o hook não usa $@.
set -- "$notes_dir"/*.md
[ -e "$1" ] || exit 0

# --- Seleção por scan do frontmatter (sem jq). UM único awk sobre todas as notas
# (NFR2: 1 fork, não 1/nota): extrai linked_files/topic (entre os dois primeiros
# `---`), parseia a lista inline por aspas (valores em índice par) e casa cada
# entrada contra o abs (read_path) e o rel — igualdade ou sufixo "/<entrada>" (D3).
# Emite "arquivo<TAB>topic" só p/ notas que casam.
matched=$(awk -v abs="$read_path" -v rel="$rel" '
  function endswith(s, suf,   ls, lsuf) {
    lsuf = length(suf); ls = length(s);
    if (lsuf == 0 || lsuf > ls) return 0;
    return substr(s, ls - lsuf + 1) == suf;
  }
  FNR==1 { fm=0; tp=""; hit=0; done_file=0 }
  done_file { next }
  /^---[[:space:]]*$/ {
    fm++
    if (fm==2) { if (hit) print FILENAME "\t" tp; done_file=1 }
    next
  }
  fm==1 && /^linked_files:/ {
    n = split($0, arr, "\"")
    for (i=2; i<=n; i+=2) {
      e = arr[i]
      if (e == "") continue
      if (e == abs || e == rel || endswith(abs, "/" e)) hit=1
    }
    next
  }
  fm==1 && /^topic:/ {
    v=$0; sub(/^topic:[[:space:]]*/,"",v)
    sub(/^"/,"",v); sub(/"[[:space:]]*$/,"",v); sub(/[[:space:]]+$/,"",v)
    tp=v; next
  }
' "$@" 2>/dev/null) || matched=""

# Ordena determinístico por nome de arquivo (NFR7), LC_ALL=C independente de locale.
selected=$(printf '%s\n' "$matched" | grep -v '^[[:space:]]*$' | LC_ALL=C sort)

# Nenhuma nota associada ⇒ silencioso (FR29/AC#3).
[ -n "$selected" ] || exit 0

tab=$(printf '\t')
nl='
'

# Compõe o corpo das notas e a lista de tópicos. O loop roda no shell atual
# (heredoc, não pipe) p/ preservar as variáveis. set -e: usar if explícito, nunca
# AND-list que aborte no ramo falso.
topics=""
first_topic=""
bodies=""
while IFS="$tab" read -r file topic; do
  [ -n "$file" ] || continue
  # topic vazio ⇒ fallback ao slug do arquivo (evita prompt degenerado).
  [ -n "$topic" ] || topic=$(basename "$file" .md)
  if [ -z "$first_topic" ]; then first_topic="$topic"; fi
  if [ -z "$topics" ]; then topics="$topic"; else topics="$topics e $topic"; fi
  # Corpo = tudo após o segundo `---` (awk sempre sai 0).
  body=$(awk 'seen; /^---[[:space:]]*$/{c++; if(c==2) seen=1}' "$file" 2>/dev/null) || body=""
  bodies="${bodies}${nl}--- nota: ${topic} ---${nl}${body}${nl}"
done <<EOF
$selected
EOF

# Instrução socrática (NFR23: ≤3 linhas, termina em pergunta, não revela a solução),
# direcionada à IA: ordena pedir a verbalização ANTES de revelar; seguida do corpo
# das notas como DADO p/ a IA usar DEPOIS do recall. Gancho contextual: "você está
# olhando <arquivo>".
ctx="Spacing contextual (ciclo Kolb). Você está olhando ${rel} — há nota(s) AC associada(s) a este arquivo: ${topics}.
Antes de revelar qualquer conteúdo da nota, peça ao dev que tente lembrar e verbalize o que ainda sabe; só então confronte a verbalização com o conteúdo abaixo, apontando lacunas por perguntas — não entregue a resposta pronta.
O que você ainda lembra sobre ${first_topic}?
${bodies}"

# JSON de saída montado COM jq (conteúdo de nota é texto arbitrário ⇒ escape seguro).
# Falha de montagem ⇒ passthrough.
json=$(jq -n --arg ctx "$ctx" \
  '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$ctx}}') \
  || { kolb_log_error "spacing-read: falha ao montar JSON com jq; passthrough."; exit 0; }

# Emite. Falha de emissão (EPIPE/stdout fechado) ⇒ log + passthrough. NENHUMA
# escrita após emitir (D1: hook estritamente read-only).
printf '%s\n' "$json" 2>/dev/null \
  || kolb_log_error "spacing-read: falha ao emitir additionalContext (stdout fechado?); passthrough."
exit 0
