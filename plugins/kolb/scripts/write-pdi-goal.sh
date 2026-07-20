#!/usr/bin/env sh
# write-pdi-goal.sh "<id-da-meta>" — Anexa UMA meta (na formulação do dev) ao
# $CLAUDE_PROJECT_DIR/.kolb/pdi.md, com os 4 campos-contrato (skill atual · skill
# alvo · evidência · próxima ação). Os 4 valores chegam por STDIN (heredoc da skill
# /kolb:create-pdi), em 4 linhas rotuladas:
#     skill-atual: <...>
#     skill-alvo: <...>
#     evidencia: <...>
#     proxima-acao: <...>
#
# Por que um script (e não a tool Write): em modo aprendizado o block-write.sh (2.2)
# NEGA Write/Edit. O pdi.md é estado durável do PRÓPRIO Kolb (.kolb/) — mesma família
# de write-note.sh/init-pdi.sh; gravá-lo por shell aqui é o canal previsto. NÃO é a
# "brecha via Bash" da 2.2 (que é a IA escrever CÓDIGO DE PROJETO).
#
# Papel: create-pdi ELICIA (a skill conduz a conversa socrática); este script apenas
# PERSISTE a formulação do dev — as palavras são dele (corpo verbatim, como
# write-note.sh). Sem jq (pdi.md é Markdown; NFR12). Sem kolb_gate (skills são
# explícitas — o guard de modo é dos HOOKS). NÃO sobrescreve: arquivo ausente ⇒
# materializa via REUSO de init-pdi.sh; id colidindo com uma seção `## <id>` já
# presente ⇒ avisa e não toca (garantia central de write-note.sh:88-93/init-pdi.sh).
# Falha graciosa (NFR9): qualquer problema ⇒ log + exit 0, sem derrubar o hospedeiro.
set -eu

# Sourcing de _common.sh: prioriza CLAUDE_PLUGIN_ROOT; cai para o diretório deste
# script quando a env var não está setada (ex.: execução direta em teste).
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
# shellcheck source=/dev/null
. "$_kolb_common"

# Neutraliza CR/LF/TAB de um valor de campo para preservar "uma linha lógica" no
# Markdown (um valor multilinha quebraria o rótulo-contrato que o pdi-checkin
# parseia). Ao contrário do write-note.sh (que escreve YAML), aqui é Markdown puro:
# NÃO mexemos em aspas nem em barra invertida (o dev pode citar código/paths nas
# metas); acentos são preservados (é prosa do dev, não vira id).
_kolb_line_safe() {
  printf '%s' "${1:-}" | tr '\r\n\t' '   '
}

# --- Título (id da meta) obrigatório, 1º posicional. -----------------------
topic="${1:-}"
if [ -z "$topic" ]; then
  kolb_log_error "write-pdi-goal: id da meta (topic) ausente."
  printf '%s\n' "Kolb: informe um id de meta: /kolb:create-pdi. Nada foi gravado."
  exit 0
fi

# Slug determinístico (mesmo kolb_slugify de write-note.sh — id ASCII do pdi.md,
# alvo do pdi_goal das notas AC). Vazio (título sem [a-z0-9] ASCII) ⇒ falha graciosa.
slug=$(kolb_slugify "$topic")
if [ -z "$slug" ]; then
  kolb_log_error "write-pdi-goal: slug vazio para topic='$topic' (sem caractere ASCII utilizável)."
  printf '%s\n' "Kolb: esse id de meta não gera um nome válido. Use letras ou números."
  exit 0
fi

# --- Os 4 campos, na formulação do dev, via stdin (4 linhas rotuladas). Lido AQUI,
# ANTES de tocar o filesystem, para que uma meta sem núcleo seja recusada sem sequer
# materializar o pdi.md (e para capturar o stdin antes de qualquer subprocesso).
# Extraímos cada valor pelo prefixo do rótulo (1ª ocorrência) e reescrevemos para os
# rótulos Markdown-contrato exatos que o pdi-checkin (4.2) parseia. Guardado contra set -e.
_stdin=$(cat) || _stdin=""
_field() { # <label-de-entrada> ⇒ valor da 1ª linha com aquele prefixo
  printf '%s\n' "$_stdin" | sed -n "s/^$1:[[:space:]]*//p" | head -n 1
}
atual=$(_kolb_line_safe "$(_field 'skill-atual')")
alvo=$(_kolb_line_safe "$(_field 'skill-alvo')")
evid=$(_kolb_line_safe "$(_field 'evidencia')")
prox=$(_kolb_line_safe "$(_field 'proxima-acao')")

