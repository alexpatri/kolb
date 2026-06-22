#!/bin/sh
# check-snapshot.sh — Harness de snapshot do contrato pedagógico do Kolb (NFR22).
#
# PROPÓSITO (Story 6.3, AC#2): o git já dá VERSIONAMENTO do contrato; este harness
# adiciona o TESTÁVEL — detecta DRIFT (uma superfície canônica mudar entre dois
# momentos) e, sobretudo, DRIFT CRUZADO (uma mensagem socrática hardcoded num script
# divergir do CLAUDE.md / da transcrição sample-run.md sem ninguém perceber).
#
# NÃO É RUNTIME. Vive em kolb-marketplace/tests/ (IRMÃO de plugins/, NÃO sob
# plugins/kolb/). Nenhum hook/skill/script o lê; não é copiado para .kolb/; não
# viaja como runtime. Versionado com o marketplace (auditável e V2-friendly).
# Por estar FORA de plugins/kolb/, não dispara warning no gate `claude plugin
# validate` (Opção A, AC#1) — a Task 1/Task 6 da story confirmam zero warning novo.
#
# SEM DEPENDÊNCIAS (NFR12): POSIX sh + coreutils (sha256sum) + git. JQ-FREE
# (paridade com a postura jq-opcional dos scripts do plugin).
#
# DESENHO HÍBRIDO (decisão da story — granularidade do snapshot):
#   (A) DIGEST DE ARQUIVO INTEIRO para as superfícies de DOCUMENTAÇÃO/TEMPLATE,
#       onde a auditoria por `git diff` já é fina e qualquer edição é intencional:
#       CLAUDE.md, agents/tutor.md, as 6 skills/*/SKILL.md e os 5 templates/*.
#       Mudança intencional ⇒ rodar `--update`; o diff do SNAPSHOT.sha256 no git
#       vira o registro auditável da mudança de contrato (NFR22).
#   (B) ASSERÇÕES DE CONVERGÊNCIA FONTE↔CÓPIA para as MENSAGENS socráticas/runtime,
#       cuja fonte-de-verdade é um SCRIPT. Os scripts NÃO são digest-pinados de
#       propósito: o endurecimento de CÓDIGO (Bucket B, deferido a uma story de
#       hardening dedicada) deve poder mexer no script SEM exigir --update — o que
#       precisa ficar estável é a MENSAGEM. A asserção exige que a frase canônica
#       apareça VERBATIM em TODAS as superfícies do par; se uma divergir, RED.
#
# PARES DE DRIFT CRUZADO QUE ESTE HARNESS PROTEGE (Bucket A — NFR22):
#   P1  princípio #1 do contrato ......... CLAUDE.md  ↔ prompt-steer.sh
#   P2  princípio #2 ("não gera código") . CLAUDE.md  ↔ prompt-steer.sh ↔ sample-run.md
#   P3  deny (linha 1) do bloqueio ....... block-write.sh ↔ sample-run.md
#   P4  deny (linha 2, pergunta) ......... block-write.sh ↔ sample-run.md
#   P5  contrato injetado (steer) ........ prompt-steer.sh ↔ sample-run.md
#   P6  ativação do modo ................. toggle-mode.sh ↔ sample-run.md
#   P7  retorno de write-note ............ write-note.sh ↔ sample-run.md
#   P8  registro de fase ................. log-phase.sh ↔ sample-run.md
#   P9  instrução de retrieval (spacing) . spacing-start.sh ↔ spacing-read.sh
# (P2..P8 são as 7 citações verbatim que o sample-run.md — 6.1 — faz das mensagens
#  de runtime; P1/P2 amarram o contrato declarado ao contrato injetado a cada turno.)
#
# USO:
#   sh check-snapshot.sh            # CHECK: recomputa digests + convergência; rc=0 se tudo bate, rc!=0 com diff legível
#   sh check-snapshot.sh --update   # regrava SNAPSHOT.sha256 (mudança de contrato INTENCIONAL); roda convergência antes
#   sh check-snapshot.sh --help     # ajuda
#
# Códigos de saída: 0 = GREEN (sem drift). 1 = RED (drift de digest e/ou convergência).
#                   2 = erro de uso/ambiente (arquivo/diretório ausente).

set -eu

usage() {
  sed -n '2,50p' "$0"
  exit "${1:-0}"
}

# --- Resolução de diretórios (independe do cwd) -----------------------------
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || {
  printf '%s\n' "check-snapshot: não consegui resolver o diretório do script." >&2; exit 2; }
