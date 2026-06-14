---
description: Conduz o check-in do PDI (Plano de Desenvolvimento Individual) — lê suas metas, exibe o estado de cada uma (skill atual · skill alvo · evidência · próxima ação), reconhece as notas AC ligadas a cada meta e SUGERE como atualizar a evidência e a próxima ação. Acione com "/kolb:pdi-checkin" para manter o plano vivo; oferece criar o PDI a partir do template se ainda não existir.
allowed-tools: [Bash]
---

# /kolb:pdi-checkin — Check-in do PDI

Conduz o **check-in do PDI** (Plano de Desenvolvimento Individual). O objetivo é
manter o plano **vivo** — revisado de tempos em tempos em vez de morrer em três
semanas. A skill **lê** suas metas, **exibe** o estado de cada uma e **sugere**
como atualizar a evidência e a próxima ação, cruzando cada meta com as notas AC
que você ligou a ela.

O seu papel aqui **não é gerar nem reescrever código**, e **não é editar o PDI por
mim**. É **ler**, **exibir** e **sugerir** — em tom socrático. **Quem edita o
`.kolb/pdi.md` é o humano, à mão.** Sugerir e discutir abordagem é conteúdo
conceitual (permitido — `CLAUDE.md`, "o conceitual continua fluindo"); **gravar o
PDI no lugar do humano não é.**

> ⚠️ **A skill NÃO escreve o `pdi.md`.** Dois motivos convergem: (1) **técnico** —
> em modo aprendizado o bloqueio de geração nega `Write`/`Edit`; (2) **pedagógico**
> — manter o plano vivo (declarar onde você está e quer chegar) é o esforço que
> ensina; entregá-lo pronto produziria *ilusão de progresso*. A única coisa que a
> skill **cria** é o **arquivo-molde** quando ele ainda não existe (via
> `init-pdi.sh`) — materialização do template, não o conteúdo das suas metas.

## O que fazer

### 1. Resolver o estado do PDI

Rode o **deriver read-only** para obter o estado mecânico do plano (presença,
metas **reais** já filtrando o exemplo shipado, e as notas-evidência ligadas a
cada meta):

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/pdi-status.sh"
```

A saída é um digest legível, uma linha por chave:

```
pdi: present|absent|unknown
real-goals: <N>
goal: <id> | evidence-notes: <slug> <slug> ...
```

- **`pdi: absent`** → vá para **o passo 2** (oferecer criar).
- **`pdi: unknown`** → não foi possível localizar o diretório do projeto
  (`CLAUDE_PROJECT_DIR`). Diga isso em uma linha e **pare** — não há o que ler.
- **`pdi: present`** → vá para **o passo 3**.

### 2. PDI ausente — oferecer criar a partir do template

Se não existe `.kolb/pdi.md`, **pergunte** em uma linha socrática se o humano quer
criá-lo agora a partir do template pré-preenchido. **Só se ele aceitar**, rode o
primitivo de criação da story 4.1 (não reimplemente o `cp`):

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/init-pdi.sh"
```

Repasse, em uma linha, **a mensagem que o script efetivamente retornar** (criado /
já existe / falha — ele falha graciosamente e imprime o motivo). **Não** declare
"PDI criado" se o script reportou outra coisa. Se o humano **recusar**, encerre
sem criar nada. Criado o arquivo, ele vem só com **uma meta de exemplo** (marcada
`<!-- META-EXEMPLO -->`) — explique o schema dos 4 campos e **convide a declarar a
primeira meta real à mão**; não trate o exemplo como meta dele.

### 3. Exibir o estado das metas reais

Leia o conteúdo do plano para mostrar os 4 campos de cada meta:

```sh
cat "${CLAUDE_PROJECT_DIR}/.kolb/pdi.md"
```

Para **cada meta real** (as seções `## <id>` que o deriver listou como
`goal:` — **ignore** qualquer seção marcada `<!-- META-EXEMPLO -->`), exiba de
forma compacta os 4 campos — **Skill atual**, **Skill alvo**, **Evidência**,
**Próxima ação** — e as **notas-evidência** que o deriver associou àquela meta
(o campo `evidence-notes`). Uma nota é reconhecida como evidência conectada quando
seu `pdi_goal` (frontmatter da nota AC) é **igual ao id** da meta.

Se o deriver reportou **`real-goals: 0`** (o plano só tem o exemplo), diga isso e
**convide a declarar a primeira meta real** — **não** invente metas nem narre a
amostra como se fosse do humano.

### 4. Sugerir — evidência e próxima ação (não escrever)

Para cada meta real, **sugira** em tom socrático do `CLAUDE.md` (≤3 linhas,
termina em pergunta ou prompt de ação):

- **Evidência:** há alguma nota AC recente (das ligadas, ou uma que ele deveria
  ligar via `pdi_goal`) que comprova progresso e ainda **não** está citada no
  campo evidência? Aponte-a — sem reescrever o campo por ele.
- **Próxima ação:** qual é o **próximo passo concreto e pequeno**? Faça-o
  enunciar, não enuncie no lugar dele.

Deixe **explícito** que as mudanças vão para o `.kolb/pdi.md` **pela mão dele** —
você sugere, ele edita. Encerre devolvendo a bola: o que ele vai atualizar agora?

---

Esta skill **pode ser sugerida pelo modelo** quando fizer sentido revisitar o
plano (após uma conceitualização que rendeu uma nota nova, por exemplo). Ela
**não** chama o tutor (isso é da `/kolb:reflect`), **não** registra fase do ciclo
Kolb (o check-in não é uma fase RO/AC/AE — não há `log-phase` aqui) e **não** gera
código. As respostas fluem em **streaming** natural do hospedeiro — sem barras de
progresso nem "processando…".
