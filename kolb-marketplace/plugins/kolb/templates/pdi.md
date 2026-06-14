<!--
  Molde do PDI (Plano de Desenvolvimento Individual) — FR40.
  Este arquivo é o template SHIPADO do plugin: vive em
  $CLAUDE_PLUGIN_ROOT/templates/pdi.md, é READ-ONLY e NÃO é estado (o path do
  plugin muda a cada update — architecture.md:110,148,373). Na 1ª vez que o PDI
  é necessário, scripts/init-pdi.sh o COPIA para $CLAUDE_PROJECT_DIR/.kolb/pdi.md
  (durável, versionável — architecture.md:146,162,362), sem nunca sobrescrever um
  pdi.md já existente. A partir daí o .kolb/pdi.md é EDITADO à mão pelo Alex; este
  template permanece só como referência do schema.

  SCHEMA — cada meta é uma seção `## <id-da-meta>` com EXATAMENTE 4 campos, nesta
  ordem (FR21, architecture.md:162):
    Skill atual    onde você está hoje nessa competência
    Skill alvo     onde quer chegar
    Evidência      o que comprova progresso; PODE referenciar uma nota AC por
                   .kolb/notes/<slug>.md (ou pelo slug/topic) — o lado PDI do link
                   nota↔meta (FR24); o lado nota é o pdi_goal do frontmatter da
                   nota AC (templates/ac-note.md:6,23).
    Próxima ação   o próximo passo concreto e pequeno

  ID DA META — é o próprio título da seção (slug ASCII, ex.: `seguranca-web`).
  NÃO há campo "id" redundante: a nota AC liga-se à meta por `pdi_goal: "<id>"`
  apontando para este título (FR24/FR27 — índice derivado, sem sincronização
  redundante). Mantenha o id em ASCII minúsculo-com-hífen (kolb_slugify não
  translitera acentos — _common.sh:38-41).

  Os RÓTULOS dos 4 campos (`**Skill atual:**` etc.) são CONTRATO: o check-in
  (/kolb:pdi-checkin, story 4.2) parseia exatamente esses rótulos. Não os renomeie
  sem atualizar a 4.2.

  META-EXEMPLO — a meta abaixo é uma AMOSTRA shipada (referencia uma nota AC e um
  arquivo que NÃO existem no seu projeto). Ela vem precedida do marcador
  `<!-- META-EXEMPLO -->` para que NÃO seja confundida com uma meta sua: o check-in
  (4.2) IGNORA seções marcadas assim ao listar suas metas. Apague-a (ou edite por
  cima) ao declarar metas reais. Uma meta real é uma seção `##` SEM esse marcador.
-->

# PDI — Plano de Desenvolvimento Individual

Minhas metas de aprendizado. Cada meta tem 4 campos: **skill atual**, **skill
alvo**, **evidência** e **próxima ação**. O check-in (`/kolb:pdi-checkin`) lê estas
metas; as notas AC ligam-se a elas por `pdi_goal`. Edite à mão — é seu estado,
versionável em `.kolb/`. A meta abaixo é só um **exemplo** (marcado
`<!-- META-EXEMPLO -->`) — apague-a ou edite por cima com suas metas reais.

<!-- META-EXEMPLO -->
## seguranca-web

**Skill atual:** Sei o que é OAuth2 em alto nível, mas implemento o callback sem
proteger contra CSRF nem validar o `state`.

**Skill alvo:** Implementar um fluxo de redirect com terceiros de forma segura por
padrão — `state` imprevisível por requisição, conferido na volta — e saber generalizar
o princípio para além do OAuth2.

**Evidência:** Conceito consolidado em `.kolb/notes/oauth2-state-csrf.md` (nota AC,
`pdi_goal: "seguranca-web"`); apliquei no callback de `src/auth/oauth.ts`.

**Próxima ação:** Revisar os demais endpoints de redirect do projeto e checar se cada
um vincula ida↔volta a um segredo por requisição.
