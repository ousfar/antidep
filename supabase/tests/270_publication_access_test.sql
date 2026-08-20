-- Migrasjon 006 — tilgang til publiseringslaget.
--
-- Kritisk negativ test fra MVP_IMPLEMENTATION_PLAN.md §42, §47 og §48 og
-- DATABASE_ARCHITECTURE.md §5, §48, §49, §50 og §67: verken anonyme eller
-- vanlige innloggede brukere skal kunne publisere, avpublisere, flytte
-- publiseringspekeren eller lese publiseringshistorikken direkte. Klientflaten
-- leser publiserte projeksjoner i api (migrasjon 007).
--
-- Publiseringsfunksjonene er SECURITY DEFINER, og det gjør EXECUTE-privilegiet
-- til den avgjørende sperren. Kunne en vanlig bruker kalt dem, ville de kjørt med
-- definerens rettigheter og lest både rollemodellen og reviewbeslutningene forbi
-- RLS. Testene her kontrollerer derfor både at privilegiet mangler, og at de to
-- andre veiene til den samme tilstanden — direkte skriving i historikken og
-- direkte flytting av pekeren — er stengt.
--
-- SQLSTATE 42501 = insufficient_privilege.
begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

-- ---------------------------------------------------------------------------
-- Testdata som bare finnes inne i denne transaksjonen, slik at et tomt resultat
-- under RLS ikke kan forveksles med en tom tabell.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email)
values ('dddddddd-0000-0000-0000-000000000001', 'publisher-270@test.invalid');

insert into provenance.actors (actor_type, actor_key, display_name, description, auth_user_id)
values ('human', 'human:publisher-270', 'Testpublisher',
        'Menneskelig aktør for tilgangstestene i 270.',
        'dddddddd-0000-0000-0000-000000000001');

insert into knowledge.publication_events
  (claim_id, action, revision_id, revision_number,
   published_by_actor_id, published_by_actor_type, reason, published_at)
select r.claim_id, 'publish', r.id, r.revision_number, a.id, 'human',
       'Hendelse opprettet for tilgangstestene.', now()
from knowledge.claim_revisions r, provenance.actors a
join catalog.drugs d on true
where a.actor_key = 'human:publisher-270'
  and d.canonical_name = 'sertralin'
  and r.subject_drug_id = d.id;

-- ---------------------------------------------------------------------------
-- Lag 1: grants
-- ---------------------------------------------------------------------------
select is_empty(
  $$
    select r.role_name, p.privilege
    from (values ('anon'), ('authenticated'), ('service_role'), ('public'))
           as r(role_name)
    cross join (values ('select'), ('insert'), ('update'), ('delete'), ('truncate'),
                       ('references'), ('trigger')) as p(privilege)
    where has_table_privilege(r.role_name, 'knowledge.publication_events', p.privilege)
  $$,
  'ingen klientrolle har noe tabellprivilegium på publiseringshistorikken'
);

-- Uttømmende over schemaet: en ny funksjon i knowledge skal ikke kunne bli
-- kjørbar for en klientrolle ved at noen glemmer å føre den opp her. EXECUTE til
-- authenticated er bevisst ikke gitt: knowledge er ikke et eksponert schema i
-- Data API-en, så granten ville ikke gitt noen reell skrivevei — den eksponerte
-- RPC-flaten hører til api-schemaet i migrasjon 007.
select is_empty(
  $$
    select p.oid::regprocedure::text, r.role_name
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join (values ('anon'), ('authenticated'), ('service_role'), ('public'))
           as r(role_name)
    where n.nspname = 'knowledge'
      and has_function_privilege(r.role_name, p.oid, 'execute')
  $$,
  'ingen klientrolle kan kjøre noen funksjon i knowledge, heller ikke publiseringsoperasjonene'
);

-- ---------------------------------------------------------------------------
-- Lag 2: RLS er aktivert, uten policies i dette steget
-- ---------------------------------------------------------------------------
select ok(
  (select c.relrowsecurity from pg_class c
   where c.oid = 'knowledge.publication_events'::regclass),
  'RLS er aktivert på publiseringshistorikken'
);
select is_empty(
  $$
    select p.polname
    from pg_policy p
    where p.polrelid = 'knowledge.publication_events'::regclass
  $$,
  'ingen RLS-policy er skrevet på publiseringshistorikken; den kontrollerte skriveveien er en funksjon, ikke tabelltilgang'
);

