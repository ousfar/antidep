-- ============================================================================
-- Antidep migrasjon 003 — Source og EvidenceItem
--
-- Formål: etablere kilde- og evidenslaget mellom originallitteraturen og
-- Antideps egne påstander, og registrere nøyaktig de kildene og evidensfunnene
-- den første golden slicen trenger (sertralin + mirtazapin × vektendring).
--
-- Styrende dokumenter:
--   docs/ANTIDEP_CONSTITUTION.md
--     §4  enhver klinisk relevant påstand skal være etterprøvbar
--     §5  tre kunnskapstyper med ulik epistemisk status
--     §6  usikkerhet skal graderes, aldri erstattes av falsk presisjon
--     §8  evidens og proveniens er førsteklasses data
--     §9  motstridende evidens bevares
--     §12 KI foreslår; mennesker har det faglige ansvaret
--   docs/MVP_IMPLEMENTATION_PLAN.md
--     §12 første golden slice
--     §20 innholdet i denne migrasjonen
--     §29 Slice 1
--     §41-§42 teststrategi og kritiske negative tester
--     §47-§50 sikkerhet og tilgang
--   docs/DATABASE_ARCHITECTURE.md
--     §16 knowledge.sources, §17 studie og rapport, §18 knowledge.source_versions
--     §19 + §19.1 knowledge.evidence_items og null/ukjent-semantikk
--     §20 rå ekstraksjon og kanoniske felt
--     §36-§37 ingen normal DELETE, RESTRICT på fremmednøkler
--     §57-§60 deklarative constraints, cross-row-regler og triggerbruk
--   docs/KNOWLEDGE_MODEL.md §10 (Source), §11 + §11.1-§11.2 (EvidenceItem)
--
-- Avgrensning (MVP_IMPLEMENTATION_PLAN.md §20-§26):
--   Ingen Claims, ClaimEvidenceLinks eller EvidenceAssessments (004), ingen
--   review eller proveniens (005), ingen publisering (006), ingen api-views
--   (007), ingen audit.events (008) og ingen ingest (009).
--   Ingen RLS-policies: medlemskapsmodellen (workflow.user_roles) kommer i
--   migrasjon 005. Tabellene er default deny uten unntak i dette steget.
--
--   knowledge.studies og knowledge.study_sources (DATABASE_ARCHITECTURE.md §17)
--   står ikke i §20 og opprettes derfor ikke her. Konsekvensen er at
--   evidence_items foreløpig ikke har study_id, og at flere publikasjoner om
--   samme underliggende studie ikke kan avsløres av databasen. Det er en reell
--   risiko for dobbelttelling i senere synteser, og den hører til migrasjonen
--   som innfører Study-modellen. Ingen av de to kildene under rapporterer samme
--   studie, så første slice er ikke berørt.
--
--   evidence_items har heller ikke created_by_actor_id (§19): provenance.actors
--   opprettes i migrasjon 005. Kolonnen legges til der, sammen med aktørene den
--   skal peke på.
--
-- Konvensjonene fra migrasjon 001 gjelder og håndheves av
-- supabase/tests/030_conventions_test.sql: én databasegenerert uuid som
-- primærnøkkel, timestamptz overalt, created_at med default now(), RLS aktivert
-- og ingen grants til anon/authenticated/service_role/PUBLIC.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Kontrollerte vokabularer
--
-- Som i migrasjon 002 håndheves vokabularene som enum, altså på datatypenivå,
-- øverst i prioriteringsrekkefølgen i DATABASE_ARCHITECTURE.md §57. Det åpne
-- spørsmålet om enum kontra oppslagstabell (DATABASE_ARCHITECTURE.md §72) blir
-- større for hver migrasjon og bør avgjøres før redaksjonelle skriveveier og
-- api-projeksjoner begynner å peke på verdiene.
--
-- Prinsipp for hvor mange verdier hvert vokabular får:
--   * Der arkitekturdokumentene faktisk lister opp vokabularet, følges listen.
--   * Ellers registreres bare de verdiene første slice bruker, pluss verdier en
--     constraint i denne migrasjonen trenger for å uttrykke en reell regel.
--     Nye verdier legges til av migrasjonen som trenger dem, slik migrasjon 002
--     gjorde for catalog.drug_identifier_system. En manglende verdi gir en
--     synlig feil ved innsetting, ikke en stille feilklassifisering.
-- ----------------------------------------------------------------------------

create type knowledge.source_type as enum (
  'journal_article',
  'clinical_guideline',
  'summary_of_product_characteristics',
  'regulatory_communication',
  'public_dataset'
);

comment on type knowledge.source_type is
  'Hva slags dokument kilden er: journal_article (fagfellevurdert artikkel), clinical_guideline (retningslinje), summary_of_product_characteristics (preparatomtale), regulatory_communication (regulatorisk sikkerhetsmelding e.l.) og public_dataset (offentlig datasett). KNOWLEDGE_MODEL.md §10 nevner også studiedesign som randomisert studie, systematisk oversikt og metaanalyse. De er bevisst ikke kildetyper her: dokumenttype og studiedesign er to akser (DATABASE_ARCHITECTURE.md §17), og én artikkel kan rapportere ulike design for ulike utfall. Designet ligger derfor på knowledge.evidence_items.design_code, der det gjelder det konkrete funnet.';

create type knowledge.source_status as enum (
  'active',
  'outdated',
  'superseded',
  'retracted',
  'withdrawn'
);

comment on type knowledge.source_status is
  'Kildens status (KNOWLEDGE_MODEL.md §10): active (i bruk), outdated (fortsatt gyldig som historikk, men ikke lenger dekkende), superseded (erstattet av en nyere kilde, se superseded_by_source_id), retracted (trukket tilbake av tidsskrift eller utgiver) og withdrawn (dokumentet er tatt ut av bruk av utgiveren). retracted og withdrawn er egne tilstander nettopp fordi en publiseringsgate senere skal kunne nekte å bruke slike kilder (DATABASE_ARCHITECTURE.md §58); de skal aldri kunne passere som om statusen var normal.';

create type knowledge.source_identifier_system as enum ('doi', 'pmid');

comment on type knowledge.source_identifier_system is
  'Identifikatorsystem for globale kildeidentifikatorer: doi (Digital Object Identifier) og pmid (PubMed-ID). Nye systemer, for eksempel PMCID, ISBN eller nasjonale dokument-ID-er, legges til i den migrasjonen som faktisk trenger dem.';

create type knowledge.date_precision as enum ('year', 'month', 'day');

comment on type knowledge.date_precision is
  'Hvor presist en dato faktisk er kjent. Bibliografiske kilder oppgir ofte bare år eller år og måned. Uten et presisjonsnivå ville en slik dato blitt lagret som om dagen var kjent, altså som falsk presisjon, noe ANTIDEP_CONSTITUTION.md §6 forbyr. Datoen lagres avkortet til presisjonsnivået, og avkortingen håndheves deklarativt.';

create type knowledge.study_design as enum ('randomized_controlled_trial');

comment on type knowledge.study_design is
  'Studiedesignet for det konkrete evidensfunnet, ikke for dokumentet. Vokabularet inneholder foreløpig bare designet de to kildene i første golden slice bruker. Kohortstudier, metaanalyser og øvrige design legges til av migrasjonen som trenger dem; fram til da vil et forsøk på å registrere et annet design feile synlig i stedet for å bli klassifisert feil.';

create type knowledge.comparator_kind as enum ('drug', 'placebo', 'none');

comment on type knowledge.comparator_kind is
  'Hva evidensfunnet sammenlignes mot: drug (et virkestoff i catalog.drugs, oppgitt i comparator_drug_id), placebo, eller none (funnet er armspesifikt og har ingen komparator). Kategorien beskriver kontrasten i selve funnet, ikke studiens design: et enarmet gjennomsnitt hentet fra en sammenlignende studie har komparator none, og studiekonteksten dokumenteres i limitations_text. placebo er med fordi en komparatorkategori som ikke kan skille placebo fra et aktivt virkestoff ville tvunget neste ekstraksjon til å velge mellom to feil.';

