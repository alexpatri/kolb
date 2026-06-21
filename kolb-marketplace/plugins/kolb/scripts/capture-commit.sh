#!/usr/bin/env sh
# capture-commit.sh — Hook PostToolUse/Bash do Kolb (PROVENIÊNCIA DE COMMITS, FR35).
# Em modo aprendizado, quando um `git commit` roda via Bash, captura o SHA do HEAD
# resultante (`git rev-parse HEAD`) e ANEXA um evento `commit` a .kolb/sessions.jsonl
# (append-only) SEM tocar na mensagem do commit. Correlaciona commit↔sessão para que
# a razão autoral/assistido (FR35) seja derivável offline: assistidos = `git log`
# MENOS os SHAs autorais aqui registrados (NFR20).
#
# É o gêmeo de session-end.sh: ambos são hooks que apenas ANEXAM um evento ao índice,
# sem emitir additionalContext. O consumidor já existe e é forward-compatible —
# session-status.sh (1.4) já faz `commits: [select(.event=="commit").sha]`; esta story
# só PRODUZ a linha que o fold já CONSOME (schema = templates/sessions.jsonl:5).
#
# Diferenças vs. session-end.sh: (a) filtra `git commit` no comando (.tool_input.command);
# (b) usa jq (lê string de comando arbitrária — após o gate, p/ não furar o off-path);
# (c) captura o SHA via git rev-parse; (d) dedup defensivo (o consumidor não deduplica).
#
# Estrutura canônica de hook: gate barato PRIMEIRO (NFR5, jq-free); ADITIVO/fail-open —
# qualquer erro interno ⇒ hook-errors.log + exit 0, NUNCA exit≠0 (abortaria o commit do
# usuário, inaceitável — NFR9).
set -eu

# Sourcing endurecido de _common.sh (igual a spacing-read.sh/session-end.sh): prioriza
# CLAUDE_PLUGIN_ROOT; cai para o diretório deste script quando a env var não está setada
# (ex.: execução direta em teste). `.` é builtin ESPECIAL: arquivo ilegível aborta antes
# de um `|| exit 0` colado no dot — por isso guardamos com `[ -r ]` ANTES de sourcear.
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 0
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
[ -r "$_kolb_common" ] || exit 0
# shellcheck source=/dev/null
. "$_kolb_common" 2>/dev/null || exit 0

# 1ª lógica: guard universal. Modo OFF (flag ausente) ⇒ exit 0 barato, sem jq (AC#2/
# NFR5). Commits fora do modo NÃO são registrados como autorais — passthrough puro.
input=$(cat)
kolb_gate "$input"

# Modo ATIVO a partir daqui. jq é necessário p/ LER .tool_input.command (string de
# comando arbitrária — não dá pra parsear com o sed restrito do session_id) ⇒ require_jq
# logo APÓS o gate, mantendo o off-path 100% jq-free.
kolb_require_jq || exit 0

# Filtro de comando (AC#3): só uma invocação de `git commit` registra. Ausente/null ou
# não-commit ⇒ exit 0 SILENCIOSO (sem log — caso normalíssimo de altíssima frequência).
# O matcher do hook casa o NOME da tool ("Bash"); a detecção do comando é AQUI, no script.
# `--dry-run` NUNCA cria commit (só relata) ⇒ excluído antes do match geral, senão um
# dry-run com algo staged (que sai 0) registraria o HEAD atual como se fosse autoral.
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0
case "$cmd" in
  *"--dry-run"*) exit 0 ;;
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# Sucesso REAL do commit (hardening do code review da 5.1): PostToolUse expõe o exit code
# do comando em `.tool_response.exit_code`. Um `git commit` que NÃO produziu commit novo
# (nada staged, pre-commit rejeitou, mensagem abortada) sai com código ≠ 0 — e aí o
# `git rev-parse HEAD` abaixo devolveria o HEAD ANTERIOR (possivelmente um commit assistido
# feito FORA do modo) e o registraria como autoral, inflando indevidamente a razão FR35
# (o consumidor session-status.sh não deduplica). Só registramos quando o commit teve
# sucesso de fato. Campo ausente/null ⇒ NÃO bloqueia (fail-open: preserva o comportamento
# anterior sob qualquer variação de schema, sem regressão). Lê do mesmo $input (sem custo
# de jq extra relevante — já estamos no caminho ativo pós-filtro de comando).
rc=$(printf '%s' "$input" | jq -r '.tool_response.exit_code // empty' 2>/dev/null) || rc=""
case "$rc" in
  ""|0) ;;       # sucesso (0) ou desconhecido (campo ausente) ⇒ segue
  *) exit 0 ;;   # comando falhou ⇒ não houve commit novo, nada a registrar
