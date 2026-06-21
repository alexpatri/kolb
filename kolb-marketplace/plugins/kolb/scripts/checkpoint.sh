#!/usr/bin/env sh
# checkpoint.sh [--weeks 4|8] [--asof <epoch>] [--reimpl <n>] [--explain <n>]
#   checkpoint.sh — Deriver READ-ONLY determinístico do checkpoint Go/No-Go (5.2).
#
# Calcula os TRÊS sinais antecedentes do ciclo (sessões/semana, razão de commits
# autorais/assistidos, evidências novas no PDI), compara-os contra ALVOS HARDCODED
# (pré-comprometidos, prd.md:90-104), e emite um veredito categórico GO/NO-GO,
# além das flags de erosão (FR32) e de Goodhart (FR33). É o AGREGADOR que fecha o
# Epic 5: COMPÕE os derivers irmãos em vez de re-foldar o índice.
#
# Fronteira determinística (como session-status.sh/pdi-status.sh): este script só
# CALCULA e NARRA os números brutos + flags + veredito. NÃO formata relatório
# humano nem narra recomendações — isso é da skill /kolb:checkpoint (5.3), que
# consome esta saída SEM recálculo por LLM. Entrada idêntica ⇒ saída byte-a-byte
# idêntica (NFR7/AC#3).
#
# Determinismo & relógio (AC#3, Decisão #1): "agora" é um INPUT INJETÁVEL —
# precedência: --asof <epoch>  >  $KOLB_CHECKPOINT_NOW  >  date +%s (uma vez).
# "Entrada idêntica" inclui essa referência temporal; o smoke test a fixa p/ provar
# a igualdade. Precedente: KOLB_SPACING_DENY_TODAY em spacing-start.sh:25.
#
# Bucketização (Decisão #2): por DIA-CALENDÁRIO. Cada data (start de sessão,
# created de nota, ou committer-date de commit) é reduzida a um "dia desde a época"
# (inteiro) e agrupada em janelas de 7 dias relativas a `now`:
#   bucket 0 = [now-7d, now] ; bucket 1 = [now-14d, now-7d) ; ...
# Sessões/notas: a data ISO YYYY-MM-DD vira dia via fórmula civil (awk, sem date -d
# GNU/NFR12). Commits: %ct (epoch) ÷ 86400 = dia UTC. A deriva de tz nas bordas é
# ≤1 dia (single-user V1) — aceita e documentada.
#
# Deriver, não hook: SEM kolb_gate (invocado por skill explícita 5.3, não por hook).
# READ-ONLY: nunca escreve em .kolb/ nem em $CLAUDE_PLUGIN_ROOT; o único efeito
# colateral é kolb_log_error (best-effort). Usa mktemp p/ buffers, com trap.
#
# Falha graciosa (NFR8/NFR9): sessions.jsonl/notes/pdi ausentes ou parcialmente
# malformados ⇒ tratados como vazio, nunca quebra; jq ausente ⇒ erro legível via
# kolb_require_jq + exit 0. Todo caminho ⇒ exit 0.
#
# Tooling POSIX (NFR12): sh + jq + git + awk. Sem date -d, sem float, sem GNU-isms.
set -eu
# Determinismo (NFR7/AC#3): os `set -- $(...)` abaixo dependem do word-splitting padrão
# (space/tab/newline) p/ ler a saída das awk de bucketização. `unset IFS` garante o
# default mesmo se o ambiente exportar um IFS não-default (que zeraria as métricas).
unset IFS 2>/dev/null || IFS='
	 '

# --- Sourcing endurecido de _common.sh (idioma session-status.sh/pdi-status.sh):
# prioriza CLAUDE_PLUGIN_ROOT; cai para o dir deste script (execução direta/teste).
_kolb_self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
_kolb_common="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/_common.sh"
[ -f "$_kolb_common" ] || _kolb_common="$_kolb_self_dir/_common.sh"
# shellcheck source=/dev/null
. "$_kolb_common"

# O fold de sessões e a extração de commits[] exigem jq. Ausente ⇒ erro + exit 0.
kolb_require_jq || exit 0

# Caminho do deriver irmão session-status.sh (resolvido como ele resolve _common.sh).
# Ele NÃO é executável (modo 0644); invocamos via `sh` explicitamente.
_kolb_sstatus="${CLAUDE_PLUGIN_ROOT:-$_kolb_self_dir/..}/scripts/session-status.sh"
[ -f "$_kolb_sstatus" ] || _kolb_sstatus="$_kolb_self_dir/session-status.sh"