create type knowledge.effect_measure as enum (
  'mean_change',
  'mean_difference',
  'standardised_mean_difference',
  'risk_ratio',
  'odds_ratio'
);

comment on type knowledge.effect_measure is
  'Effektmål for estimatet. KNOWLEDGE_MODEL.md §11 lister RR, OR, MD og SMD; mean_change er lagt til fordi et armspesifikt gjennomsnitt av endring fra baseline ikke er et differansemål mellom to grupper. Målene deles i dimensjonale mål (mean_change, mean_difference), som krever en enhet, og dimensjonsløse mål (standardised_mean_difference, risk_ratio, odds_ratio), som ikke skal ha enhet. Skillet håndheves deklarativt.';

create type knowledge.estimate_unit as enum ('kg', 'percent');

comment on type knowledge.estimate_unit is
  'Enheten et dimensjonalt estimat er uttrykt i. Uten enhet er et vekttall klinisk tvetydig: 0,8 kan være kilogram, BMI-poeng eller prosent. Vokabularet inneholder de enhetene første slice bruker; nye enheter legges til av migrasjonen som trenger dem.';

create type knowledge.effect_direction as enum (
  'increase',
  'decrease',
  'no_clear_difference',
  'not_stated'
);

comment on type knowledge.effect_direction is
  'Retningen kilden selv rapporterer for utfallet: increase, decrease, no_clear_difference (kilden fant ingen klar forskjell, altså et resultat, ikke fravær av data) eller not_stated (kilden angir ingen retning). Kolonnen er NOT NULL nettopp for at et nullfunn skal være en registrert tilstand og ikke kunne kollapse til NULL sammen med «ikke rapportert» og «ikke målt» (ANTIDEP_CONSTITUTION.md §6, DATABASE_ARCHITECTURE.md §19.1). Retningen er den kilden oppgir, ikke Antideps tolkning på tvers av studier; den hører til Claim og EvidenceAssessment (KNOWLEDGE_MODEL.md §11.1).';

create type knowledge.value_availability as enum (
  'reported_value',
  'not_measured',
  'not_reported',
  'not_applicable',
  'not_extractable',
  'uncertain_extraction'
);

comment on type knowledge.value_availability is
  'Hvorfor et klinisk viktig felt har eller ikke har en verdi (DATABASE_ARCHITECTURE.md §19.1). reported_value: kilden oppgir verdien, og den står i kolonnen. not_measured: kilden opplyser at størrelsen ikke ble målt. not_reported: størrelsen kunne vært oppgitt, men kilden oppgir den ikke. not_applicable: størrelsen gir ikke mening for dette funnet. not_extractable: verdien finnes i kilden, men kan ikke leses entydig ut av den kildeversjonen og det stedet raden peker på. uncertain_extraction: en verdi er lest ut, men ekstraksjonen er usikker. Statusen gjelder alltid den kildeversjonen og den kildepekeren raden viser til, ikke nødvendigvis hele publikasjonen. reported_value og uncertain_extraction er de to tilstandene der en verdi faktisk står i kolonnen; de øvrige krever NULL. NULL alene er for tvetydig, og et nullfunn er en verdi, ikke et fravær.';

create type knowledge.extraction_method as enum (
  'manual',
  'ai_assisted',
  'deterministic_import'
);

comment on type knowledge.extraction_method is
  'Hvordan evidensfunnet ble hentet ut (KNOWLEDGE_MODEL.md §11): manual (menneskelig ekstraksjon), ai_assisted (KI-assistert forslag) og deterministic_import (maskinell import fra strukturert kilde). Feltet sier hvordan raden ble til, ikke om den er kontrollert. Verifikasjonsstatus er en egen arbeidsflytregistrering (DATABASE_ARCHITECTURE.md §29) og kommer i migrasjon 005; generering og verifikasjon skal ikke være samme operasjon (ANTIDEP_CONSTITUTION.md §10).';

-- PUBLIC har som standard usage på nye typer. Antidep gir privilegier eksplisitt
-- (DATABASE_ARCHITECTURE.md §5), som i migrasjon 001 og 002.
revoke usage on type
  knowledge.source_type,
  knowledge.source_status,
  knowledge.source_identifier_system,
  knowledge.date_precision,
  knowledge.study_design,
  knowledge.comparator_kind,
  knowledge.effect_measure,
  knowledge.estimate_unit,
  knowledge.effect_direction,
  knowledge.value_availability,
  knowledge.extraction_method
  from public;

-- ----------------------------------------------------------------------------
-- 2. Tidsstempler
--
-- catalog.set_row_timestamps() fra migrasjon 002 gjenbrukes for kildetabellene.
-- Funksjonen er ren teknisk metadata — den gir databasen eierskap til
-- created_at og updated_at og inneholder ingen klinisk logikk — og en kopi i
-- knowledge ville bare gitt to steder å vedlikeholde samme regel. Kommentaren
-- oppdateres slik at den beskriver den faktiske bruken. Hvis et tredje schema
-- får behov for den, bør den flyttes til et felles hjelpeschema.
--
-- knowledge.evidence_items har bevisst ingen updated_at og ingen slik trigger:
-- raden kan ikke endres etter innsetting, så et «sist endret»-felt ville vært
-- en garanti uten innhold.
-- ----------------------------------------------------------------------------
comment on function catalog.set_row_timestamps() is
  'Trigger-funksjon som gir databasen eierskap til created_at og updated_at, ved INSERT og UPDATE. Brukes av katalogtabellene og av kildetabellene i knowledge. Teknisk metadata; endrer ingen klinisk verdi.';

-- ----------------------------------------------------------------------------
-- 3. knowledge.sources — hva kilden er
--    (DATABASE_ARCHITECTURE.md §16, KNOWLEDGE_MODEL.md §10)
--
-- Raden beskriver dokumentet. Den sier ikke hva Antidep mener dokumentet viser;
-- det er evidensfunnenes og påstandenes oppgave (KNOWLEDGE_MODEL.md §10).
--
-- Bibliografiske identifikatorer ligger i knowledge.source_identifiers, aldri
-- som intern primærnøkkel (DATABASE_ARCHITECTURE.md §8).
-- ----------------------------------------------------------------------------
create table knowledge.sources (
  id uuid primary key default gen_random_uuid(),
  source_type knowledge.source_type not null,
  title text not null,
  authors_or_issuer text not null,
  publisher_or_journal text,
  volume text,
  issue text,
  pages text,
  publication_date date,
  publication_date_precision knowledge.date_precision,
  source_status knowledge.source_status not null default 'active',
  status_note text,
  superseded_by_source_id uuid
    references knowledge.sources (id) on update restrict on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sources_title_trimmed_check check (title = btrim(title)),
  constraint sources_title_not_blank_check check (length(title) between 1 and 600),
  constraint sources_authors_trimmed_check
    check (authors_or_issuer = btrim(authors_or_issuer)),
  constraint sources_authors_not_blank_check
    check (length(authors_or_issuer) between 1 and 1000),
  constraint sources_publisher_not_blank_check
    check (publisher_or_journal is null
           or (publisher_or_journal = btrim(publisher_or_journal)
               and length(publisher_or_journal) between 1 and 300)),
  constraint sources_volume_not_blank_check
    check (volume is null or (volume = btrim(volume) and length(volume) between 1 and 50)),
  constraint sources_issue_not_blank_check
    check (issue is null or (issue = btrim(issue) and length(issue) between 1 and 50)),
  constraint sources_pages_not_blank_check
    check (pages is null or (pages = btrim(pages) and length(pages) between 1 and 50)),
  -- Datoen og presisjonen hører sammen: en dato uten presisjonsnivå ville blitt
  -- lest som om dagen var kjent (ANTIDEP_CONSTITUTION.md §6).
  constraint sources_publication_date_precision_pairing_check
    check ((publication_date is null) = (publication_date_precision is null)),
  -- Datoen lagres avkortet til presisjonsnivået, slik at den ikke kan bære mer
  -- informasjon enn presisjonen sier at den har.
  constraint sources_publication_date_year_precision_check
    check (publication_date_precision is distinct from 'year'
           or (date_part('month', publication_date) = 1
               and date_part('day', publication_date) = 1)),
  constraint sources_publication_date_month_precision_check
    check (publication_date_precision is distinct from 'month'
           or date_part('day', publication_date) = 1),
  -- En kilde som ikke lenger er normal skal ikke kunne bli det stille: enhver
  -- status utenom active krever en begrunnelse (DATABASE_ARCHITECTURE.md §58).
  constraint sources_status_note_required_check
    check (source_status = 'active'
           or (status_note is not null and btrim(status_note) <> '')),
  constraint sources_status_note_trimmed_check
    check (status_note is null
           or (status_note = btrim(status_note) and length(status_note) between 1 and 1000)),
  -- Erstatningspekeren gir statusen superseded et faktisk referansepunkt.
  constraint sources_superseded_by_requires_status_check
    check (superseded_by_source_id is null or source_status = 'superseded'),
  constraint sources_no_self_supersession_check
    check (superseded_by_source_id is null or superseded_by_source_id <> id)
);

