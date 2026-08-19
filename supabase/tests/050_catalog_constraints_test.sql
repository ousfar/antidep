-- Migrasjon 002 — deklarative constraints og FK-integritet i catalog.
--
-- DATABASE_ARCHITECTURE.md §57 krever at integritet håndheves deklarativt i
-- databasen, ikke bare i applikasjonskode, og §67 krever at constraints, FK-er
-- og negative stier faktisk testes. Hver regel testes både positivt (en gyldig
-- rad går inn) og negativt (et brudd avvises med riktig SQLSTATE).
--
-- SQLSTATE: 23502 not_null_violation, 23503 foreign_key_violation,
-- 23505 unique_violation, 23514 check_violation, 22P02 invalid_text_representation.
begin;

create extension if not exists pgtap with schema extensions;

select plan(40);

-- Testdata som bare finnes inne i denne transaksjonen.
insert into catalog.drugs (canonical_name) values ('testvirkestoff');
insert into catalog.clinical_concepts (canonical_label, concept_type)
values ('testtilstand', 'condition'), ('testutfall', 'outcome');

-- ---------------------------------------------------------------------------
-- catalog.drugs — kanonisk navn og status
-- ---------------------------------------------------------------------------
select lives_ok(
  $$insert into catalog.drugs (canonical_name) values ('gyldig testnavn')$$,
  'et gyldig virkestoffnavn kan registreres'
);
select throws_ok(
  $$insert into catalog.drugs (canonical_name) values (null)$$,
  '23502', null,
  'et virkestoff uten kanonisk navn avvises'
);
select throws_ok(
  $$insert into catalog.drugs (canonical_name) values ('')$$,
  '23514', null,
  'et tomt kanonisk navn avvises'
);
select throws_ok(
  $$insert into catalog.drugs (canonical_name) values ('  sertralin  ')$$,
  '23514', null,
  'et kanonisk navn med omkringliggende blanktegn avvises'
);
select throws_ok(
  $$insert into catalog.drugs (canonical_name) values ('Testvirkestoff')$$,
  '23505', null,
  'kanonisk navn er unikt uavhengig av bokstavstørrelse'
);
select throws_ok(
  $$insert into catalog.drugs (canonical_name, status) values ('ukjent status', 'aktiv')$$,
  '22P02', null,
  'en status utenfor det kontrollerte vokabularet avvises'
);

-- Statusendring er tillatt og oppdaterer updated_at; historikk slettes ikke.
select lives_ok(
  $$update catalog.drugs set status = 'historical' where canonical_name = 'testvirkestoff'$$,
  'status kan endres uten at raden slettes'
);

-- Tidsstemplene eies av databasen ved både INSERT og UPDATE. Testen oppgir
-- bevisst forfalskede verdier: en default alene gjelder bare når kolonnen
-- utelates, så uten trigger ville verdiene under blitt lagret som de er.
insert into catalog.drugs (canonical_name, created_at, updated_at)
values ('triggertestvirkestoff', '2000-01-01T00:00:00Z', '2000-01-01T00:00:00Z');
select results_eq(
  $$
    select created_at = now(), updated_at = now()
    from catalog.drugs where canonical_name = 'triggertestvirkestoff'
  $$,
  $$values (true, true)$$,
  'created_at og updated_at settes av databasen ved INSERT, ikke av klienten'
);

update catalog.drugs
set status = 'historical', created_at = '2000-01-01T00:00:00Z',
    updated_at = '2000-01-01T00:00:00Z'
where canonical_name = 'triggertestvirkestoff';
select results_eq(
  $$
    select created_at = now(), updated_at = now()
    from catalog.drugs where canonical_name = 'triggertestvirkestoff'
  $$,
  $$values (true, true)$$,
  'created_at bevares og updated_at settes av databasen ved UPDATE, ikke av klienten'
);

-- ---------------------------------------------------------------------------
-- catalog.drug_identifiers — eksterne identifikatorer
-- ---------------------------------------------------------------------------
select lives_ok(
  $$
    insert into catalog.drug_identifiers (drug_id, identifier_system, identifier_value)
    select id, 'atc', 'N06AB99' from catalog.drugs where canonical_name = 'testvirkestoff'
  $$,
  'en gyldig ATC-kode kan registreres'
);
select throws_ok(
  $$
    insert into catalog.drug_identifiers (drug_id, identifier_system, identifier_value)
    select id, 'atc', 'ikke-en-atc-kode' from catalog.drugs where canonical_name = 'gyldig testnavn'
  $$,
  '23514', null,
  'en ATC-verdi med feil format avvises deklarativt'
);
select throws_ok(
  $$
    insert into catalog.drug_identifiers (drug_id, identifier_system, identifier_value)
    select id, 'atc', 'N06AB99' from catalog.drugs where canonical_name = 'gyldig testnavn'
  $$,
  '23505', null,
  'samme ATC-kode kan ikke peke på to virkestoffer'
);
select throws_ok(
  $$
    insert into catalog.drug_identifiers (drug_id, identifier_system, identifier_value)
    values (gen_random_uuid(), 'atc', 'N06AB98')
  $$,
  '23503', null,
  'en identifikator for et ukjent virkestoff avvises'
);