PLUGIN_DIR=$(CDPATH= cd -- "$SELF_DIR/../../plugins/kolb" && pwd) || {
  printf '%s\n' "check-snapshot: não encontrei o plugin em ../../plugins/kolb a partir de $SELF_DIR." >&2; exit 2; }
MANIFEST="$SELF_DIR/SNAPSHOT.sha256"

# --- Preflight de dependência (NFR12) ---------------------------------------
# sha256sum é a única dependência não-POSIX obrigatória (coreutils). Ausente ⇒
# erro de ambiente DOCUMENTADO (rc=2), não um rc=127 cru com saída pela metade.
# (Sem fallback p/ cksum/shasum: o manifesto é em formato sha256sum; trocar o
#  digest exigiria regravar o baseline e quebraria a auditoria por git diff.)
if ! command -v sha256sum >/dev/null 2>&1; then
  printf '%s\n' "check-snapshot: 'sha256sum' não encontrado no PATH (dependência obrigatória — coreutils). Em macOS: 'brew install coreutils' ou ajuste o PATH." >&2
  exit 2
fi

# --- (A) Lista FECHADA de superfícies digest-pinadas (rel. ao PLUGIN_DIR) ----
# Ordem fixa ⇒ manifesto determinístico. Sem espaços nos caminhos.
DIGEST_FILES="
CLAUDE.md
agents/tutor.md
skills/checkpoint/SKILL.md
skills/conceptualize/SKILL.md
skills/experiment/SKILL.md
skills/learn-mode/SKILL.md
skills/pdi-checkin/SKILL.md
skills/reflect/SKILL.md
templates/ac-note.md
templates/exit-log.md
templates/pdi.md
templates/sample-run.md
templates/sessions.jsonl
"

rc=0

# --- Helpers ----------------------------------------------------------------
# Computa os digests na ORDEM FIXA, caminhos relativos ao PLUGIN_DIR.
compute_digests() {
  ( cd "$PLUGIN_DIR" && for f in $DIGEST_FILES; do
      if [ ! -f "$f" ]; then
        printf 'MISSING  %s\n' "$f"
      else
        sha256sum "$f"
      fi
    done )
}

# assert_in <frase> <arquivo-rel-ao-plugin> [<arquivo> ...]
# A frase DEVE aparecer (literal, -F) em TODOS os arquivos. Falta ⇒ RED.
assert_in() {
  phrase=$1; shift
  for f in "$@"; do
    if [ ! -f "$PLUGIN_DIR/$f" ]; then
      printf 'CONVERGÊNCIA RED: arquivo ausente: %s\n' "$f" >&2
      rc=1; continue
    fi
    if ! grep -Fq -- "$phrase" "$PLUGIN_DIR/$f"; then
      printf 'CONVERGÊNCIA RED: frase canônica ausente em %s:\n   «%s»\n' "$f" "$phrase" >&2
      rc=1
    fi
  done
}

run_convergence() {
  # P1 — princípio #1: contrato declarado (CLAUDE.md) ↔ contrato injetado (steer)
  assert_in 'acelera o que não ensina e é proibida de remover o esforço que ensina' \
    CLAUDE.md scripts/prompt-steer.sh
  # P2 — princípio #2 ("não gera código"): declarado ↔ injetado ↔ transcrição
  assert_in 'a IA não gera código' \
    CLAUDE.md scripts/prompt-steer.sh templates/sample-run.md
  # P3 — deny linha 1 (bloqueio de geração) ↔ transcrição
  assert_in 'escrever o código é o seu esforço — eu oriento, não gero' \
    scripts/block-write.sh templates/sample-run.md
  # P4 — deny linha 2 (pergunta socrática) ↔ transcrição
  assert_in 'Qual é o primeiro passo da sua abordagem?' \
    scripts/block-write.sh templates/sample-run.md
  # P5 — contrato injetado (steer) ↔ transcrição
  assert_in 'ela dá dicas sobre a abordagem e avalia depois' \
    scripts/prompt-steer.sh templates/sample-run.md
  # P6 — ativação do modo ↔ transcrição
  assert_in 'Kolb: modo aprendizado ATIVADO nesta sessão.' \
    scripts/toggle-mode.sh templates/sample-run.md
  # P7 — retorno de write-note ↔ transcrição (prefixo invariante, antes do caminho)
  assert_in 'Kolb: nota AC criada em ' \
    scripts/write-note.sh templates/sample-run.md
  # P8 — registro de fase ↔ transcrição (sufixo invariante, após a fase)
  assert_in 'registrada no índice da sessão.' \
    scripts/log-phase.sh templates/sample-run.md
  # P9 — instrução de retrieval: os dois hooks de spacing convergem na mesma frase
  assert_in 'Antes de revelar qualquer conteúdo da nota, peça ao dev que tente lembrar e verbalize o que ainda sabe' \
    scripts/spacing-start.sh scripts/spacing-read.sh
}