comment on table knowledge.sources is
  'En identifiserbar informasjonskilde: publikasjon, retningslinje, preparatomtale, regulatorisk dokument eller datasett. Raden sier hva kilden er, ikke hva Antidep mener den viser (KNOWLEDGE_MODEL.md §10). Bibliografiske identifikatorer ligger i knowledge.source_identifiers, hentede øyeblikksbilder i knowledge.source_versions.';
comment on column knowledge.sources.title is
  'Tittel slik kilden selv skriver den, på kildens eget språk. Ikke oversatt, slik at den kan slås opp igjen ordrett.';
comment on column knowledge.sources.authors_or_issuer is
  'Forfattere for en publikasjon, eller utgivende instans for en retningslinje, preparatomtale eller et datasett.';
comment on column knowledge.sources.publication_date is
  'Publiseringsdato avkortet til publication_date_precision. NULL når kilden ikke er datert; da skal også presisjonen være NULL.';
comment on column knowledge.sources.publication_date_precision is
  'Hvor presist publiseringsdatoen er kjent. year og month betyr at datoen er avkortet til 1. januar eller den 1. i måneden, ikke at den faktisk er den dagen.';
comment on column knowledge.sources.source_status is
  'Kildens status. retracted og withdrawn skal blokkere senere publiseringsgater (DATABASE_ARCHITECTURE.md §58); gaten selv hører til migrasjon 006.';
comment on column knowledge.sources.status_note is
  'Begrunnelse for en status som ikke er active, for eksempel tilbaketrekkingsgrunn med dato. Påkrevd for alle andre statuser enn active, slik at en tilbaketrukket kilde ikke kan bli det uten spor.';
comment on column knowledge.sources.superseded_by_source_id is
  'Kilden som erstatter denne. Kan bare settes når status er superseded. Den gamle raden slettes ikke (DATABASE_ARCHITECTURE.md §36).';

-- Kilder skal kunne søkes opp etter status, blant annet av den senere
-- publiseringsgaten som må kunne finne tilbaketrukne kilder.
create index sources_source_status_idx on knowledge.sources (source_status);

create index sources_superseded_by_source_id_idx
  on knowledge.sources (superseded_by_source_id);

create trigger sources_set_row_timestamps
  before insert or update on knowledge.sources
  for each row execute function catalog.set_row_timestamps();

-- ----------------------------------------------------------------------------
-- 4. knowledge.source_identifiers — globale identifikatorer
--    (DATABASE_ARCHITECTURE.md §8, §16)
--
-- Samme mønster som catalog.drug_identifiers i migrasjon 002: eksterne
-- identifikatorer er egne relasjoner med unike constraints, aldri intern
-- primærnøkkel. De kan mangle, korrigeres og finnes i flere systemer.
--
-- Unikhet gjelder (system, verdi), slik at én DOI eller PMID ikke kan peke på
-- to kilder. Det er bevisst ikke satt en unikhet per (kilde, system): en kilde
-- kan i praksis ha flere DOI-er, for eksempel ved parallellpublisering, og en
-- slik dublett skal kunne registreres og vurderes redaksjonelt framfor å bli
-- avvist ved import.
-- ----------------------------------------------------------------------------
create table knowledge.source_identifiers (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null
    references knowledge.sources (id) on update restrict on delete restrict,
  identifier_system knowledge.source_identifier_system not null,
  identifier_value text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint source_identifiers_system_value_key
    unique (identifier_system, identifier_value),
  constraint source_identifiers_value_trimmed_check
    check (identifier_value = btrim(identifier_value)
           and length(identifier_value) between 1 and 300),
  -- DOI-er er ikke bokstavstørrelsesfølsomme. Verdien lagres derfor normalisert
  -- til små bokstaver, ellers ville unikhetsregelen over kunne omgås med to
  -- skrivemåter av samme DOI.
  constraint source_identifiers_doi_lowercase_check
    check (identifier_system <> 'doi' or identifier_value = lower(identifier_value)),
  constraint source_identifiers_doi_format_check
    check (identifier_system <> 'doi' or identifier_value ~ '^10\.[0-9]{4,9}/\S+$'),
  constraint source_identifiers_pmid_format_check
    check (identifier_system <> 'pmid' or identifier_value ~ '^[1-9][0-9]{0,8}$')
);

comment on table knowledge.source_identifiers is
  'Globale bibliografiske identifikatorer for en kilde, for eksempel DOI og PubMed-ID. Unik per (system, verdi), slik at samme identifikator ikke kan peke på to kilder. Aldri intern primærnøkkel (DATABASE_ARCHITECTURE.md §8).';
comment on column knowledge.source_identifiers.identifier_value is
  'Verdien slik identifikatorsystemet skriver den. DOI lagres med små bokstaver og valideres mot prefiksformatet; PMID valideres som et positivt heltall uten ledende null.';

create index source_identifiers_source_id_idx
  on knowledge.source_identifiers (source_id);

create trigger source_identifiers_set_row_timestamps
  before insert or update on knowledge.source_identifiers
  for each row execute function catalog.set_row_timestamps();

-- ----------------------------------------------------------------------------
-- 5. knowledge.source_versions — hvilken utgave vi faktisk leste
--    (DATABASE_ARCHITECTURE.md §18, KNOWLEDGE_MODEL.md §11.2)
--
-- Levende kilder kan endres uten å få ny URL, og selv en fast publikasjon leses
-- gjennom en representasjon: et sammendrag, en bibliografisk post, en PDF.
-- ANTIDEP_CONSTITUTION.md §11 tillater eksplisitt verifikasjon mot «en
-- etterprøvbar representasjon» av originalkilden. Raden her sier hvilken
-- representasjon som ble hentet, når, og hva den inneholdt.
--
-- retrieved_from er derfor NOT NULL og går ut over minimumslisten i §18: en
-- content_hash uten en adresse å hente på nytt fra kan ikke etterprøves, og da
-- er den bare et tall. Sammen gjør de to feltene at hvem som helst kan hente
-- representasjonen på nytt, hashe den og se om kilden har endret seg.
--
-- Fulltekst lagres bare når det er tillatt og nødvendig (§18). storage_reference
-- er NULL når vi ikke lagrer et eget øyeblikksbilde.
-- ----------------------------------------------------------------------------
create table knowledge.source_versions (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null
    references knowledge.sources (id) on update restrict on delete restrict,
  retrieved_at timestamptz not null,
  retrieved_from text not null,
  external_version text,
  content_hash text,
  storage_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Gjør (id, source_id) refererbar, slik at knowledge.evidence_items kan kreve
  -- deklarativt at kildeversjonen tilhører den samme kilden. Regelen går på
  -- tvers av rader og hører derfor ikke hjemme i en CHECK
  -- (DATABASE_ARCHITECTURE.md §59).
  constraint source_versions_id_source_key unique (id, source_id),
  -- Samme øyeblikksbilde av samme kilde skal ikke registreres to ganger.
  -- NULL-verdier regnes som forskjellige, så uhashede versjoner er ikke berørt.
  constraint source_versions_source_content_key unique (source_id, content_hash),
  constraint source_versions_retrieved_from_trimmed_check
    check (retrieved_from = btrim(retrieved_from)
           and length(retrieved_from) between 1 and 2000),
  constraint source_versions_external_version_not_blank_check
    check (external_version is null
           or (external_version = btrim(external_version)
               and length(external_version) between 1 and 200)),
  -- Hashen er selvbeskrivende: algoritmen står i verdien, slik at en senere
  -- algoritme kan innføres uten at gamle verdier blir tvetydige.
  constraint source_versions_content_hash_format_check
    check (content_hash is null or content_hash ~ '^sha256:[0-9a-f]{64}$'),
  constraint source_versions_storage_reference_not_blank_check
    check (storage_reference is null
           or (storage_reference = btrim(storage_reference)
               and length(storage_reference) between 1 and 2000))
);

