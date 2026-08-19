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
  $$,
  'ingen klientrolle har noe tabellprivilegium på katalogtabellene'
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
-- Lag 2: RLS er aktivert på alle katalogtabeller, uten policies i dette steget
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
select is_empty(
  $$
    select p.polname, c.relname
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'catalog'
  $$,
  'ingen RLS-policy er skrevet ennå; medlemskapsmodellen kommer i migrasjon 005'
);

-- ---------------------------------------------------------------------------
-- Faktiske forsøk med Data API-rollene (42501 = insufficient_privilege)
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