# TRAVA DE NÚCLEO (AC#2 — code review 2026-07-20): skill-atual E skill-alvo são o
# núcleo mensurável ("onde estou" · "aonde quero chegar"). A garantia de que uma meta
# não-mensurável NÃO é materializada vive na elicitação socrática da SKILL; esta trava
# é defense-in-depth no canal seguro: se o núcleo chegar vazio (modelo invocou cedo),
# recusa SEM gravar e SEM materializar. evidencia/proxima-acao podem ser vazios (o dev
# preenche depois no check-in). Falha HONESTA: não afirma "adicionada".
if [ -z "$atual" ] || [ -z "$alvo" ]; then
  kolb_log_error "write-pdi-goal: núcleo vazio para \"$slug\" (skill-atual e/ou skill-alvo em branco); nada gravado."
  printf '%s\n' "Kolb: a meta \"$slug\" precisa de skill atual E skill alvo (onde você está e aonde quer chegar). Nada foi gravado."
  exit 0
fi

# Base de estado: fonte única kolb_project_dir. Ausente ⇒ falha graciosa.
base="$(kolb_project_dir)"
if [ -z "$base" ]; then
  kolb_log_error "write-pdi-goal: não foi possível resolver o diretório do projeto."
  printf '%s\n' "Kolb: não consegui localizar o diretório do projeto. Meta não gravada."
  exit 0
fi
pdi="$base/.kolb/pdi.md"

# --- Materializar o pdi.md se ausente, via REUSO de init-pdi.sh (não reimplementar
# o cp). stdout suprimido para que a mensagem final DESTE script seja a única ao
# humano (honestidade de relato). init-pdi.sh já é fail-open e não-clobber; se ele
# não conseguir criar o arquivo, não há onde anexar ⇒ falha graciosa.
if [ ! -f "$pdi" ]; then
  _init="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/init-pdi.sh"
  [ -f "$_init" ] || _init="$_kolb_self_dir/init-pdi.sh"
  if [ -f "$_init" ]; then
    sh "$_init" >/dev/null 2>&1 || true
  fi
  if [ ! -f "$pdi" ]; then
    kolb_log_error "write-pdi-goal: não foi possível materializar o pdi.md (init-pdi falhou?)."
    printf '%s\n' "Kolb: não consegui preparar o PDI. Meta não gravada."
    exit 0
  fi
fi

# --- Colisão de id: já existe uma seção `## <slug>` no pdi.md? Detecção ciente de
# fence (```) e de comentário HTML (<!-- -->), espelhando pdi-status.sh:63-76 — um
# `## slug` dentro de code-block/rascunho NÃO conta. Aqui listamos TODAS as seções
# `## <id>` (inclusive a META-EXEMPLO shipada), pois anexar um heading duplicado
# sujaria o arquivo mesmo que o pdi-status a filtre. O awk sempre sai 0 (não deixa o
# set -e abortar); a comparação de igualdade é por linha exata via grep -Fxq.
existing_ids=$(awk '
  /^[[:space:]]*```/ { in_fence = !in_fence; next }
  in_fence { next }
  in_comment { if ($0 ~ /-->/) in_comment=0; next }
  /<!--/ && $0 !~ /-->/ { in_comment=1; next }
  /^## / { id=$0; sub(/^## /,"",id); sub(/[[:space:]]+$/,"",id); if (id!="") print id }
' "$pdi" 2>/dev/null) || existing_ids=""
if printf '%s\n' "$existing_ids" | grep -Fxq -- "$slug"; then
  printf '%s\n' "Kolb: já existe a meta \"$slug\" no PDI — nada foi sobrescrito. Use outro id ou edite o PDI à mão."
  exit 0
fi

# --- Anexar a seção da meta ao fim do pdi.md (append). Formato idêntico ao
# templates/pdi.md:47-60 (SEM o marcador de exemplo): heading + 4 rótulos-contrato,
# um por bloco, separados por linha em branco. Falha de escrita ⇒ log + exit 0
# (mensagem HONESTA: só afirma sucesso se o append teve êxito). Paridade
# write-note.sh:133-148.
if {
  printf '\n## %s\n\n' "$slug"
  printf '**Skill atual:** %s\n\n' "$atual"
  printf '**Skill alvo:** %s\n\n' "$alvo"
  printf '**Evidência:** %s\n\n' "$evid"
  printf '**Próxima ação:** %s\n' "$prox"
} >> "$pdi" 2>/dev/null; then
  printf '%s\n' "Kolb: meta \"$slug\" adicionada ao PDI em $pdi."
else
  kolb_log_error "write-pdi-goal: falha ao anexar a meta \"$slug\" em $pdi."
  printf '%s\n' "Kolb: não consegui gravar a meta (falha de escrita). O PDI existente não foi alterado."
fi
exit 0
