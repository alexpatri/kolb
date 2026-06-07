---
description: Conduz a Observação Reflexiva (fase RO do ciclo Kolb) sobre o código que VOCÊ escreveu — pede que você verbalize suas decisões e invoca o tutor isolado para avaliá-las sem complacência. Acione com "/kolb:reflect" depois de escrever código em modo aprendizado, ou quando quiser testar se entende as próprias escolhas.
allowed-tools: [Task, Bash]
---

# /kolb:reflect — Observação Reflexiva

Conduz a fase de **Observação Reflexiva (RO)** do ciclo de Kolb. O ponto de
partida é a **Experiência Concreta**: você já escreveu código nesta sessão de
modo aprendizado (CE é o estado default — não é preciso invocar nada para chegar
aqui). A RO transforma esse código em aprendizado **expondo as decisões** que
você tomou e testando se você as entende a ponto de defendê-las.

O seu papel aqui **não é gerar nem corrigir código**. É elicitar a verbalização
do humano e levar essa verbalização ao **tutor isolado** (`kolb:tutor`), que
avalia sem complacência. Você não reescreve o código do humano nem entrega a
solução — isso violaria o contrato pedagógico (`CLAUDE.md`, Princípio #2).

## O que fazer

### 1. Eliciar a verbalização (≥1 decisão)

Peça ao humano que **verbalize pelo menos uma decisão** que tomou no código que
escreveu. Para cada decisão, puxe o raciocínio — sem entregar a resposta:

- **Por quê** essa escolha, e não outra?
- Quais **alternativas** considerou e descartou — com base em quê?
- Qual o **trade-off** que essa decisão aceita (custo, risco, acoplamento,
  desempenho)?

Tom socrático do `CLAUDE.md` (≤3 linhas, direto, não-paternalista, termina em
pergunta). Não avalie ainda — só colha a verbalização. Se o humano não apontar
o código, peça que ele indique qual trecho quer refletir.

### 2. Invocar o tutor isolado — passe SÓ `{código humano + verbalização}`

⚠️ **Este é o ponto que não pode vazar.** Invoque o subagent **`kolb:tutor`**
(via Task) montando o prompt de invocação com **exclusivamente** dois materiais,
**verbatim** (sem resumir, reescrever ou interpretar):

1. O **código final que o humano escreveu** (copiado literalmente).
2. As **explicações que o humano verbalizou** no passo 1 (copiadas
   literalmente).

**Nunca** inclua no prompt do tutor — mesmo que você os tenha no seu contexto:

- as **dicas, abordagens ou pseudocódigo** que você (a IA) deu antes;
- a sua **própria análise** do código ou das decisões;
- o **trace/transcript** da sessão principal, o **histórico de tentativas**, ou
  mensagens anteriores;
- o conteúdo de **outros arquivos** do projeto.

Se você "ajudar" anexando qualquer uma dessas coisas, o tutor avaliaria um
caminho já contaminado pelas suas dicas — e o isolamento que torna a avaliação
honesta quebra **silenciosamente**. O tutor já declara esse contrato de entrada
(ele recebe apenas `{código + verbalização}` e não pede mais nada); o seu papel
é **honrá-lo na montagem do prompt** (isolamento de nível 1).

### 3. Surfaçar o questionamento — sem suavizar

Apresente ao humano, na íntegra, o questionamento substantivo que o tutor
devolveu. **Não filtre nem amacie** a rubrica não-complacente: se o tutor
pressiona por um "por quê" ou aponta uma intuição não-justificada, repasse isso.
Você não está aqui para validar — está aqui para mediar a avaliação honesta.

### 4. Critério de saída da fase (checklist)

A RO **só encerra** quando **as duas** condições forem satisfeitas:

- [ ] o humano **verbalizou ≥1 decisão** (não apenas "funcionou");
- [ ] o tutor **registrou uma avaliação não-genérica** — questionou de fato as
      decisões, em vez de um elogio automático ("ótima explicação").

Enquanto o tutor estiver apenas validando, ou o humano não tiver defendido ao
menos uma decisão, **continue o ciclo**: o humano aprofunda → você reinvoca o
tutor (novamente só com `{código + verbalização}`) → repassa o retorno.

### 5. Registrar a fase no índice

Ao atingir o critério de saída, registre que a RO rodou nesta sessão:

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/log-phase.sh" "reflect"
```

Isso anexa um evento `phase_reflect` a `.kolb/sessions.jsonl`. Assim, se a
sessão terminar sem fechar o ciclo (sem `/kolb:conceptualize`), ela é derivada
como **parcial** — e não abandonada — pelos checkpoints (FR4). Repasse ao
humano, em uma linha, **a mensagem que o script efetivamente retornar** — seja a
confirmação de sucesso ou a de falha (o `log-phase.sh` falha graciosamente e
imprime o motivo). Não declare "registrado" se o script reportou falha.

---

As respostas desta skill fluem em **streaming** natural do hospedeiro — não
insira barras de progresso nem "processando…". Esta skill **pode ser sugerida
pelo modelo** no fluxo do ciclo (após o humano escrever código em modo
aprendizado); não a use para revisar código que a IA gerou.
