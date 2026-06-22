#!/usr/bin/env sh
# pdi-status.sh — Deriver READ-ONLY do PDI, consumido pela skill /kolb:pdi-checkin
# (story 4.2). LÊ $CLAUDE_PROJECT_DIR/.kolb/pdi.md e .kolb/notes/ e EMITE um digest
# legível+parseável do estado das metas — a parte MECÂNICA do check-in (filtrar o
# exemplo + correlacionar notas), deixando a NARRATIVA/sugestão para a skill (LLM).
#
# Fronteira (como session-status.sh): este script só LÊ e DERIVA — NÃO escreve
# estado (nem .kolb/, nem o plugin), NÃO calcula veredito, NÃO sugere. A skill
# narra por cima e lê o conteúdo dos 4 campos do pdi.md (legível) para exibir.
#
# Schema do PDI (fixado pela 4.1 — templates/pdi.md): cada META é uma seção
# `## <id>` cujo id (= título da seção, slug ASCII) é o alvo do `pdi_goal` das
# notas AC (FR24). A seção precedida do marcador `<!-- META-EXEMPLO -->` é uma
# AMOSTRA shipada e é IGNORADA ao listar metas reais (contrato do code review 4.1).
#
# Saída (stdout), uma linha por chave (NFR18):
#   pdi: present|absent|unknown
#   real-goals: <N>                                   (só quando present)
#   goal: <id> | evidence-notes: <slug> <slug> ...    (uma por meta real)
#
# Correlação nota->meta (FR24/FR27): scan do frontmatter de .kolb/notes/*.md; uma
# nota lista-se sob a meta cujo id == pdi_goal da nota (match EXATO). pdi_goal
# vazio/ausente/sem-correspondência ⇒ não atribui. notes/ ausente ⇒ listas vazias.
#
# Sem jq (pdi.md/frontmatter não é JSON — awk/sed basta; NFR12). Sem kolb_gate
# (skill explícita). Falha graciosa (NFR8/NFR9): qualquer problema ⇒ log + exit 0,
# nunca derruba o hospedeiro nem emite metas espúrias.
set -eu

# Sourcing de _common.sh: prioriza CLAUDE_PLUGIN_ROOT; cai para o diretório deste
# script quando a env var não está setada (ex.: execução direta em teste).
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
# shellcheck source=/dev/null
. "$_kolb_common"

# Base de estado: fonte única CLAUDE_PROJECT_DIR (kolb_project_dir). Ausente ⇒
# estado 'unknown' (não 'absent': a skill não deve oferecer criar se nem sabe onde).
base="$(kolb_project_dir)"
if [ -z "$base" ]; then
  kolb_log_error "pdi-status: CLAUDE_PROJECT_DIR ausente; não foi possível resolver o diretório do projeto."
  printf 'pdi: unknown\n'
  exit 0
fi
pdi="$base/.kolb/pdi.md"

# PDI ausente (ou não-regular: dir/symlink pendurado) ⇒ 'absent' sem erro: a skill
# oferece criar via init-pdi.sh (AC#3, NFR8).
if [ ! -f "$pdi" ]; then
  printf 'pdi: absent\n'
  exit 0
fi

# --- Metas REAIS: seções `## <id>` SEM o marcador META-EXEMPLO imediatamente antes.
# O marcador "pende" através de linhas em branco até o próximo `##`; qualquer outra
# linha de conteúdo o cancela (o marcador precede a seção — templates/pdi.md:46-47).
# `## ` exige nível 2 exato (não casa `# ` título nem `### `). Linhas dentro de um
# bloco de código cercado (```) ou de um comentário HTML multilinha (<!-- ... -->)
# NÃO contam como heading — um `## ` em snippet/rascunho do humano não vira meta
# espúria. Tolera pdi malformado (sem headings ⇒ lista vazia). Falha de leitura ⇒
# lista vazia (guardado).
real_goals=$(awk '
  /^[[:space:]]*```/ { in_fence = !in_fence; next }
  in_fence { next }
  in_comment { if ($0 ~ /-->/) in_comment=0; next }
  /^[[:space:]]*<!-- META-EXEMPLO -->[[:space:]]*$/ { pending=1; next }
  /<!--/ && $0 !~ /-->/ { in_comment=1; next }
  /^## / {
    id=$0; sub(/^## /,"",id); sub(/[[:space:]]+$/,"",id);
    if (pending!=1 && id!="") print id;
    pending=0; next
  }
  /^[[:space:]]*$/ { next }
  { pending=0 }
' "$pdi" 2>/dev/null) || real_goals=""

# --- Mapa nota->meta: para cada nota, extrai o pdi_goal do frontmatter. Acumula
# linhas "<pdi_goal><TAB><slug>" (slug = nome do arquivo sem .md). Determinístico:
# o glob de pathname é ordenado por POSIX. notes/ ausente ⇒ mapa vazio.
tab=$(printf '\t')
nl='
'
notes_dir="$base/.kolb/notes"
note_map=""
if [ -d "$notes_dir" ]; then
  for nf in "$notes_dir"/*.md; do
    [ -e "$nf" ] || continue   # glob sem match ⇒ pula o literal
    g=$(awk '
      /^---[[:space:]]*$/ { fm++; if (fm==2) exit; next }
      fm==1 && /^pdi_goal:/ {
        v=$0; sub(/^pdi_goal:[[:space:]]*/,"",v);
        sub(/^"/,"",v); sub(/"[[:space:]]*$/,"",v); sub(/[[:space:]]+$/,"",v);
        print v; exit
      }
    ' "$nf" 2>/dev/null) || g=""
    [ -n "$g" ] || continue    # pdi_goal vazio/ausente ⇒ não entra no mapa
    slug=$(basename "$nf" .md)
    note_map="${note_map}${g}${tab}${slug}${nl}"
  done
fi

# --- Saída.
printf 'pdi: present\n'
n=$(printf '%s\n' "$real_goals" | awk 'NF{c++} END{print c+0}')
printf 'real-goals: %s\n' "$n"

# Uma linha por meta real, com as notas cujo pdi_goal == id (match exato, ordem do
# glob). O filtro é por awk (sempre sai 0 — evita que um não-match, sob `set -e`,
# aborte o laço); o id vai por ENVIRON (não -v) para não sofrer escape de backslash.
printf '%s\n' "$real_goals" | while IFS= read -r gid; do
  [ -n "$gid" ] || continue
  ev=$(printf '%s' "$note_map" | gid="$gid" awk -F"$tab" '$1==ENVIRON["gid"]{printf "%s ", $2}')
  ev=${ev% }   # remove o espaço final
  printf 'goal: %s | evidence-notes: %s\n' "$gid" "$ev"
done

exit 0