comment on table knowledge.source_versions is
  'Et hentet øyeblikksbilde av en kilde: hvilken representasjon som ble lest, når den ble hentet, hvilken versjon kilden selv oppga, og hva innholdet hashet til. Gjør en ekstraksjon etterprøvbar og gjør det mulig å oppdage at en levende kilde har endret seg (DATABASE_ARCHITECTURE.md §18).';
comment on column knowledge.source_versions.retrieved_at is
  'Når representasjonen ble hentet. Et hendelsestidspunkt fra virkeligheten, ikke registreringstidspunktet for raden; det siste er created_at (DATABASE_ARCHITECTURE.md §7.3).';
comment on column knowledge.source_versions.retrieved_from is
  'Den nøyaktige adressen eller representasjonen som ble hentet og hashet, slik at hashen kan reproduseres av andre.';
comment on column knowledge.source_versions.external_version is
  'Versjonsmerket kilden selv oppgir, for eksempel revisjonsdato for en bibliografisk post eller versjonsnummer for en preparatomtale. NULL betyr at kilden ikke eksponerer noe versjonsmerke, ikke at versjonen er ukjent.';
comment on column knowledge.source_versions.content_hash is
  'sha256 av innholdet som ble hentet, med algoritmen som prefiks. NULL betyr at det ikke ble hashet noe øyeblikksbilde.';
comment on column knowledge.source_versions.storage_reference is
  'Peker til et lagret øyeblikksbilde når lagring er tillatt og nødvendig. NULL betyr at fulltekst bevisst ikke er lagret; da er retrieved_from og content_hash sporet.';

create index source_versions_source_id_idx on knowledge.source_versions (source_id);

create trigger source_versions_set_row_timestamps
  before insert or update on knowledge.source_versions
  for each row execute function catalog.set_row_timestamps();

-- Et øyeblikksbilde er en historisk observasjon: «denne adressen inneholdt
-- dette på dette tidspunktet». Kunne feltene endres i ettertid, ville
-- provenienskjeden til alle evidensfunn som peker hit blitt omskrevet uten spor
-- (DATABASE_ARCHITECTURE.md §7, §7.1). Et nytt innhold er en ny versjon.
--
-- storage_reference er bevisst utenfor vernet: hvor et lagret øyeblikksbilde
-- ligger er driftsinformasjon og kan endres uten at observasjonen endres.
-- Dette er en immutable-row guard, som §60 navngir som god triggerbruk.
create function knowledge.freeze_source_version()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  if new.source_id is distinct from old.source_id
    or new.retrieved_at is distinct from old.retrieved_at
    or new.retrieved_from is distinct from old.retrieved_from
    or new.external_version is distinct from old.external_version
    or new.content_hash is distinct from old.content_hash
  then
    raise exception using
      errcode = 'restrict_violation',
      message = 'Et hentet øyeblikksbilde av en kilde er uforanderlig og kan ikke endres.',
      hint = 'Registrer en ny kildeversjon for det nye innholdet. Evidensfunn som peker på den gamle versjonen skal beholde sin opprinnelige dokumentasjon.';
  end if;

  return new;
end;
$$;

comment on function knowledge.freeze_source_version() is
  'Immutable-row guard: hindrer at et hentet øyeblikksbilde endres etter innsetting, slik at provenienskjeden til evidensfunn som peker på versjonen forblir etterprøvbar. storage_reference kan endres.';

revoke execute on function knowledge.freeze_source_version() from public;

create trigger source_versions_freeze_snapshot
  before update on knowledge.source_versions
  for each row execute function knowledge.freeze_source_version();