# ======================================================================
# ALVOS HARDCODED (FR31 — pré-comprometidos, imunes a ajuste oportunístico).
# Fonte canônica: prd.md:90-104 (Measurable Outcomes). NÃO exponha como flags.
# ======================================================================
# Alvos SEMANAIS (alerta de erosão FR32 + pass por semana):
S_WEEK=3            # sessões `complete` por semana                 (prd.md:93)
RATIO_NUM=4         # razão >= 0,4  <=>  autorais*10 >= assistidos*4 (prd.md:94)
RATIO_DEN=10
EV_WEEK=1           # evidências (notas AC criadas) por semana       (prd.md:95)
# Alvos CUMULATIVOS do checkpoint Go/No-Go (prd.md:100-104). A semana 4 canônica
# é >=8 sessões e >=4 evidências (razão >=0,4). Expresso como PISO POR SEMANA
# (8/4 = 2 sessões/sem; 4/4 = 1 evidência/sem) para valer em --weeks 4 e 8 sem
# fabricar números novos: S_GO = 2*weeks (8 @sem.4, 16 @sem.8);
# EV_GO = 1*weeks (4 @sem.4, 8 @sem.8). Razão cumulativa: o mesmo >=0,4.
S_GO_RATE=2
EV_GO_RATE=1
# Critério FINAL de usuário (NÃO mensurável pelo script — atestado humano via flag):
REIMPL_GO=1         # semana 4: >=1 reimplementação parcial bem-sucedida (prd.md:101)
EXPLAIN_GO=3        # semana 8: explicar 3 decisões sem reabrir código   (prd.md:102)

# ======================================================================
# Argumentos / contrato de invocação (5.3 depende deste contrato).
# ======================================================================
weeks=4             # janela do checkpoint em semanas (4|8); default 4
asof=""             # epoch injetável (--asof); precede KOLB_CHECKPOINT_NOW e o relógio
reimpl=""           # critério final atestado: nº de reimplementações (vazio = não informado)
explain=""          # critério final atestado: nº de explicações      (vazio = não informado)
while [ $# -gt 0 ]; do
  case "$1" in
    --weeks)   shift; weeks="${1:-}" ;;
    --weeks=*) weeks="${1#--weeks=}" ;;
    --asof)    shift; asof="${1:-}" ;;
    --asof=*)  asof="${1#--asof=}" ;;
    --reimpl)  shift; reimpl="${1:-}" ;;
    --reimpl=*) reimpl="${1#--reimpl=}" ;;
    --explain) shift; explain="${1:-}" ;;
    --explain=*) explain="${1#--explain=}" ;;
    *) kolb_log_error "checkpoint: argumento ignorado: $1" ;;
  esac
  # Shift guardado (idioma session-status.sh:62): o ramo de flag-com-valor pode ter
  # consumido o último token; um `shift` cru abortaria sob set -eu. Só desloca se há token.
  [ $# -gt 0 ] && shift
done

# Sanidade dos argumentos (falha graciosa: valor inválido ⇒ default/descartado).
# Contrato fixo 4|8 (whitelist): qualquer outro valor — vazio, não-numérico, fora do
# conjunto (5, 100, …) — cai p/ o default 4. Evita alvos não-documentados (S_GO/EV_GO
# escalam com weeks) e a troca silenciosa reimpl↔explain no limiar `weeks>=8`.
case "$weeks" in 4|8) ;; *) weeks=4 ;; esac
case "$asof" in *[!0-9]*) asof="" ;; esac        # não-numérico ⇒ ignora (cai p/ env/relógio)
case "$reimpl" in *[!0-9]*) reimpl="" ;; esac     # não-numérico ⇒ não informado
case "$explain" in *[!0-9]*) explain="" ;; esac

# Referência temporal `now` (epoch): --asof > KOLB_CHECKPOINT_NOW > date +%s.
now_epoch=""
if [ -n "$asof" ]; then
  now_epoch="$asof"
elif [ -n "${KOLB_CHECKPOINT_NOW:-}" ]; then
  case "$KOLB_CHECKPOINT_NOW" in
    ''|*[!0-9]*) now_epoch="" ;;
    *) now_epoch="$KOLB_CHECKPOINT_NOW" ;;
  esac
fi
if [ -z "$now_epoch" ]; then
  now_epoch=$(date +%s 2>/dev/null) || now_epoch=""
  case "$now_epoch" in ''|*[!0-9]*) kolb_log_error "checkpoint: relógio indisponível; now=0."; now_epoch=0 ;; esac
