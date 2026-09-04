-- Migrasjon 002 — tilgang til catalog.
--
-- Kritisk negativ test fra MVP_IMPLEMENTATION_PLAN.md §42 og §47 og
-- DATABASE_ARCHITECTURE.md §48, §73: katalogtabellene er default deny.
-- Verken anonyme eller vanlige innloggede brukere skal kunne lese eller skrive
-- i catalog, og RLS skal være den andre sperren, ikke bare fraværet av grants.
-- Klientflaten leser publiserte projeksjoner i api (migrasjon 007).
begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- ---------------------------------------------------------------------------
-- Lag 1: grants
-- ---------------------------------------------------------------------------
-- Migrasjon 007 ga SELECT på de fire katalogtabellene api-lesemodellen slår opp
-- navn i. catalog.drug_names står bevisst utenfor: aliaser og handelsnavn er
-- ikke del av den publiserte projeksjonen ennå. Alt annet er fortsatt stengt.
select is_empty(
  $$
    select t.table_name, r.role_name, p.privilege
    from (values ('catalog.drugs'), ('catalog.drug_names'), ('catalog.drug_identifiers'),
                 ('catalog.clinical_concepts'), ('catalog.populations')) as t(table_name)
    cross join (values ('anon'), ('authenticated'), ('service_role'), ('public'))
           as r(role_name)
    cross join (values ('select'), ('insert'), ('update'), ('delete'), ('truncate'),
                       ('references'), ('trigger')) as p(privilege)
    where has_table_privilege(r.role_name, t.table_name, p.privilege)
      and not (
        p.privilege = 'select'
        and r.role_name in ('anon', 'authenticated')
        and t.table_name in ('catalog.drugs', 'catalog.drug_identifiers',
                             'catalog.clinical_concepts', 'catalog.populations')
      )
  $$,
  'klientrollene har bare SELECT, og bare på de katalogtabellene api-lesemodellen leser'
);

-- Klientrollene har heller ikke usage på selve schemaet, så et framtidig
-- uhell med en enkelt GRANT på en tabell er ikke nok til å åpne catalog.
select ok(
  not has_schema_privilege('anon', 'catalog', 'usage'),
  'anon har ikke usage på catalog'
);
select ok(
  not has_schema_privilege('authenticated', 'catalog', 'usage'),
  'authenticated har ikke usage på catalog'
);

-- ---------------------------------------------------------------------------
-- Lag 2: RLS er aktivert på alle katalogtabeller, og policyene er lesepolicyer
-- ---------------------------------------------------------------------------
select is_empty(
  $$
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'catalog'
      and c.relkind = 'r'
      and not c.relrowsecurity
  $$,
  'RLS er aktivert på alle katalogtabeller'
);
-- Uttømmende inventar, ikke bare et fravær av brudd: en ny policy i catalog må
-- føres opp her, og polcmd 'r' betyr SELECT. En skrivepolicy ville vært en
-- skrivevei forbi publiseringsgaten (DATABASE_ARCHITECTURE.md §43).
--
-- De tre `*_editor_read`-policyene kom med migrasjon 007d og har et annet
-- predikat enn de publiserte: de gir en editor hele katalogen, fordi et
-- evidensfunn må kunne registreres mot et virkestoff, et endepunkt eller en
-- populasjon Antidep ennå ikke har publisert noe om. drug_identifiers har
-- bevisst ingen slik policy: ATC-koder er ikke noe registreringen velger mellom.
select set_eq(
  $$
    select c.relname || ':' || p.polname || ':' || p.polcmd::text
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'catalog'
  $$,
  $$
    values ('drugs:drugs_published_read:r'),
           ('drugs:drugs_editor_read:r'),
           ('drug_identifiers:drug_identifiers_published_read:r'),
           ('clinical_concepts:clinical_concepts_published_read:r'),
           ('clinical_concepts:clinical_concepts_editor_read:r'),
           ('populations:populations_published_read:r'),
           ('populations:populations_editor_read:r')
  $$,
  'catalog har nøyaktig de sju lesepolicyene lesemodellene trenger, og ingen skrivepolicy'
);

-- ---------------------------------------------------------------------------
-- Faktiske forsøk med Data API-rollene (42501 = insufficient_privilege)
--
-- Merk hva som nå stopper dem. Etter migrasjon 007 *har* anon og authenticated
-- SELECT på flere av tabellene under, men de mangler fortsatt usage på schemaet
-- og kan derfor ikke navngi dem: feilen er «permission denied for schema», ikke
-- «for table». Grantene virker bare gjennom viewene i api, som ble navneoppslått
-- da de ble opprettet. Skulle usage bli gitt ved et uhell, er RLS neste sperre,
-- og den kontrolleres i 290_api_read_model_access_test.sql.
-- ---------------------------------------------------------------------------
set local role anon;
select throws_ok(
  'select 1 from catalog.drugs',
  '42501', null,
  'anon nektes lesing av virkestoffkatalogen'
);
select throws_ok(
  'select 1 from catalog.clinical_concepts',
  '42501', null,
  'anon nektes lesing av begrepsvokabularet'
);
select throws_ok(
  $$insert into catalog.drugs (canonical_name) values ('anon-innsatt')$$,
  '42501', null,
  'anon kan ikke opprette virkestoff'
);
reset role;

set local role authenticated;
select throws_ok(
  'select 1 from catalog.drugs',
  '42501', null,
  'vanlig innlogget bruker nektes lesing av virkestoffkatalogen'
);
select throws_ok(
  'select 1 from catalog.populations',
  '42501', null,
  'vanlig innlogget bruker nektes lesing av populasjonene'
);
select throws_ok(
  $$update catalog.drugs set status = 'withdrawn'$$,
  '42501', null,
  'vanlig innlogget bruker kan ikke endre virkestoffstatus'
);
select throws_ok(
  'delete from catalog.clinical_concepts',
  '42501', null,
  'vanlig innlogget bruker kan ikke slette kliniske begreper'
);
reset role;

-- service_role omgår RLS, men ikke grants, og er ikke applikasjonens
-- universalnøkkel (DATABASE_ARCHITECTURE.md §49).
set local role service_role;
select throws_ok(
  'select 1 from catalog.drugs',
  '42501', null,
  'service_role nektes lesing av catalog fordi grants mangler'
);
reset role;

-- ---------------------------------------------------------------------------
-- RLS er en reell sperre, ikke bare fraværet av grants
--
-- Selvtest av lag 2: hvis en framtidig migrasjon ved et uhell gir SELECT til en
-- klientrolle, skal RLS fortsatt gi null rader. Granten finnes bare inne i
-- denne transaksjonen og rulles tilbake.
-- ---------------------------------------------------------------------------
grant usage on schema catalog to authenticated;
grant select on catalog.drugs to authenticated;

set local role authenticated;
select is(
  (select count(*) from catalog.drugs),
  0::bigint,
  'RLS gir null rader selv med SELECT-grant, fordi ingen policy slipper noen inn'
);
reset role;

select * from finish();

rollback;
