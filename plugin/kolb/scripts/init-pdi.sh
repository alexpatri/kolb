#!/usr/bin/env sh
# init-pdi.sh — Cria $CLAUDE_PROJECT_DIR/.kolb/pdi.md a partir do template shipado
# (templates/pdi.md) na 1ª vez que o PDI é necessário (FR23/FR40). É o primitivo de
# criação que o check-in /kolb:pdi-checkin (story 4.2) CONSUMA — sem reimplementar cp.
#
# Por que um script (e não a tool Write): o pdi.md é estado durável do PRÓPRIO Kolb
# em .kolb/ — mesma família de write-note.sh. Em modo aprendizado o block-write.sh
# (2.2) NEGA Write/Edit; copiar o template por shell aqui é o canal previsto. NÃO é
# a "brecha via Bash" da 2.2 (que é a IA escrever CÓDIGO DE PROJETO).
#
# É só `cp` + guardas: SEM jq (NFR12, zero deps). NÃO sobrescreve um pdi.md existente
# (estado do usuário — mesma garantia de write-note.sh:88-93). Sem kolb_gate (skills
# são explícitas — o guard de modo é dos HOOKS). Falha graciosa (NFR9): qualquer
# problema ⇒ log + exit 0, sem derrubar o hospedeiro nem deixar arquivo parcial.
set -eu

# Sourcing de _common.sh: prioriza CLAUDE_PLUGIN_ROOT; cai para o diretório deste
# script quando a env var não está setada (ex.: execução direta em teste).
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
# shellcheck source=/dev/null
. "$_kolb_common"

# Base de estado: fonte única CLAUDE_PROJECT_DIR. Ausente ⇒ falha graciosa
# (skill e hook precisam concordar na base — sem fallback git/pwd).
base="$(kolb_project_dir)"
if [ -z "$base" ]; then
  kolb_log_error "init-pdi: CLAUDE_PROJECT_DIR ausente; não foi possível resolver o diretório do projeto."
  printf '%s\n' "Kolb: não consegui localizar o diretório do projeto. PDI não criado."
  exit 0
fi
pdi="$base/.kolb/pdi.md"

# Garante .kolb/ (durável). Sob set -e, falha de FS (read-only, .kolb é arquivo
# regular) abortaria cru; interceptamos com log + exit 0 (NFR9).
if ! mkdir -p "$base/.kolb" 2>/dev/null; then
  kolb_log_error "init-pdi: não foi possível criar $base/.kolb (FS não-gravável?)."
  printf '%s\n' "Kolb: não consegui preparar o diretório .kolb. PDI não criado."
  exit 0
fi

# NÃO sobrescrever (garantia central do AC#2): o pdi.md é estado durável/versionável
# do usuário, editado à mão. Já existe ⇒ reporta e sai, sem clobber.
if [ -e "$pdi" ]; then
  printf '%s\n' "Kolb: já existe um PDI em $pdi — nada foi sobrescrito."
  exit 0
fi

# Resolve o template shipado (read-only no plugin). Mesmo padrão de resolução do
# toggle-mode.sh:144-145 (exit-log): prioriza CLAUDE_PLUGIN_ROOT, cai para o dir do
# script. Template ausente ⇒ falha HONESTA (NÃO inventa conteúdo mínimo: o pdi.md é
# contrato lido pela 4.2; um molde silencioso divergente seria pior que não criar).
_tpl="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/templates/pdi.md"
[ -f "$_tpl" ] || _tpl="$_kolb_self_dir/../templates/pdi.md"
if [ ! -f "$_tpl" ]; then
  kolb_log_error "init-pdi: template pdi.md não encontrado (procurado em \$CLAUDE_PLUGIN_ROOT/templates e ao lado do script)."
  printf '%s\n' "Kolb: o template do PDI não foi encontrado na instalação do plugin. PDI não criado."
  exit 0
fi

# Copia o template para .kolb/pdi.md. Falha de escrita ⇒ log + exit 0, limpando
# arquivo parcial (paridade write-note.sh:131-148). Mensagem final HONESTA: só
# afirma sucesso se o cp teve êxito.
if cp "$_tpl" "$pdi" 2>/dev/null; then
  printf '%s\n' "Kolb: PDI criado em $pdi a partir do template. Edite as metas à mão."
else
  kolb_log_error "init-pdi: falha ao copiar o template para $pdi."
  rm -f "$pdi" 2>/dev/null || true
  printf '%s\n' "Kolb: não consegui criar o PDI (falha de escrita). Nada foi criado."
fi
exit 0
