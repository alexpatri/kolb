#!/usr/bin/env sh
# prompt-steer.sh — Hook UserPromptSubmit do Kolb. Em modo aprendizado, injeta a
# CADA TURNO o contrato dos dois princípios (FR7) + um steer anti-cola (FR11) via
# additionalContext. É o HOME do FR7 (a 2.1 deferiu "contrato a cada turno" para
# cá; um CLAUDE.md de plugin NÃO é auto-relido pelo host — architecture.md:494).
#
# NÃO reescreve o prompt do usuário (restrição de plataforma, architecture.md:185):
# só ADICIONA contexto. A garantia DURA de não-geração permanece o block-write.sh
# (2.2). Injeção INCONDICIONAL por turno — sem classificar o conteúdo do prompt
# (FR7 subsume FR11; heurística de detecção seria frágil e desnecessária).
#
# Fail-safe = PASSTHROUGH (mais simples que o block-write, que bloqueia): como o
# steer é ADITIVO, erro interno ⇒ exit 0 SEM emitir additionalContext (a IA só
# não recebe o reforço NAQUELE turno; o garante DURO 2.2 segue ativo) + log (NFR9).
#
# Sem jq: o único dado lido do stdin é o session_id (via kolb_gate, sem jq) e a
# saída é uma string CONSTANTE (contrato + steer fixos, sem interpolar o prompt),
# montável por printf literal. Não chamar kolb_require_jq aqui.
set -eu

# Sourcing endurecido de _common.sh (idêntico ao block-write.sh, code review 2.2):
# prioriza CLAUDE_PLUGIN_ROOT; cai para o diretório deste script quando a env var
# não está setada (ex.: execução direta em teste). Fail-safe também aqui: sob
# `set -e`, qualquer falha em resolver $0 ou sourcear _common.sh ⇒ exit 0 SEM
# emitir nada (passthrough), nunca abort com status≠0 (ruído de "hook error" no host).
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 0
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
# `.` é builtin ESPECIAL: arquivo ausente/ilegível aborta (status≠0) ANTES de um
# `|| exit 0` colado no dot — por isso guardamos com `[ -r ]` ANTES de sourcear.
[ -r "$_kolb_common" ] || exit 0
# shellcheck source=/dev/null
. "$_kolb_common" 2>/dev/null || exit 0

# 1ª lógica: guard universal. Modo OFF (flag ausente) ou sid irresolvível ⇒ exit 0
# barato, sem jq (AC#5 off ≤10ms / passthrough, NFR5). Sem o flag presente NUNCA
# se chega à injeção abaixo — não há caminho que injete fora do modo.
input=$(cat)
kolb_gate "$input"

# Modo ATIVO a partir daqui: injeta o contrato + steer no contexto do turno. A
# string é LITERAL (sem aspas duplas internas ⇒ JSON montável por printf sem
# escape; o \n separa as 3 linhas DENTRO do valor JSON, mantendo UMA linha no
# stdout). Substância fiel a plugin/kolb/CLAUDE.md (princípios #1/#2 + vocabulário
# FR8); a porção de steer honra o registro de tom (≤3 linhas · termina em pergunta
# · não revela solução, NFR23). Direcionada à IA (instrução de turno).
#
# Fail-safe (NFR9): se o printf falhar (EPIPE/stdout fechado), o `||` impede o
# abort do `set -e` — loga e sai 0 (passthrough). Mesmo idioma de block-write.sh.
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"Modo aprendizado ativo. Contrato: (#1) a IA acelera o que não ensina e é proibida de remover o esforço que ensina; (#2) a IA não gera código — nada de função pronta, assinatura completada ou bloco compilável — ela dá dicas sobre a abordagem e avalia depois.\nSe o pedido for por código pronto, oriente para a abordagem em vez de entregar a solução; respostas conceituais e dicas continuam permitidas.\nQual é o primeiro passo que o dev deveria tentar por conta própria?"}}' \
  || kolb_log_error "prompt-steer: falha ao emitir additionalContext; passthrough (sem injetar)."
exit 0
