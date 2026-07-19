#!/usr/bin/env sh
# _common.sh — Helpers compartilhados do Kolb + guard de gating barato.
#
# É sourçado por todos os scripts e hooks do plugin. Fornece a fundação de
# resolução de estado, timestamp, log de erro e o GUARD universal de gating.
#
# Regras invioláveis:
#   - NUNCA escreve estado em $CLAUDE_PLUGIN_ROOT (read-only, efêmero).
#   - Caminho "modo off" do guard é barato: sem jq, ~1 stat de arquivo (NFR5).
#   - Falha graciosa: ausência de arquivo nunca é erro; quem chama decide o exit.

# Resolve o diretório de estado durável do projeto (.kolb/ vive aqui).
# FONTE PRIMÁRIA: CLAUDE_PROJECT_DIR — o harness do Claude Code a injeta ao rodar
# HOOKS (hot-path). Numa SKILL o harness NÃO injeta CLAUDE_PROJECT_DIR (só
# CLAUDE_PLUGIN_ROOT e CLAUDE_CODE_SESSION_ID); por isso o fallback
# `git rev-parse --show-toplevel` resolve a MESMA base nas skills (cold-path) —
# no caso normal o toplevel do git == CLAUDE_PROJECT_DIR. NFR5 preservado: em hook
# a env var está SEMPRE presente ⇒ o ramo git NUNCA dispara no hot-path (kolb_gate).
# Fora de um repo git ⇒ último recurso `pwd` (o CWD do Bash de skill == dir de
# lançamento == CLAUDE_PROJECT_DIR no caso normal), cobrindo projetos não-versionados.
kolb_project_dir() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"
  else
    git rev-parse --show-toplevel 2>/dev/null || pwd
  fi
}

# Timestamp ISO 8601 com timezone (NFR19). `date +%z` emite o offset SEM dois-pontos
# (`-0300`) em GNU e BSD; o sed insere o `:` antes dos 2 últimos dígitos para produzir
# o formato RFC 3339 com colon (`-03:00`), consistente com os templates e o exit-log.
kolb_ts() {
  date +%Y-%m-%dT%H:%M:%S%z | sed 's/\([0-9][0-9]\)$/:\1/'
}

# slugify(topic) determinístico (AR-Naming): recebe o título em $1 e emite o slug
# usado como nome de arquivo da nota AC (.kolb/notes/<slug>.md). Regra: minúsculas,
# runs de qualquer caractere fora de [a-z0-9] viram um único '-', com '-' das pontas
# aparados. O mesmo tópico gera SEMPRE o mesmo slug (evita notas duplicadas).
# Saída VAZIA quando o título não tem nenhum [a-z0-9] ASCII (ex.: "!!!") — quem
# chama (write-note.sh) trata com falha graciosa, sem criar arquivo espúrio.
# Newline/CR no título são normalizados para espaço ANTES do sed (que é orientado
# a linha — sua classe [^a-z0-9] não casa \n, então um título multilinha vazaria o
# newline para dentro do slug/nome de arquivo); assim o run vira um único '-'.
# Limitação documentada (deferida, cross-cutting): acentos não são transliterados
# (á⇒'-'), pois iconv não é POSIX garantido (NFR12); e os ranges de bracket são
# sensíveis a locale por POSIX — o endurecimento LC_ALL=C fica deferido junto com
# os guards de charset dos scripts irmãos (toggle-mode.sh/log-phase.sh).
kolb_slugify() {
  printf '%s' "${1:-}" | tr '\n\r' '  ' | tr '[:upper:]' '[:lower:]' | \
    sed -e 's/[^a-z0-9][^a-z0-9]*/-/g' -e 's/^-//' -e 's/-$//'
}

# Registra uma mensagem de erro em .kolb/runtime/hook-errors.log e NUNCA propaga
# falha (NFR9). Argumentos: a mensagem de erro. Se o log não puder ser gravado
# (base ausente ou FS não-gravável — exatamente os casos que o script deve
# sobreviver), cai para stderr em vez de perder o diagnóstico silenciosamente.
kolb_log_error() {
  _kolb_base="$(kolb_project_dir)"
  if [ -n "$_kolb_base" ]; then
    _kolb_rt="$_kolb_base/.kolb/runtime"
    if mkdir -p "$_kolb_rt" 2>/dev/null && \
       printf '%s | %s\n' "$(kolb_ts)" "$*" >> "$_kolb_rt/hook-errors.log" 2>/dev/null; then
      return 0
    fi
  fi
  printf 'Kolb [erro]: %s\n' "$*" >&2 2>/dev/null || true
  return 0
}

# Extrai o session_id de um JSON de stdin SEM jq (fast-path, NFR5). Lê de stdin.
# `tr` quebra o JSON compacto em 1 token por linha (evita o `.*` greedy casar a
# ÚLTIMA chave "session_id" de uma linha com várias); o charset restrito
# [0-9A-Za-z-] (UUID v4) nunca emite barra/aspas/newline para path ou JSON; e
# `head -n 1` garante somente a 1ª ocorrência.
kolb_session_id_from_stdin() {
  tr ',{}' '\n' | \
    sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([0-9A-Za-z-]*\)".*/\1/p' | \
    head -n 1
}

# GUARD universal de gating. Recebe o JSON bruto do stdin do hook como $1.
# Em modo OFF (flag ausente) faz `exit 0` — passthrough barato, sem jq.
# Esta deve ser a 1ª lógica de todo hook futuro.
kolb_gate() {
  _kolb_sid=$(printf '%s' "$1" | kolb_session_id_from_stdin)
  [ -n "$_kolb_sid" ] && [ -f "$(kolb_project_dir)/.kolb/runtime/mode-$_kolb_sid" ] || exit 0
}

# Garante a presença de jq para o caminho de modo ativo. Se ausente, loga um
# erro legível e retorna não-zero (NFR12) — sem quebrar o hospedeiro.
kolb_require_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  kolb_log_error "jq não encontrado: instale 'jq' para os recursos de modo ativo do Kolb."
  printf '%s\n' "Kolb: 'jq' não está instalado; recursos do modo ativo ficam indisponíveis." >&2
  return 1
}
