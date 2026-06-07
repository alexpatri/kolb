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
# FONTE ÚNICA: CLAUDE_PROJECT_DIR (garantido em hooks; herdado do ambiente do
# Claude Code numa skill). Sem fallback git/pwd — assim o guard não dispara
# subprocesso no hot-path (NFR5) e skill e hook resolvem SEMPRE a mesma base
# (evita que o flag escrito pela skill caia num .kolb/ que o hook não checa).
# Ausente ⇒ string vazia; quem chama trata com falha graciosa.
kolb_project_dir() {
  printf '%s' "${CLAUDE_PROJECT_DIR:-}"
}

# Timestamp ISO 8601 com timezone (NFR19). `date +%z` emite o offset SEM dois-pontos
# (`-0300`) em GNU e BSD; o sed insere o `:` antes dos 2 últimos dígitos para produzir
# o formato RFC 3339 com colon (`-03:00`), consistente com os templates e o exit-log.
kolb_ts() {
  date +%Y-%m-%dT%H:%M:%S%z | sed 's/\([0-9][0-9]\)$/:\1/'
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
