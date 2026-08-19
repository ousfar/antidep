-- Migrasjon 003 — kilder og evidensfunn for første golden slice.
--
-- MVP_IMPLEMENTATION_PLAN.md §12 definerer slicen som sertralin + mirtazapin ×
-- vektendring og krever minst én reell kilde og minst ett evidensfunn per
-- relevant kilde. §20 sier at migrasjon 003 bare skal registrere det slicen
-- trenger. Testen verifiserer både at dataene finnes slik de er kontrollert mot
-- PubMed og Crossref, og at omfanget ikke har vokst.
--
-- Testen er også en vaktpost mot den farligste feilen i dette laget: at et
-- klinisk viktig felt får en naken NULL i stedet for en eksplisitt
-- null/ukjent-status (ANTIDEP_CONSTITUTION.md §6, DATABASE_ARCHITECTURE.md
-- §19.1).
begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

-- ---------------------------------------------------------------------------
-- Kildene i slicen
-- ---------------------------------------------------------------------------
select results_eq(
  $$
    select title, authors_or_issuer, publisher_or_journal, volume, issue, pages,
           publication_date, publication_date_precision::text, source_status::text
    from knowledge.sources
    order by publication_date
  $$,
  $$values
    ('Fluoxetine versus sertraline and paroxetine in major depressive disorder: changes in weight with long-term treatment',
     'Fava M, Judge R, Hoog SL, Nilsson ME, Koke SC',
     'The Journal of Clinical Psychiatry', '61', '11', '863-867',
     date '2000-11-01', 'month', 'active'),
    ('Comparison of the effects of mirtazapine and fluoxetine in severely depressed patients',
     'Versiani M, Moreno R, Ramakers-van Moorsel CJ, Schutte AJ; Comparative Efficacy of Antidepressants Study Group',
     'CNS Drugs', '19', '2', '137-146',
     date '2005-01-01', 'year', 'active')$$,
  'begge kildene er registrert med de bibliografiske opplysningene som er kontrollert mot to uavhengige tjenester'
);

-- Presisjonen skal speile det som faktisk er belagt, ikke pyntes opp.
-- ANTIDEP_CONSTITUTION.md §6 forbyr falsk presisjon, og en kilde som bare er
-- årfestet skal ikke se ut som om utgivelsesdagen er kjent.
select is_empty(
  $$
    select title
    from knowledge.sources
    where publication_date_precision = 'day'
  $$,
  'ingen av kildene er datert med dagpresisjon, fordi ingen av dem er belagt med det'
);

select results_eq(
  $$
    select i.identifier_system::text, i.identifier_value
    from knowledge.source_identifiers i
    order by i.identifier_system, i.identifier_value
  $$,
  $$values ('doi', '10.2165/00023210-200519020-00004'),
           ('doi', '10.4088/jcp.v61n1109'),
           ('pmid', '11105740'),
           ('pmid', '15697327')$$,
  'DOI og PMID er registrert som eksterne identifikatorer, ikke som identitet'
);

-- ---------------------------------------------------------------------------
-- Kildeversjonene: hva som faktisk ble hentet og kontrollert
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from knowledge.source_versions),
  2::bigint,
  'hver kilde har nøyaktig ett registrert øyeblikksbilde'
);
select is_empty(
  $$
    select v.id
    from knowledge.source_versions v
    where v.content_hash is null
       or v.external_version is null
       or v.retrieved_from not like 'https://%'
  $$,
  'hvert øyeblikksbilde har hentaddresse, kildens versjonsmerke og innholdshash, slik at det kan hentes og kontrolleres på nytt'
);
select is_empty(
  $$select v.id from knowledge.source_versions v where v.storage_reference is not null$$,
  'ingen fulltekst er lagret; bare metadata, hash og presis kildepeker (DATABASE_ARCHITECTURE.md §18)'
);

-- ---------------------------------------------------------------------------
-- Evidensfunnene
-- ---------------------------------------------------------------------------
select results_eq(
  $$
    select d.canonical_name, c.canonical_label, p.canonical_label,
           e.design_code::text, e.comparator_kind::text, e.reported_direction::text,
           e.effect_measure::text, e.estimate, e.estimate_unit::text,
           e.estimate_availability::text, e.confidence_interval_availability::text,
           e.sample_size, e.timepoint_min, e.timepoint_max, e.extraction_method::text
    from knowledge.evidence_items e
    join catalog.drugs d on d.id = e.intervention_drug_id
    join catalog.clinical_concepts c on c.id = e.outcome_concept_id
    join catalog.populations p on p.id = e.population_id
    order by d.canonical_name
  $$,
  $$values
    ('mirtazapin', 'vektendring', 'voksne med depressiv lidelse',
     'randomized_controlled_trial', 'none', 'increase', 'mean_change',
     0.8::numeric, 'kg', 'reported_value', 'not_reported',
     null::integer, interval '8 weeks', interval '8 weeks', 'ai_assisted'),
    ('sertralin', 'vektendring', 'voksne med depressiv lidelse',
     'randomized_controlled_trial', 'none', 'increase', 'mean_change',
     null::numeric, 'percent', 'not_reported', 'not_reported',
     48, interval '26 weeks', interval '32 weeks', 'ai_assisted')$$,
  'begge evidensfunnene er registrert slik den verifiserte kildeversjonen faktisk rapporterer dem'
);

