#!/usr/bin/env sh
# SessionStart: 1-2 notas p/ retrieval — FR25,28
# spacing-start.sh — Hook SessionStart do Kolb. Em modo aprendizado, apresenta
# 1-2 notas AC "antigas" para RETRIEVAL ATIVO: injeta um additionalContext que
# ORDENA à IA pedir a verbalização do conceito ANTES de revelar o conteúdo da
# nota (a IA primeiro elicita o que o dev lembra; só depois confronta com a nota).
#
# É o 1º hook SessionStart do plugin. Gate por flag per-session: numa sessão
# totalmente nova o flag ainda não existe (toggle-mode.sh:91-93) ⇒ passthrough;
# o retrieval dispara em resume/continuação cujo flag já está presente. NÃO há
# persistência de modo entre sessões (FR3).
#
# Fail-safe = PASSTHROUGH/fail-open (igual a prompt-steer.sh): hook ADITIVO, então
# qualquer erro interno ⇒ exit 0 SEM injetar additionalContext (a IA só não recebe
# o reforço naquele start) + log best-effort (NFR9). Nunca exit≠0, nunca aborta o
# hospedeiro.
#
# jq: SÓ no JSON de saída (o conteúdo das notas é texto arbitrário e DEVE ser
# escapado). O off-path (gate) é 100% jq-free (NFR5); o frontmatter das notas é
# YAML e é lido por awk (mesmo idioma de pdi-status.sh) — NUNCA jq aqui.
#
# Janela de spacing (FR28, dia-calendário): uma nota é elegível se a DATA de seu
# last_review (YYYY-MM-DD) for estritamente menor que hoje — comparação lexicográfica
# de ISO 8601, POSIX puro (sem `date -d`, GNU-only/NFR12). Override de teste:
# KOLB_SPACING_DENY_TODAY=0 desliga o filtro de hoje (força elegibilidade).
#
# Avanço da janela (FR28, D1): as notas EXIBIDAS têm seu last_review atualizado
# para "agora", de modo que não reapareçam no mesmo dia. Escrita só sob
# .kolb/notes/ (AC#8) — NUNCA em $CLAUDE_PLUGIN_ROOT.
set -eu

# Sourcing endurecido de _common.sh (idêntico a prompt-steer.sh/block-write.sh):
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

# Modo ATIVO a partir daqui. Base de estado: fonte única CLAUDE_PROJECT_DIR.
base="$(kolb_project_dir)"
[ -n "$base" ] || { kolb_log_error "spacing-start: CLAUDE_PROJECT_DIR ausente; nada injetado."; exit 0; }
notes_dir="$base/.kolb/notes"

# notes/ ausente ⇒ silencioso (FR29).
[ -d "$notes_dir" ] || exit 0

# notes/ sem *.md ⇒ silencioso (FR29). `set --` é seguro: o hook não usa $@.
set -- "$notes_dir"/*.md
[ -e "$1" ] || exit 0

# --- Seleção determinística por scan do frontmatter (sem jq). Para cada nota,
# extrai last_review/topic (entre os dois primeiros `---`) e decide elegibilidade
# pela janela. UM único awk sobre todos os arquivos (NFR2: 1 fork, não 1/nota).
# Emite "last_review<TAB>arquivo<TAB>topic" só p/ elegíveis com last_review presente.
today=$(date +%Y-%m-%d)
deny_today="${KOLB_SPACING_DENY_TODAY:-1}"   # !=0 ⇒ aplica filtro de hoje (padrão)

candidates=$(awk -v today="$today" -v deny="$deny_today" '
  FNR==1 { fm=0; lr=""; tp=""; done_file=0 }
  done_file { next }
  /^---[[:space:]]*$/ {
    fm++
    if (fm==2) {
      datepart = substr(lr, 1, 10)
      eligible = 0
      if (lr != "") {
        if (deny == "0") eligible = 1
        else if (datepart ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ && datepart < today) eligible = 1
      }
      if (eligible) print lr "\t" FILENAME "\t" tp
      done_file = 1
    }
    next
  }
  fm==1 && /^last_review:/ {
    v=$0; sub(/^last_review:[[:space:]]*/,"",v);
    sub(/^"/,"",v); sub(/"[[:space:]]*$/,"",v); sub(/[[:space:]]+$/,"",v);
    lr=v; next
  }
  fm==1 && /^topic:/ {
    v=$0; sub(/^topic:[[:space:]]*/,"",v);
    sub(/^"/,"",v); sub(/"[[:space:]]*$/,"",v); sub(/[[:space:]]+$/,"",v);
    tp=v; next
  }
