-- Migrasjon 004 — påstandene for første golden slice.
--
-- MVP_IMPLEMENTATION_PLAN.md §12 definerer slicen som sertralin + mirtazapin ×
-- vektendring og krever atomiske Claims, ClaimEvidenceLinks og EvidenceAssessment.
-- §21 sier at migrasjon 004 bare skal registrere det slicen trenger. Testen
-- verifiserer både at påstandene finnes slik grunnlaget faktisk bærer dem, og at
-- omfanget ikke har vokst.
--
-- Testen er først og fremst en vaktpost mot den farligste feilen i dette laget:
-- at en påstand blir mer presis, mer generell eller mer normativ enn evidensen
-- under den (ANTIDEP_CONSTITUTION.md §4, §5, §6).
begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- ---------------------------------------------------------------------------
-- Påstandene i slicen
-- ---------------------------------------------------------------------------
select results_eq(
  $$
    select d.canonical_name, c.canonical_label, cl.knowledge_type::text
    from knowledge.claims cl
    join catalog.drugs d on d.id = cl.subject_drug_id
    join catalog.clinical_concepts c on c.id = cl.topic_concept_id
    order by d.canonical_name
  $$,
  $$values ('mirtazapin', 'vektendring', 'evidence_synthesis'),
           ('sertralin', 'vektendring', 'evidence_synthesis')$$,
  'slicen har én påstand per virkestoff om vektendring, begge klassifisert som evidenssyntese'
);

-- ANTIDEP_CONSTITUTION.md §5: de to evidensfunnene bærer evidenssynteser, ikke
-- anbefalinger. En klinisk anbefaling her ville ikke hatt dekning i grunnlaget.
select is_empty(
  $$
    select cl.id from knowledge.claims cl
    where cl.knowledge_type = 'clinical_recommendation'
  $$,
  'ingen klinisk anbefaling er formulert på dette grunnlaget'
);

-- ANTIDEP_CONSTITUTION.md §12: ingenting er publisert. Verken publiseringspeker,
-- review eller api-projeksjon finnes, så radene er forslag.
select is_empty(
  $$
    select cl.id from knowledge.claims cl
    where cl.current_published_revision_id is not null
       or cl.retired_at is not null
  $$,
  'ingen påstand er publisert eller trukket tilbake i dette steget'
);

-- ---------------------------------------------------------------------------
-- Revisjonene
-- ---------------------------------------------------------------------------
select results_eq(
  $$
    select d.canonical_name, r.revision_number, p.canonical_label,
           r.timeframe_min, r.timeframe_max, r.comparator_kind::text,
           r.direction::text, r.magnitude_measure::text, r.magnitude_value,
           r.magnitude_unit::text
    from knowledge.claim_revisions r
    join knowledge.claims cl on cl.id = r.claim_id
    join catalog.drugs d on d.id = cl.subject_drug_id
    join catalog.populations p on p.id = r.population_id
    order by d.canonical_name
  $$,
  $$values
    ('mirtazapin', 1, 'voksne med depressiv lidelse',
     interval '8 weeks', interval '8 weeks', 'none', 'increase',
     null::text, null::numeric, null::text),
    ('sertralin', 1, 'voksne med depressiv lidelse',
     interval '26 weeks', interval '32 weeks', 'none', 'increase',
     null::text, null::numeric, null::text)$$,
  'begge revisjonene har strukturert populasjon, tidsrom, komparator og retning, og ingen tallfestet størrelse'
);

-- Den viktigste enkeltassertionen i denne migrasjonen. Sertralinfunnet oppgir
-- ingen tallverdi i det hele tatt, og mirtazapinfunnet ett armspesifikt
-- gjennomsnitt uten kjent analysestørrelse og med usikker populasjonskobling.
-- En påstand som tallfestet størrelsen ville vært mer presis enn grunnlaget
-- under den (ANTIDEP_CONSTITUTION.md §4, §6).
select is_empty(
  $$
    select r.id from knowledge.claim_revisions r
    where r.magnitude_value is not null or r.magnitude_measure is not null
  $$,
  'ingen påstand tallfester størrelsen på vektendringen; tallene blir stående på evidensfunnene'
);

-- Tidsrommet skal ikke være videre enn det funnet under påstanden dekker.
select is_empty(
  $$
    select r.id
    from knowledge.claim_revisions r
    join knowledge.claim_evidence_links l on l.claim_revision_id = r.id
    join knowledge.evidence_items e on e.id = l.evidence_item_id
    where r.timeframe_min < e.timepoint_min or r.timeframe_max > e.timepoint_max
  $$,
  'ingen påstand dekker et videre tidsrom enn evidensfunnet den hviler på'
);

