---
description: Roda o checkpoint Go/No-Go por janela (4 ou 8 semanas) e NARRA o resultado do checkpoint.sh — sinais vs. alvos, veredito categórico e recomendações (retrospectiva na erosão, divergência de Goodhart). Acione com "/kolb:checkpoint 4" ou "/kolb:checkpoint 8". Só-humana — o modelo não roda checkpoint por conta própria.
disable-model-invocation: true
allowed-tools: [Bash]
---

# /kolb:checkpoint — Checkpoint Go/No-Go (narrativa)

Roda o **checkpoint Go/No-Go** do ciclo de aprendizado por uma janela fixa (**4**
ou **8** semanas) e **narra** o resultado. O propósito do checkpoint é ser **imune
a racionalização**: o veredito é pré-comprometido contra alvos fixos, para você
decidir Go/No-Go **sem ajustar os critérios depois de ver os dados**.

> ⚠️ **O seu papel aqui é narrar, NUNCA recalcular.** Todos os números, as flags
> (erosão / Goodhart) e o veredito Go/No-Go vêm **inteiros** do `checkpoint.sh` —
> comparação determinística por aritmética inteira contra alvos hardcoded. Você é
> uma **camada de apresentação fina**: lê as chaves do script e as traduz para
> prosa legível. **Regra dura:** se a sua aritmética divergir da saída do script,
> **o script vence** — você não tem permissão de "corrigir", suavizar nem reabrir
> nada. Recalcular ou ajustar o veredito reintroduz exatamente o viés de Goodhart
> que este checkpoint existe para eliminar.

Esta skill é **só-humana** (`disable-model-invocation: true`): o modelo **não**
roda o checkpoint por conta própria — decisões Go/No-Go pré-comprometidas são do
humano.

## O que fazer

### 1. Resolver a janela (4 ou 8 semanas)

A janela vem do argumento do comando (`$ARGUMENTS`). **Normalize** primeiro —
apare espaços e tokens extras — e aceite **exatamente** `4` ou `8`. Se vier
**vazia**, **diferente** de `{4, 8}` (incluindo `08`, `4 ...` com sobra, etc.),
pergunte em **uma** linha socrática — "Checkpoint de 4 ou 8 semanas?" — e
**aguarde** a resposta. **Revalide** essa resposta do mesmo modo (só `4` ou `8`);
se ainda não for válida, repergunte — **não** assuma um default silencioso nem
deixe um valor inválido escapar para o script (que faria fallback **silencioso** a
4, divergindo do que você confirmou). A janela é parte do pré-comprometimento.

### 2. Eliciar o critério final atestado (humano) — sem fabricar

O `checkpoint.sh` **não mede** o critério final de usuário; ele é um **atestado
humano**. Antes de rodar, pergunte **uma** linha, conforme a janela:

- **Janela < 8 semanas** → "Quantas reimplementações parciais bem-sucedidas você
  fez?"
- **Janela ≥ 8 semanas** → "Quantas decisões você explicou sem reabrir o código?"

Repasse o **valor inteiro** atestado ao script — "verbatim" aqui significa o
número que o humano disse, **não** texto livre:

- O atestado deve ser um **inteiro não-negativo** (`0`, `1`, `2`, …). Se a resposta
  não for um inteiro simples (ex.: "umas três", `0; rm`, vazio com lixo),
  **repergunte** uma linha — **não** passe texto bruto à linha de comando do shell.
- Janela `4` → `--reimpl <n>` · Janela `8` → `--explain <n>`.
- Atestado-como-**zero** ⇒ `--reimpl 0` / `--explain 0` (≠ omitir a flag).
- Se o humano **não souber ou recusar** ⇒ **omita** a flag (o script emite
  `goodhart: inconclusive`).

> 🚫 **NUNCA fabrique nem estime esse número.** Você só **coleta** o atestado do
> humano e o passa ao script — quem decide é o script. Inventar o número seria
> recálculo do critério final pelo LLM (viola o papel "narrar, não recalcular").

### 3. Invocar o `checkpoint.sh` (sem alteração)