fi
# Dia-desde-época de `now` (UTC). epoch ÷ 86400 = dias desde 1970-01-01.
now_day=$(( now_epoch / 86400 ))

# Base de estado: fonte única CLAUDE_PROJECT_DIR. Ausente ⇒ saída "unknown" + exit 0
# (mesma disciplina de pdi-status.sh:40-45).
base="$(kolb_project_dir)"
if [ -z "$base" ]; then
  kolb_log_error "checkpoint: CLAUDE_PROJECT_DIR ausente; não foi possível derivar o checkpoint."
  printf 'checkpoint-week: %s\n' "$weeks"
  printf 'state: unknown\n'
  printf 'verdict: NO-GO\n'
  exit 0
fi
sessions="$base/.kolb/sessions.jsonl"
notes_dir="$base/.kolb/notes"

# Alvos cumulativos derivados da janela (piso por semana × weeks).
S_GO=$(( S_GO_RATE * weeks ))
EV_GO=$(( EV_GO_RATE * weeks ))

# ======================================================================
# Buffers temporários (read-only: só tmp, nunca .kolb/). trap garante limpeza.
# ======================================================================
authf=$(mktemp 2>/dev/null) || { kolb_log_error "checkpoint: mktemp falhou."; exit 0; }
gitf=$(mktemp 2>/dev/null) || { rm -f "$authf"; kolb_log_error "checkpoint: mktemp falhou."; exit 0; }
trap 'rm -f "$authf" "$gitf"' EXIT INT TERM

# Programa awk de bucketização dia-calendário (reusado p/ sessões e notas). Lê uma
# data ISO (YYYY-MM-DD...) por linha; emite "cumulativo w0 w1" na janela de N semanas.
# dfc(): dias desde 1970-01-01 a partir de (ano,mês,dia) — algoritmo civil de
# Howard Hinnant, aritmética inteira pura (sem date -d). Datas futuras (diff<0) e
# linhas não-data são ignoradas.
BUCKET_AWK='
function dfc(y,m,d,  era,yoe,doy,doe){
  if (m<=2) y--;
  era = int((y>=0?y:y-399)/400);
  yoe = y - era*400;
  doy = int((153*(m>2?m-3:m+9)+2)/5) + d - 1;
  doe = yoe*365 + int(yoe/4) - int(yoe/100) + doy;
  return era*146097 + doe - 719468;
}
/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
  y=substr($0,1,4)+0; m=substr($0,6,2)+0; d=substr($0,9,2)+0;
  dn=dfc(y,m,d); diff=nowd-dn;
  if (diff<0) next;
  b=int(diff/7);
  if (b<N) cum++;
  if (b==0) w0++;
  if (b==1) w1++;
}
END { printf "%d %d %d\n", cum+0, w0+0, w1+0 }
'

# ======================================================================
# Coleta via session-status.sh (NÃO re-foldar — fronteira determinística 1.4).
#   complete_dates : start[0:10] das sessões status=="complete" (FR4) — sinal sessões.
#   authored SHAs  : união de commits[] de TODAS as sessões de modo (Decisão #3:
#                    a autoria ocorreu no ato do commit; FR4 corta só sessões/semana).
# ======================================================================
ss=""
if [ -f "$sessions" ]; then
  ss=$(sh "$_kolb_sstatus" "$sessions" 2>/dev/null) || ss=""
fi

complete_dates=""
if [ -n "$ss" ]; then
  complete_dates=$(printf '%s\n' "$ss" | jq -r 'select(.status=="complete") | .start[0:10]' 2>/dev/null) || complete_dates=""
  # Autorais: union dedup dos SHAs. notes -> arquivo p/ a awk de razão.
  printf '%s\n' "$ss" | jq -r '.commits[]? // empty' 2>/dev/null | LC_ALL=C sort -u > "$authf" || : > "$authf"
fi

# Sinal SESSÕES: cumulativo + w0/w1 (descartando partial/abandoned via filtro acima).
set -- $(printf '%s\n' "$complete_dates" | awk -v nowd="$now_day" -v N="$weeks" "$BUCKET_AWK")
sess_cum=${1:-0}; sess_w0=${2:-0}; sess_w1=${3:-0}