-- ----------------------------------------------------------------------------
-- 6. knowledge.evidence_items — ett konkret funn fra én kildeversjon
--    (DATABASE_ARCHITECTURE.md §19, §19.1, §20, KNOWLEDGE_MODEL.md §11)
--
-- Laget mellom originalkilden og Antideps syntese. Raden skal ligge så nær det
-- kilden faktisk rapporterer som mulig; fortolkning på tvers av studier hører
-- til Claim og EvidenceAssessment (KNOWLEDGE_MODEL.md §11.1).
--
-- Manglende verdier har eksplisitt semantikk (§19.1). Hvert klinisk viktig felt
-- har en ledsagende *_availability-kolonne av typen knowledge.value_availability,
-- og koblingen håndheves deklarativt: en verdi står i kolonnen hvis og bare hvis
-- statusen er reported_value eller uncertain_extraction. Regelen er den samme
-- for alle feltene, slik at det ikke finnes noe felt der NULL betyr «vi vet
-- ikke hvorfor». «Ikke målt», «ikke rapportert» og «ingen klar forskjell» er
-- tre forskjellige tilstander: de to første er availability-verdier, den siste
-- er en registrert retning i reported_direction. Dette er en konstitusjonell
-- regel (ANTIDEP_CONSTITUTION.md §6), ikke en preferanse.
--
-- Rå ekstraksjon og kanoniske felt holdes atskilt (§20): raw_extraction bevarer
-- kildens egne formuleringer og tall ordrett for reproduksjon og verifikasjon,
-- mens effektmål, estimat, populasjon og tidsramme samtidig normaliseres til
-- validerbare kolonner. JSONB bevarer variasjon; JSONB skjuler ikke kjernemodellen.
--
-- Bevisst utelatt i dette steget:
--   * study_id — knowledge.studies finnes ikke ennå, se avgrensningen øverst.
--   * created_by_actor_id — provenance.actors kommer i migrasjon 005.
--   * absolute_effect (§19, «når tilgjengelig og relevant») — et absolutt
--     effektmål trenger sin egen skala- og nevnermodell, og ingen av funnene i
--     første slice rapporterer et. Vektendring i kilogram er allerede absolutt.
--   * spredningsmål som standardavvik — §19 modellerer usikkerhet som
--     konfidensintervall. Et standardavvik i en kilde bevares ordrett i
--     raw_extraction fram til en migrasjon trenger det strukturert.
-- ----------------------------------------------------------------------------
create table knowledge.evidence_items (
  id uuid primary key default gen_random_uuid(),

  -- Opphav
  source_id uuid not null
    references knowledge.sources (id) on update restrict on delete restrict,
  source_version_id uuid,
  design_code knowledge.study_design not null,

  -- Populasjon
  population_id uuid
    references catalog.populations (id) on update restrict on delete restrict,
  population_availability knowledge.value_availability not null,
  population_detail text not null,

  sample_size integer,
  sample_size_availability knowledge.value_availability not null,

  -- Armer
  intervention_drug_id uuid not null
    references catalog.drugs (id) on update restrict on delete restrict,
  intervention_detail text,
  comparator_kind knowledge.comparator_kind not null,
  comparator_drug_id uuid
    references catalog.drugs (id) on update restrict on delete restrict,
  comparator_detail text,

  -- Endepunkt
  outcome_concept_id uuid not null,
  outcome_detail text not null,
  timepoint_min interval,
  timepoint_max interval,
  timepoint_availability knowledge.value_availability not null,

  -- Resultat
  reported_direction knowledge.effect_direction not null,
  effect_measure knowledge.effect_measure,
  estimate numeric,
  estimate_unit knowledge.estimate_unit,
  estimate_availability knowledge.value_availability not null,
  ci_lower numeric,
  ci_upper numeric,
  ci_level_percent numeric,
  confidence_interval_availability knowledge.value_availability not null,

  -- Dokumentasjon av ekstraksjonen
  limitations_text text,
  source_locator text not null,
  extraction_method knowledge.extraction_method not null,
  raw_extraction jsonb,
  content_hash text not null,
  created_at timestamptz not null default now(),

  -- Konstant kolonne som lar fremmednøkkelen under kreve concept_type =
  -- 'outcome', samme mønster som catalog.populations i migrasjon 002. Holder
  -- typekravet deklarativt i stedet for i applikasjonskode.
  required_outcome_type catalog.clinical_concept_type
    generated always as ('outcome'::catalog.clinical_concept_type) stored,

  -- Kildeversjonen må tilhøre den samme kilden. Cross-row-regel løst med
  -- sammensatt fremmednøkkel, ikke med CHECK (DATABASE_ARCHITECTURE.md §59).
  -- MATCH SIMPLE gjør at en NULL kildeversjon slår av kravet for den raden.
  constraint evidence_items_source_version_fkey
    foreign key (source_version_id, source_id)
    references knowledge.source_versions (id, source_id)
    on update restrict on delete restrict,

  -- Endepunktet må være et begrep av typen outcome.
  constraint evidence_items_outcome_fkey
    foreign key (outcome_concept_id, required_outcome_type)
    references catalog.clinical_concepts (id, concept_type)
    on update restrict on delete restrict,

  -- Null/ukjent-semantikk: en verdi finnes hvis og bare hvis statusen sier det.
  constraint evidence_items_population_availability_check
    check ((population_id is not null)
           = (population_availability in ('reported_value', 'uncertain_extraction'))),
  constraint evidence_items_sample_size_availability_check
    check ((sample_size is not null)
           = (sample_size_availability in ('reported_value', 'uncertain_extraction'))),
  constraint evidence_items_timepoint_availability_check
    check ((timepoint_min is not null)
           = (timepoint_availability in ('reported_value', 'uncertain_extraction'))),
  constraint evidence_items_timepoint_pairing_check
    check ((timepoint_min is null) = (timepoint_max is null)),
  constraint evidence_items_estimate_availability_check
    check ((estimate is not null)
           = (estimate_availability in ('reported_value', 'uncertain_extraction'))),
  constraint evidence_items_confidence_interval_availability_check
    check ((ci_lower is not null)
           = (confidence_interval_availability in ('reported_value', 'uncertain_extraction'))),
  constraint evidence_items_confidence_interval_pairing_check
    check ((ci_lower is null) = (ci_upper is null)),

  -- Representative invariants (DATABASE_ARCHITECTURE.md §58).
  constraint evidence_items_sample_size_positive_check
    check (sample_size is null or sample_size > 0),
  constraint evidence_items_timepoint_positive_check
    check (timepoint_min is null or timepoint_min > interval '0'),
  constraint evidence_items_timepoint_interval_check
    check (timepoint_min is null or timepoint_max >= timepoint_min),
  constraint evidence_items_confidence_interval_order_check
    check (ci_lower is null or ci_upper >= ci_lower),
  -- Et estimat utenfor sitt eget konfidensintervall er praktisk talt alltid en
  -- avskrivingsfeil. Databasen avviser den heller høyt enn å lagre den stille.
  constraint evidence_items_estimate_within_interval_check
    check (estimate is null or ci_lower is null
           or estimate between ci_lower and ci_upper),
  constraint evidence_items_confidence_level_pairing_check
    check ((ci_lower is null) = (ci_level_percent is null)),
  constraint evidence_items_confidence_level_range_check
    check (ci_level_percent is null or ci_level_percent between 50 and 99.99),

  -- Et tall uten effektmål er ikke tolkbart.
  constraint evidence_items_estimate_requires_measure_check
    check (estimate is null or effect_measure is not null),
  -- Dimensjonale mål krever enhet; dimensjonsløse mål skal ikke ha enhet.
  constraint evidence_items_estimate_unit_check
    check (
      case
        when effect_measure is null then estimate_unit is null
        when effect_measure in ('mean_change', 'mean_difference')
          then estimate_unit is not null
        else estimate_unit is null
      end
    ),
  -- Forholdstall er strengt positive; en negativ RR eller OR er en feil.
  constraint evidence_items_ratio_positive_check
    check (effect_measure is null
           or effect_measure not in ('risk_ratio', 'odds_ratio')
           or (coalesce(estimate, 1) > 0 and coalesce(ci_lower, 1) > 0)),

  -- Armer
  constraint evidence_items_comparator_drug_check
    check ((comparator_kind = 'drug') = (comparator_drug_id is not null)),
  constraint evidence_items_comparator_differs_check
    check (comparator_drug_id is null or comparator_drug_id <> intervention_drug_id),

  -- Tekstfelter
  constraint evidence_items_population_detail_check
    check (population_detail = btrim(population_detail)
           and length(population_detail) between 1 and 2000),
  constraint evidence_items_outcome_detail_check
    check (outcome_detail = btrim(outcome_detail)
           and length(outcome_detail) between 1 and 2000),
  -- KNOWLEDGE_MODEL.md §11.2: funnet skal ha en presis peker til stedet i
  -- kilden som underbygger ekstraksjonen.
  constraint evidence_items_source_locator_check
    check (source_locator = btrim(source_locator)
           and length(source_locator) between 1 and 500),
  constraint evidence_items_intervention_detail_check
    check (intervention_detail is null
           or (intervention_detail = btrim(intervention_detail)
               and length(intervention_detail) between 1 and 2000)),
  constraint evidence_items_comparator_detail_check
    check (comparator_detail is null
           or (comparator_detail = btrim(comparator_detail)
               and length(comparator_detail) between 1 and 2000)),
  constraint evidence_items_limitations_text_check
    check (limitations_text is null
           or (limitations_text = btrim(limitations_text)
               and length(limitations_text) between 1 and 4000)),

  -- Rå ekstraksjon skal være et objekt, ikke en løs skalar (§20).
  constraint evidence_items_raw_extraction_object_check
    check (raw_extraction is null or jsonb_typeof(raw_extraction) = 'object'),

  -- Hashen er selvbeskrivende og versjonert: definisjonen av hva som hashes
  -- kan endres av en senere migrasjon uten at gamle verdier blir tvetydige.
  constraint evidence_items_content_hash_format_check
    check (content_hash ~ '^sha256-v[0-9]+:[0-9a-f]{64}$'),
  -- Nøyaktig samme funn skal ikke kunne registreres to ganger; en dublett ville
  -- blitt dobbelttalt i enhver senere syntese. En kontroll av en eksisterende
  -- ekstraksjon er en arbeidsflytregistrering (migrasjon 005), ikke et nytt
  -- evidensobjekt.
  constraint evidence_items_content_hash_key unique (content_hash)
);

comment on table knowledge.evidence_items is
  'Ett konkret evidensfunn ekstrahert fra én kildeversjon: hva som ble målt, i hvilken populasjon, med hvilket resultat, og nøyaktig hvor i kilden det står. Raden er uforanderlig etter innsetting. Den sier hva kilden rapporterer, ikke hva Antidep konkluderer; syntese hører til Claim og EvidenceAssessment (KNOWLEDGE_MODEL.md §11.1).';
comment on column knowledge.evidence_items.source_version_id is
  'Kildeversjonen funnet er lest ut av. Må tilhøre samme kilde som source_id; kravet håndheves av den sammensatte fremmednøkkelen. NULL når funnet ikke er knyttet til et registrert øyeblikksbilde.';
comment on column knowledge.evidence_items.design_code is
  'Studiedesignet for dette funnet. Ligger på funnet, ikke på kilden, fordi én publikasjon kan rapportere flere design.';
comment on column knowledge.evidence_items.population_id is
  'Katalogpopulasjonen funnet indekseres under, altså gyldighetsgrensen påstander skal kunne kontrolleres mot. Kan være videre enn den studerte populasjonen; det ordrette utvalget står i population_detail, og et avvik mellom dem er indirekthet, som vurderes i evidence_assessments (DATABASE_ARCHITECTURE.md §22).';
comment on column knowledge.evidence_items.population_availability is
  'Hvorfor populasjonen er eller ikke er koblet til katalogen. uncertain_extraction brukes når koblingen er gjort, men er usikker, slik at usikkerheten er maskinlesbar og ikke bare står i prosa.';
