-- Migrasjon 003 — struktur i knowledge.
--
-- Verifiserer at kilde- og evidenslaget fra MVP_IMPLEMENTATION_PLAN.md §20
-- finnes med den identiteten, de vokabularene og de relasjonene
-- DATABASE_ARCHITECTURE.md §16-§20 krever. Constraint-atferd testes i
-- 090_knowledge_constraints_test.sql, immutabilitet i
-- 100_knowledge_immutability_test.sql, tilgang i 110_knowledge_access_test.sql
-- og selve slicedataene i 120_knowledge_seed_test.sql.
begin;

create extension if not exists pgtap with schema extensions;

select plan(48);

-- ---------------------------------------------------------------------------
-- Tabellene i migrasjon 003
-- ---------------------------------------------------------------------------
select has_table('knowledge', 'sources', 'knowledge.sources finnes');
select has_table('knowledge', 'source_identifiers', 'knowledge.source_identifiers finnes');
select has_table('knowledge', 'source_versions', 'knowledge.source_versions finnes');
select has_table('knowledge', 'evidence_items', 'knowledge.evidence_items finnes');

-- Claims, evidenslenker, vurderinger og review hører til migrasjon 004-005 og
-- skal ikke ha sneket seg inn i dette steget.
select hasnt_table('knowledge', 'claims', 'knowledge.claims er ikke opprettet ennå');
select hasnt_table(
  'knowledge', 'claim_revisions', 'knowledge.claim_revisions er ikke opprettet ennå'
);
select hasnt_table(
  'knowledge', 'claim_evidence_links', 'knowledge.claim_evidence_links er ikke opprettet ennå'
);
select hasnt_table(
  'knowledge', 'evidence_assessments', 'knowledge.evidence_assessments er ikke opprettet ennå'
);
select hasnt_table(
  'knowledge', 'publication_events', 'knowledge.publication_events er ikke opprettet ennå'
);

-- ---------------------------------------------------------------------------
-- Kontrollerte vokabularer
-- ---------------------------------------------------------------------------
select enum_has_labels(
  'knowledge', 'source_type',
  array['journal_article', 'clinical_guideline', 'summary_of_product_characteristics',
        'regulatory_communication', 'public_dataset'],
  'knowledge.source_type beskriver dokumenttype, ikke studiedesign'
);

-- DATABASE_ARCHITECTURE.md §58: en tilbaketrukket kilde skal ikke kunne passere
-- en senere publiseringsgate som om statusen var normal. Da må vokabularet
-- kunne uttrykke tilstanden i det hele tatt, og verdiene må ikke kunne
-- forsvinne senere uten at denne testen sier fra.
select enum_has_labels(
  'knowledge', 'source_status',
  array['active', 'outdated', 'superseded', 'retracted', 'withdrawn'],
  'knowledge.source_status kan uttrykke retracted og withdrawn'
);
select enum_has_labels(
  'knowledge', 'source_identifier_system', array['doi', 'pmid'],
  'knowledge.source_identifier_system dekker DOI og PMID'
);
select enum_has_labels(
  'knowledge', 'date_precision', array['year', 'month', 'day'],
  'knowledge.date_precision skiller år, måned og dag'
);
select enum_has_labels(
  'knowledge', 'study_design', array['randomized_controlled_trial'],
  'knowledge.study_design dekker designet første slice bruker'
);
select enum_has_labels(
  'knowledge', 'comparator_kind', array['drug', 'placebo', 'none'],
  'knowledge.comparator_kind skiller virkestoff, placebo og ingen komparator'
);
select enum_has_labels(
  'knowledge', 'effect_measure',
  array['mean_change', 'mean_difference', 'standardised_mean_difference',
        'risk_ratio', 'odds_ratio'],
  'knowledge.effect_measure dekker målene i KNOWLEDGE_MODEL.md §11'
);
select enum_has_labels(
  'knowledge', 'estimate_unit', array['kg', 'percent'],
  'knowledge.estimate_unit dekker enhetene første slice bruker'
);

-- ANTIDEP_CONSTITUTION.md §6 og DATABASE_ARCHITECTURE.md §19.1: et nullfunn er
-- en registrert tilstand, ikke fravær av data.
select enum_has_labels(
  'knowledge', 'effect_direction',
  array['increase', 'decrease', 'no_clear_difference', 'not_stated'],
  'knowledge.effect_direction skiller nullfunn fra manglende retning'
);
select enum_has_labels(
  'knowledge', 'value_availability',
  array['reported_value', 'not_measured', 'not_reported', 'not_applicable',
        'not_extractable', 'uncertain_extraction'],
  'knowledge.value_availability skiller ikke målt, ikke rapportert og ikke uthentbar'
);
select enum_has_labels(
  'knowledge', 'extraction_method',
  array['manual', 'ai_assisted', 'deterministic_import'],
  'knowledge.extraction_method dekker metodene i KNOWLEDGE_MODEL.md §11'
);