-- Funnet uten tallverdi er den viktigste raden i denne migrasjonen: kilden
-- oppgir retningen, men ikke estimatet, og da skal feltet stå tomt med en
-- forklarende status framfor et anslag (ANTIDEP_CONSTITUTION.md §4, §6).
select is(
  (select estimate_availability::text from knowledge.evidence_items e
   join catalog.drugs d on d.id = e.intervention_drug_id
   where d.canonical_name = 'sertralin'),
  'not_reported',
  'et estimat den verifiserte kildeversjonen ikke gjengir er merket not_reported, ikke gjettet'
);

-- Et randomiseringstall er ikke et analysetall. sample_size er definert som
-- antallet analysen faktisk omfatter, og når kilden ikke oppgir det, skal
-- kolonnen stå tom framfor å låne armstørrelsen fra randomiseringen — ellers
-- ville en senere syntese vektet funnet på et tall kilden aldri oppga.
select results_eq(
  $$
    select e.sample_size, e.sample_size_availability::text
    from knowledge.evidence_items e
    join catalog.drugs d on d.id = e.intervention_drug_id
    where d.canonical_name = 'mirtazapin'
  $$,
  $$values (null::integer, 'not_reported')$$,
  'antallet i vektanalysen er ikke oppgitt av kilden og lånes ikke fra randomiseringen'
);
select ok(
  (select intervention_detail from knowledge.evidence_items e
   join catalog.drugs d on d.id = e.intervention_drug_id
   where d.canonical_name = 'mirtazapin') like '%147%',
  'randomisert armstørrelse er bevart i intervention_detail, der den hører hjemme'
);

-- Usikkerhet i selve ekstraksjonen skal være maskinlesbar, ikke bare stå i prosa.
select is(
  (select population_availability::text from knowledge.evidence_items e
   join catalog.drugs d on d.id = e.intervention_drug_id
   where d.canonical_name = 'mirtazapin'),
  'uncertain_extraction',
  'en usikker populasjonskobling er merket uncertain_extraction'
);

-- Hver rad skal kunne føres tilbake til et konkret sted i en konkret
-- kildeversjon (ANTIDEP_CONSTITUTION.md §4, KNOWLEDGE_MODEL.md §11.2).
select is_empty(
  $$
    select e.id
    from knowledge.evidence_items e
    where e.source_version_id is null
       or e.source_locator is null
       or e.raw_extraction is null
  $$,
  'hvert evidensfunn peker på en kildeversjon, et presist sted og kildens egne formuleringer'
);

-- Rå ekstraksjon skal bevare kildens egne ord, ikke Antideps omskrivning
-- (DATABASE_ARCHITECTURE.md §20).
select is_empty(
  $$
    select e.id
    from knowledge.evidence_items e
    where not (e.raw_extraction ? 'resultat')
       or length(e.raw_extraction ->> 'resultat') < 40
  $$,
  'rå ekstraksjon inneholder kildens ordrette resultatformulering'
);

-- ---------------------------------------------------------------------------
-- Språkregelen fra konstitusjonen (§3)
-- ---------------------------------------------------------------------------
select is_empty(
  $$
    select s.title from knowledge.sources s where s.title ~* 'antidepressiva'
    union all
    select e.population_detail from knowledge.evidence_items e
      where e.population_detail ~* 'antidepressiva'
    union all
    select e.outcome_detail from knowledge.evidence_items e
      where e.outcome_detail ~* 'antidepressiva'
    union all
    select e.limitations_text from knowledge.evidence_items e
      where e.limitations_text ~* 'antidepressiva'
    union all
    select e.intervention_detail from knowledge.evidence_items e
      where e.intervention_detail ~* 'antidepressiva'
  $$,
  'ingen norsk tekst i kunnskapslaget bruker den forbudte ordformen'
);

-- ---------------------------------------------------------------------------
-- Omfanget har ikke vokst utover slicen
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from knowledge.sources),
  2::bigint,
  'nøyaktig de to kildene slicen trenger er registrert'
);
select is(
  (select count(*) from knowledge.evidence_items),
  2::bigint,
  'nøyaktig ett evidensfunn per kilde er registrert'
);

-- Migrasjon 003 skal ikke ha utvidet katalogen. Begge funnene bruker begrepet
-- og populasjonen migrasjon 002 allerede seedet.
select results_eq(
  $$select (select count(*) from catalog.drugs),
           (select count(*) from catalog.clinical_concepts),
           (select count(*) from catalog.populations)$$,
  $$values (2::bigint, 2::bigint, 1::bigint)$$,
  'migrasjon 003 har ikke lagt til nye virkestoffer, begreper eller populasjoner'
);

-- Ingenting i dette steget kan publisere ekstraksjonene: de er forslag fram til
-- verifikasjons- og reviewgatene (ANTIDEP_CONSTITUTION.md §12).
select is_empty(
  $$
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'api' and c.relkind in ('r', 'p', 'v', 'm')
  $$,
  'det finnes ingen api-projeksjon som kan eksponere ekstraksjonene ennå'
);

select * from finish();

rollback;