comment on column knowledge.evidence_items.population_detail is
  'Den studerte populasjonen slik kilden selv beskriver den, inkludert kjente forbehold om utvalget. Alltid utfylt.';
comment on column knowledge.evidence_items.sample_size is
  'Antall deltakere funnet bygger på. Skal være det antallet analysen faktisk omfatter, ikke antallet randomisert, når de er forskjellige.';
comment on column knowledge.evidence_items.comparator_kind is
  'Kontrasten i selve funnet. none betyr at funnet er armspesifikt, også når studien det er hentet fra hadde en komparator; studiekonteksten dokumenteres da i limitations_text.';
comment on column knowledge.evidence_items.outcome_concept_id is
  'Endepunktet funnet gjelder. Må være et begrep av typen outcome; kravet håndheves av fremmednøkkelen mot (id, concept_type).';
comment on column knowledge.evidence_items.outcome_detail is
  'Hva som faktisk ble målt, slik kilden definerer det. Begrepet alene, for eksempel vektendring, er for grovt til å si om det gjelder gjennomsnittlig endring i kilo, prosentvis endring eller andelen med en gitt økning.';
comment on column knowledge.evidence_items.timepoint_min is
  'Nedre grense for oppfølgingstiden funnet gjelder. Lagret som interval, slik at verdi og enhet ikke kan komme fra hverandre. Kilder som oppgir ett tidspunkt har lik nedre og øvre grense; kilder som oppgir et spenn, for eksempel 26 til 32 uker, beholder spennet i stedet for å bli avrundet til falsk presisjon.';
comment on column knowledge.evidence_items.reported_direction is
  'Retningen kilden rapporterer. Alltid utfylt, slik at et nullfunn (no_clear_difference) er en registrert tilstand og ikke kan forveksles med manglende data.';
comment on column knowledge.evidence_items.estimate_unit is
  'Enhet for et dimensjonalt estimat. Påkrevd for mean_change og mean_difference, forbudt for dimensjonsløse mål.';
comment on column knowledge.evidence_items.source_locator is
  'Presis peker til stedet i kildeversjonen som underbygger ekstraksjonen, for eksempel avsnitt, side, tabell eller figur (KNOWLEDGE_MODEL.md §11.2).';
comment on column knowledge.evidence_items.raw_extraction is
  'Kildens egne formuleringer og tall, bevart ordrett for reproduksjon og for verifikasjon mot originalen. Skal aldri være eneste sted et kanonisk felt finnes (DATABASE_ARCHITECTURE.md §20).';
comment on column knowledge.evidence_items.content_hash is
  'Fingeravtrykk av de kanoniske feltene, satt av databasen ved innsetting. Identifiserer samme funn på tvers av systemer og hindrer at en dublett dobbelttelles. Prefikset angir hvilken hashdefinisjon som er brukt.';
comment on column knowledge.evidence_items.required_outcome_type is
  'Teknisk konstant som lar fremmednøkkelen kreve concept_type = outcome. Ingen klinisk betydning.';

create index evidence_items_source_id_idx on knowledge.evidence_items (source_id);
create index evidence_items_source_version_id_idx
  on knowledge.evidence_items (source_version_id);
create index evidence_items_population_id_idx on knowledge.evidence_items (population_id);
create index evidence_items_comparator_drug_id_idx
  on knowledge.evidence_items (comparator_drug_id);
-- Oppslaget kliniker-UI-et og senere claim-arbeid faktisk gjør: hvilken evidens
-- finnes for dette virkestoffet på dette endepunktet.
create index evidence_items_intervention_outcome_idx
  on knowledge.evidence_items (intervention_drug_id, outcome_concept_id);

-- Fingeravtrykket eies av databasen, ikke av kalleren. En hash klienten kunne
-- oppgi selv ville sett ut som en garanti uten å være det. Funksjonen hasher
-- bare de kanoniske feltene: to ekstraksjoner av samme funn er samme funn selv
-- om rå payload eller ekstraksjonsmetode er ulik.
--
-- Numeriske verdier normaliseres med trim_scale, og tidsrom hashes som sekunder,
-- slik at 0.80 og 0.8, og «8 uker» skrevet på to måter, gir samme verdi.
-- Prefikset sha256-v1 versjonerer definisjonen: endrer en senere migrasjon hva
-- som inngår, skal den innføre et nytt prefiks framfor å gjøre gamle verdier
-- stille uforenlige med nye.
--
-- Dette er en bevisst og snever trigger (DATABASE_ARCHITECTURE.md §60): den
-- utleder ett teknisk felt fra radens egne kolonner og inneholder ingen klinisk
-- logikk og ingen arbeidsflyt.
create function knowledge.set_evidence_item_content_hash()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
declare
  canonical text;
begin
  canonical := concat_ws(
    '|',
    'sha256-v1',
    new.source_id::text,
    coalesce(new.source_version_id::text, ''),
    new.design_code::text,
    coalesce(new.population_id::text, ''),
    new.population_availability::text,
    new.population_detail,
    coalesce(new.sample_size::text, ''),
    new.sample_size_availability::text,
    new.intervention_drug_id::text,
    coalesce(new.intervention_detail, ''),
    new.comparator_kind::text,
    coalesce(new.comparator_drug_id::text, ''),
    coalesce(new.comparator_detail, ''),
    new.outcome_concept_id::text,
    new.outcome_detail,
    coalesce(extract(epoch from new.timepoint_min)::text, ''),
    coalesce(extract(epoch from new.timepoint_max)::text, ''),
    new.timepoint_availability::text,
    new.reported_direction::text,
    coalesce(new.effect_measure::text, ''),
    coalesce(trim_scale(new.estimate)::text, ''),
    coalesce(new.estimate_unit::text, ''),
    new.estimate_availability::text,
    coalesce(trim_scale(new.ci_lower)::text, ''),
    coalesce(trim_scale(new.ci_upper)::text, ''),
    coalesce(trim_scale(new.ci_level_percent)::text, ''),
    new.confidence_interval_availability::text,
    coalesce(new.limitations_text, ''),
    new.source_locator
  );

  new.content_hash := 'sha256-v1:' || encode(sha256(convert_to(canonical, 'UTF8')), 'hex');

  return new;
end;
$$;

comment on function knowledge.set_evidence_item_content_hash() is
  'Trigger-funksjon som utleder content_hash fra de kanoniske feltene på et evidensfunn ved innsetting. Gir databasen eierskap til fingeravtrykket, slik at det ikke kan oppgis av kalleren. Teknisk metadata; endrer ingen klinisk verdi.';

revoke execute on function knowledge.set_evidence_item_content_hash() from public;

create trigger evidence_items_set_content_hash
  before insert on knowledge.evidence_items
  for each row execute function knowledge.set_evidence_item_content_hash();

-- Immutabilitetsstrategi for EvidenceItem (MVP_IMPLEMENTATION_PLAN.md §20).
--
-- Valgt strategi: append-only. Raden kan verken endres eller slettes etter
-- innsetting; korreksjon skjer ved å registrere et nytt evidensfunn.
--
-- Hvorfor hele raden, og ikke bare de definerende feltene slik
-- catalog.freeze_population_definition() gjør: en populasjon har en
-- livssyklus utenfor definisjonen sin — den kan fases ut — mens et evidensfunn
-- i sin helhet er påstanden «denne kilden rapporterte dette, her». Det finnes
-- ikke noe felt på raden som kan endres uten at den påstanden endres.
--
-- Hvorfor også DELETE: vanlig redaksjonelt arbeid skal ikke fysisk slette
-- kanonisk kunnskap (DATABASE_ARCHITECTURE.md §36). Fremmednøklene beskytter
-- bare rader andre rader peker på, og i dette steget peker ingenting ennå på
-- evidensfunn. Vernet gjelder også eieren av tabellen: en reell
-- vedlikeholdsoperasjon må slå av triggeren eksplisitt, som en synlig og
-- reviewbar handling, på samme måte som i migrasjon 002.
--
-- Kjent konsekvens: et evidensfunn kan foreløpig ikke merkes som tilbaketrukket
-- eller erstattet, fordi raden ikke har en livssyklus å endre. Det er
-- akseptabelt her fordi ingenting ennå konsumerer evidensfunn — det finnes
-- verken claims, publisering eller api-projeksjoner — men spørsmålet må
-- avgjøres når review og verifikasjon kommer i migrasjon 005: en trukket
-- ekstraksjon er en faglig beslutning, og beslutninger hører til workflow
-- (DATABASE_ARCHITECTURE.md §29), ikke til en muterbar statuskolonne her.
create function knowledge.reject_evidence_item_mutation()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  raise exception using
    errcode = 'restrict_violation',
    message = format(
      'Evidensfunn %L er uforanderlig; %s er ikke tillatt.', old.id, tg_op
    ),
    hint = 'Registrer et nytt evidensfunn for den korrigerte ekstraksjonen. En eksisterende ekstraksjon skal ikke overskrives eller slettes, fordi den dokumenterer hva kilden faktisk rapporterte.';
