-- Migrasjon 002 — struktur i catalog.
--
-- Verifiserer at katalogfundamentet fra MVP_IMPLEMENTATION_PLAN.md §19 finnes
-- med den identiteten, de vokabularene og de relasjonene
-- DATABASE_ARCHITECTURE.md §8-§12 krever. Constraint-atferd testes i
-- 050_catalog_constraints_test.sql, tilgang i 060_catalog_access_test.sql.
begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

-- ---------------------------------------------------------------------------
-- Tabellene i migrasjon 002, og ingen flere
-- ---------------------------------------------------------------------------
select has_table('catalog', 'drugs', 'catalog.drugs finnes');
select has_table('catalog', 'drug_names', 'catalog.drug_names finnes');
select has_table('catalog', 'drug_identifiers', 'catalog.drug_identifiers finnes');
select has_table('catalog', 'clinical_concepts', 'catalog.clinical_concepts finnes');
select has_table('catalog', 'populations', 'catalog.populations finnes');

-- catalog.drug_products og ingest hører til migrasjon 009 og skal ikke ha
-- sneket seg inn i dette steget.
select hasnt_table('catalog', 'drug_products', 'catalog.drug_products er ikke opprettet ennå');
select is_empty(
  $$
    select n.nspname
    from pg_namespace n
    where n.nspname = 'ingest'
  $$,
  'ingest-schemaet er ikke opprettet ennå'
);

-- Kanoniske kunnskapstabeller kommer i migrasjon 003-006.
select is_empty(
  $$
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('knowledge', 'workflow', 'provenance', 'audit', 'api')
      and c.relkind in ('r', 'p', 'v', 'm')
  $$,
  'migrasjon 002 oppretter ingen objekter utenfor catalog'
);

-- ---------------------------------------------------------------------------
-- Kontrollerte vokabularer
-- ---------------------------------------------------------------------------
select enum_has_labels(
  'catalog', 'drug_status', array['active', 'historical', 'withdrawn'],
  'catalog.drug_status har statusene active, historical og withdrawn'
);
select enum_has_labels(
  'catalog', 'drug_name_type', array['alias', 'trade_name', 'historical_name'],
  'catalog.drug_name_type skiller alias, handelsnavn og historisk navn'
);
select enum_has_labels(
  'catalog', 'drug_identifier_system', array['atc'],
  'catalog.drug_identifier_system dekker atc'
);
select enum_has_labels(
  'catalog', 'clinical_concept_type',
  array['condition', 'outcome', 'pharmacokinetic_property', 'interaction_mechanism'],
  'catalog.clinical_concept_type dekker pilottemaene i MVP_IMPLEMENTATION_PLAN.md §11'
);
select enum_has_labels(
  'catalog', 'vocabulary_status', array['active', 'deprecated'],
  'catalog.vocabulary_status har active og deprecated'
);
select enum_has_labels(
  'catalog', 'population_pregnancy_context',
  array['pregnancy', 'breastfeeding', 'pregnancy_or_breastfeeding'],
  'catalog.population_pregnancy_context dekker graviditet og amming'
);

select is_empty(
  $$
    select t.type_name
    from (values ('catalog.drug_status'), ('catalog.drug_name_type'),
                 ('catalog.drug_identifier_system'), ('catalog.clinical_concept_type'),
                 ('catalog.vocabulary_status'), ('catalog.population_pregnancy_context'))
           as t(type_name)
    where has_type_privilege('public', t.type_name, 'usage')
  $$,
  'PUBLIC har ikke usage på noen av katalogtypene'
);

-- ---------------------------------------------------------------------------
-- Stabil identitet (DATABASE_ARCHITECTURE.md §7, §8)
-- ---------------------------------------------------------------------------
select col_is_pk('catalog', 'drugs', 'id', 'catalog.drugs har uuid-primærnøkkel på id');
select col_not_null('catalog', 'drugs', 'canonical_name', 'kanonisk navn er påkrevd');
select col_type_is(
  'catalog', 'drugs', 'status', 'catalog.drug_status',
  'status på catalog.drugs er et kontrollert vokabular, ikke fritekst'
);
select col_type_is(
  'catalog', 'drugs', 'updated_at', 'timestamp with time zone',
  'catalog.drugs.updated_at er timestamptz (KNOWLEDGE_MODEL.md §4)'
);
select has_index(
  'catalog', 'drugs', 'drugs_canonical_name_key',
  'kanonisk navn er unikt, men ikke primærnøkkel'
);