Rode o deriver com a janela resolvida e, se houver atestado, a flag do critério
final:

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/checkpoint.sh" --weeks <4|8> [--reimpl <n> | --explain <n>]
```

- **NÃO** passe `--asof` — em produção o checkpoint usa o **relógio real**.
- **NÃO** reimplemente nenhum cálculo do script.

No **caminho feliz**, a saída é **chave-por-linha**, ordem fixa, sem prosa:

```
checkpoint-week: <4|8>
now-epoch: <epoch>
sessions: <cum> | target: <S_GO> | pass: <true|false>
ratio: <disp> | authored: <a> | assisted: <s> | target: 0.<n> | pass: <true|false>
evidence: <cum> | target: <EV_GO> | pass: <true|false>
erosion-alert: <true|false>
erosion-metrics: <"sessions ratio evidence" | vazio>
final-criterion: <absent|provided>
final-satisfied: <true|false|n/a>
goodhart: <true|false|inconclusive>
verdict: <GO|NO-GO>
```

**Caminho degradado (`state: unknown`) — saída curta de 3 linhas.** Se
`CLAUDE_PROJECT_DIR` não puder ser localizado, o script emite apenas:

```
checkpoint-week: <4|8>
state: unknown
verdict: NO-GO
```

Ao ver **`state: unknown`**, diga em **uma** linha que **não há como derivar o
checkpoint** e **pare**. Aqui `state: unknown` **vence** o `verdict:`: **ignore** o
`verdict: NO-GO` desta saída curta — ele é um placeholder, **não** um veredito a
narrar. Não invente números nem relate um Go/No-Go.

**Saída ausente ou inesperada — pare honestamente.** Se o stdout vier **vazio**,
sem as chaves esperadas, ou o script **falhar** (ex.: `jq` ausente ⇒ a mensagem vai
só para o stderr e o stdout fica vazio; `CLAUDE_PLUGIN_ROOT` não resolvido; exit
≠ 0), diga em uma linha que o checkpoint **não pôde rodar** (nomeando a causa
provável, se visível no stderr) e **pare**. **Nunca** narre sinais ou veredito a
partir de saída ausente — sem as chaves do script, não há o que narrar.

### 4. Narrar o relatório (a partir das chaves do script)

Esta seção vale **só no caminho feliz** (saída completa de 11 chaves). Se você
parou no passo 3 por `state: unknown` ou saída ausente, **não** execute o passo 4.

Renderize um relatório legível — pode ser uma tabela/lista — onde, para **cada
sinal**, você mostra **valor vs. alvo** e **pass/fail** exatamente como o script
emitiu:

- **`sessions`** — sessões `complete` na janela vs. alvo (`target`).
- **`ratio`** — razão autorais/assistidos. Use `authored`/`assisted` e o `pass`;
  o `<disp>` (ex.: `0,47`, `inf`, `n/a`) é **cosmético** — **o veredito do sinal é
  o `pass`**, não o display.
- **`evidence`** — notas AC criadas na janela vs. alvo.

Depois exiba o **`verdict:`** (`GO` / `NO-GO`) de forma **categórica**:

- **Não** suavize um `NO-GO`, não console, não racionalize, **não** recompute
  `pass` nem `verdict`. Havendo divergência entre a sua conta e o script, **o
  script vence**.
- Em **`NO-GO`**: relate o veredito direto e **devolva a bola** — "o que você
  ajusta na próxima semana?". **Não** reabra nem afrouxe o critério (anti-Goodhart
  é o propósito).
- Em **`GO`**: confirme o veredito sem inflar; aponte o que sustentou os sinais.

### 5. Recomendações condicionais às flags

Some à narração, **só quando a flag estiver ligada**, as recomendações abaixo —
em tom socrático do `CLAUDE.md` (≤3 linhas cada, terminando em pergunta ou prompt
de ação):

- **`erosion-alert: true`** → recomende **explicitamente o ritual de
  retrospectiva**, **nomeando** as métricas listadas em `erosion-metrics:` (ex.:
  "sessões e razão abaixo do alvo há 2 semanas consecutivas — vale uma
  retrospectiva. O que mudou nessas duas semanas?").
- **`goodhart: true`** → **destaque a divergência** entre os sinais antecedentes e
  o critério final (números bons + final **não** satisfeito, **ou** números ruins
  + final satisfeito), citando `final-criterion`/`final-satisfied`. Não explique a
  divergência para longe — exponha-a.
- **`goodhart: inconclusive`** → diga, em **uma** linha, que o critério final não
  foi atestado nesta janela (sem fabricar o número).
- **`goodhart: false`** → nada a destacar nessa dimensão.

---

As respostas fluem em **streaming** natural do hospedeiro — sem barras de
progresso nem "processando…". Esta skill **não** chama o tutor (isso é da
`/kolb:reflect`), **não** registra fase do ciclo Kolb (o checkpoint não é uma fase
RO/AC/AE), **não** escreve estado (`.kolb/`, `pdi.md`, notas — tudo read-only) e
**não** gera código. Ela só roda o `checkpoint.sh` e narra a saída.