end;
$$;

comment on function knowledge.reject_evidence_item_mutation() is
  'Immutable-row guard: gjør knowledge.evidence_items append-only ved å avvise både UPDATE og DELETE. En korrigert ekstraksjon registreres som et nytt evidensfunn.';

revoke execute on function knowledge.reject_evidence_item_mutation() from public;

create trigger evidence_items_reject_mutation
  before update or delete on knowledge.evidence_items
  for each row execute function knowledge.reject_evidence_item_mutation();

-- ----------------------------------------------------------------------------
-- 7. RLS og grants (DATABASE_ARCHITECTURE.md §5, §48,
--    MVP_IMPLEMENTATION_PLAN.md §47)
--
-- RLS aktiveres på alle nye tabeller og er default deny: uten policy gir
-- tabellen ingen rader til noen rolle som ikke eier den. Ingen policy skrives
-- her. Redaksjonell lesetilgang forutsetter medlemskapsmodellen i migrasjon
-- 005, og klientlesing skal uansett gå gjennom publiserte projeksjoner i api
-- (migrasjon 007), aldri direkte mot knowledge.
--
-- Nye tabeller får ingen privilegier til klientrollene i PostgreSQL, men
-- grensen skrives eksplisitt, som i migrasjon 001 og 002.
--
-- service_role får fortsatt ingenting. Evidenspipelinen trenger en
-- skriveidentitet, men den skal være en egen least privilege-identitet med
-- smale grants, ikke plattformens universalnøkkel (DATABASE_ARCHITECTURE.md
-- §49, MVP_IMPLEMENTATION_PLAN.md §49). Identiteten opprettes av migrasjonen
-- som innfører den første automatiske skriveveien.
-- ----------------------------------------------------------------------------
alter table knowledge.sources enable row level security;
alter table knowledge.source_identifiers enable row level security;
alter table knowledge.source_versions enable row level security;
alter table knowledge.evidence_items enable row level security;

revoke all privileges on all tables in schema knowledge from public;
revoke all privileges on all tables in schema knowledge
  from anon, authenticated, service_role;

-- ============================================================================
-- 8. Kilder og evidensfunn for første golden slice
--    (MVP_IMPLEMENTATION_PLAN.md §12, §20, §29)
--
-- Omfang: nøyaktig det slicen trenger, sertralin + mirtazapin × vektendring i
-- voksne med depressiv lidelse. Én kilde per virkestoff, ett evidensfunn per
-- kilde. Ingen øvrige pilottemaer og ingen nye katalograder: begge funnene
-- bruker begrepet og populasjonen migrasjon 002 allerede seedet.
--
-- Plassering: radene ligger i migrasjonen, ikke i supabase/seed.sql, av samme
-- grunn som katalogdataene i migrasjon 002. Claims og publiserte projeksjoner
-- får fremmednøkler hit, og seed.sql kjøres bare ved lokal db reset.
--
-- Etterprøvbarhet (ANTIDEP_CONSTITUTION.md §4, §11): begge kildene er
-- kontrollert mot to uavhengige tjenester, PubMed/E-utilities og Crossref, som
-- er samstemte om tittel, tidsskrift, volum, hefte, sider og forfattere. Ingen
-- av dem har tilbaketrekkings- eller errata-merknad. Feltet
-- publication_date_precision speiler det tjenestene faktisk belegger: PubMed
-- oppgir «2000 Nov» og Crossref 15. november 2000 for den første kilden, så
-- bare måneden er belagt, og den andre kilden er bare årfestet av begge.
--
-- Evidensfunnene er ekstrahert fra de bibliografiske postene med sammendrag,
-- som er den etterprøvbare representasjonen ANTIDEP_CONSTITUTION.md §11 tillater
-- å verifisere mot. Ingen av kildene er åpent tilgjengelig i fulltekst herfra.
-- Det er derfor bare det sammendragene faktisk sier som er registrert:
-- ingen tall er hentet fra hukommelse, avrundet eller regnet om, og der
-- sammendraget beskriver et resultat uten å oppgi verdien, står feltet tomt med
-- statusen not_extractable framfor et anslag. Kildens egne formuleringer er
-- bevart ordrett i raw_extraction, slik at en verifikator kan kontrollere
-- ekstraksjonen mot originalen og ikke bare mot dette sammendraget.
--
-- Epistemisk status (ANTIDEP_CONSTITUTION.md §5, §12): radene er ekstraksjoner,
-- ikke synteser og ikke kliniske anbefalinger. extraction_method er ai_assisted
-- fordi de er hentet ut av en KI-assistert prosess, og de er forslag inntil de
-- har passert verifikasjons- og reviewgatene i migrasjon 005 og 006. Ingenting
-- i dette steget kan publisere dem: det finnes verken claims, publisering eller
-- api-projeksjoner.
-- ============================================================================

insert into knowledge.sources (
  source_type, title, authors_or_issuer, publisher_or_journal,
  volume, issue, pages, publication_date, publication_date_precision, source_status
)
values
  (
    'journal_article',
    'Fluoxetine versus sertraline and paroxetine in major depressive disorder: changes in weight with long-term treatment',
    'Fava M, Judge R, Hoog SL, Nilsson ME, Koke SC',
    'The Journal of Clinical Psychiatry',
    '61', '11', '863-867',
    date '2000-11-01', 'month', 'active'
  ),
  (
    'journal_article',
    'Comparison of the effects of mirtazapine and fluoxetine in severely depressed patients',
    'Versiani M, Moreno R, Ramakers-van Moorsel CJ, Schutte AJ; Comparative Efficacy of Antidepressants Study Group',
    'CNS Drugs',
    '19', '2', '137-146',
    date '2005-01-01', 'year', 'active'
  );

insert into knowledge.source_identifiers (source_id, identifier_system, identifier_value)
select s.id, v.identifier_system::knowledge.source_identifier_system, v.identifier_value
from (values
  ('863-867', 'doi', '10.4088/jcp.v61n1109'),
  ('863-867', 'pmid', '11105740'),
  ('137-146', 'doi', '10.2165/00023210-200519020-00004'),
  ('137-146', 'pmid', '15697327')
) as v(pages, identifier_system, identifier_value)
join knowledge.sources s on s.pages = v.pages;

-- Kildeversjonene er de MEDLINE-postene som faktisk ble hentet og kontrollert.
-- retrieved_from er den nøyaktige adressen, og content_hash er sha256 av
-- svaret; den samme adressen ga identisk hash ved gjentatt henting, så en senere
-- endring i posten vil kunne oppdages. Fulltekst er ikke lagret, og
-- storage_reference er derfor NULL.
insert into knowledge.source_versions (
  source_id, retrieved_at, retrieved_from, external_version, content_hash
)
select
  s.id,
  timestamptz '2026-08-19T06:17:31Z',
  'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id='
    || v.pmid || '&retmode=xml',
  v.external_version,
  v.content_hash
