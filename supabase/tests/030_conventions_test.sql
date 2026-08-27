-- Migrasjon 001 — konvensjoner for UUID, tidsstempler, RLS, grants,
-- view-sikkerhet og privilegerte funksjoner.
--
-- Konvensjonene er definert i migrasjon 001 og i DATABASE_ARCHITECTURE.md
-- §5, §7.3, §8, §42, §48 og §50. Denne testen er en varig vaktpost: den gjelder
-- alle objekter som senere migrasjoner oppretter i Antidep-schemaene.
--
-- Hver regel selvtestes først mot bevisst ikke-konforme probeobjekter, slik at
-- en regel som er stille ødelagt ikke kan se ut som om den er oppfylt. Alt som
-- opprettes her rulles tilbake når testen er ferdig.
begin;

create extension if not exists pgtap with schema extensions;

select plan(31);

-- ---------------------------------------------------------------------------
-- Regeldefinisjoner. Hver view returnerer bruddene på én konvensjon.
-- ---------------------------------------------------------------------------

-- 1. Alle tabeller i de kanoniske schemaene har primærnøkkel.
create view pg_temp.violation_missing_primary_key as
select n.nspname as schema_name, c.relname as object_name
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit')
  and c.relkind in ('r', 'p')
  and not exists (select 1 from pg_index i where i.indrelid = c.oid and i.indisprimary);

-- 2. Tidspunkter lagres alltid med tidssone.
create view pg_temp.violation_timestamp_without_time_zone as
select n.nspname as schema_name, c.relname as object_name, a.attname as column_name
from pg_attribute a
join pg_class c on c.oid = a.attrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit', 'api')
  and c.relkind in ('r', 'p', 'v', 'm')
  and a.attnum > 0
  and not a.attisdropped
  and a.atttypid in ('pg_catalog.timestamp'::regtype, 'pg_catalog.time'::regtype);

-- 3. Primærnøkkelen er én enkelt uuid-kolonne (DATABASE_ARCHITECTURE.md §8).
-- Eksterne identifikatorer og naturlige nøkler modelleres som egne kolonner med
-- unike constraints, ikke som intern primærnøkkel.
create view pg_temp.violation_non_uuid_primary_key as
select n.nspname as schema_name,
       c.relname as object_name,
       a.attname as column_name,
       format_type(a.atttypid, a.atttypmod) as column_type
from pg_index i
join pg_class c on c.oid = i.indrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute a on a.attrelid = c.oid and a.attnum = any (i.indkey)
where i.indisprimary
  and n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit')
  and c.relkind in ('r', 'p')
  and (i.indnkeyatts <> 1 or a.atttypid <> 'pg_catalog.uuid'::regtype);

-- 4. UUID-primærnøkler genereres av databasen.
create view pg_temp.violation_uuid_primary_key_default as
select n.nspname as schema_name, c.relname as object_name, a.attname as column_name
from pg_index i
join pg_class c on c.oid = i.indrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute a on a.attrelid = c.oid and a.attnum = any (i.indkey)
left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
where i.indisprimary
  and n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit')
  and a.atttypid = 'pg_catalog.uuid'::regtype
  and coalesce(pg_get_expr(d.adbin, d.adrelid), '') not like '%gen_random_uuid()%';

-- 5. Alle tabeller registrerer når raden ble opprettet.
create view pg_temp.violation_missing_created_at as
select n.nspname as schema_name, c.relname as object_name
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit')
  and c.relkind in ('r', 'p')
  and not exists (
    select 1
    from pg_attribute a
    where a.attrelid = c.oid
      and a.attname = 'created_at'
      and a.attnum > 0
      and not a.attisdropped
      and a.atttypid = 'pg_catalog.timestamptz'::regtype
      and a.attnotnull
  );

-- 6. created_at settes av databasen, ikke av klienten.
create view pg_temp.violation_created_at_without_default as
select n.nspname as schema_name,
       c.relname as object_name,
       coalesce(pg_get_expr(d.adbin, d.adrelid), '(ingen default)') as default_expression
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute a
  on a.attrelid = c.oid
  and a.attname = 'created_at'
  and a.attnum > 0
  and not a.attisdropped
