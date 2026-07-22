#!/usr/bin/env sh
# block-write.sh — Hook PreToolUse do Kolb. Em modo aprendizado, NEGA toda
# escrita/edição de arquivo (matcher Write|Edit|NotebookEdit no hooks.json) com
# uma mensagem socrática. É o ÚNICO garante DURO de não-geração do produto
# (FR10/FR12, architecture.md:185,445).
#
# Estrutura canônica de hook: gating barato PRIMEIRO (NFR5), depois a ação.
# DIFERENÇA CRÍTICA vs. Epic 1: aqui o fail-safe é fail-OPEN (NFR9,
# architecture.md:480) — erro interno ⇒ exit 0 SEM emitir deny (o Write
# prossegue) + log. A não-interferência com o hospedeiro tem prioridade sobre o
# contrato pedagógico (fail-closed foi rejeitado por risco de travar o host).
#
# Sem jq: o único dado lido do stdin é o session_id (via kolb_gate, sem jq) e a
# saída é uma string CONSTANTE (mensagem fixa, sem interpolar tool_name/path),
# montável por printf literal. Não chamar kolb_require_jq aqui.
set -eu

# Sourcing de _common.sh: prioriza CLAUDE_PLUGIN_ROOT; cai para o diretório deste
# script quando a env var não está setada (ex.: execução direta em teste).
#
# Fail-OPEN também na FASE DE SETUP (AC#6 lista "sourcing" como erro que deve
# falhar aberto): sob `set -e`, qualquer falha em resolver $0 ou sourcear
# _common.sh deve resultar em `exit 0` SEM emitir deny (o Write prossegue),
# nunca em abort com status≠0 (que viraria ruído de "hook error" no host, NFR9).
# O log é best-effort e impossível aqui se o próprio _common.sh (dono do
# kolb_log_error) não sourçar — a não-interferência tem prioridade sobre o
# diagnóstico.
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 0
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
# `.` é um builtin ESPECIAL: arquivo ausente/ilegível faz o shell não-interativo
# ABORTAR (status≠0) ANTES de avaliar um `|| exit 0` colado no próprio dot — logo
# o `||` no dot NÃO basta. Guardamos com um teste de leitura ANTES de sourcear:
# sem arquivo legível ⇒ exit 0 limpo (fail-open), nunca abort.
# Resíduo consciente: se _common.sh EXISTE mas tem ERRO DE SINTAXE, o parse do
# dot ainda aborta com status≠0 (sem deny ⇒ host não é bloqueado, intenção
# fail-open intacta). O único contorno (`sh -n` antes do dot) custaria um fork
# por chamada no caminho OFF, violando o NFR5 — rejeitado: _common.sh é arquivo
# controlado e validado pelo pacote.
[ -r "$_kolb_common" ] || exit 0
# shellcheck source=/dev/null
. "$_kolb_common" 2>/dev/null || exit 0

# 1ª lógica: guard universal. Modo OFF (flag ausente) ou sid irresolvível ⇒
# exit 0 barato, sem jq (AC#3 off ≤10ms, AC#4 passthrough, NFR5). Sem o flag
# presente NUNCA se chega ao deny abaixo — não há caminho que negue sem modo.
input=$(cat)
kolb_gate "$input"

# Modo ATIVO a partir daqui: nega a operação de escrita. A mensagem socrática é
# LITERAL (sem aspas duplas internas ⇒ JSON montável por printf sem escape; o
# \n separa as 2 linhas dentro do valor JSON, mantendo UMA única linha no stdout).
# Critérios de tom honram plugin/kolb/CLAUDE.md (≤3 linhas · direto · termina em
# pergunta · não revela a solução, NFR23). Resolve a prioridade NFR23 para
# bloqueio: comunica o bloqueio + reorienta + termina em pergunta, em 2 linhas.
#
# Fail-OPEN (NFR9, architecture.md:480): se o printf falhar (ex.: EPIPE, stdout
# fechado), o `||` impede o abort do `set -e` — registramos e saímos 0 (o Write
# prossegue), NUNCA travamos o host. Mesmo idioma do session-end.sh.
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Modo aprendizado: escrever o código é o seu esforço — eu oriento, não gero. Posso dar uma dica em alto nível ou revisar o que você escrever.\nQual é o primeiro passo da sua abordagem?"}}' \
  || kolb_log_error "block-write: falha ao emitir o JSON de deny; passthrough (fail-open)."
exit 0