from (values
  ('11105740', 'MEDLINE DateRevised 2026-01-28',
   'sha256:797e91b6c4a6c075bdde4113d263608d708fb07c3c0a7b656ff3c231d12895d3'),
  ('15697327', 'MEDLINE DateRevised 2018-12-01',
   'sha256:c62a66215fc51b8c164cda70072ea30ff055b7c8e565a173a0be17cdf4e75722')
) as v(pmid, external_version, content_hash)
join knowledge.source_identifiers i
  on i.identifier_system = 'pmid' and i.identifier_value = v.pmid
join knowledge.sources s on s.id = i.source_id;

-- Evidensfunn 1 — sertralin.
--
-- Sammendraget rapporterer retningen, men ikke tallet: metodeavsnittet sier at
-- gjennomsnittlig prosentvis vektendring ble sammenlignet, og resultatavsnittet
-- karakteriserer sertralinarmen uten å oppgi verdien. Estimatet er derfor tomt
-- med statusen not_extractable, mens effektmål og enhet er kjent. Funnet er
-- armspesifikt: studien sammenlignet fluoksetin, sertralin og paroksetin, men
-- ingen av komparatorene er registrert i Antideps katalog, og den kontrasten er
-- derfor ikke påstått her.
insert into knowledge.evidence_items (
  source_id, source_version_id, design_code,
  population_id, population_availability, population_detail,
  sample_size, sample_size_availability,
  intervention_drug_id, intervention_detail,
  comparator_kind, comparator_drug_id,
  outcome_concept_id, outcome_detail,
  timepoint_min, timepoint_max, timepoint_availability,
  reported_direction, effect_measure, estimate, estimate_unit, estimate_availability,
  confidence_interval_availability,
  limitations_text, source_locator, extraction_method, raw_extraction
)
select
  s.id,
  sv.id,
  'randomized_controlled_trial',
  p.id,
  'reported_value',
  'Pasienter med depressiv lidelse etter DSM-IV, randomisert i en dobbeltblind multisenterstudie. MEDLINE-indekseringen omfatter Adult og Middle Aged, og ikke Adolescent, slik at utvalget er voksne.',
  48,
  'reported_value',
  d.id,
  'Sertralin i dobbeltblind langtidsbehandling. 96 pasienter ble randomisert til sertralin; 48 fullførte og inngikk i vektanalysen. Dosering er ikke oppgitt i den verifiserte kildeversjonen.',
  'none',
  null,
  c.id,
  'Gjennomsnittlig prosentvis vektendring fra baseline til endepunkt.',
  interval '26 weeks',
  interval '32 weeks',
  'reported_value',
  'increase',
  'mean_change',
  null,
  'percent',
  'not_extractable',
  'not_extractable',
  'Kilden karakteriserer vektøkningen som beskjeden og ikke statistisk signifikant, men oppgir ingen tallverdi i den verifiserte kildeversjonen. Analysen omfatter bare de 48 av 96 randomiserte som fullførte, noe som gir risiko for frafallsskjevhet. Funnet er armspesifikt og hentet fra en studie som sammenlignet fluoksetin, sertralin og paroksetin; sammenligningen mellom armene er ikke registrert her fordi komparatorene ikke finnes i katalogen.',
  'Sammendrag (MEDLINE-post), avsnittene METHOD og RESULTS',
  'ai_assisted',
  jsonb_build_object(
    'kildespraak', 'en',
    'metode', 'Patients (N = 284) with major depressive disorder (DSM-IV) were randomly assigned to double-blind treatment with fluoxetine (N = 92), sertraline, (N = 96), or paroxetine (N = 96) for a total of 26 to 32 weeks. The mean percent change in weight was compared for each group, as was the number of patients who had > or = 7% weight increase from baseline.',
    'resultat', 'Patients (fluoxetine, N = 44; sertraline, N = 48; paroxetine, N = 47) who completed the trial were included in these analyses. Paroxetine-treated patients experienced a significant weight increase, fluoxetine-treated patients had a modest but nonsignificant weight decrease, and patients treated with sertraline had a modest but nonsignificant weight increase.'
  )
from knowledge.source_identifiers i
join knowledge.sources s on s.id = i.source_id
join knowledge.source_versions sv on sv.source_id = s.id
join catalog.drugs d on d.canonical_name = 'sertralin'
join catalog.clinical_concepts c on c.canonical_label = 'vektendring'
join catalog.populations p on p.canonical_label = 'voksne med depressiv lidelse'
where i.identifier_system = 'pmid' and i.identifier_value = '11105740';

-- Evidensfunn 2 — mirtazapin.
--
-- Her oppgir sammendraget en tallverdi, og den er registrert som den står.
-- Spredningen er rapportert som standardavvik, ikke som konfidensintervall, så
-- konfidensintervallet er not_reported og standardavviket bevart ordrett.
-- Populasjonskoblingen er usikker: utvalget er alvorlig deprimerte pasienter,
-- og nedre aldersgrense er ikke oppgitt i den verifiserte kildeversjonen, mens
-- MEDLINE-indekseringen også omfatter Adolescent. Koblingen til «voksne med
-- depressiv lidelse» er derfor merket uncertain_extraction framfor å bli
-- framstilt som sikker.
insert into knowledge.evidence_items (
  source_id, source_version_id, design_code,
  population_id, population_availability, population_detail,
  sample_size, sample_size_availability,
  intervention_drug_id, intervention_detail,
  comparator_kind, comparator_drug_id,
  outcome_concept_id, outcome_detail,
  timepoint_min, timepoint_max, timepoint_availability,
  reported_direction, effect_measure, estimate, estimate_unit, estimate_availability,
  confidence_interval_availability,
  limitations_text, source_locator, extraction_method, raw_extraction
)
select
  s.id,
  sv.id,
  'randomized_controlled_trial',
  p.id,
  'uncertain_extraction',
  'Alvorlig deprimerte pasienter, definert som minst 25 poeng på de 17 første leddene i Hamilton Depression Rating Scale. Nedre aldersgrense er ikke oppgitt i den verifiserte kildeversjonen, og MEDLINE-indekseringen omfatter Adolescent i tillegg til Adult, Middle Aged og Aged.',
  147,
  'uncertain_extraction',
  d.id,
  'Mirtazapin 15-60 mg per dag i 8 uker. 147 pasienter ble randomisert til mirtazapin.',
  'none',
  null,
  c.id,
  'Gjennomsnittlig vektendring fra baseline til studieslutt, i kilogram.',
  interval '8 weeks',
  interval '8 weeks',
  'reported_value',
  'increase',
  'mean_change',
  0.8,
  'kg',
  'reported_value',
  'not_reported',
  'Kilden oppgir spredningen som standardavvik, 0,8 +/- 2,7 kg, ikke som konfidensintervall; standardavviket er bevart ordrett i raw_extraction. Signifikansnivået p < 0,001 gjelder sammenligningen mot fluoksetin, ikke den armspesifikke endringen alene. Antallet som faktisk inngår i vektanalysen er ikke oppgitt, så 147 er antallet randomisert til mirtazapin. Studien er ikke avgrenset til den populasjonen funnet er indeksert under.',
  'Sammendrag (MEDLINE-post), avsnittene METHODS og RESULTS',
  'ai_assisted',
  jsonb_build_object(
    'kildespraak', 'en',
    'populasjon', 'patients with severe depression (> or = 25 points on the first 17 items of the Hamilton Depression Rating Scale [HDRS-17])',
    'metode', 'In this double-blind study, 297 severely depressed patients were randomised to receive mirtazapine 15-60 mg/day (n = 147) or fluoxetine 20-40 mg/day (n = 152) for 8 weeks.',
    'resultat', 'Both agents were generally well tolerated but mirtazapine-treated patients experienced a mean weight gain of 0.8 +/- 2.7 kg compared with a mean decrease in weight of 0.4 +/- 2.1 kg for fluoxetine-treated patients (p < 0.001).'
  )
from knowledge.source_identifiers i
join knowledge.sources s on s.id = i.source_id
join knowledge.source_versions sv on sv.source_id = s.id
join catalog.drugs d on d.canonical_name = 'mirtazapin'
join catalog.clinical_concepts c on c.canonical_label = 'vektendring'
join catalog.populations p on p.canonical_label = 'voksne med depressiv lidelse'
where i.identifier_system = 'pmid' and i.identifier_value = '15697327';