left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit')
  and c.relkind in ('r', 'p')
  and coalesce(pg_get_expr(d.adbin, d.adrelid), '') !~* '^(now\(\)|current_timestamp|transaction_timestamp\(\)|statement_timestamp\(\)|clock_timestamp\(\))$';

-- 7. RLS er default deny og skal være aktivert på kanoniske tabeller.
create view pg_temp.violation_rls_disabled as
select n.nspname as schema_name, c.relname as object_name
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit')
  and c.relkind in ('r', 'p')
  and not c.relrowsecurity;

-- 8. Klientrollene kan bare ha SELECT i de kanoniske schemaene.
--
-- Regelen var «ingen grants i det hele tatt» fram til migrasjon 007. Den
-- api-lesemodellen krever SELECT på tabellene under viewene, fordi et
-- security_invoker-view leser med kallerens rettigheter
-- (DATABASE_ARCHITECTURE.md §42, §44). Alt annet er fortsatt forbudt: enhver
-- skriverett, enhver rett til PUBLIC, og enhver rett til service_role, som
-- omgår RLS og ikke er applikasjonens universalnøkkel (§49).
--
-- Både tabellvide og kolonnevise grants telles. Et grant på kolonnenivå ligger i
-- pg_attribute.attacl og ikke i pg_class.relacl, og er heller ikke synlig i
-- has_table_privilege(); en regel som bare leste relacl ville derfor sluttet å
-- måle i det migrasjon 007a tok kolonnegrant i bruk, uten å feile. Formen er nå
-- brukt av tre migrasjoner (007a, 007b), så blindsonen er reell og ikke
-- hypotetisk.
create view pg_temp.violation_client_write_grants as
select n.nspname as schema_name,
       c.relname as object_name,
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
union all
select n.nspname,
       c.relname || '.' || att.attname,
       case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end,
       a.privilege_type
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute att
  on att.attrelid = c.oid and att.attnum > 0 and not att.attisdropped
cross join lateral aclexplode(att.attacl) a
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit')
  and (
    a.grantee = 0
    or a.grantee::regrole::text = 'service_role'
    or (a.grantee::regrole::text in ('anon', 'authenticated')
        and a.privilege_type <> 'SELECT')
  );

-- 8b. En SELECT-grant til en klientrolle skal alltid ha en policy under seg.
--
-- Uten policy gir RLS null rader, så en grant alene lekker ingenting. Den er
-- likevel et brudd: den signaliserer at noen mente å eksponere tabellen, og
-- neste migrasjon som skriver en policy vil da åpne mer enn den tror. Grant og
-- policy hører sammen og skal innføres sammen (DATABASE_ARCHITECTURE.md §44
-- punkt 2 og 3, §48).
--
-- Kolonnegrant teller på samme måte, og av samme grunn som i regel 8a: en
-- migrasjon som åpnet en enkeltkolonne uten å skrive policyen under, ville
-- ellers gått gjennom vakten.
create view pg_temp.violation_client_grant_without_policy as
select n.nspname as schema_name,
       c.relname as object_name,
       case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end as grantee
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(c.relacl) a
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit')
  and a.grantee::regrole::text in ('anon', 'authenticated')
  and not exists (select 1 from pg_policy pol where pol.polrelid = c.oid)
union all
select n.nspname,
       c.relname || '.' || att.attname,
       case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute att
  on att.attrelid = c.oid and att.attnum > 0 and not att.attisdropped
cross join lateral aclexplode(att.attacl) a
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit')
  and a.grantee::regrole::text in ('anon', 'authenticated')
  and not exists (select 1 from pg_policy pol where pol.polrelid = c.oid);