-- ---------------------------------------------------------------------------
-- Faktiske forsøk med Data API-rollene
-- ---------------------------------------------------------------------------
set local role anon;
select throws_ok(
  'select 1 from knowledge.publication_events', '42501', null,
  'anon nektes lesing av publiseringshistorikken'
);
select throws_ok(
  $$
    insert into knowledge.publication_events
      (claim_id, action, revision_id, revision_number,
       published_by_actor_id, published_by_actor_type, reason, published_at)
    values (gen_random_uuid(), 'publish', gen_random_uuid(), 1,
            gen_random_uuid(), 'human', 'Anonym publisering.', now())
  $$,
  '42501', null,
  'anon kan ikke registrere en publisering'
);
select throws_ok(
  $$select knowledge.publish_claim_revision(gen_random_uuid(), gen_random_uuid(), 'Anonym.')$$,
  '42501', null,
  'anon kan ikke kalle publiseringsoperasjonen'
);
reset role;

set local role authenticated;
select throws_ok(
  'select 1 from knowledge.publication_events', '42501', null,
  'vanlig innlogget bruker nektes lesing av publiseringshistorikken'
);
select throws_ok(
  $$
    insert into knowledge.publication_events
      (claim_id, action, revision_id, revision_number,
       published_by_actor_id, published_by_actor_type, reason, published_at)
    values (gen_random_uuid(), 'publish', gen_random_uuid(), 1,
            gen_random_uuid(), 'human', 'Selvpublisering.', now())
  $$,
  '42501', null,
  'vanlig innlogget bruker kan ikke skrive rett i publiseringshistorikken og dermed forbi gaten'
);
select throws_ok(
  $$update knowledge.publication_events set reason = 'Omskrevet.'$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke skrive om en registrert publisering'
);
select throws_ok(
  $$delete from knowledge.publication_events$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke slette en publiseringshendelse for å skjule den'
);
-- Den andre veien til den samme tilstanden: pekeren selv.
select throws_ok(
  $$update knowledge.claims set current_published_revision_id = gen_random_uuid()$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke flytte publiseringspekeren direkte'
);
select throws_ok(
  $$select knowledge.publish_claim_revision(gen_random_uuid(), gen_random_uuid(), 'Forsøk.')$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke publisere gjennom operasjonen'
);
select throws_ok(
  $$select knowledge.withdraw_claim_publication(gen_random_uuid(), gen_random_uuid(), 'Forsøk.')$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke avpublisere'
);
select throws_ok(
  $$select knowledge.rollback_claim_publication(
      gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'Forsøk.')$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke rulle tilbake en publisering'
);
-- Gaten og rettighetskontrollen er ikke kjørbare i seg selv heller. Kunne de
-- kalles, ville gaten vært et oppslagsverktøy mot review- og verifikasjonsdata
-- for enhver innlogget bruker.
select throws_ok(
  $$select knowledge.assert_claim_revision_publishable(gen_random_uuid())$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke kjøre publiseringsgaten som oppslag'
);
select throws_ok(
  $$select knowledge.assert_publisher_authorized(gen_random_uuid(), gen_random_uuid())$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke kjøre rettighetskontrollen'
);
reset role;

-- service_role omgår RLS, men ikke grants (DATABASE_ARCHITECTURE.md §49).
set local role service_role;
select throws_ok(
  'select 1 from knowledge.publication_events', '42501', null,
  'service_role nektes lesing av publiseringshistorikken fordi grants mangler'
);
reset role;

-- ---------------------------------------------------------------------------
-- RLS er en reell sperre, ikke bare fraværet av grants
--
-- Selvtest av lag 2: hvis en framtidig migrasjon ved et uhell gir privilegier til
-- en klientrolle, skal RLS fortsatt gi null rader og avvise skriving. Grantene
-- finnes bare inne i denne transaksjonen og rulles tilbake.
-- ---------------------------------------------------------------------------
grant usage on schema knowledge to authenticated;
grant select, insert, update, delete on knowledge.publication_events to authenticated;

select isnt_empty(
  'select 1 from knowledge.publication_events',
  'publiseringshendelsen finnes, sett fra eieren'
);

set local role authenticated;
select is(
  (select count(*) from knowledge.publication_events),
  0::bigint,
  'RLS gir null publiseringshendelser selv med SELECT-grant, fordi ingen policy slipper noen inn'
);
select throws_ok(
  $$
    insert into knowledge.publication_events
      (claim_id, action, revision_id, revision_number,
       published_by_actor_id, published_by_actor_type, reason, published_at)
    values (gen_random_uuid(), 'publish', gen_random_uuid(), 1,
            gen_random_uuid(), 'human', 'Publisering med grant.', now())
  $$,
  '42501', null,
  'RLS stopper skriving i publiseringshistorikken selv om INSERT-granten er gitt ved et uhell'
);
reset role;

select * from finish();

rollback;
