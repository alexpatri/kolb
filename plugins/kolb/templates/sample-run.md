<!--
  TRANSCRIÇÃO DE EXEMPLO do ciclo Kolb completo (CE→RO→AC→AE) — FR40.

  É REFERÊNCIA-APENAS e PARTE DO PRODUTO (AR-Templates, architecture.md:420):
  ilustra "como deveria fluir" uma sessão de modo aprendizado. Como os demais
  templates/* (ac-note.md, sessions.jsonl), NÃO é runtime — nenhum hook, skill ou
  script lê este arquivo, e ele NÃO é copiado para .kolb/. Lê-se a olho nu, sem
  executar nada.

  As mensagens de runtime citadas abaixo (ativação do modo, bloqueio de geração,
  contrato injetado, retornos de write-note.sh/log-phase.sh) são VERBATIM das
  fontes reais do plugin (toggle-mode.sh, block-write.sh, prompt-steer.sh,
  write-note.sh, log-phase.sh) e do contrato CLAUDE.md — com a única ressalva de
  que caminhos de arquivo aparecem na forma relativa (.kolb/notes/...) para leitura;
  em runtime, write-note.sh imprime o caminho absoluto do projeto. Se você editar o
  plugin e divergir destas mensagens, atualize esta transcrição também — ela é a
  face pedagógica do pacote e o leitor confia nela.

  Rótulos de turno:
    Humano:   o desenvolvedor que aprende.
    IA:       o Claude Code rodando sob o contrato do modo aprendizado.
    Tutor:    o subagent isolado kolb:tutor (só na fase RO).
    Sistema:  saída literal de um hook/skill/script do plugin.
    (nota: …) narração curta, fora do diálogo, para situar o leitor.

  Cenário único: implementar o callback de OAuth2 com defesa de CSRF via parâmetro
  `state` (o mesmo conceito de ouro da Jornada 1 do PRD e de templates/ac-note.md).
-->

# Sessão de exemplo — ciclo Kolb completo (CE → RO → AC → AE)

Uma sessão curta de modo aprendizado, do início ao fim das quatro fases, sobre um
único problema: **proteger o callback OAuth2 contra CSRF com o parâmetro `state`**.

---

## CE — Experiência Concreta

A Experiência Concreta é o **estado default** do modo aprendizado: não há comando
para "entrar" nela. O humano liga o modo e começa a escrever código; o bloqueio de
geração garante que o esforço de escrever seja dele.

**Humano:** `/kolb:learn-mode on`

**Sistema:**
```
Kolb: modo aprendizado ATIVADO nesta sessão.
```

**Humano:** Escreve o código do callback OAuth2 pra mim, em `src/auth/oauth.ts`.

**Sistema:** _(o hook de bloqueio nega a operação de escrita — `permissionDecisionReason`)_
> Modo aprendizado: escrever o código é o seu esforço — eu oriento, não gero. Posso dar uma dica em alto nível ou revisar o que você escrever.
> Qual é o primeiro passo da sua abordagem?

**IA:** O callback recebe o `code` do IdP e o troca por um token. Antes disso, há
um risco clássico: como o seu app sabe que *esta* resposta pertence ao fluxo que
*ele mesmo* iniciou, e não a um redirect forjado? Vale pensar em como **amarrar a
ida e a volta** do redirect. Qual informação você poderia gerar na ida e conferir
na volta?

_(nota: a IA fica do lado ✅ da tabela pareada do CLAUDE.md — explica o conceito e
dá uma dica em alto nível; **não** entrega função pronta, assinatura completada nem
bloco compilável. O contrato segue injetado a cada turno — `prompt-steer.sh`:
"(#2) a IA não gera código … ela dá dicas sobre a abordagem e avalia depois".)_

**Humano:** Faz sentido. Vou escrever eu mesmo. _(escreve em `src/auth/oauth.ts`:
gera um `state` aleatório na ida, guarda na sessão e, no callback, compara o `state`
recebido com o guardado antes de trocar o `code`.)_

Esse código que o humano escreveu é a **CE** — a experiência concreta que as
próximas fases vão transformar em aprendizado.

---

## RO — Observação Reflexiva (`/kolb:reflect`)

A RO expõe as **decisões** do código e testa se o humano as entende a ponto de
defendê-las. A IA **não corrige nem reescreve** — ela elicia a verbalização e a
leva ao tutor isolado.

**Humano:** `/kolb:reflect`

**IA:** Vamos olhar o que você escreveu. Escolha **uma** decisão e defenda-a: por
que você gerou o `state` como valor aleatório guardado na sessão, em vez de algo
fixo ou derivado do usuário? Que alternativa você descartou — e por quê?

**Humano:** Gerei o `state` como valor aleatório por requisição e guardei na
sessão. No callback comparo o que voltou com o guardado: se baterem, o fluxo é o
que eu iniciei; se não, rejeito. Pensei em usar o id do usuário, mas seria
previsível — um atacante poderia adivinhar e forjar a volta. Aleatório por
requisição não dá esse gancho.

**IA:** _(invoca o subagent `kolb:tutor` via Task, passando **apenas** o código que
o humano escreveu + a verbalização acima, verbatim — sem as dicas que dei antes,
sem minha análise, sem o trace da sessão; isolamento de nível 1.)_

**Tutor:** Comparar o `state` na volta com o guardado prova que **alguém** conhecia
o valor — mas o que garante que esse alguém é o seu usuário, e não o navegador
dele sendo levado a iniciar um fluxo que **você** não pediu? Onde, exatamente, o
`state` é gravado e por quanto tempo ele vale? E se a mesma sessão abrir dois
fluxos OAuth concorrentes — um valor único na sessão dá conta dos dois?

_(nota: a IA repassa o questionamento do tutor **sem suavizar** — não troca por um
"boa explicação". A RO **só encerra** quando as duas condições valem: o humano
defendeu ≥1 decisão **e** o tutor questionou de fato. Aqui valem.)_

**Humano:** Verdade — preciso pensar em expiração e em fluxos concorrentes. Anoto
isso. Por ora o conceito central que quero fixar é o vínculo ida-volta por segredo
imprevisível.

**IA:** _(registra a fase)_

**Sistema:**
```
Kolb: fase 'reflect' registrada no índice da sessão.
```

_(nota: com `phase_reflect` no índice, se a sessão terminasse agora ela seria
derivada como **`partial`** — refletida mas sem conceito fechado — e não como
abandonada. O `/kolb:conceptualize` a seguir é o que fecha o ciclo.)_

---

## AC — Conceitualização (`/kolb:conceptualize "OAuth2 state CSRF"`)

A AC destila **um** conceito atômico da reflexão e o **persiste** como nota
reutilizável. A IA ajuda a recortar o conceito **na formulação do humano** — não
redige um resumo bonito para aceitação passiva (isso seria ilusão de fluência).

**Humano:** `/kolb:conceptualize "OAuth2 state CSRF"`

**IA:** Qual é a **ideia única** que você quer levar desta sessão para a próxima
vez? Tente formulá-la de modo que ela faça sentido para você daqui a três meses,
**fora** deste código — e o que a torna geral, além do OAuth2?

**Humano:** A ideia é: vincular a ida e a volta de um fluxo de redirect a um
segredo aleatório, imprevisível por requisição, guardado na ida e conferido na
volta. Se a volta não traz o segredo certo, foi forjada (CSRF) e se rejeita. Vale
para qualquer redirect a terceiros, não só OAuth2.

**IA:** Esse é um conceito atômico e reutilizável. Vou gravá-lo na **sua**
formulação — em modo aprendizado a IA não usa a tool `Write` (bloqueada); a nota
nasce pelo script do plugin:

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/write-note.sh" "OAuth2 state CSRF" \
  --pdi-goal "seguranca-web" --linked "src/auth/oauth.ts" <<'EOF'
O parâmetro `state` no fluxo OAuth2 é um valor aleatório e imprevisível que o
cliente gera, guarda na sessão e envia ao IdP no início do fluxo; no retorno, ele
compara o `state` recebido com o que guardou. Se diferem, a resposta foi forjada
(ataque CSRF no callback) e deve ser rejeitada.

O conceito generalizável: vincular a ida e a volta de um fluxo de redirect a um
segredo imprevisível por requisição, conferido na volta. Aplica-se a qualquer
redirecionamento para terceiros, não só OAuth2.
EOF
```

**Sistema:**
```
Kolb: nota AC criada em .kolb/notes/oauth2-state-csrf.md (tópico: "OAuth2 state CSRF").
```

A nota gravada (`.kolb/notes/oauth2-state-csrf.md`) segue o schema de
`templates/ac-note.md` — **5 campos** no frontmatter, corpo atômico:

```
---
topic: "OAuth2 state CSRF"
linked_files: ["src/auth/oauth.ts"]
created: "2026-05-25T10:00:00-03:00"
last_review: "2026-05-25T10:00:00-03:00"
pdi_goal: "seguranca-web"
---

O parâmetro `state` no fluxo OAuth2 é um valor aleatório e imprevisível que o
cliente gera, guarda na sessão e envia ao IdP no início do fluxo; no retorno, ele
compara o `state` recebido com o que guardou. Se diferem, a resposta foi forjada
(ataque CSRF no callback) e deve ser rejeitada.

O conceito generalizável: vincular a ida e a volta de um fluxo de redirect a um
segredo imprevisível por requisição, conferido na volta. Aplica-se a qualquer
redirecionamento para terceiros, não só OAuth2.
```

_(nota: o nome do arquivo `oauth2-state-csrf` é `slugify("OAuth2 state CSRF")`. O
`pdi_goal: "seguranca-web"` liga esta nota a uma meta do PDI, que passa a contar
com ela como evidência — FR24. `last_review` nasce igual a `created`; o spacing do
Epic 4 é quem o avança ao longo do tempo.)_

**IA:** _(fecha o ciclo registrando a fase)_

**Sistema:**
```
Kolb: fase 'conceptualize' registrada no índice da sessão.
```

_(nota: com `phase_conceptualize` no índice, a sessão deixa de ser `partial` e é
derivada como **`complete`** — o ciclo CE→RO→AC fechou (FR4).)_

---

## AE — Experimentação Ativa (`/kolb:experiment`)

A AE consolida o aprendizado **por transferência**: aplicar o conceito a um
contexto novo, resolvido pelo humano **sem a IA**. O papel da IA é **propor uma
variação não-trivial e parar**.

**Humano:** `/kolb:experiment`

**IA:** Você fixou o conceito de amarrar ida e volta por um segredo imprevisível
guardado na sessão. A variação: **implemente o mesmo `state` num fluxo OAuth sem
sessão server-side** — uma API stateless, sem onde "guardar" o valor entre a ida e
a volta. A dimensão que muda é **onde o segredo vive**: sem sessão, você precisa
carregá-lo de outra forma (um cookie assinado, ou amarrá-lo ao token) sem abrir
brecha para forjar a volta. Isso força o conceito a um terreno novo — o vínculo
não pode mais depender de estado no servidor. Como você garantiria a conferência
da volta sem guardar o `state` no servidor?

_(nota: a variação muda ≥1 dimensão e é resolvível com o que o humano acabou de
aprender — não é "o mesmo com nomes trocados". A IA **nomeou** a dimensão.)_

**IA:** Resolva esta variação **sem assistência da IA** — o esforço de raciocinar
e codificar é o que ensina (Princípio #1). O modo aprendizado **continua ativo**:
o bloqueio de geração de código segue valendo, e eu não vou esboçar a solução nem
desligar o modo. Posso tirar dúvidas **conceituais**, mas o caminho é seu.

**IA:** _(registra a fase)_

**Sistema:**
```
Kolb: fase 'experiment' registrada no índice da sessão.
```

_(nota: `phase_experiment` marca a fase como **proposta/alcançada** nesta sessão —
a variação se resolve offline, sem IA. Ele **não** muda o status: a sessão
continua `complete` por causa do `phase_conceptualize` da AC.)_

---

## Fechamento

O ciclo completou-se: **CE** (o humano escreveu o callback) → **RO** (defendeu a
decisão; o tutor questionou sem complacência) → **AC** (destilou e gravou a nota
`oauth2-state-csrf`) → **AE** (recebeu uma variação não-trivial para resolver
sozinho). Em todas as fases o contrato do `CLAUDE.md` se manteve: nenhuma resposta
da IA entregou função pronta, assinatura completada ou bloco compilável — a IA
**orientou**; o **humano escreveu**.