' "$@" 2>/dev/null) || candidates=""

# Ordena oldest-first (last_review ascendente; desempate por nome de arquivo, NFR7)
# e toma no máximo 2. LC_ALL=C p/ ordenação determinística independente de locale.
selected=$(printf '%s\n' "$candidates" | grep -v '^[[:space:]]*$' | LC_ALL=C sort | head -n 2)

# Nenhuma elegível ⇒ silencioso (FR29).
[ -n "$selected" ] || exit 0

# --- jq SÓ a partir daqui (caminho ativo com notas a exibir). Ausente ⇒ passthrough.
kolb_require_jq || exit 0

tab=$(printf '\t')
nl='
'

# Compõe o corpo das notas e a lista de tópicos. O loop roda no shell atual
# (heredoc, não pipe) p/ preservar as variáveis. set -e: usar if explícito, nunca
# AND-list que aborte no ramo falso.
topics=""
first_topic=""
bodies=""
files_selected=""
while IFS="$tab" read -r lr file topic; do
  [ -n "$file" ] || continue
  files_selected="${files_selected}${file}${nl}"
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
# das notas como DADO p/ a IA usar DEPOIS do recall (Task 3).
ctx="Retrieval ativo (spacing — ciclo Kolb). Há nota(s) AC antiga(s) para revisar: ${topics}.
Antes de revelar qualquer conteúdo da nota, peça ao dev que tente lembrar e verbalize o que ainda sabe; só então confronte a verbalização com o conteúdo abaixo, apontando lacunas por perguntas — não entregue a resposta pronta.
O que você ainda lembra sobre ${first_topic}?
${bodies}"

# JSON de saída montado COM jq (conteúdo de nota é texto arbitrário ⇒ escape seguro).
# Falha de montagem ⇒ passthrough (sem avançar a janela — a nota não foi exibida).
json=$(jq -n --arg ctx "$ctx" \
  '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}') \
  || { kolb_log_error "spacing-start: falha ao montar JSON com jq; passthrough."; exit 0; }

# Emite e SÓ ENTÃO avança a janela das notas exibidas. Falha de emissão (EPIPE/
# stdout fechado) ⇒ log + passthrough, sem avançar last_review (nota não entregue).
if printf '%s\n' "$json" 2>/dev/null; then
  new_ts=$(kolb_ts)
  printf '%s' "$files_selected" | while IFS= read -r nf; do
    [ -n "$nf" ] || continue
    tmp="$nf.kolb-tmp.$$"
    # Reescreve APENAS a 1ª linha `last_review:` dentro do frontmatter (fm==1);
    # demais linhas e o corpo intactos. tmp + mv atômico; falha ⇒ não corrompe.
    if awk -v ts="$new_ts" '
        /^---[[:space:]]*$/ { fm++; print; next }
        fm==1 && done!=1 && /^last_review:/ { print "last_review: \"" ts "\""; done=1; next }
        { print }
      ' "$nf" > "$tmp" 2>/dev/null && mv "$tmp" "$nf" 2>/dev/null; then
      :
    else
      rm -f "$tmp" 2>/dev/null || true
      kolb_log_error "spacing-start: falha ao avançar last_review de $nf."
    fi
  done
else
  kolb_log_error "spacing-start: falha ao emitir additionalContext (stdout fechado?); passthrough."
fi
exit 0