esac

# sid do STDIN — este é um HOOK, então o sid vem de .session_id (kolb_session_id_from_stdin,
# já validado p/ [0-9A-Za-z-]), NUNCA de CLAUDE_CODE_SESSION_ID (env das skills, que pode
# não estar setada em hook). Vazio ⇒ falha graciosa.
sid=$(printf '%s' "$input" | kolb_session_id_from_stdin)
[ -n "$sid" ] || { kolb_log_error "capture-commit: session_id ausente no stdin; nada anexado."; exit 0; }

# Base de estado: fonte única CLAUDE_PROJECT_DIR. Ausente ⇒ falha graciosa.
base="$(kolb_project_dir)"
[ -n "$base" ] || { kolb_log_error "capture-commit: CLAUDE_PROJECT_DIR ausente; nada anexado."; exit 0; }
sessions="$base/.kolb/sessions.jsonl"

# Captura o SHA do HEAD resultante. `git -C "$base"` não depende do cwd do hook. Sob
# set -e, o `|| sha=""` impede que rev-parse falho (sem repo / sem commits ainda / git
# ausente) aborte o script. Valida o formato hex antes de compor a linha JSON (mesma
# disciplina do sid em log-phase.sh — nunca confiar cegamente).
sha=$(git -C "$base" rev-parse HEAD 2>/dev/null) || sha=""
case "$sha" in
  ""|*[!0-9a-f]*)
    kolb_log_error "capture-commit: git rev-parse HEAD falhou ou SHA inválido em $base; nada anexado."
    exit 0
    ;;
esac

# Dedup defensivo (idempotência, NFR6): o consumidor (session-status.sh:114) NÃO
# deduplica — listaria SHAs repetidos e inflaria a razão de FR35. PostToolUse pode
# disparar p/ comandos que NÃO produziram commit novo (--dry-run, no-op, falso-positivo
# textual como `echo "git commit"`), todos retornando o HEAD atual. Se o ÚLTIMO evento
# commit do MESMO sid já tem este sha ⇒ exit 0 sem gravar. grep+sed (robusto a linhas
# malformadas — não aborta como jq streaming faria) sobre o schema fixo onde `sha` é o
# último campo. Mantém o índice append-only (não reescreve nada).
if [ -f "$sessions" ]; then
  last_sha=$(grep -F '"event":"commit"' "$sessions" 2>/dev/null \
             | grep -F "\"sid\":\"$sid\"" \
             | tail -n 1 \
             | sed -n 's/.*"sha":"\([0-9a-f]*\)".*/\1/p') || last_sha=""
  if [ "$last_sha" = "$sha" ]; then
    exit 0
  fi
fi

# Append do evento (append-only) com schema EXATO = templates/sessions.jsonl:5. sid é
# UUID validado e sha é hex validado ⇒ printf puro, sem jq na escrita (idioma dos
# appenders: session-end.sh/log-phase.sh). Falha de FS ⇒ log + exit 0 (NFR9). NÃO emite
# additionalContext — este hook só grava o índice.
if printf '{"ts":"%s","sid":"%s","event":"commit","mode":"learn","sha":"%s"}\n' \
    "$(kolb_ts)" "$sid" "$sha" >> "$sessions" 2>/dev/null; then
  :
else
  kolb_log_error "capture-commit: falha ao anexar evento commit em $sessions."
fi
exit 0
