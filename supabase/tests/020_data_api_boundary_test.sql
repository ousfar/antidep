-- Migrasjon 001 — Data API-grensen.
-- Dette er den kritiske negative testen fra MVP_IMPLEMENTATION_PLAN.md §18 og §42:
-- kanoniske schemaer skal ikke være lesbare for anonyme eller vanlige innloggede
-- brukere, og api-schemaet skal bare gi tilgang til objekter som eksplisitt er
-- gitt en grant (DATABASE_ARCHITECTURE.md §5, §44, §47, §49).
begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

-- ---------------------------------------------------------------------------
-- Schema-nivå
-- ---------------------------------------------------------------------------

-- has_schema_privilege tar hensyn til privilegier som er gitt til PUBLIC, så
-- matrisen dekker både direkte grants og arv fra PUBLIC.
select is_empty(
  $$
    select s.schema_name, r.role_name, p.privilege
    from (values ('catalog'), ('knowledge'), ('workflow'), ('provenance'), ('audit'))
           as s(schema_name)
    cross join (values ('anon'), ('authenticated'), ('service_role'), ('public'))
           as r(role_name)
    cross join (values ('usage'), ('create')) as p(privilege)
    where has_schema_privilege(r.role_name, s.schema_name, p.privilege)
  $$,
  'ingen klientrolle har usage eller create på catalog, knowledge, workflow, provenance eller audit'
);

select ok(has_schema_privilege('anon', 'api', 'usage'), 'anon har usage på api');
select ok(
  has_schema_privilege('authenticated', 'api', 'usage'),
  'authenticated har usage på api'
);
select ok(not has_schema_privilege('anon', 'api', 'create'), 'anon kan ikke opprette objekter i api');
select ok(
  not has_schema_privilege('authenticated', 'api', 'create'),
  'authenticated kan ikke opprette objekter i api'
);
select ok(
  not has_schema_privilege('service_role', 'api', 'usage'),
  'service_role har ingen tilgang til api og er ikke applikasjonens universalnøkkel'
);
select ok(not has_schema_privilege('public', 'api', 'usage'), 'PUBLIC har ikke usage på api');

-- ---------------------------------------------------------------------------
-- Objektnivå: nye tabeller arver ingen tilgang
--
-- Probetabellene finnes bare inne i denne transaksjonen og rulles tilbake.
-- ---------------------------------------------------------------------------
create table knowledge.rls_probe (id uuid primary key default gen_random_uuid());
create table api.exposure_probe (id uuid primary key default gen_random_uuid());

select is_empty(
  $$
    select t.table_name, r.role_name, p.privilege
    from (values ('knowledge.rls_probe'), ('api.exposure_probe')) as t(table_name)
    cross join (values ('anon'), ('authenticated'), ('service_role'), ('public'))
           as r(role_name)
    cross join (values ('select'), ('insert'), ('update'), ('delete'), ('truncate'),
                       ('references'), ('trigger')) as p(privilege)
    where has_table_privilege(r.role_name, t.table_name, p.privilege)
  $$,
  'en ny tabell i knowledge eller api gir ingen tabellprivilegier til klientrollene'
);

-- Fram til migrasjon 007 hadde ingen tabell i de kanoniske schemaene noen
-- ACL-oppføring for klientrollene i det hele tatt. api-lesemodellen krever
-- SELECT på tabellene under viewene, fordi et security_invoker-view leser med
-- kallerens rettigheter (DATABASE_ARCHITECTURE.md §42). Grensen her er derfor
-- ikke lenger «ingenting», men «bare lesing, bare til de to Data API-rollene».
--
-- Hvilke tabeller som faktisk er åpnet, er en egen og uttømmende kontrakt i
-- 290_api_read_model_access_test.sql. Denne assertionen er den generelle
-- regelen som gjelder uansett hvilke tabeller lesemodellen vokser til.
select is_empty(
  $$
    select c.relname,
           case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end as grantee,
           a.privilege_type
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(c.relacl) a
    where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit')
      and (
        a.grantee = 0
        or a.grantee::regrole::text = 'service_role'
        or (a.grantee::regrole::text in ('anon', 'authenticated')
            and a.privilege_type <> 'SELECT')
      )
  $$,
  'ingen tabell i de kanoniske schemaene gir klientrollene mer enn SELECT, og verken PUBLIC eller service_role har noe'
);

-- ---------------------------------------------------------------------------
-- Faktiske forsøk med Data API-rollene (42501 = insufficient_privilege)
-- ---------------------------------------------------------------------------
set local role anon;
select throws_ok(
  'select 1 from knowledge.rls_probe',
  '42501',
  null,
  'anon nektes lesing i knowledge'
);
select throws_ok(
  'select 1 from api.exposure_probe',
  '42501',
  null,
  'anon nektes lesing av et api-objekt uten egen grant'
);
select throws_ok(
  'create table knowledge.anon_probe (x int)',
  '42501',
  null,
  'anon kan ikke opprette objekter i knowledge'
);
select throws_ok(
  'create table api.anon_probe (x int)',
  '42501',
  null,
  'anon kan ikke opprette objekter i api'
);
select throws_ok('create schema anon_probe', '42501', null, 'anon kan ikke opprette schemaer');
reset role;

set local role authenticated;
select throws_ok(
  'select 1 from knowledge.rls_probe',
  '42501',
  null,
  'vanlig innlogget bruker nektes lesing i knowledge'
);
select throws_ok(
  'create table knowledge.authenticated_probe (x int)',
  '42501',
  null,
  'vanlig innlogget bruker kan ikke opprette objekter i knowledge'
);
reset role;

-- service_role omgår RLS, men ikke grants.
set local role service_role;
select throws_ok(
  'select 1 from knowledge.rls_probe',
  '42501',
  null,
  'service_role nektes lesing i knowledge fordi grants mangler'
);
reset role;

-- ---------------------------------------------------------------------------
-- public brukes ikke som lagringsplass for Antidep-objekter
-- (DATABASE_ARCHITECTURE.md §6)
-- ---------------------------------------------------------------------------
select is_empty(
  $$
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p', 'v', 'm', 'f')
  $$,
  'public-schemaet inneholder ingen Antidep-objekter'
);

select * from finish();

rollback;