-- KNOWLEDGE_MODEL.md §9.2: den strukturerte betydningen skal ikke bare finnes i
-- fritekst, og hver revisjon skal si hva den gjelder for og hvor usikker den er.
select is_empty(
  $$
    select r.id from knowledge.claim_revisions r
    where r.scope is null or btrim(r.scope) = ''
       or r.uncertainty_summary is null or btrim(r.uncertainty_summary) = ''
       or r.qualifiers is null or btrim(r.qualifiers) = ''
  $$,
  'hver revisjon har uttalt omfang, forbehold og usikkerhetstekst'
);

-- Grunnlaget er armspesifikke endringer fra behandlingsstart i to forskjellige
-- studier over forskjellig tid. En sammenligningsvisning skal ikke kunne stille
-- dem opp mot hverandre uten at forbeholdet følger med
-- (ANTIDEP_CONSTITUTION.md §2, MVP_IMPLEMENTATION_PLAN.md §31).
select is_empty(
  $$
    select r.id from knowledge.claim_revisions r
    where r.qualifiers !~* 'tillater ingen sammenligning'
  $$,
  'begge revisjonene sier eksplisitt at grunnlaget ikke tillater sammenligning mellom virkestoffene'
);
select is_empty(
  $$
    select r.id from knowledge.claim_revisions r where r.comparator_kind <> 'none'
  $$,
  'ingen påstand påstår en komparator; begge funnene er armspesifikke endringer fra behandlingsstart'
);

-- Fingeravtrykket eies av databasen.
select is_empty(
  $$
    select r.id from knowledge.claim_revisions r
    where r.content_hash !~ '^sha256-v1:[0-9a-f]{64}$'
  $$,
  'begge revisjonene har et databasesatt og versjonert fingeravtrykk'
);

-- ---------------------------------------------------------------------------
-- Evidenslenkene (ANTIDEP_CONSTITUTION.md §4)
-- ---------------------------------------------------------------------------
select results_eq(
  $$
    select d.canonical_name, l.relationship_type::text, l.directness::text,
           ed.canonical_name
    from knowledge.claim_evidence_links l
    join knowledge.claim_revisions r on r.id = l.claim_revision_id
    join knowledge.claims cl on cl.id = r.claim_id
    join catalog.drugs d on d.id = cl.subject_drug_id
    join knowledge.evidence_items e on e.id = l.evidence_item_id
    join catalog.drugs ed on ed.id = e.intervention_drug_id
    order by d.canonical_name
  $$,
  $$values ('mirtazapin', 'supports', 'indirect', 'mirtazapin'),
           ('sertralin', 'supports', 'direct', 'sertralin')$$,
  'hver påstand er koblet til evidensfunnet for sitt eget virkestoff, med eksplisitt relasjonstype og indirekthet'
);

-- Mirtazapinfunnet har population_availability = uncertain_extraction. Det
-- avviket er indirekthet, og skal være maskinlesbart både på lenken og i
-- vurderingen — ikke bare stå i prosa (DATABASE_ARCHITECTURE.md §22).
select results_eq(
  $$
    select l.directness::text, a.indirectness::text
    from knowledge.claim_evidence_links l
    join knowledge.claim_revisions r on r.id = l.claim_revision_id
    join knowledge.evidence_assessments a on a.claim_revision_id = r.id
    join knowledge.evidence_items e on e.id = l.evidence_item_id
    where e.population_availability = 'uncertain_extraction'
  $$,
  $$values ('indirect', 'serious')$$,
  'en usikker populasjonskobling i evidensen slår ut som indirekthet både på lenken og i vurderingen'
);

-- Hver påstand er etterprøvbar: hver revisjon har minst én evidenslenke, og
-- hver lenke har en skriftlig begrunnelse.
select is_empty(
  $$
    select r.id from knowledge.claim_revisions r
    where not exists (
      select 1 from knowledge.claim_evidence_links l where l.claim_revision_id = r.id
    )
  $$,
  'ingen påstandsrevisjon står uten evidenslenke (ANTIDEP_CONSTITUTION.md §4)'
);
select is_empty(
  $$
    select l.id from knowledge.claim_evidence_links l
    where length(btrim(l.relevance_note)) < 40
  $$,
  'hver evidenslenke begrunner hvordan funnet forholder seg til formuleringen'
);

