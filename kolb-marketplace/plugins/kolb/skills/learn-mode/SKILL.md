---
description: Liga/desliga o modo aprendizado do Kolb nesta sessão. Acione com "/kolb:learn-mode on" para ativar ou "/kolb:learn-mode off" para desativar.
disable-model-invocation: true
allowed-tools: [Bash]
---

# /kolb:learn-mode

Liga ou desliga o **modo aprendizado** do Kolb para a sessão atual. O estado é
isolado por sessão: ativar aqui não afeta outras janelas do Claude Code.

Uso: `/kolb:learn-mode on` ou `/kolb:learn-mode off`.

## O que fazer

1. A ação vem do argumento do comando (`$ARGUMENTS`) e deve ser exatamente `on`
   ou `off`. Se vier vazia ou diferente, explique o uso acima e **não** execute
   nada.
2. Execute o toggle — a lógica determinística vive no script, não nesta prosa:

   ```sh
   "${CLAUDE_PLUGIN_ROOT}/scripts/toggle-mode.sh" "$ARGUMENTS"
   ```

3. Repasse ao usuário, em uma linha, a saída do script (ativado / desativado /
   já estava nesse estado).

Este comando é acionado **apenas pelo usuário**; nunca ligue ou desligue o modo
aprendizado por conta própria.