# ======================================================================
# Sinal RAZÃO: git log %H %ct vs. conjunto de autorais. Assistidos = total − autorais
# (NFR20). Bucketização por %ct/86400 (dia UTC). Cumulativo + w0/w1 p/ erosão.
# ======================================================================
gitout=$(git -C "$base" log --format='%H %ct' 2>/dev/null) || gitout=""
printf '%s\n' "$gitout" | grep -E '^[0-9a-f]+ [0-9]+$' > "$gitf" 2>/dev/null || : > "$gitf"

# awk de razão: 1º arg = authf (conjunto de autorais por FILENAME); 2º = gitf.
# Emite "acum scum aw0 sw0 aw1 sw1" (a=autorais, s=assistidos).
set -- $(awk -v nowd="$now_day" -v N="$weeks" -v af="$authf" '
  FILENAME==af { auth[$1]=1; next }
  {
    sha=$1; ct=$2+0;
    dn=int(ct/86400); diff=nowd-dn;
    if (diff<0) next;
    b=int(diff/7);
    isa=(sha in auth)?1:0;
    if (b<N) { if (isa) acum++; else scum++ }
    if (b==0) { if (isa) aw0++; else sw0++ }
    if (b==1) { if (isa) aw1++; else sw1++ }
  }
  END { printf "%d %d %d %d %d %d\n", acum+0,scum+0, aw0+0,sw0+0, aw1+0,sw1+0 }
' "$authf" "$gitf")
ratio_acum=${1:-0}; ratio_scum=${2:-0}
ratio_aw0=${3:-0}; ratio_sw0=${4:-0}; ratio_aw1=${5:-0}; ratio_sw1=${6:-0}

# ======================================================================
# Sinal EVIDÊNCIAS: notas AC (.kolb/notes/*.md) cujo `created` cai na janela
# (Decisão #4). Scan do frontmatter por awk (sem jq no YAML; idioma pdi-status.sh).
# ======================================================================
created_dates=""
if [ -d "$notes_dir" ]; then
  for nf in "$notes_dir"/*.md; do
    [ -e "$nf" ] || continue
    c=$(awk '
      /^---[[:space:]]*$/ { fm++; if (fm==2) exit; next }
      fm==1 && /^created:/ {
        v=$0; sub(/^created:[[:space:]]*/,"",v);
        sub(/^"/,"",v); sub(/"[[:space:]]*$/,"",v); sub(/[[:space:]]+$/,"",v);
        print v; exit
      }
    ' "$nf" 2>/dev/null) || c=""
    [ -n "$c" ] && created_dates="${created_dates}${c}
"
  done
fi
set -- $(printf '%s\n' "$created_dates" | awk -v nowd="$now_day" -v N="$weeks" "$BUCKET_AWK")
ev_cum=${1:-0}; ev_w0=${2:-0}; ev_w1=${3:-0}

# ======================================================================
# Razão: comparação por aritmética inteira (sem float) + display + div-por-zero.
# ======================================================================
# ratio_cmp <autorais> <assistidos> -> imprime pass|fail|na (na = sem commits).
ratio_cmp() {
  if [ "$2" -eq 0 ]; then
    if [ "$1" -gt 0 ]; then printf pass; else printf na; fi
  elif [ $(( $1 * RATIO_DEN )) -ge $(( $2 * RATIO_NUM )) ]; then
    printf pass
  else
    printf fail
  fi
}
# ratio_disp <autorais> <assistidos> -> string de exibição (cosmética; o veredito é inteiro).
ratio_disp() {
  if [ "$2" -eq 0 ]; then
    if [ "$1" -gt 0 ]; then printf 'inf'; else printf 'n/a'; fi
  else
    _h=$(( ($1 * 1000 / $2 + 5) / 10 ))   # centésimos arredondados
    printf '%d.%02d' $(( _h / 100 )) $(( _h % 100 ))
  fi
}

ratio_cum_status=$(ratio_cmp "$ratio_acum" "$ratio_scum")
ratio_cum_disp=$(ratio_disp "$ratio_acum" "$ratio_scum")
ratio_w0_status=$(ratio_cmp "$ratio_aw0" "$ratio_sw0")
ratio_w1_status=$(ratio_cmp "$ratio_aw1" "$ratio_sw1")

# Pass por sinal (cumulativo, p/ o veredito GO/NO-GO).
[ "$sess_cum" -ge "$S_GO" ] && sess_pass=true || sess_pass=false
[ "$ratio_cum_status" = "pass" ] && ratio_pass=true || ratio_pass=false
[ "$ev_cum" -ge "$EV_GO" ] && ev_pass=true || ev_pass=false

