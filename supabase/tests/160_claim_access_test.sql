-- Migrasjon 004 — tilgang til påstandslaget.
--
-- Kritisk negativ test fra MVP_IMPLEMENTATION_PLAN.md §42 og §47 og
-- DATABASE_ARCHITECTURE.md §5, §48 og §49: påstandstabellene er default deny.
-- Verken anonyme eller vanlige innloggede brukere skal kunne lese eller skrive
-- i knowledge, og RLS skal være den andre sperren, ikke bare fraværet av grants.
-- Klientflaten leser publiserte projeksjoner i api (migrasjon 007).
--
-- Her er kravet strengere enn for kilde- og evidenslaget: radene er
-- KI-utarbeidede påstandsforslag som verken er verifisert av en separat
-- kontrollfase eller godkjent av en navngitt kvalifisert redaktør
-- (ANTIDEP_CONSTITUTION.md §11, §12). At ingen klientrolle kan nå dem er derfor
-- et innholdskrav før det er et sikkerhetskrav.
begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

-- ---------------------------------------------------------------------------
-- Lag 1: grants
-- ---------------------------------------------------------------------------
select is_empty(
  $$
    select t.table_name, r.role_name, p.privilege
    from (values ('knowledge.claims'), ('knowledge.claim_revisions'),
                 ('knowledge.claim_evidence_links'), ('knowledge.evidence_assessments'))
           as t(table_name)
    cross join (values ('anon'), ('authenticated'), ('service_role'), ('public'))
           as r(role_name)
    cross join (values ('select'), ('insert'), ('update'), ('delete'), ('truncate'),
                       ('references'), ('trigger')) as p(privilege)
    where has_table_privilege(r.role_name, t.table_name, p.privilege)
  $$,
  'ingen klientrolle har noe tabellprivilegium på påstandstabellene'
);

-- ---------------------------------------------------------------------------
-- Lag 2: RLS er aktivert, uten policies i dette steget
-- ---------------------------------------------------------------------------
select is_empty(
  $$
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'knowledge'
      and c.relkind = 'r'
      and c.relname in ('claims', 'claim_revisions', 'claim_evidence_links',
                        'evidence_assessments')
      and not c.relrowsecurity
  $$,
  'RLS er aktivert på alle påstandstabellene'
);
select is_empty(
  $$
    select p.polname, c.relname
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'knowledge'
  $$,
  'ingen RLS-policy er skrevet på påstandslaget; klientlesing går gjennom api-projeksjonene i migrasjon 007'
);

-- ---------------------------------------------------------------------------
-- Faktiske forsøk med Data API-rollene (42501 = insufficient_privilege)
-- ---------------------------------------------------------------------------
set local role anon;
select throws_ok(
  'select 1 from knowledge.claims',
  '42501', null,
  'anon nektes lesing av påstandene'
);
select throws_ok(
  'select 1 from knowledge.claim_revisions',
  '42501', null,
  'anon nektes lesing av påstandsrevisjonene'
);
select throws_ok(
  'select 1 from knowledge.claim_evidence_links',
  '42501', null,
  'anon nektes lesing av evidenslenkene'
);
select throws_ok(
  'select 1 from knowledge.evidence_assessments',
  '42501', null,
  'anon nektes lesing av evidensvurderingene'
);
select throws_ok(
  $$
    insert into knowledge.claims (knowledge_type, topic_concept_id, subject_drug_id)
    values ('evidence_synthesis', gen_random_uuid(), gen_random_uuid())
  $$,
  '42501', null,
  'anon kan ikke opprette påstander'
);
reset role;

set local role authenticated;
select throws_ok(
  'select 1 from knowledge.claim_revisions',
  '42501', null,
  'vanlig innlogget bruker nektes lesing av påstandsrevisjonene'
);
select throws_ok(
  'select 1 from knowledge.evidence_assessments',
  '42501', null,
  'vanlig innlogget bruker nektes lesing av evidensvurderingene'
);
-- Den farligste skriveveien: å flytte publiseringspekeren er å publisere.
select throws_ok(
  $$update knowledge.claims set current_published_revision_id = gen_random_uuid()$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke flytte publiseringspekeren'
);
select throws_ok(
  $$update knowledge.claims set retired_at = now(), retirement_note = 'forsøk'$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke trekke tilbake en påstand'
);
select throws_ok(
  $$
    insert into knowledge.evidence_assessments (
      claim_revision_id, assessed_knowledge_type, framework, certainty_level, rationale, assessed_at
    )
    values (gen_random_uuid(), 'evidence_synthesis', 'grade', 'high', 'forsøk', now())
  $$,
  '42501', null,
  'vanlig innlogget bruker kan ikke registrere en evidensvurdering'
);
select throws_ok(
  'delete from knowledge.claim_revisions',
  '42501', null,
  'vanlig innlogget bruker kan ikke slette påstandsrevisjoner'
);
reset role;

-- service_role omgår RLS, men ikke grants, og er ikke applikasjonens
-- universalnøkkel (DATABASE_ARCHITECTURE.md §49).
set local role service_role;
select throws_ok(
  'select 1 from knowledge.claim_revisions',
  '42501', null,
  'service_role nektes lesing av påstandslaget fordi grants mangler'
);
reset role;

-- ---------------------------------------------------------------------------
-- RLS er en reell sperre, ikke bare fraværet av grants
--
-- Selvtest av lag 2: hvis en framtidig migrasjon ved et uhell gir SELECT til en
-- klientrolle, skal RLS fortsatt gi null rader. Granten finnes bare inne i denne
-- transaksjonen og rulles tilbake.
-- ---------------------------------------------------------------------------
grant usage on schema knowledge to authenticated;
grant select on knowledge.claim_revisions to authenticated;
grant select on knowledge.evidence_assessments to authenticated;

-- Kontroll av selve selvtesten: radene finnes faktisk, så et tomt resultat under
-- skyldes RLS og ikke en tom tabell.
select isnt_empty(
  'select 1 from knowledge.claim_revisions',
  'påstandsrevisjonene finnes, sett fra eieren'
);

set local role authenticated;
select is(
  (select count(*) from knowledge.claim_revisions),
  0::bigint,
  'RLS gir null påstandsrevisjoner selv med SELECT-grant, fordi ingen policy slipper noen inn'
);
select is(
  (select count(*) from knowledge.evidence_assessments),
  0::bigint,
  'RLS gir null evidensvurderinger selv med SELECT-grant'
);
reset role;

select * from finish();

rollback;