-- ---------------------------------------------------------------------------
-- Evidensvurderingene (ANTIDEP_CONSTITUTION.md §6)
-- ---------------------------------------------------------------------------
select results_eq(
  $$
    select d.canonical_name, a.framework::text, a.certainty_level::text,
           a.risk_of_bias::text, a.inconsistency::text, a.indirectness::text,
           a.imprecision::text, a.publication_bias::text
    from knowledge.evidence_assessments a
    join knowledge.claim_revisions r on r.id = a.claim_revision_id
    join knowledge.claims cl on cl.id = r.claim_id
    join catalog.drugs d on d.id = cl.subject_drug_id
    order by d.canonical_name
  $$,
  $$values
    ('mirtazapin', 'grade', 'very_low', 'serious', 'not_assessable', 'serious',
     'serious', 'not_assessable'),
    ('sertralin', 'grade', 'very_low', 'serious', 'not_assessable', 'not_serious',
     'very_serious', 'not_assessable')$$,
  'begge vurderingene er svært lav sikkerhet med eksplisitt vurderte GRADE-domener'
);

-- Ett enkelt funn gir ikke grunnlag for å bedømme konsistens eller
-- publikasjonsskjevhet. not_serious der ville vært falsk presisjon.
select is_empty(
  $$
    select a.id from knowledge.evidence_assessments a
    where a.inconsistency <> 'not_assessable' or a.publication_bias <> 'not_assessable'
  $$,
  'konsistens og publikasjonsskjevhet står som ikke vurderbare, ikke som ikke alvorlige'
);

-- Sikkerhetsgraden skal ikke kunne leses som «ingen vurderbar evidens», og
-- omvendt: her finnes det evidens, den er bare svært usikker.
select is_empty(
  $$
    select a.id from knowledge.evidence_assessments a
    where a.certainty_level = 'no_assessable_evidence'
  $$,
  'ingen av vurderingene er ingen vurderbar evidens; det finnes evidens, men den er svært usikker'
);

-- ---------------------------------------------------------------------------
-- Språkregelen fra konstitusjonen (§3)
-- ---------------------------------------------------------------------------
select is_empty(
  $$
    select r.statement from knowledge.claim_revisions r where r.statement ~* 'antidepressiva'
    union all
    select r.scope from knowledge.claim_revisions r where r.scope ~* 'antidepressiva'
    union all
    select r.qualifiers from knowledge.claim_revisions r where r.qualifiers ~* 'antidepressiva'
    union all
    select r.uncertainty_summary from knowledge.claim_revisions r
      where r.uncertainty_summary ~* 'antidepressiva'
    union all
    select l.relevance_note from knowledge.claim_evidence_links l
      where l.relevance_note ~* 'antidepressiva'
    union all
    select a.rationale from knowledge.evidence_assessments a where a.rationale ~* 'antidepressiva'
    union all
    select a.evidence_gap from knowledge.evidence_assessments a
      where a.evidence_gap ~* 'antidepressiva'
  $$,
  'ingen norsk tekst i påstandslaget bruker den forbudte ordformen'
);

-- ---------------------------------------------------------------------------
-- Omfanget har ikke vokst utover slicen
-- ---------------------------------------------------------------------------
select results_eq(
  $$select (select count(*) from knowledge.claims),
           (select count(*) from knowledge.claim_revisions),
           (select count(*) from knowledge.claim_evidence_links),
           (select count(*) from knowledge.evidence_assessments)$$,
  $$values (2::bigint, 2::bigint, 2::bigint, 2::bigint)$$,
  'nøyaktig to påstander, én revisjon, én evidenslenke og én vurdering hver'
);

-- Migrasjon 004 skal ikke ha utvidet katalogen eller kildelaget. Trengs en ny
-- katalograd eller et nytt evidensfunn, har scopet glippet.
select results_eq(
  $$select (select count(*) from catalog.drugs),
           (select count(*) from catalog.clinical_concepts),
           (select count(*) from catalog.populations),
           (select count(*) from knowledge.sources),
           (select count(*) from knowledge.evidence_items)$$,
  $$values (2::bigint, 2::bigint, 1::bigint, 2::bigint, 2::bigint)$$,
  'migrasjon 004 har verken utvidet katalogen eller kildelaget'
);

select * from finish();

rollback;
