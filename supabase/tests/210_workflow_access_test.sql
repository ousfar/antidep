-- Migrasjon 005 — tilgang til review- og provenienslaget.
--
-- Kritisk negativ test fra MVP_IMPLEMENTATION_PLAN.md §42 og §47 og
-- DATABASE_ARCHITECTURE.md §5, §46, §48, §49 og §67: workflow og provenance er
-- default deny. Verken anonyme eller vanlige innloggede brukere skal kunne lese
-- eller skrive der, og RLS skal være den andre sperren, ikke bare fraværet av
-- grants.
--
-- Den viktigste testen her er privilege escalation: medlemskapstabellen er
-- autorisasjonskilden (§46), og en bruker som kan skrive i den kan gi seg selv
-- hvilken som helst rolle. Testen kontrollerer derfor både at granten mangler,
-- og at RLS ville stoppet forsøket selv om granten ble gitt ved et uhell.
--
-- SQLSTATE 42501 = insufficient_privilege.
begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

-- ---------------------------------------------------------------------------
-- Testdata som bare finnes inne i denne transaksjonen, slik at et tomt resultat
-- under RLS ikke kan forveksles med en tom tabell.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values (gen_random_uuid(), 'tilgang@test.invalid');

insert into provenance.actors (actor_type, actor_key, display_name, description)
values ('system', 'system:tilgang', 'Testsystemaktør',
        'Systemaktør for tilgangstestene.');

insert into workflow.user_roles
  (user_id, role_code, granted_by_actor_id, grant_reason)
select u.id, 'editor', a.id, 'Testtildeling for tilgangstestene.'
from auth.users u, provenance.actors a
where u.email = 'tilgang@test.invalid' and a.actor_key = 'system:tilgang';

-- ---------------------------------------------------------------------------
-- Lag 1: grants
-- ---------------------------------------------------------------------------
select is_empty(
  $$
    select t.table_name, r.role_name, p.privilege
    from (values ('provenance.actors'), ('workflow.user_roles'),
                 ('workflow.evidence_verifications'), ('workflow.claim_verifications'),
                 ('workflow.review_decisions')) as t(table_name)
    cross join (values ('anon'), ('authenticated'), ('service_role'), ('public'))
           as r(role_name)
    cross join (values ('select'), ('insert'), ('update'), ('delete'), ('truncate'),
                       ('references'), ('trigger')) as p(privilege)
    where has_table_privilege(r.role_name, t.table_name, p.privilege)
  $$,
  'ingen klientrolle har noe tabellprivilegium på review- eller proveniensetabellene'
);
select is_empty(
  $$
    select s.schema_name, r.role_name, p.privilege
    from (values ('workflow'), ('provenance')) as s(schema_name)
    cross join (values ('anon'), ('authenticated'), ('service_role'), ('public'))
           as r(role_name)
    cross join (values ('usage'), ('create')) as p(privilege)
    where has_schema_privilege(r.role_name, s.schema_name, p.privilege)
  $$,
  'ingen klientrolle har usage eller create på workflow eller provenance'
);
select is_empty(
  $$
    select f.function_name, r.role_name
    from (values ('workflow.enforce_reviewer_qualification()'),
                 ('workflow.freeze_role_grant()'),
                 ('provenance.freeze_actor_identity()')) as f(function_name)
    cross join (values ('anon'), ('authenticated'), ('service_role'), ('public'))
           as r(role_name)
    where has_function_privilege(r.role_name, f.function_name, 'execute')
  $$,
  'ingen klientrolle kan kjøre de privilegerte funksjonene i workflow eller provenance'
);

-- ---------------------------------------------------------------------------
-- Lag 2: RLS er aktivert, uten policies i dette steget
-- ---------------------------------------------------------------------------
select is_empty(
  $$
    select n.nspname || '.' || c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('workflow', 'provenance')
      and c.relkind = 'r'
      and not c.relrowsecurity
  $$,
  'RLS er aktivert på alle tabellene i workflow og provenance'
);
select is_empty(
  $$
    select p.polname, c.relname
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('workflow', 'provenance')
  $$,
  'ingen RLS-policy er skrevet i workflow eller provenance; skriveveiene og grantene de skal styre kommer i migrasjon 006'
);

-- ---------------------------------------------------------------------------
-- Faktiske forsøk med Data API-rollene
-- ---------------------------------------------------------------------------
set local role anon;
select throws_ok(
  'select 1 from provenance.actors', '42501', null,
  'anon nektes lesing av aktørregisteret'
);
select throws_ok(
  'select 1 from workflow.user_roles', '42501', null,
  'anon nektes lesing av medlemskapstabellen'
);
select throws_ok(
  'select 1 from workflow.evidence_verifications', '42501', null,
  'anon nektes lesing av ekstraksjonsverifikasjonene'
);
select throws_ok(
  'select 1 from workflow.claim_verifications', '42501', null,
  'anon nektes lesing av claim-verifikasjonene'
);
select throws_ok(
  'select 1 from workflow.review_decisions', '42501', null,
  'anon nektes lesing av reviewbeslutningene'
);
reset role;

