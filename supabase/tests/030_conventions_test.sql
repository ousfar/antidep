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

select plan(18);

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

-- 3. UUID-primærnøkler genereres av databasen.
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

-- 4. Alle tabeller registrerer når raden ble opprettet.
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

-- 5. RLS er default deny og skal være aktivert på kanoniske tabeller.
create view pg_temp.violation_rls_disabled as
select n.nspname as schema_name, c.relname as object_name
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit')
  and c.relkind in ('r', 'p')
  and not c.relrowsecurity;

-- 6. Ingen kanoniske objekter er gitt til klientrollene.
create view pg_temp.violation_client_grants as
select n.nspname as schema_name,
       c.relname as object_name,
       case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end as grantee,
       a.privilege_type
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(c.relacl) a
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit')
  and (a.grantee = 0 or a.grantee::regrole::text in ('anon', 'authenticated', 'service_role'));

-- 7. Views i api skal ikke omgå underliggende tilgangskontroll.
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

-- 8. SECURITY DEFINER-funksjoner skal ha eksplisitt search_path.
create view pg_temp.violation_security_definer_search_path as
select n.nspname as schema_name, p.proname as object_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit', 'api')
  and p.prosecdef
  and not exists (
    select 1
    from unnest(coalesce(p.proconfig, array[]::text[])) as cfg
    where cfg ~ '^search_path='
  );

-- 9. SECURITY DEFINER-funksjoner skal ikke være kjørbare for PUBLIC.
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
grant select on knowledge.bad_probe_b to anon;
create view api.bad_probe_view as select 1 as x;
create function knowledge.bad_probe_fn() returns integer
  language sql
  security definer
  as $fn$ select 1 $fn$;

select isnt_empty(
  'select * from pg_temp.violation_missing_primary_key',
  'regelen fanger en tabell uten primærnøkkel'
);
select isnt_empty(
  'select * from pg_temp.violation_timestamp_without_time_zone',
  'regelen fanger en kolonne uten tidssone'
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
  'select * from pg_temp.violation_rls_disabled',
  'regelen fanger en tabell uten RLS'
);
select isnt_empty(
  'select * from pg_temp.violation_client_grants',
  'regelen fanger en grant til en klientrolle'
);
select isnt_empty(
  'select * from pg_temp.violation_api_view_security_invoker',
  'regelen fanger et api-view uten security_invoker'
);
select isnt_empty(
  'select * from pg_temp.violation_security_definer_search_path',
  'regelen fanger en SECURITY DEFINER-funksjon uten search_path'
);
select isnt_empty(
  'select * from pg_temp.violation_security_definer_public_execute',
  'regelen fanger en SECURITY DEFINER-funksjon som PUBLIC kan kjøre'
);

drop function knowledge.bad_probe_fn();
drop view api.bad_probe_view;
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
  'select * from pg_temp.violation_uuid_primary_key_default',
  'alle uuid-primærnøkler har default gen_random_uuid()'
);
select is_empty(
  'select * from pg_temp.violation_missing_created_at',
  'alle kanoniske tabeller har created_at timestamptz not null'
);
select is_empty(
  'select * from pg_temp.violation_rls_disabled',
  'alle kanoniske tabeller har RLS aktivert'
);
select is_empty(
  'select * from pg_temp.violation_client_grants',
  'ingen kanoniske objekter er gitt til anon, authenticated, service_role eller PUBLIC'
);
select is_empty(
  'select * from pg_temp.violation_api_view_security_invoker',
  'alle views i api bruker security_invoker'
);
select is_empty(
  'select * from pg_temp.violation_security_definer_search_path',
  'alle SECURITY DEFINER-funksjoner har eksplisitt search_path'
);
select is_empty(
  'select * from pg_temp.violation_security_definer_public_execute',
  'ingen SECURITY DEFINER-funksjon er kjørbar for PUBLIC'
);

select * from finish();

rollback;