select is_empty(
  $$
    select t.type_name
    from (values ('knowledge.source_type'), ('knowledge.source_status'),
                 ('knowledge.source_identifier_system'), ('knowledge.date_precision'),
                 ('knowledge.study_design'), ('knowledge.comparator_kind'),
                 ('knowledge.effect_measure'), ('knowledge.estimate_unit'),
                 ('knowledge.effect_direction'), ('knowledge.value_availability'),
                 ('knowledge.extraction_method')) as t(type_name)
    where has_type_privilege('public', t.type_name, 'usage')
  $$,
  'PUBLIC har ikke usage på noen av kunnskapstypene'
);

-- ---------------------------------------------------------------------------
-- Stabil identitet (DATABASE_ARCHITECTURE.md §7, §8)
-- ---------------------------------------------------------------------------
select col_is_pk('knowledge', 'sources', 'id', 'knowledge.sources har uuid-primærnøkkel');
select col_is_pk(
  'knowledge', 'evidence_items', 'id', 'knowledge.evidence_items har uuid-primærnøkkel'
);

-- Eksterne identifikatorer er egne relasjoner, aldri intern primærnøkkel.
select col_isnt_pk(
  'knowledge', 'source_identifiers', 'identifier_value',
  'DOI/PMID-verdien er ikke primærnøkkel (DATABASE_ARCHITECTURE.md §8)'
);
select col_is_unique(
  'knowledge', 'source_identifiers', array['identifier_system', 'identifier_value'],
  'samme DOI eller PMID kan ikke peke på to kilder'
);

-- ---------------------------------------------------------------------------
-- Relasjoner, med RESTRICT som hovedregel (DATABASE_ARCHITECTURE.md §37)
-- ---------------------------------------------------------------------------
select fk_ok(
  'knowledge', 'source_identifiers', 'source_id', 'knowledge', 'sources', 'id',
  'identifikatorer peker på kilden'
);
select fk_ok(
  'knowledge', 'source_versions', 'source_id', 'knowledge', 'sources', 'id',
  'kildeversjoner peker på kilden'
);
select fk_ok(
  'knowledge', 'sources', 'superseded_by_source_id', 'knowledge', 'sources', 'id',
  'erstatningspekeren peker på en annen kilde'
);
select fk_ok(
  'knowledge', 'evidence_items', 'source_id', 'knowledge', 'sources', 'id',
  'evidensfunn peker på kilden'
);
select fk_ok(
  'knowledge', 'evidence_items', 'population_id', 'catalog', 'populations', 'id',
  'evidensfunn peker på en katalogpopulasjon'
);
select fk_ok(
  'knowledge', 'evidence_items', 'intervention_drug_id', 'catalog', 'drugs', 'id',
  'intervensjonen peker på et virkestoff i katalogen'
);

-- Cross-row-reglene er løst med sammensatte fremmednøkler, ikke med CHECK som
-- leser andre tabeller (DATABASE_ARCHITECTURE.md §59).
select fk_ok(
  'knowledge', 'evidence_items', array['source_version_id', 'source_id'],
  'knowledge', 'source_versions', array['id', 'source_id'],
  'kildeversjonen på et evidensfunn må tilhøre den samme kilden'
);
select fk_ok(
  'knowledge', 'evidence_items', array['outcome_concept_id', 'required_outcome_type'],
  'catalog', 'clinical_concepts', array['id', 'concept_type'],
  'endepunktet må være et begrep av typen outcome'
);

select is_empty(
  $$
    select n.nspname, rel.relname, con.conname, con.confdeltype, con.confupdtype
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace n on n.oid = rel.relnamespace
    where n.nspname = 'knowledge'
      and con.contype = 'f'
      and (con.confdeltype <> 'r' or con.confupdtype <> 'r')
  $$,
  'alle fremmednøkler i knowledge bruker RESTRICT ved delete og update'
);

-- ---------------------------------------------------------------------------
-- Presis kildepeker og null/ukjent-semantikk som kolonner
-- ---------------------------------------------------------------------------
select col_not_null(
  'knowledge', 'evidence_items', 'source_locator',
  'et evidensfunn må ha en presis kildepeker (KNOWLEDGE_MODEL.md §11.2)'
);
select col_not_null(
  'knowledge', 'evidence_items', 'reported_direction',
  'retningen er alltid registrert, slik at et nullfunn ikke kan kollapse til NULL'
);
select col_not_null(
  'knowledge', 'evidence_items', 'population_detail',
  'den studerte populasjonen beskrives alltid ordrett'
);