-- Ett virkestoff kan ha flere koder i samme system (jf. bupropion i §10).
select lives_ok(
  $$
    insert into catalog.drug_identifiers (drug_id, identifier_system, identifier_value)
    select id, 'atc', 'N07BA99' from catalog.drugs where canonical_name = 'testvirkestoff'
  $$,
  'ett virkestoff kan ha flere ATC-koder'
);

-- ---------------------------------------------------------------------------
-- catalog.drug_names — alternative navn
-- ---------------------------------------------------------------------------
select lives_ok(
  $$
    insert into catalog.drug_names (drug_id, name, name_type)
    select id, 'testalias', 'alias' from catalog.drugs where canonical_name = 'testvirkestoff'
  $$,
  'et alias kan registreres'
);
select throws_ok(
  $$
    insert into catalog.drug_names (drug_id, name, name_type)
    select id, 'Testalias', 'alias' from catalog.drugs where canonical_name = 'testvirkestoff'
  $$,
  '23505', null,
  'samme navn og navnetype kan ikke registreres to ganger på ett virkestoff'
);
select lives_ok(
  $$
    insert into catalog.drug_names (drug_id, name, name_type)
    select id, 'testalias', 'historical_name'
    from catalog.drugs where canonical_name = 'testvirkestoff'
  $$,
  'samme navnestreng kan registreres med en annen navnetype'
);
select throws_ok(
  $$
    insert into catalog.drug_names (drug_id, name, name_type)
    values (gen_random_uuid(), 'foreldreløst navn', 'alias')
  $$,
  '23503', null,
  'et navn uten eksisterende virkestoff avvises'
);

-- RESTRICT: et referert virkestoff kan ikke slettes bort
-- (DATABASE_ARCHITECTURE.md §36, §37). Hver relasjon testes for seg, slik at
-- testen faktisk sier hvilken fremmednøkkel som holder igjen.
insert into catalog.drugs (canonical_name) values ('navnereferert testvirkestoff');
insert into catalog.drug_names (drug_id, name, name_type)
select id, 'kun navn', 'alias'
from catalog.drugs where canonical_name = 'navnereferert testvirkestoff';
select throws_ok(
  $$delete from catalog.drugs where canonical_name = 'navnereferert testvirkestoff'$$,
  '23503', null,
  'et virkestoff med registrerte navn kan ikke slettes'
);

insert into catalog.drugs (canonical_name) values ('kodereferert testvirkestoff');
insert into catalog.drug_identifiers (drug_id, identifier_system, identifier_value)
select id, 'atc', 'N06AB97'
from catalog.drugs where canonical_name = 'kodereferert testvirkestoff';
select throws_ok(
  $$delete from catalog.drugs where canonical_name = 'kodereferert testvirkestoff'$$,
  '23503', null,
  'et virkestoff med registrerte identifikatorer kan ikke slettes'
);

-- ---------------------------------------------------------------------------
-- catalog.clinical_concepts — kontrollert vokabular og hierarki
-- ---------------------------------------------------------------------------
select lives_ok(
  $$
    insert into catalog.clinical_concepts (canonical_label, concept_type, parent_concept_id)
    select 'testunderutfall', 'outcome', id
    from catalog.clinical_concepts where canonical_label = 'testutfall'
  $$,
  'et underbegrep kan knyttes til et overordnet begrep'
);
select throws_ok(
  $$
    update catalog.clinical_concepts set parent_concept_id = id
    where canonical_label = 'testutfall'
  $$,
  '23514', null,
  'et begrep kan ikke være sin egen forelder'
);
select throws_ok(
  $$insert into catalog.clinical_concepts (canonical_label, concept_type)
    values ('Testutfall', 'outcome')$$,
  '23505', null,
  'kanonisk etikett er unik uavhengig av bokstavstørrelse'
);
select throws_ok(
  $$insert into catalog.clinical_concepts (canonical_label, concept_type)
    values ('ukjent begrepstype', 'tema')$$,
  '22P02', null,
  'en begrepstype utenfor det kontrollerte vokabularet avvises'
);