-- 8c. Ingen policy i de kanoniske schemaene åpner for skriving.
--
-- Skriveveien er og blir en kontrollert SECURITY DEFINER-funksjon
-- (DATABASE_ARCHITECTURE.md §43). En policy for INSERT, UPDATE, DELETE eller
-- ALL ville vært en skrivevei forbi publiseringsgaten. pg_policy.polcmd er
-- 'r' for SELECT og '*' for ALL.
create view pg_temp.violation_write_policy as
select n.nspname as schema_name,
       c.relname as object_name,
       pol.polname as policy_name,
       pol.polcmd::text as policy_command
from pg_policy pol
join pg_class c on c.oid = pol.polrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit')
  and pol.polcmd <> 'r';

-- 9. Views i api skal ikke omgå underliggende tilgangskontroll.
create view pg_temp.violation_api_view_security_invoker as
select n.nspname as schema_name, c.relname as object_name
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'api'
  and c.relkind = 'v'
  and coalesce(
        (select o.option_value
         from pg_options_to_table(c.reloptions) o
         where o.option_name = 'security_invoker'),
        'false'
      ) not in ('true', 'on');

-- 10. SECURITY DEFINER-funksjoner skal ha et kontrollert og tomt search_path.
-- En eksplisitt, men utrygg verdi (`public`, `"$user", public`, `pg_temp`) lar
-- kalleren styre navneoppslag i en funksjon som kjører med eierens rettigheter,
-- og skal derfor behandles som brudd. Konvensjonen er `set search_path = ''`
-- kombinert med schemakvalifiserte objektnavn (DATABASE_ARCHITECTURE.md §50).
create view pg_temp.violation_security_definer_search_path as
select n.nspname as schema_name,
       p.proname as object_name,
       coalesce(array_to_string(p.proconfig, ', '), '(ingen search_path)') as configuration
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit', 'api')
  and p.prosecdef
  and not exists (
    select 1
    from unnest(coalesce(p.proconfig, array[]::text[])) as cfg
    where cfg in ('search_path=""', 'search_path=')
  );

-- 11. SECURITY DEFINER-funksjoner skal ikke være kjørbare for PUBLIC.
create view pg_temp.violation_security_definer_public_execute as
select n.nspname as schema_name, p.proname as object_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit', 'api')
  and p.prosecdef
  and (
    p.proacl is null
    or exists (
      select 1
      from aclexplode(p.proacl) a
      where a.grantee = 0 and a.privilege_type = 'EXECUTE'
    )
  );

-- ---------------------------------------------------------------------------
-- Selvtest: reglene skal fange bevisste brudd.
-- ---------------------------------------------------------------------------
create table knowledge.bad_probe_a (id uuid primary key, noted_at timestamp);
create table knowledge.bad_probe_b (x integer);
-- SELECT uten policy under: bruddet regel 8b beskriver.
grant select on knowledge.bad_probe_b to anon;
-- En skriverett til en klientrolle: bruddet regel 8a beskriver.
grant insert on knowledge.bad_probe_b to authenticated;
-- En policy som åpner for mer enn lesing: bruddet regel 8c beskriver.
create table knowledge.bad_probe_e (id uuid primary key default gen_random_uuid());
create policy bad_probe_e_write on knowledge.bad_probe_e
  for all to authenticated using (true);
-- Kolonnegrant uten policy under, og en skriverett på kolonnenivå: de to
-- formene regel 8a og 8b ikke så før de leste pg_attribute.attacl.
create table knowledge.bad_probe_f (
  id uuid primary key default gen_random_uuid(),
  begrunnelse text
);
grant select (begrunnelse) on knowledge.bad_probe_f to anon;
grant insert (begrunnelse) on knowledge.bad_probe_f to authenticated;
create table knowledge.bad_probe_c (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now()
);
create table knowledge.bad_probe_d (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null
);
create view api.bad_probe_view as select 1 as x;
create function knowledge.bad_probe_fn() returns integer
  language sql
  security definer
  as $fn$ select 1 $fn$;
create function knowledge.bad_probe_fn_unsafe_path() returns integer
  language sql
  security definer
  set search_path = public
  as $fn$ select 1 $fn$;
revoke execute on function knowledge.bad_probe_fn_unsafe_path() from public;

