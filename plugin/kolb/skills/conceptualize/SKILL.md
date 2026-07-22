---
description: Conduz a Conceitualização (fase AC do ciclo Kolb) — ajuda você a extrair UM conceito atômico da sua reflexão e o salva como nota AC reutilizável em .kolb/notes/. Acione com "/kolb:conceptualize \"<título do conceito>\"" depois de refletir (/kolb:reflect) sobre o código que você escreveu em modo aprendizado.
allowed-tools: [Bash]
---

# /kolb:conceptualize — Conceitualização (extração de nota AC)

Conduz a fase de **Abstract Conceptualization (AC)** do ciclo de Kolb. Vem **depois
da Observação Reflexiva** (`/kolb:reflect`): a reflexão expôs as decisões; agora você
**destila um conceito** daquilo que aprendeu e o **persiste** como uma nota atômica e
**reutilizável fora do contexto original** — material para o retrieval espaçado do
Kolb mais adiante.

O seu papel aqui **não é gerar nem reescrever código**. É ajudar o humano a **recortar
um conceito** e redigi-lo **na formulação dele**, e então gravar a nota via script.
Escrever uma **nota conceitual** é permitido (é conteúdo conceitual — `CLAUDE.md`,
"o conceitual continua fluindo"); **gerar/completar/reescrever código não é**.

> ⚠️ **Quem escreve o conceito é o humano.** Não redija um resumo bonito para o
> humano aceitar passivamente — isso produz *ilusão de fluência* (o oposto do
> objetivo). Puxe a formulação **dele**; você organiza e grava, não substitui a
> recuperação ativa.

## O que fazer

### 1. Recortar UM conceito atômico

A partir da reflexão concluída, ajude o humano a isolar **um** conceito — não vários,
não um diário da sessão. Pergunte, em tom socrático do `CLAUDE.md` (≤3 linhas,
termina em pergunta):

- Qual é a **ideia única** que você quer levar desta sessão para a próxima vez?
- Como você a explicaria para **você mesmo daqui a três meses**, fora deste código?
- O que a torna **geral** — onde mais ela se aplica, além deste caso?

O título do conceito vem do argumento do comando (`$ARGUMENTS`, ex.:
`/kolb:conceptualize "OAuth2 state CSRF"`). Se vier vazio, peça um título curto antes
de prosseguir.

### 2. Coletar os metadados da nota

Junte, sem inventar:

- **`linked_files`** — os arquivos que o humano trabalhou nesta sessão (do contexto
  da CE). Liste só os que se associam ao conceito; vazio se não houver.
- **`pdi_goal`** *(opcional)* — o identificador de uma meta do PDI à qual esta nota
  serve de evidência (FR24). Se o humano não tiver/quiser, deixe vazio.

### 3. Critério de saída da fase (checklist)

A AC **só encerra** — e a nota **só é gravada** — quando **as duas** condições valem:

- [ ] o **frontmatter está completo** (os 5 campos; `linked_files`/`pdi_goal` podem
      ser lista/valor vazios, mas presentes);
- [ ] o **corpo é atômico** — **um** conceito, redigido de forma reutilizável fora do
      contexto original (não um relato da sessão, não vários conceitos misturados).

Enquanto não, **itere com o humano** (afine o recorte do conceito) antes de persistir.

### 4. Persistir a nota — via `write-note.sh` (não pela tool Write)

Em modo aprendizado a escrita de arquivos pela IA é bloqueada; a nota é gravada pelo
**script do plugin**, que cuida do slug determinístico, do timestamp ISO 8601 e do
schema. Invoque-o passando o título, os metadados e o **corpo do conceito por stdin**,
**verbatim na formulação do humano**:

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/write-note.sh" "<título>" --pdi-goal "<meta ou vazio>" --linked "<arq1,arq2>" <<'EOF'
<corpo do conceito atômico, na formulação do humano>
EOF
```

O script cria `.kolb/notes/<slug>.md` (slug = `slugify(título)`) e **não sobrescreve**
uma nota já existente para o mesmo tópico — se houver colisão, ele avisa e nada é
perdido (escolha outro título ou edite a nota à mão).

### 5. Fechar o ciclo Kolb — registrar a fase no índice

**Só se a nota foi criada com sucesso** (passo 4), registre que a AC fechou o ciclo:

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/log-phase.sh" "conceptualize"
```

Isso anexa um evento `phase_conceptualize` a `.kolb/sessions.jsonl`. Com ele, a sessão
é derivada como **`complete`** pelos checkpoints (ciclo CE→RO→AC fechado — FR4),
fechando o que a `/kolb:reflect` deixou como `partial`.

Repasse ao humano, em uma linha, **a mensagem que cada script efetivamente retornar**
— seja a confirmação de sucesso, a de colisão (nada sobrescrito) ou a de falha (os
scripts falham graciosamente e imprimem o motivo). **Não** declare "nota criada" nem
"ciclo fechado" se o script reportou colisão ou falha.

---

As respostas desta skill fluem em **streaming** natural do hospedeiro — não insira
barras de progresso nem "processando…". Esta skill **pode ser sugerida pelo modelo**
no fluxo do ciclo (depois da `/kolb:reflect`); ela **não** chama o tutor (isso é da RO)
e **não** gera código — só elicita o conceito e o persiste.