set local role authenticated;
select throws_ok(
  'select 1 from workflow.user_roles', '42501', null,
  'vanlig innlogget bruker nektes lesing av medlemskapstabellen'
);
select throws_ok(
  'select 1 from provenance.actors', '42501', null,
  'vanlig innlogget bruker nektes lesing av aktørregisteret'
);
select throws_ok(
  'select 1 from workflow.review_decisions', '42501', null,
  'vanlig innlogget bruker nektes lesing av reviewbeslutningene'
);
-- Privilege escalation: den farligste skriveveien i hele schemaet.
select throws_ok(
  $$
    insert into workflow.user_roles
      (user_id, role_code, granted_by_actor_id, grant_reason)
    values (gen_random_uuid(), 'admin', gen_random_uuid(), 'Selvtildelt rolle.')
  $$,
  '42501', null,
  'vanlig innlogget bruker kan ikke gi seg selv en rolle'
);
select throws_ok(
  $$update workflow.user_roles set valid_to = null, ended_by_actor_id = null, end_reason = null$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke gjenåpne en tilbakekalt rolle'
);
select throws_ok(
  $$delete from workflow.user_roles$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke slette en rolletildeling for å skjule den'
);
select throws_ok(
  $$
    insert into provenance.actors (actor_type, actor_key, display_name, description)
    values ('human', 'human:selvopprettet', 'Selvopprettet', 'Aktør opprettet av bruker.')
  $$,
  '42501', null,
  'vanlig innlogget bruker kan ikke opprette en aktør å attribuere handlinger til'
);
select throws_ok(
  $$
    insert into workflow.review_decisions (
      claim_revision_id, claim_revision_creator_actor_id, review_type, decision,
      rationale, reviewer_actor_id, reviewer_actor_type, decided_at
    )
    values (gen_random_uuid(), gen_random_uuid(), 'publication_approval', 'approved',
            'Selvgodkjenning.', gen_random_uuid(), 'human', now())
  $$,
  '42501', null,
  'vanlig innlogget bruker kan ikke godkjenne klinisk innhold'
);
select throws_ok(
  $$
    insert into workflow.claim_verifications (
      claim_revision_id, verified_revision_creator_actor_id, verifier_actor_id,
      outcome, source_access, source_support, population_match, comparator_match,
      timeframe_match, direction_and_magnitude, qualifiers_complete,
      contradictory_evidence_represented, rationale, verified_at
    )
    values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
            'verified', 'original_source', 'ok', 'ok', 'ok', 'ok', 'ok', 'ok', 'ok',
            'Selvverifikasjon.', now())
  $$,
  '42501', null,
  'vanlig innlogget bruker kan ikke registrere en verifikasjon'
);
select throws_ok(
  $$select workflow.enforce_reviewer_qualification()$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke kjøre den privilegerte kvalifikasjonskontrollen'
);
reset role;

-- service_role omgår RLS, men ikke grants, og er ikke applikasjonens
-- universalnøkkel (DATABASE_ARCHITECTURE.md §49).
set local role service_role;
select throws_ok(
  'select 1 from workflow.user_roles', '42501', null,
  'service_role nektes lesing av medlemskapstabellen fordi grants mangler'
);
select throws_ok(
  'select 1 from provenance.actors', '42501', null,
  'service_role nektes lesing av aktørregisteret fordi grants mangler'
);
reset role;

-- ---------------------------------------------------------------------------
-- RLS er en reell sperre, ikke bare fraværet av grants
--
-- Selvtest av lag 2: hvis en framtidig migrasjon ved et uhell gir privilegier
-- til en klientrolle, skal RLS fortsatt gi null rader og avvise skriving.
-- Grantene finnes bare inne i denne transaksjonen og rulles tilbake.
-- ---------------------------------------------------------------------------
grant usage on schema workflow, provenance to authenticated;
grant select, insert, update, delete on workflow.user_roles to authenticated;
grant select on provenance.actors to authenticated;

-- Kontroll av selve selvtesten: radene finnes faktisk, sett fra eieren.
select isnt_empty(
  'select 1 from workflow.user_roles',
  'rolletildelingen finnes, sett fra eieren'
);
select isnt_empty(
  'select 1 from provenance.actors',
  'aktørene finnes, sett fra eieren'
);

set local role authenticated;
select is(
  (select count(*) from workflow.user_roles),
  0::bigint,
  'RLS gir null rolletildelinger selv med SELECT-grant, fordi ingen policy slipper noen inn'
);
select is(
  (select count(*) from provenance.actors),
  0::bigint,
  'RLS gir null aktører selv med SELECT-grant'
);
select throws_ok(
  $$
    insert into workflow.user_roles
      (user_id, role_code, granted_by_actor_id, grant_reason)
    values (gen_random_uuid(), 'admin', gen_random_uuid(), 'Selvtildelt rolle med grant.')
  $$,
  '42501', null,
  'RLS stopper selvtildeling av rolle selv om INSERT-granten er gitt ved et uhell'
);
reset role;

select * from finish();

rollback;
