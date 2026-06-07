---
topic: "OAuth2 state CSRF"
linked_files: ["src/auth/oauth.ts"]
created: "2026-05-25T10:00:00-03:00"
last_review: "2026-05-25T10:00:00-03:00"
pdi_goal: "seguranca-web"
---

<!--
  Molde de NOTA AC (Conceptualização — fase AC do ciclo Kolb) — FR40.
  As notas reais são GERADAS campo a campo por scripts/write-note.sh em
  .kolb/notes/<slug>.md (slug = slugify(topic)). Este arquivo é REFERÊNCIA-APENAS:
  ilustra o schema (architecture.md:152-160) e o registro de "um conceito atômico".
  NÃO é copiado para .kolb/ (a nota real nasce do /kolb:conceptualize), assim como
  templates/sessions.jsonl é só exemplo do vocabulário de eventos.

  Frontmatter — 5 campos, SEMPRE presentes (o índice de notas do Epic 4 os deriva
  por scan do frontmatter, sem índice redundante a sincronizar — FR27):
    topic        título do conceito; é a origem do slug do nome do arquivo
    linked_files arquivos associados, p/ o spacing contextual (FR26); pode ser []
    created      ISO 8601 com timezone (NFR19)
    last_review  == created na criação; o spacing do Epic 4 o atualiza (FR28)
    pdi_goal     liga a nota a uma meta do PDI (FR24); pode ser ""

  Corpo — UM conceito atômico, redigido para ser reutilizável FORA do contexto
  original (não um diário da sessão; não vários conceitos misturados).
-->

# OAuth2 state CSRF

O parâmetro `state` no fluxo OAuth2 é um valor aleatório e imprevisível que o
cliente gera, guarda na sessão e envia ao IdP no início do fluxo; no retorno, ele
compara o `state` recebido com o que guardou. Se diferem, a resposta foi forjada
(ataque CSRF no callback) e deve ser rejeitada.

O conceito generalizável: **vincular a ida e a volta de um fluxo de redirect a um
segredo imprevisível por requisição**, conferido na volta. Aplica-se a qualquer
redirecionamento para terceiros, não só OAuth2.
