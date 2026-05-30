---
description: Liga/desliga o modo aprendizado do Kolb nesta sessão. Acione com "/kolb:learn-mode on" para ativar ou "/kolb:learn-mode off \"<motivo>\"" para desativar com justificativa.
disable-model-invocation: true
allowed-tools: [Bash]
---

# /kolb:learn-mode

Liga ou desliga o **modo aprendizado** do Kolb para a sessão atual. O estado é
isolado por sessão: ativar aqui não afeta outras janelas do Claude Code.

Uso: `/kolb:learn-mode on` ou `/kolb:learn-mode off "<motivo de uma linha>"`.

## O que fazer

1. A ação vem do argumento do comando (`$ARGUMENTS`) e deve ser exatamente `on`
   ou `off`. Se vier vazia ou diferente, explique o uso acima e **não** execute
   nada.

2. **Ao ativar** (`on`) — invoque o script direto:

   ```sh
   "${CLAUDE_PLUGIN_ROOT}/scripts/toggle-mode.sh" "on"
   ```

3. **Ao desativar** (`off`) — a desativação **exige uma justificativa de uma
   linha** (rastro de erosão, FR2). Extraia o motivo do que o usuário escreveu
   após `off`. Se o usuário **não** informou um motivo, pergunte-o de forma curta
   ("Qual o motivo de sair do modo agora?") **antes** de prosseguir — não invente
   um motivo em nome dele. Com o motivo em mãos, invoque com **dois argumentos
   entre aspas** (a ação e o motivo como um único argumento):

   ```sh
   "${CLAUDE_PLUGIN_ROOT}/scripts/toggle-mode.sh" "off" "<motivo de uma linha>"
   ```

   O script é a garantia dura: sem motivo, o modo **permanece ativo** e nada é
   registrado.

4. Repasse ao usuário, em uma linha, a saída do script (ativado / desativado com
   motivo registrado / já estava nesse estado / motivo exigido).

Este comando é acionado **apenas pelo usuário**; nunca ligue ou desligue o modo
aprendizado por conta própria.