-- Eksterne identifikatorer er egne relasjoner, aldri intern primærnøkkel.
select col_isnt_pk(
  'catalog', 'drug_identifiers', 'identifier_value',
  'ATC-verdien er ikke primærnøkkel (DATABASE_ARCHITECTURE.md §8)'
);
select col_is_unique(
  'catalog', 'drug_identifiers', array['identifier_system', 'identifier_value'],
  'samme identifikator i samme system kan ikke peke på to virkestoffer'
);

-- ---------------------------------------------------------------------------
-- Relasjoner, med RESTRICT som hovedregel (DATABASE_ARCHITECTURE.md §37)
-- ---------------------------------------------------------------------------
select fk_ok(
  'catalog', 'drug_names', 'drug_id', 'catalog', 'drugs', 'id',
  'catalog.drug_names peker på catalog.drugs'
);
select fk_ok(
  'catalog', 'drug_identifiers', 'drug_id', 'catalog', 'drugs', 'id',
  'catalog.drug_identifiers peker på catalog.drugs'
);
select fk_ok(
  'catalog', 'clinical_concepts', 'parent_concept_id', 'catalog', 'clinical_concepts', 'id',
  'begrepshierarkiet peker på seg selv'
);
select fk_ok(
  'catalog', 'populations', array['indication_concept_id', 'required_condition_type'],
  'catalog', 'clinical_concepts', array['id', 'concept_type'],
  'indikasjon peker på et begrep med riktig type'
);
select fk_ok(
  'catalog', 'populations', array['comorbidity_concept_id', 'required_condition_type'],
  'catalog', 'clinical_concepts', array['id', 'concept_type'],
  'komorbiditet peker på et begrep med riktig type'
);

select is_empty(
  $$
    select n.nspname, rel.relname, con.conname, con.confdeltype, con.confupdtype
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace n on n.oid = rel.relnamespace
    where n.nspname = 'catalog'
      and con.contype = 'f'
      and (con.confdeltype <> 'r' or con.confupdtype <> 'r')
  $$,
  'alle fremmednøkler i catalog bruker RESTRICT ved delete og update'
);

-- ---------------------------------------------------------------------------
-- Populasjonsdimensjoner (DATABASE_ARCHITECTURE.md §12)
-- ---------------------------------------------------------------------------
select col_is_null(
  'catalog', 'populations', 'age_min_years',
  'alder er en valgfri avgrensning; NULL betyr ingen nedre grense'
);
select col_is_null(
  'catalog', 'populations', 'pregnancy_context',
  'graviditet/amming er en valgfri avgrensning'
);
select col_is_null(
  'catalog', 'populations', 'comorbidity_concept_id',
  'komorbiditet er en valgfri avgrensning'
);

-- ---------------------------------------------------------------------------
-- updated_at vedlikeholdes av databasen, ikke av klienten
-- ---------------------------------------------------------------------------
select is_empty(
  $$
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'catalog'
      and c.relkind = 'r'
      and not exists (
        select 1
        from pg_trigger t
        where t.tgrelid = c.oid
          and not t.tgisinternal
          and t.tgfoid = 'catalog.set_updated_at()'::regprocedure
      )
  $$,
  'alle katalogtabeller vedlikeholder updated_at med catalog.set_updated_at()'
);

select ok(
  not has_function_privilege('public', 'catalog.set_updated_at()', 'execute'),
  'PUBLIC kan ikke kjøre catalog.set_updated_at()'
);

-- ---------------------------------------------------------------------------
-- Dokumentasjon i databasen
-- ---------------------------------------------------------------------------
select is_empty(
  $$
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'catalog'
      and c.relkind = 'r'
      and coalesce(obj_description(c.oid, 'pg_class'), '') = ''
  $$,
  'alle katalogtabeller har en kommentar som dokumenterer formålet'
);
select is_empty(
  $$
    select t.typname
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'catalog'
      and t.typtype = 'e'
      and coalesce(obj_description(t.oid, 'pg_type'), '') = ''
  $$,
  'alle kontrollerte vokabularer i catalog er dokumentert'
);

select * from finish();

rollback;