-- ---------------------------------------------------------------------------
-- catalog.populations — gyldighetsgrenser
-- ---------------------------------------------------------------------------
select lives_ok(
  $$
    insert into catalog.populations
      (canonical_label, age_min_years, age_max_years, indication_concept_id, pregnancy_context)
    select 'testpopulasjon', 18, 64, id, 'pregnancy'
    from catalog.clinical_concepts where canonical_label = 'testtilstand'
  $$,
  'en populasjon med strukturerte gyldighetsgrenser kan registreres'
);
select lives_ok(
  $$insert into catalog.populations (canonical_label) values ('uavgrenset testpopulasjon')$$,
  'en populasjon uten avgrensning på noen dimensjon er tillatt'
);
select throws_ok(
  $$
    insert into catalog.populations (canonical_label, age_min_years, age_max_years)
    values ('invertert aldersintervall', 65, 18)
  $$,
  '23514', null,
  'et invertert aldersintervall avvises'
);
select throws_ok(
  $$
    insert into catalog.populations (canonical_label, age_min_years)
    values ('negativ alder', -1)
  $$,
  '23514', null,
  'en negativ aldersgrense avvises'
);

-- Typekravet på begrepsreferansene er deklarativt: et utfall er ikke en
-- indikasjon, og databasen avviser sammenblandingen uten applikasjonskode.
select throws_ok(
  $$
    insert into catalog.populations (canonical_label, indication_concept_id)
    select 'populasjon med feil begrepstype', id
    from catalog.clinical_concepts where canonical_label = 'testutfall'
  $$,
  '23503', null,
  'et begrep av typen outcome kan ikke brukes som indikasjon'
);
select throws_ok(
  $$
    insert into catalog.populations (canonical_label, comorbidity_concept_id)
    select 'populasjon med feil komorbiditetstype', id
    from catalog.clinical_concepts where canonical_label = 'testutfall'
  $$,
  '23503', null,
  'et begrep av typen outcome kan ikke brukes som komorbiditet'
);

-- ---------------------------------------------------------------------------
-- RESTRICT på begrepsreferansene, når hierarkiet og populasjonen finnes
-- ---------------------------------------------------------------------------
select throws_ok(
  $$delete from catalog.clinical_concepts where canonical_label = 'testutfall'$$,
  '23503', null,
  'et begrep med underbegreper kan ikke slettes'
);
select throws_ok(
  $$delete from catalog.clinical_concepts where canonical_label = 'testtilstand'$$,
  '23503', null,
  'et begrep en populasjon peker på kan ikke slettes'
);

-- ---------------------------------------------------------------------------
-- Populasjonsdefinisjonen er uforanderlig (DATABASE_ARCHITECTURE.md §7, §7.1)
--
-- En populasjon er en gyldighetsgrense. Hvis de definerende feltene kunne
-- endres etterpå, ville omfanget av all historikk som peker hit endre seg uten
-- ny revisjon. Et endret omfang skal derfor bli en ny populasjon.
-- SQLSTATE 23001 = restrict_violation.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$update catalog.populations set age_min_years = 6 where canonical_label = 'testpopulasjon'$$,
  '23001', null,
  'nedre aldersgrense kan ikke endres etter innsetting'
);
select throws_ok(
  $$update catalog.populations set age_max_years = 99 where canonical_label = 'testpopulasjon'$$,
  '23001', null,
  'øvre aldersgrense kan ikke endres etter innsetting'
);
select throws_ok(
  $$update catalog.populations set canonical_label = 'omdøpt testpopulasjon'
    where canonical_label = 'testpopulasjon'$$,
  '23001', null,
  'etiketten kan ikke endres etter innsetting'
);
select throws_ok(
  $$update catalog.populations set indication_concept_id = null
    where canonical_label = 'testpopulasjon'$$,
  '23001', null,
  'indikasjonen kan ikke endres etter innsetting'
);
select throws_ok(
  $$update catalog.populations set pregnancy_context = 'breastfeeding'
    where canonical_label = 'testpopulasjon'$$,
  '23001', null,
  'graviditets-/ammedimensjonen kan ikke endres etter innsetting'
);
select throws_ok(
  $$
    update catalog.populations
    set comorbidity_concept_id = (
      select id from catalog.clinical_concepts where canonical_label = 'testtilstand'
    )
    where canonical_label = 'testpopulasjon'
  $$,
  '23001', null,
  'komorbiditeten kan ikke endres etter innsetting'
);

-- Utfasing skal fortsatt være mulig: den endrer status, ikke betydning, og
-- sletter ingen historikk (DATABASE_ARCHITECTURE.md §36).
select lives_ok(
  $$update catalog.populations set status = 'deprecated'
    where canonical_label = 'testpopulasjon'$$,
  'en populasjon kan fases ut uten at definisjonen røres'
);

-- Et endret omfang blir en ny populasjon ved siden av den gamle.
select lives_ok(
  $$
    insert into catalog.populations (canonical_label, age_min_years, age_max_years)
    values ('testpopulasjon, revidert omfang', 16, 64)
  $$,
  'et endret omfang registreres som en ny populasjon'
);

select * from finish();

rollback;