select isnt_empty(
  'select * from pg_temp.violation_missing_primary_key',
  'regelen fanger en tabell uten primærnøkkel'
);
select isnt_empty(
  'select * from pg_temp.violation_timestamp_without_time_zone',
  'regelen fanger en kolonne uten tidssone'
);
select isnt_empty(
  'select * from pg_temp.violation_non_uuid_primary_key',
  'regelen fanger en primærnøkkel som ikke er én uuid-kolonne'
);
select isnt_empty(
  'select * from pg_temp.violation_uuid_primary_key_default',
  'regelen fanger en uuid-primærnøkkel uten gen_random_uuid()'
);
select isnt_empty(
  'select * from pg_temp.violation_missing_created_at',
  'regelen fanger en tabell uten created_at'
);
select isnt_empty(
  'select * from pg_temp.violation_created_at_without_default',
  'regelen fanger en created_at uten databasegenerert default'
);
select isnt_empty(
  'select * from pg_temp.violation_rls_disabled',
  'regelen fanger en tabell uten RLS'
);
select isnt_empty(
  'select * from pg_temp.violation_client_write_grants',
  'regelen fanger en skriverett gitt til en klientrolle'
);
select isnt_empty(
  'select * from pg_temp.violation_client_grant_without_policy',
  'regelen fanger en SELECT-grant uten policy under seg'
);
select isnt_empty(
  'select * from pg_temp.violation_write_policy',
  'regelen fanger en policy som åpner for skriving'
);
select isnt_empty(
  $$
    select * from pg_temp.violation_client_write_grants
    where object_name = 'bad_probe_f.begrunnelse' and privilege_type = 'INSERT'
  $$,
  'regelen fanger en skriverett gitt på kolonnenivå, som pg_class.relacl ikke bærer'
);
select isnt_empty(
  $$
    select * from pg_temp.violation_client_grant_without_policy
    where object_name = 'bad_probe_f.begrunnelse'
  $$,
  'regelen fanger et kolonnegrant uten policy under seg'
);
select isnt_empty(
  'select * from pg_temp.violation_api_view_security_invoker',
  'regelen fanger et api-view uten security_invoker'
);
select isnt_empty(
  'select * from pg_temp.violation_security_definer_search_path',
  'regelen fanger en SECURITY DEFINER-funksjon uten trygt search_path'
);
select isnt_empty(
  'select * from pg_temp.violation_security_definer_public_execute',
  'regelen fanger en SECURITY DEFINER-funksjon som PUBLIC kan kjøre'
);

-- En funksjon med tomt search_path og uten EXECUTE til PUBLIC er konform og
-- skal ikke flagges av noen av funksjonsreglene.
create function knowledge.good_probe_fn() returns integer
  language sql
  security definer
  set search_path = ''
  as $fn$ select 1 $fn$;
revoke execute on function knowledge.good_probe_fn() from public;

