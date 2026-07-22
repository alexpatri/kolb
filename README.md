# Kolb: modo aprendizado para o Claude Code

Kolb põe o Claude Code em **modo aprendizado**: em zonas que você declara, a IA
deixa de gerar código e passa a **orientar socraticamente e avaliar**, sob o
ciclo de Kolb (CE → RO → AC → AE). A premissa é inegociável: *a IA acelera o que
não ensina e é proibida de remover o esforço que ensina.* Em vez de entregar a
solução, ela dá dicas sobre como abordar o problema, força reflexão estruturada
e depois verifica se o código que **você** escreveu corresponde ao que você
entendeu — com um PDI leve, versionado em Markdown junto do código, organizando
objetivos e evidências de progresso.

Dois princípios fundadores governam tudo:

> **#1 — A IA acelera o que não ensina e é proibida de remover o esforço que ensina.**
>
> **#2 — Em modo aprendizado, a IA não gera código. Dá dicas sobre como escrever e avalia depois.**

## Para quem é

Para o desenvolvedor que usa IA intensamente e sente que **"não está aprendendo
nada"** — quer continuar evoluindo de verdade em zonas de aprendizado declaradas,
em vez de cair na **"ilusão de fluência"**. O
sentimento tem suporte empírico convergente: METR (jul/2025), Anthropic
(fev/2026) e Tian Pan (abr/2026) medem o mesmo fenômeno — delegar a geração
inteira corrói compreensão, retenção e a capacidade de reproduzir o que se
acabou de fazer. Kolb é o antídoto operacional para quem quer manter essa
capacidade afiada onde ela importa.

## Como começar

1. Adicione o marketplace e instale o plugin (no Claude Code):

   ```
   /plugin marketplace add alexpatri/ajs-market
   /plugin install kolb@ajs-market
   ```

   Não precisa clonar este repositório — o marketplace referencia o plugin
   diretamente daqui (`source: git-subdir`).

2. Ative o modo aprendizado na sessão:

   ```
   /kolb:learn-mode on
   ```

A partir daí, em modo aprendizado a IA orienta em vez de gerar, e você conduz o
ciclo com `/kolb:reflect` (refletir), `/kolb:conceptualize` (extrair um
conceito), `/kolb:experiment` (variação para resolver sozinho), além de
`/kolb:pdi-checkin` e `/kolb:checkpoint`.

> O passo-a-passo completo (pré-requisitos, verificação e o estado `.kolb/` que
> nasce automaticamente no 1º uso) está em
> [`plugin/kolb/INSTALL.md`](plugin/kolb/INSTALL.md). 
## Saiba mais

- **Como flui uma sessão** (transcrição CE → RO → AC → AE de exemplo):
  [`plugin/kolb/templates/sample-run.md`](plugin/kolb/templates/sample-run.md).
