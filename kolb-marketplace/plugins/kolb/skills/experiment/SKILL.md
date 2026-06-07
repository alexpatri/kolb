---
description: Conduz a Experimentação Ativa (fase AE do ciclo Kolb) — propõe uma variação não-trivial do problema que você acabou de resolver, para você resolver SEM ajuda da IA e consolidar o aprendizado por transferência. Acione com "/kolb:experiment" depois de refletir/conceituar sobre o código que você escreveu em modo aprendizado.
allowed-tools: [Bash]
---

# /kolb:experiment — Experimentação Ativa (variação não-trivial)

Conduz a fase de **Active Experimentation (AE)** do ciclo de Kolb — a última fase
(CE→RO→AC→**AE**). Vem **depois** de você ter refletido (`/kolb:reflect`) e
destilado um conceito (`/kolb:conceptualize`). Aqui o aprendizado se **consolida
por transferência**: você pega o conceito e o aplica a um **contexto novo**,
resolvendo uma variação do problema **por conta própria**.

O seu papel aqui **não é resolver nem esboçar a solução**. É **propor uma
variação não-trivial** e então **parar** — devolver o problema para o humano
resolver **sem a IA**. Explicar o **conceito** e o **eixo** da variação é
permitido (é conteúdo conceitual — `CLAUDE.md`, "o conceitual continua
fluindo"). **Esboçar a solução, dar o passo a passo da implementação ou gerar
código da variação não é** — isso destruiria o propósito da AE.

> ⚠️ **Quem resolve a variação é o humano, sem IA.** Se você "ajudar" entregando
> o caminho da solução, anula a transferência ativa (o que de fato consolida o
> aprendizado — `docs/aprendizado-com-ia-fundamentos.md`). Proponha e saia da
> frente.

## O que fazer

### 1. Identificar o problema recém-resolvido

A partir do contexto desta sessão (a Experiência Concreta — o código que o humano
escreveu, e a reflexão/conceito que vieram depois), identifique **qual** foi o
problema resolvido e **qual** conceito ele exercitou. É sobre esse conceito que a
variação vai transferir. Se não estiver claro, pergunte em uma linha qual problema
o humano quer variar — e aguarde a resposta antes de propor a variação.

### 2. Propor UMA variação não-trivial

Proponha **uma** variação **concreta** que mude **≥1 dimensão** do problema
original — não uma repetição com nomes trocados. Eixos de variação típicos
(`architecture.md:207`):

- **Novo provedor / IdP / serviço** — mesmo conceito, outro integrante.
- **Novo tipo de entrada** — outra forma/origem/formato dos dados.
- **Restrição adicional** — tempo, memória, concorrência, tamanho de entrada,
  ausência de uma facilidade que antes existia.

Diga **qual dimensão** muda e **por que** isso força o conceito a um terreno
novo. Tom socrático do `CLAUDE.md` (≤3 linhas, termina em pergunta ou prompt de
ação).

### 3. Critério de "não-trivial" (checklist)

A variação **só** vale como experimento quando **as três** condições valem:

- [ ] muda **≥1 dimensão** identificável do original (e você nomeou qual);
- [ ] **não** é uma repetição — não o mesmo exercício com rótulos trocados
      (mesma dimensão, outro nome);
- [ ] é **resolvível** pelo humano com o que ele acabou de aprender — transfere o
      conceito, não introduz um problema desconexo nem exige um pré-requisito novo.

Enquanto não, **reformule** a variação antes de apresentá-la como o experimento.
(Ex.: "faça igual, mas em outra linguagem" muda dimensão, mas costuma ser trivial
— procure uma variação que force a **adaptar** o conceito, não só transcrevê-lo.)

### 4. Pedir a resolução — sem IA

Peça explicitamente que o humano **resolva a variação sem assistência da IA**. O
esforço de raciocinar e codificar é o que ensina (Princípio #1 do `CLAUDE.md`) —
e permanece com ele.

Lembre, em uma linha, que **enquanto o modo aprendizado estiver ativo** a IA
continua **sem gerar código**: o bloqueio de `Write`/`Edit`/`NotebookEdit` e a
reorientação anti-cola seguem valendo (são os hooks do modo, não algo desta
skill). **Não** desligue o modo nem sugira desligá-lo para resolver — isso
removeria justamente a fricção que faz a AE valer. Você pode tirar dúvidas
**conceituais**; não entrega a solução.

### 5. Registrar a fase no índice

Depois de apresentar a variação e ela passar no checklist (passo 3), registre que
a AE rodou nesta sessão:

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/log-phase.sh" "experiment"
```

Isso anexa um evento `phase_experiment` a `.kolb/sessions.jsonl`. (A AE se resolve
**offline, sem IA** — então este evento marca que a fase foi **proposta/alcançada**
nesta sessão, não que você terminou o exercício.) O `phase_experiment` **não**
muda o status de uma sessão que já fechou o ciclo na AC: `phase_conceptualize`
continua sendo o que deriva **`complete`**.

Repasse ao humano, em uma linha, **a mensagem que o script efetivamente retornar**
— seja a confirmação de sucesso ou a de falha (o `log-phase.sh` falha
graciosamente e imprime o motivo). **Não** declare "registrado" se o script
reportou falha.

---

As respostas desta skill fluem em **streaming** natural do hospedeiro — não insira
barras de progresso nem "processando…". Esta skill **pode ser sugerida pelo
modelo** no fluxo do ciclo (depois da `/kolb:conceptualize`); ela **não** chama o
tutor (isso é da RO), **não** grava nota (isso é da AC) e **não** resolve nem gera
o código da variação — só propõe e devolve o problema para o humano.
