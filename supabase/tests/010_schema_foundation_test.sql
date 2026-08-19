-- Migrasjon 001 — schemafundament og rollevokabular.
-- Verifiserer strukturen som DATABASE_ARCHITECTURE.md §6 og
-- MVP_IMPLEMENTATION_PLAN.md §16/§18 krever.
begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- De seks logiske schemaene finnes.
select has_schema('catalog', 'catalog-schemaet finnes');
select has_schema('knowledge', 'knowledge-schemaet finnes');
select has_schema('workflow', 'workflow-schemaet finnes');
select has_schema('provenance', 'provenance-schemaet finnes');
select has_schema('audit', 'audit-schemaet finnes');
select has_schema('api', 'api-schemaet finnes');

-- Schemaene eies av migrasjonsrollen, ikke av en Data API-rolle.
select schema_owner_is('catalog', 'postgres', 'catalog eies av postgres');
select schema_owner_is('knowledge', 'postgres', 'knowledge eies av postgres');
select schema_owner_is('workflow', 'postgres', 'workflow eies av postgres');
select schema_owner_is('provenance', 'postgres', 'provenance eies av postgres');
select schema_owner_is('audit', 'postgres', 'audit eies av postgres');
select schema_owner_is('api', 'postgres', 'api eies av postgres');

-- Formålet med hvert schema skal være dokumentert i databasen.
select is_empty(
  $$
    select n.nspname
    from pg_namespace n
    where n.nspname in ('catalog', 'knowledge', 'workflow', 'provenance', 'audit', 'api')
      and coalesce(obj_description(n.oid, 'pg_namespace'), '') = ''
  $$,
  'alle Antidep-schemaer har en kommentar som dokumenterer formålet'
);

-- Rollevokabularet (MVP_IMPLEMENTATION_PLAN.md §16).
select has_type('workflow', 'app_role', 'workflow.app_role finnes');
select enum_has_labels(
  'workflow',
  'app_role',
  array['editor', 'reviewer', 'publisher', 'admin'],
  'workflow.app_role har rollene editor, reviewer, publisher og admin'
);
select ok(
  not has_type_privilege('public', 'workflow.app_role', 'usage'),
  'PUBLIC har ikke usage på workflow.app_role'
);

select * from finish();

rollback;