# --- Modo --update ----------------------------------------------------------
case "${1:-}" in
  --help|-h)
    if [ "$#" -gt 1 ]; then
      printf 'check-snapshot: --help não aceita argumentos extras (%s).\n\n' "$2" >&2; usage 2
    fi
    usage 0 ;;
  --update)
    if [ "$#" -gt 1 ]; then
      printf 'check-snapshot: --update não aceita argumentos extras (%s) — recuso para não regravar o manifesto por engano.\n\n' "$2" >&2
      usage 2
    fi
    printf 'Convergência fonte↔cópia (pré-update):\n'
    run_convergence
    if [ "$rc" -ne 0 ]; then
      # Drift cruzado de mensagem socrática ⇒ NÃO abençoar um novo baseline.
      printf '\n✘ Há drift de CONVERGÊNCIA — manifesto NÃO regravado. Corrija as frases acima e rode --update de novo.\n' >&2
      exit "$rc"
    fi
    # Recusa abençoar um baseline com superfície ausente (senão MISSING==MISSING vira falso GREEN).
    _new=$(compute_digests)
    _miss=$(printf '%s\n' "$_new" | grep '^MISSING' || true)
    if [ -n "$_miss" ]; then
      printf '✘ Superfície(s) ausente(s) — manifesto NÃO regravado:\n' >&2
      printf '%s\n' "$_miss" >&2
      exit 2
    fi
    printf '%s\n' "$_new" > "$MANIFEST"
    printf '✔ Manifesto regravado: %s\n' "$MANIFEST"
    printf '  (revise o `git diff` do manifesto — ele É o registro auditável da mudança de contrato, NFR22.)\n'
    exit 0
    ;;
  '') : ;;
  *) printf 'check-snapshot: argumento desconhecido: %s\n\n' "$1" >&2; usage 2 ;;
esac

# --- Modo CHECK (default) ---------------------------------------------------
if [ ! -f "$MANIFEST" ]; then
  printf 'check-snapshot: manifesto ausente (%s). Rode `sh %s --update` para criar o baseline.\n' \
    "$MANIFEST" "$(basename "$0")" >&2
  exit 2
fi

printf '== (A) Digests das superfícies de documentação/template ==\n'
current=$(compute_digests)
stored=$(cat "$MANIFEST")
# Superfície ausente é SEMPRE RED — mesmo que o manifesto também a registre como
# MISSING (baseline herdado de um pacote incompleto): MISSING==MISSING não é GREEN.
missing=$(printf '%s\n' "$current" | grep '^MISSING' || true)
if [ -n "$missing" ]; then
  printf '✘ Superfície(s) digest-pinada(s) AUSENTE(S) do pacote:\n' >&2
  printf '%s\n' "$missing" >&2
  rc=1
fi
if [ "$current" = "$stored" ] && [ -z "$missing" ]; then
  printf '✔ %s superfícies digest-pinadas: sem drift.\n' "$(printf '%s\n' "$DIGEST_FILES" | grep -c .)"
elif [ "$current" != "$stored" ]; then
  printf '✘ DRIFT de digest (< esperado/manifesto, > atual):\n' >&2
  # diff legível via arquivos temporários (POSIX — sem process substitution).
  _tmpd=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/kolb-snap.$$")
  mkdir -p "$_tmpd" 2>/dev/null || true
  printf '%s\n' "$stored"  > "$_tmpd/stored"
  printf '%s\n' "$current" > "$_tmpd/current"
  diff "$_tmpd/stored" "$_tmpd/current" >&2 || true
  rm -rf "$_tmpd" 2>/dev/null || true
  printf '\nSe a mudança for INTENCIONAL, rode `sh %s --update` e commite o manifesto.\n' "$(basename "$0")" >&2
  rc=1
fi

printf '\n== (B) Convergência fonte↔cópia das mensagens socráticas ==\n'
run_convergence
if [ "$rc" -eq 0 ]; then
  printf '✔ 9 pares de drift cruzado (P1..P9): convergentes.\n'
fi

printf '\n'
if [ "$rc" -eq 0 ]; then
  printf 'GREEN — contrato e mensagens socráticas batem com o snapshot.\n'
else
  printf 'RED — drift detectado (ver acima).\n' >&2
fi
exit "$rc"