select is_empty(
  $$
    select * from pg_temp.violation_security_definer_search_path
    where object_name = 'good_probe_fn'
  $$,
  'en SECURITY DEFINER-funksjon med search_path = '''' regnes som konform'
);

drop function knowledge.good_probe_fn();

-- Og motsatt: en tabell med bare SELECT til klientrollene og en lesepolicy under
-- er nettopp formen migrasjon 007 innfører, og skal ikke flagges av noen av de
-- tre grantreglene. Uten denne kontrollen kunne reglene vært trivielt oppfylt
-- ved å flagge alt.
create table knowledge.good_probe_exposed (id uuid primary key default gen_random_uuid());
alter table knowledge.good_probe_exposed enable row level security;
create policy good_probe_exposed_read on knowledge.good_probe_exposed
  for select to anon, authenticated using (true);
grant select on knowledge.good_probe_exposed to anon, authenticated;

select is_empty(
  $$
    select 'skriverett' as regel, schema_name, object_name
    from pg_temp.violation_client_write_grants where object_name = 'good_probe_exposed'
    union all
    select 'grant uten policy', schema_name, object_name
    from pg_temp.violation_client_grant_without_policy where object_name = 'good_probe_exposed'
    union all
    select 'skrivepolicy', schema_name, object_name
    from pg_temp.violation_write_policy where object_name = 'good_probe_exposed'
  $$,
  'en tabell med bare SELECT til klientrollene og en lesepolicy under regnes som konform'
);

drop table knowledge.good_probe_exposed;

-- Og formen migrasjon 007a og 007b innfører: ingen tabellvid grant, bare noen
-- kolonner åpnet, med en lesepolicy under. Uten denne kontrollen kunne de to
-- utvidede reglene vært trivielt oppfylt ved å flagge hvert kolonnegrant.
create table knowledge.good_probe_columns (
  id uuid primary key default gen_random_uuid(),
  aapen text,
  lukket text
);
alter table knowledge.good_probe_columns enable row level security;
create policy good_probe_columns_read on knowledge.good_probe_columns
  for select to authenticated using (true);
grant select (aapen) on knowledge.good_probe_columns to authenticated;

select is_empty(
  $$
    select 'skriverett' as regel, schema_name, object_name
    from pg_temp.violation_client_write_grants
    where object_name like 'good_probe_columns%'
    union all
    select 'grant uten policy', schema_name, object_name
    from pg_temp.violation_client_grant_without_policy
    where object_name like 'good_probe_columns%'
  $$,
  'en tabell med bare et SELECT-grant på kolonnenivå og en lesepolicy under regnes som konform'
);

drop table knowledge.good_probe_columns;
drop function knowledge.bad_probe_fn_unsafe_path();
drop function knowledge.bad_probe_fn();
drop view api.bad_probe_view;
drop table knowledge.bad_probe_f;
drop table knowledge.bad_probe_e;
drop table knowledge.bad_probe_d;
drop table knowledge.bad_probe_c;
drop table knowledge.bad_probe_b;
drop table knowledge.bad_probe_a;

-- ---------------------------------------------------------------------------
-- Faktisk tilstand: ingen brudd i databasen.
-- ---------------------------------------------------------------------------
select is_empty(
  'select * from pg_temp.violation_missing_primary_key',
  'alle kanoniske tabeller har primærnøkkel'
);
select is_empty(
  'select * from pg_temp.violation_timestamp_without_time_zone',
  'ingen kolonne bruker timestamp eller time uten tidssone'
);
select is_empty(
  'select * from pg_temp.violation_non_uuid_primary_key',
  'alle kanoniske tabeller har én uuid-kolonne som primærnøkkel'
);
select is_empty(
  'select * from pg_temp.violation_uuid_primary_key_default',
  'alle uuid-primærnøkler har default gen_random_uuid()'
);
select is_empty(
  'select * from pg_temp.violation_missing_created_at',
  'alle kanoniske tabeller har created_at timestamptz not null'
);
select is_empty(
  'select * from pg_temp.violation_created_at_without_default',
  'alle created_at-kolonner har databasegenerert default'
);
select is_empty(
  'select * from pg_temp.violation_rls_disabled',
  'alle kanoniske tabeller har RLS aktivert'
);
select is_empty(
  'select * from pg_temp.violation_client_write_grants',
  'ingen kanonisk tabell gir skriverett til en klientrolle, og verken PUBLIC eller service_role har noe'
);
select is_empty(
  'select * from pg_temp.violation_client_grant_without_policy',
  'hver SELECT-grant til en klientrolle har en RLS-policy under seg'
);
select is_empty(
  'select * from pg_temp.violation_write_policy',
  'ingen RLS-policy i de kanoniske schemaene åpner for annet enn lesing'
);
select is_empty(
  'select * from pg_temp.violation_api_view_security_invoker',
  'alle views i api bruker security_invoker'
);
select is_empty(
  'select * from pg_temp.violation_security_definer_search_path',
  'alle SECURITY DEFINER-funksjoner har search_path = '''''
);
select is_empty(
  'select * from pg_temp.violation_security_definer_public_execute',
  'ingen SECURITY DEFINER-funksjon er kjørbar for PUBLIC'
);

select * from finish();

rollback;