-- Hvert klinisk viktig felt har en ledsagende availability-kolonne
-- (DATABASE_ARCHITECTURE.md §19.1). Testen sier fra hvis et felt legges til
-- eller fjernes uten at semantikken følger med.
select set_eq(
  $$
    select a.attname::text
    from pg_attribute a
    where a.attrelid = 'knowledge.evidence_items'::regclass
      and a.attnum > 0 and not a.attisdropped
      and a.atttypid = 'knowledge.value_availability'::regtype
  $$,
  $$values ('population_availability'), ('sample_size_availability'),
           ('timepoint_availability'), ('estimate_availability'),
           ('confidence_interval_availability')$$,
  'alle klinisk viktige felt på evidensfunnet har eksplisitt null/ukjent-semantikk'
);
select is_empty(
  $$
    select a.attname::text
    from pg_attribute a
    where a.attrelid = 'knowledge.evidence_items'::regclass
      and a.attnum > 0 and not a.attisdropped
      and a.atttypid = 'knowledge.value_availability'::regtype
      and not a.attnotnull
  $$,
  'ingen availability-kolonne kan selv være NULL'
);

-- Rå ekstraksjon og kanoniske felt er atskilt (DATABASE_ARCHITECTURE.md §20).
select col_type_is(
  'knowledge', 'evidence_items', 'raw_extraction', 'jsonb',
  'rå ekstraksjon lagres som jsonb ved siden av de kanoniske kolonnene'
);

-- ---------------------------------------------------------------------------
-- Tidsstempler, triggere og dokumentasjon
-- ---------------------------------------------------------------------------
-- tgtype-bitene: 2 = BEFORE, 4 = INSERT, 16 = UPDATE, 8 = DELETE.
select is_empty(
  $$
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'knowledge'
      and c.relkind = 'r'
      and c.relname <> 'evidence_items'
      and not exists (
        select 1
        from pg_trigger t
        where t.tgrelid = c.oid
          and not t.tgisinternal
          and t.tgfoid = 'catalog.set_row_timestamps()'::regprocedure
          and (t.tgtype & 2) <> 0
          and (t.tgtype & 4) <> 0
          and (t.tgtype & 16) <> 0
      )
  $$,
  'kildetabellene setter created_at og updated_at ved både INSERT og UPDATE'
);

-- knowledge.evidence_items kan ikke endres og har derfor bevisst ingen
-- updated_at: et sist endret-felt ville vært en garanti uten innhold.
select hasnt_column(
  'knowledge', 'evidence_items', 'updated_at',
  'et uforanderlig evidensfunn har ingen updated_at'
);

-- Triggerne som bærer immutabiliteten og det databaseeide fingeravtrykket.
-- Uten disse assertionene ville en droppet trigger først vist seg som en
-- følgefeil et annet sted (DATABASE_ARCHITECTURE.md §7.1, §60).
select has_trigger(
  'knowledge', 'evidence_items', 'evidence_items_reject_mutation',
  'knowledge.evidence_items har en immutable-row guard'
);
select has_trigger(
  'knowledge', 'evidence_items', 'evidence_items_set_content_hash',
  'knowledge.evidence_items får content_hash satt av databasen'
);
select has_trigger(
  'knowledge', 'source_versions', 'source_versions_freeze_snapshot',
  'knowledge.source_versions har en immutable-row guard på observasjonen'
);

select is_empty(
  $$
    select f.function_name
    from (values ('knowledge.freeze_source_version()'),
                 ('knowledge.set_evidence_item_content_hash()'),
                 ('knowledge.reject_evidence_item_mutation()')) as f(function_name)
    where has_function_privilege('public', f.function_name, 'execute')
  $$,
  'PUBLIC kan ikke kjøre triggerfunksjonene i knowledge'
);

select is_empty(
  $$
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'knowledge'
      and c.relkind = 'r'
      and coalesce(obj_description(c.oid, 'pg_class'), '') = ''
  $$,
  'alle kunnskapstabeller har en kommentar som dokumenterer formålet'
);
select is_empty(
  $$
    select t.typname
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'knowledge'
      and t.typtype = 'e'
      and coalesce(obj_description(t.oid, 'pg_type'), '') = ''
  $$,
  'alle kontrollerte vokabularer i knowledge er dokumentert'
);

select * from finish();

rollback;