# Antecedentes "bons" = os três sinais cumulativos passam (base do veredito + Goodhart).
if [ "$sess_pass" = "true" ] && [ "$ratio_pass" = "true" ] && [ "$ev_pass" = "true" ]; then
  antecedent_good=true
else
  antecedent_good=false
fi

# ======================================================================
# Flag de EROSÃO (FR32): métrica abaixo do alvo SEMANAL em w0 E w1 (2 semanas
# consecutivas). Razão: "abaixo" = não-pass (na conta como abaixo — duas semanas
# sem qualquer commit é erosão, conservador).
# ======================================================================
erosion_metrics=""
if [ "$sess_w0" -lt "$S_WEEK" ] && [ "$sess_w1" -lt "$S_WEEK" ]; then
  erosion_metrics="${erosion_metrics}sessions "
fi
if [ "$ratio_w0_status" != "pass" ] && [ "$ratio_w1_status" != "pass" ]; then
  erosion_metrics="${erosion_metrics}ratio "
fi
if [ "$ev_w0" -lt "$EV_WEEK" ] && [ "$ev_w1" -lt "$EV_WEEK" ]; then
  erosion_metrics="${erosion_metrics}evidence "
fi
erosion_metrics=${erosion_metrics% }
[ -n "$erosion_metrics" ] && erosion_alert=true || erosion_alert=false

# ======================================================================
# Critério FINAL atestado + flag de GOODHART (FR33, Decisão #5).
# A semana do checkpoint seleciona o critério: <8 sem ⇒ reimplementação; >=8 ⇒ explicação.
# "provided"  = a flag relevante foi informada (atestado humano presente).
# "satisfied" = o atestado atinge o piso (reimpl>=REIMPL_GO / explain>=EXPLAIN_GO).
# Goodhart (só quando provided): antecedentes bons + final NÃO satisfeito, OU
# antecedentes ruins + final satisfeito ⇒ true. Caso contrário false.
# Não informado ⇒ inconclusive (nunca fabrica — Decisão #5; reconcilia AC#5: "ausente"
# ali = atestado-como-não-atingido [ex.: --reimpl 0], distinto de flag omitida).
# ======================================================================
if [ "$weeks" -ge 8 ]; then
  final_n="$explain"; final_go="$EXPLAIN_GO"
else
  final_n="$reimpl"; final_go="$REIMPL_GO"
fi

if [ -z "$final_n" ]; then
  final_criterion=absent
  final_satisfied="n/a"
  goodhart=inconclusive
else
  final_criterion=provided
  if [ "$final_n" -ge "$final_go" ]; then final_satisfied=true; else final_satisfied=false; fi
  if { [ "$antecedent_good" = "true" ] && [ "$final_satisfied" = "false" ]; } \
     || { [ "$antecedent_good" = "false" ] && [ "$final_satisfied" = "true" ]; }; then
    goodhart=true
  else
    goodhart=false
  fi
fi

# ======================================================================
# VEREDITO GO/NO-GO (FR31): GO sse antecedentes bons E (final ausente OU satisfeito).
# Critério final ausente ⇒ veredito sobre os antecedentes (Decisão #5).
# ======================================================================
if [ "$antecedent_good" = "true" ] && { [ "$final_criterion" = "absent" ] || [ "$final_satisfied" = "true" ]; }; then
  verdict=GO
else
  verdict=NO-GO
fi

# ======================================================================
# SAÍDA estável, parseável (AC#7): uma chave por linha. Sem prosa/recomendação/emoji
# — a skill 5.3 narra. Ordem fixa ⇒ determinística.
# ======================================================================
printf 'checkpoint-week: %s\n' "$weeks"
printf 'now-epoch: %s\n' "$now_epoch"
printf 'sessions: %s | target: %s | pass: %s\n' "$sess_cum" "$S_GO" "$sess_pass"
printf 'ratio: %s | authored: %s | assisted: %s | target: 0.%s | pass: %s\n' \
  "$ratio_cum_disp" "$ratio_acum" "$ratio_scum" "$(( RATIO_NUM * 10 / RATIO_DEN ))" "$ratio_pass"
printf 'evidence: %s | target: %s | pass: %s\n' "$ev_cum" "$EV_GO" "$ev_pass"
printf 'erosion-alert: %s\n' "$erosion_alert"
printf 'erosion-metrics: %s\n' "$erosion_metrics"
printf 'final-criterion: %s\n' "$final_criterion"
printf 'final-satisfied: %s\n' "$final_satisfied"
printf 'goodhart: %s\n' "$goodhart"
printf 'verdict: %s\n' "$verdict"

exit 0
