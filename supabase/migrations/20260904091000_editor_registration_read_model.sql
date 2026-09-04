-- ============================================================================
-- Migrasjon 007d — den redaksjonelle lesemodellen registreringen trenger
--
-- Steg 3 av «manuell adminflyt» (MVP_IMPLEMENTATION_PLAN.md §29) er «Editor
-- registrerer EvidenceItem» (§15). Selve skriveveien ligger i den neste
-- migrasjonen (007e). Denne åpner det leddet den forutsetter: en editor kan
-- ikke knytte et evidensfunn til en kilde, et virkestoff, et endepunkt eller
-- en populasjon uten å kunne *se* hvilke som finnes.
--
-- Utvider api-lesemodellen fra migrasjon 007 (§24) en femte gang, og følger
-- derfor bokstavkonvensjonen videre: 007 → 007a → 007b → 007c → 007d. Står
-- utenfor den planlagte rekken i §18-§27. Nummeret 009 er fortsatt reservert
-- for DrugProduct-/importfundamentet (§26), urørt av denne migrasjonen.
--
-- Styrende dokumenter:
--   docs/ANTIDEP_CONSTITUTION.md
--     §6  usikkerhet skal graderes, aldri erstattes av falsk presisjon
--     §14 attribusjon: en handling skal spores til hvem eller hva som utførte den
--   docs/DATABASE_ARCHITECTURE.md
--     §42 views som bygger på RLS-beskyttede data skal ha security_invoker
--     §43 klienten skal ikke skrive direkte til kanoniske tabeller
--     §44 Data API-kontrakten skal være eksplisitt: eksponering, GRANT, RLS
--     §45-§48 roller, RLS default deny
--     §50 privilegerte databasefunksjoner
--   docs/MVP_IMPLEMENTATION_PLAN.md
--     §15, §16, §29  admin-workflowen og rollene den bruker
--     §47, §48  offentlig lesing og admin-skriving
--
-- ----------------------------------------------------------------------------
-- Hvorfor dette er nye policyer og ikke nye grants
--
-- Migrasjon 007 ga allerede `anon` og `authenticated` SELECT på tabellene under
-- lesemodellen — knowledge.sources, knowledge.source_versions,
-- knowledge.evidence_items, catalog.drugs, catalog.clinical_concepts og
-- catalog.populations — og lot RLS avgjøre hvilke *rader* som er synlige.
-- Predikatet der er publisering: en kilde er lesbar når den er brukt av
-- publisert kunnskap. En editor som skal registrere et evidensfunn trenger det
-- motsatte utvalget — kilden hen nettopp opprettet er per definisjon ikke
-- publisert ennå — så denne migrasjonen legger til en *andre* policy per tabell.
-- Policyer er permissive og OR-es sammen: en editor ser hele registeret, alle
-- andre ser fortsatt nøyaktig det publiserte utvalget. Ingen ny grant er nødvendig,
-- og grensen flyttes derfor bare for den som faktisk har rollen.
--
-- Alle policyene er `for select`. Skriveveien er og blir en kontrollert
-- SECURITY DEFINER-funksjon (§43); en policy for INSERT eller ALL ville vært en
-- skrivevei forbi den, og 030_conventions_test.sql avviser den formen uansett.
--
-- ----------------------------------------------------------------------------
-- Hvorfor predikatet er én funksjon og ikke seks kopier
--
-- Seks tabeller trenger den samme radgrensen: «kalleren er en editor akkurat
-- nå». Skrevet ut seks ganger ville regelen kunne drive fra hverandre, og et
-- avvik i én av dem ville vært en tilgangsforskjell ingen leste som en
-- forskjell. workflow.caller_is_active_editor() er derfor det ene stedet
-- regelen står.
--
-- Funksjonen er SECURITY DEFINER av samme grunn som resten av
-- autorisasjonskoden: provenance.actors og workflow.user_roles har begge RLS
-- med default deny, og svaret skal være det samme uansett hva kalleren
-- tilfeldigvis har lov til å lese om seg selv. Tomt search_path,
-- schemakvalifiserte navn, EXECUTE revokert fra PUBLIC og gitt bare til
-- authenticated (§50).
--
-- Den er bevisst *ikke* en ny sannhet om hvem som er editor: kravene er de
-- samme tre som knowledge.assert_editor_authorized() (migrasjon 007c) stiller —
-- registrert aktør, ikke tilbaketrukket, gyldig editor-tildeling nå — bare
-- uttrykt som en boolean framfor som tre forskjellige avvisninger. At de to
-- svarer likt, er festet som en assertion i
-- 400_editor_read_model_access_test.sql framfor å stå her som en påstand.
--
-- ----------------------------------------------------------------------------
-- Hva viewene ikke gjør
--
-- Ingen av dem filtrerer på editor-rollen selv. Radgrensen står i policyene, ett
-- sted, og et view som gjentok den ville vært en andre kopi av samme regel. En
-- innlogget kaller uten editor-rolle ser derfor det publiserte utvalget gjennom
-- disse viewene — nøyaktig det samme hen allerede ser gjennom
-- api.published_claim_evidence, og ikke en rad mer.
--
-- Viewene er heller ikke sortert. Rekkefølgen på et oppslag er en
-- presentasjonsbeslutning som hører til klienten (samme doktrine som
-- `src/lib/published-read-model.ts`), og PostgREST lar kalleren be om den.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. workflow.caller_is_active_editor() — radgrensen, ett sted
-- ----------------------------------------------------------------------------
create function workflow.caller_is_active_editor()
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from provenance.actors a
    join workflow.user_roles ur on ur.user_id = a.auth_user_id
    where a.auth_user_id = (select auth.uid())
      and a.retired_at is null
      and ur.role_code = 'editor'
      and ur.valid_from <= statement_timestamp()
      and (ur.valid_to is null or ur.valid_to > statement_timestamp())
  );
$$;

comment on function workflow.caller_is_active_editor() is
  'Om den innloggede brukeren er en registrert, ikke-tilbaketrukket aktør med en gyldig editor-tildeling på spørringens eget tidspunkt (statement_timestamp(), ikke transaksjonens starttidspunkt, slik at en tilbakekalling virker umiddelbart — MVP_IMPLEMENTATION_PLAN.md §74.6). Samme tre krav som knowledge.assert_editor_authorized(uuid), uttrykt som en boolean fordi en RLS-policy trenger et predikat og ikke en avvisning. Brukes bare som radgrense for den redaksjonelle lesemodellen; skriveveiene tar autorisasjonsbeslutningen på nytt, på sitt eget kall (DATABASE_ARCHITECTURE.md §43, §48). En avgrenset editor-tildeling teller her: hva en avgrensning betyr for retten til å SKRIVE et bestemt objekt, avgjøres av skriveveien, ikke av lesbarheten.';

revoke execute on function workflow.caller_is_active_editor() from public;
grant execute on function workflow.caller_is_active_editor() to authenticated;

-- ----------------------------------------------------------------------------
-- 2. Radgrensen for en editor, på hver tabell registreringen leser
-- ----------------------------------------------------------------------------
create policy sources_editor_read on knowledge.sources
  for select to authenticated
  using (workflow.caller_is_active_editor());

comment on policy sources_editor_read on knowledge.sources is
  'Hele kilderegisteret, for en editor. Predikatet for alle andre er fortsatt publisering (sources_published_read), og de to policyene OR-es sammen. En editor må se også den kilden som ennå ikke er brukt av publisert kunnskap: det er nettopp den et nytt evidensfunn skal knyttes til.';

create policy source_versions_editor_read on knowledge.source_versions
  for select to authenticated
  using (workflow.caller_is_active_editor());

comment on policy source_versions_editor_read on knowledge.source_versions is
  'Alle registrerte øyeblikksbilder av en kilde, for en editor. Et evidensfunn skal peke på den kildeversjonen ekstraksjonen faktisk ble lest av (DATABASE_ARCHITECTURE.md §18), og valget forutsetter at versjonene er synlige.';

create policy evidence_items_editor_read on knowledge.evidence_items
  for select to authenticated
  using (workflow.caller_is_active_editor());

comment on policy evidence_items_editor_read on knowledge.evidence_items is
  'Alle registrerte evidensfunn, for en editor. Uten den ville et nyregistrert funn vært usynlig for den som nettopp registrerte det, fordi det publiserte predikatet (evidence_items_published_read) krever en publisert påstand over funnet — noe et ferskt funn per definisjon ikke har.';

create policy drugs_editor_read on catalog.drugs
  for select to authenticated
  using (workflow.caller_is_active_editor());

comment on policy drugs_editor_read on catalog.drugs is
  'Hele virkestoffkatalogen, for en editor. Et evidensfunn må kunne peke på et virkestoff Antidep ennå ikke har publisert noe om.';

create policy clinical_concepts_editor_read on catalog.clinical_concepts
  for select to authenticated
  using (workflow.caller_is_active_editor());

comment on policy clinical_concepts_editor_read on catalog.clinical_concepts is
  'Hele begrepskatalogen, for en editor. Endepunktet et evidensfunn måler er et begrep av typen outcome, og valget forutsetter at begrepene er synlige.';

create policy populations_editor_read on catalog.populations
  for select to authenticated
  using (workflow.caller_is_active_editor());

comment on policy populations_editor_read on catalog.populations is
  'Hele populasjonskatalogen, for en editor. Populasjonen er gyldighetsgrensen et funn indekseres under (DATABASE_ARCHITECTURE.md §22).';

-- ----------------------------------------------------------------------------
-- 3. api.editor_sources — kildene et evidensfunn kan knyttes til
--
-- Volum, hefte og sider er bevisst ikke med. De hører til den bibliografiske
-- posten og ikke til det å kjenne igjen riktig kilde i en liste; tittel,
-- opphav, tidsskrift og år gjør den jobben. Kildestatusen og begrunnelsen for
-- den er derimot med: en editor skal se at en kilde er trukket tilbake *før*
-- hen knytter et funn til den, ikke etterpå (ANTIDEP_CONSTITUTION.md §14).
-- ----------------------------------------------------------------------------
create view api.editor_sources
  with (security_invoker = true) as
select
  s.id                               as source_id,
  s.source_type::text                as source_type,
  s.title                            as title,
  s.authors_or_issuer                as authors_or_issuer,
  s.publisher_or_journal             as publisher_or_journal,
  s.publication_date                 as publication_date,
  s.publication_date_precision::text as publication_date_precision,
  s.source_status::text              as source_status,
  s.status_note                      as status_note
from knowledge.sources s;

comment on view api.editor_sources is
  'Kildene en editor kan knytte et evidensfunn til. Radene filtreres av RLS på knowledge.sources: en editor ser hele registeret, en annen innlogget kaller ser det publiserte utvalget. Viewet er en projeksjon og ikke en rettighet — at en kilde er synlig her, sier ingenting om hva kalleren får skrive.';
comment on column api.editor_sources.source_id is
  'Kildens stabile identitet, og verdien api.create_evidence_item tar imot (DATABASE_ARCHITECTURE.md §8).';
comment on column api.editor_sources.source_type is
  'Hva slags dokument kilden er, som tekst. Egen akse fra studiedesignet et funn har: én artikkel kan rapportere flere design.';
comment on column api.editor_sources.publication_date is
  'Alltid avkortet til presisjonen under. NULL hvis og bare hvis presisjonen er NULL, og betyr at ingen dato er registrert.';
comment on column api.editor_sources.publication_date_precision is
  'Hvor mye av datoen over som faktisk er kjent. Uten den er datoen falsk presisjon (ANTIDEP_CONSTITUTION.md §6).';
comment on column api.editor_sources.source_status is
  'Kildens status, som tekst. En retracted eller withdrawn kilde skal ikke stille passere som en normal kilde i en nedtrekksliste.';
comment on column api.editor_sources.status_note is
  'Begrunnelsen for en avvikende status, eller NULL. NULL betyr «ingen begrunnelse er registrert», ikke «statusen er normal» — det siste leses av source_status.';

grant select on api.editor_sources to authenticated;

-- ----------------------------------------------------------------------------
-- 4. api.editor_source_versions — øyeblikksbildene under hver kilde
--
-- storage_reference er ikke projisert: hvor et lagret øyeblikksbilde ligger er
-- driftsinformasjon (migrasjon 003), ikke noe en editor velger ut fra.
-- ----------------------------------------------------------------------------
create view api.editor_source_versions
  with (security_invoker = true) as
select
  sv.id               as source_version_id,
  sv.source_id        as source_id,
  sv.retrieved_at     as retrieved_at,
  sv.retrieved_from   as retrieved_from,
  sv.external_version as external_version,
  sv.content_hash     as content_hash
from knowledge.source_versions sv;

comment on view api.editor_source_versions is
  'De registrerte øyeblikksbildene av hver kilde, slik at et evidensfunn kan peke på den representasjonen ekstraksjonen faktisk ble lest av (DATABASE_ARCHITECTURE.md §18). Et tomt svar for en kilde betyr at ingen versjon er registrert for den — ikke at kilden er uendret.';
comment on column api.editor_source_versions.retrieved_at is
  'Når representasjonen ble hentet. Et hendelsestidspunkt fra virkeligheten, ikke registreringstidspunktet for raden.';
comment on column api.editor_source_versions.retrieved_from is
  'Den nøyaktige adressen eller representasjonen som ble hentet og hashet, slik at hashen kan reproduseres av andre.';
comment on column api.editor_source_versions.external_version is
  'Versjonsmerket kilden selv oppgir, eller NULL. NULL betyr at kilden ikke eksponerer noe versjonsmerke, ikke at versjonen er ukjent.';
comment on column api.editor_source_versions.content_hash is
  'sha256 av innholdet som ble hentet, med algoritmen som prefiks, eller NULL. NULL betyr at det ikke ble hashet noe øyeblikksbilde.';

grant select on api.editor_source_versions to authenticated;

-- ----------------------------------------------------------------------------
-- 5-7. Katalogoppslagene
--
-- Tre views og ikke ett felles «vokabular»-view: et virkestoff, et klinisk
-- endepunkt og en populasjon er tre forskjellige objekter med hver sin
-- betydning, og en felles (kind, id, etikett)-tabell ville gjort dem
-- utskiftbare i klienten. Statusen er med i alle tre, og radene er ikke
-- filtrert på den: et evidensfunn fra en eldre publikasjon kan gjelde et
-- virkestoff eller et begrep Antidep har faset ut, og å skjule det ville gjort
-- registreringen umulig framfor å gjøre den riktig. Klienten viser statusen.
-- ----------------------------------------------------------------------------
create view api.editor_drugs
  with (security_invoker = true) as
select
  d.id             as drug_id,
  d.canonical_name as canonical_name,
  d.status::text   as status
from catalog.drugs d;

comment on view api.editor_drugs is
  'Virkestoffene et evidensfunn kan peke på, som intervensjon eller som komparator. Radene filtreres av RLS på catalog.drugs. Videre enn api.published_drugs med hensikt: det viewet svarer på hva Antidep har publisert kunnskap om, dette på hva som finnes i katalogen å registrere mot.';
comment on column api.editor_drugs.canonical_name is
  'Kanonisk virkestoffnavn på norsk bokmål. Aliaser og handelsnavn er ikke eksponert her.';
comment on column api.editor_drugs.status is
  'Antideps forvaltningsstatus for virkestoffet, som tekst. Ikke markedsstatus for et produkt.';

grant select on api.editor_drugs to authenticated;

create view api.editor_outcomes
  with (security_invoker = true) as
select
  c.id              as outcome_concept_id,
  c.canonical_label as canonical_label,
  c.status::text    as status
from catalog.clinical_concepts c
where c.concept_type = 'outcome';

comment on view api.editor_outcomes is
  'De kliniske begrepene som er endepunkter, altså nøyaktig de knowledge.evidence_items.outcome_concept_id kan peke på (fremmednøkkelen mot (id, concept_type) krever concept_type = outcome). Begreper av andre typer — diagnoser, tilstander — er ikke endepunkter og står derfor ikke her.';
comment on column api.editor_outcomes.canonical_label is
  'Kanonisk etikett på norsk bokmål. Begrepet alene er grovere enn hva som faktisk ble målt; det presise står i evidensfunnets outcome_detail.';
comment on column api.editor_outcomes.status is
  'Vokabularstatusen for begrepet, som tekst.';

grant select on api.editor_outcomes to authenticated;

create view api.editor_populations
  with (security_invoker = true) as
select
  p.id              as population_id,
  p.canonical_label as canonical_label,
  p.status::text    as status
from catalog.populations p;

comment on view api.editor_populations is
  'Populasjonene et evidensfunn kan indekseres under. Populasjonen er en gyldighetsgrense og ikke en etikett: koblingen kan være videre enn det studerte utvalget, og avviket er indirekthet som vurderes senere (DATABASE_ARCHITECTURE.md §22). Det ordrette utvalget hører til evidensfunnets population_detail.';
comment on column api.editor_populations.canonical_label is
  'Kort lesbart håndtak, for eksempel voksne med depressiv lidelse. De strukturerte gyldighetsgrensene er ikke eksponert her.';
comment on column api.editor_populations.status is
  'Vokabularstatusen for populasjonen, som tekst.';

grant select on api.editor_populations to authenticated;

-- ----------------------------------------------------------------------------
-- 8. api.editor_evidence_items — hva som allerede er registrert på en kilde
--
-- Finnes for at en registrering skal kunne bekreftes med noe annet enn sin egen
-- kvittering: etter et vellykket kall skal editoren kunne se funnet stå under
-- riktig kilde. Den samme listen hindrer dessuten at det samme funnet
-- registreres to ganger uten at noen ser det.
--
-- Bevisst uten estimat, konfidensintervall, utvalgsstørrelse og tidsrom. De
-- fire feltene bærer hver sin `*_availability`, og et tall vist uten sin status
-- er nettopp det ANTIDEP_CONSTITUTION.md §6 forbyr — et manglende estimat er
-- ikke et estimat på null. En liste som skulle vist dem riktig, måtte vist
-- tolv kolonner til; den visningen finnes allerede i evidensdrilldownen
-- (api.published_claim_evidence) og hører hjemme der. Her er formålet
-- gjenkjenning: hvilket endepunkt, hvilket virkestoff, hvilken retning kilden
-- oppgir, og hvor i kilden det står.
-- ----------------------------------------------------------------------------
create view api.editor_evidence_items
  with (security_invoker = true) as
select
  e.id                      as evidence_item_id,
  e.source_id               as source_id,
  s.title                   as source_title,
  e.source_version_id       as source_version_id,
  e.design_code::text       as study_design,
  d.canonical_name          as intervention_drug_name,
  e.comparator_kind::text   as comparator_kind,
  cd.canonical_name         as comparator_drug_name,
  oc.canonical_label        as outcome_label,
  e.outcome_detail          as outcome_detail,
  e.reported_direction::text as reported_direction,
  e.source_locator          as source_locator,
  e.extraction_method::text as extraction_method,
  e.created_at              as created_at
from knowledge.evidence_items e
join knowledge.sources s on s.id = e.source_id
join catalog.drugs d on d.id = e.intervention_drug_id
left join catalog.drugs cd on cd.id = e.comparator_drug_id
join catalog.clinical_concepts oc on oc.id = e.outcome_concept_id;

comment on view api.editor_evidence_items is
  'Evidensfunnene som er registrert, med kilden de hører til. Filtreres på source_id av klienten. Radene filtreres av RLS på knowledge.evidence_items og på tabellene under joinene. Viewet sier hva som er registrert, ikke hva som er kontrollert eller publisert: verifikasjon er en egen arbeidsflytregistrering (DATABASE_ARCHITECTURE.md §29), og publisering en egen operasjon.';
comment on column api.editor_evidence_items.source_title is
  'Tittelen på kilden funnet er hentet fra. Med i radene nettopp for at en bekreftelse skal kunne leses uten å slå opp kilden på nytt.';
comment on column api.editor_evidence_items.source_version_id is
  'Kildeversjonen funnet er lest ut av, eller NULL. NULL betyr at funnet ikke er knyttet til et registrert øyeblikksbilde — ikke at kilden er uendret.';
comment on column api.editor_evidence_items.study_design is
  'Studiedesignet for dette funnet, som tekst. Ligger på funnet og ikke på kilden: én publikasjon kan rapportere flere design.';
comment on column api.editor_evidence_items.comparator_kind is
  'Kontrasten i selve funnet, som tekst. none betyr at funnet er armspesifikt, ikke at komparatoren er ukjent.';
comment on column api.editor_evidence_items.comparator_drug_name is
  'Komparatorvirkestoffet, eller NULL når kontrasten ikke er et virkestoff. NULL sammen med comparator_kind = drug er umulig (evidence_items_comparator_drug_check).';
comment on column api.editor_evidence_items.reported_direction is
  'Retningen kilden selv rapporterer, som tekst. Et annet vokabular enn påstandens retning: det har den fjerde verdien not_stated, og no_clear_difference er et resultat og ikke et fravær av data.';
comment on column api.editor_evidence_items.source_locator is
  'Presis peker til stedet i kilden som underbygger ekstraksjonen (KNOWLEDGE_MODEL.md §11.2).';
comment on column api.editor_evidence_items.extraction_method is
  'Hvordan funnet ble hentet ut, som tekst. Sier hvordan raden ble til, ikke om den er kontrollert.';
comment on column api.editor_evidence_items.created_at is
  'Da raden ble registrert. Ikke tidspunktet kilden ble publisert, og ikke tidspunktet funnet ble kontrollert.';

grant select on api.editor_evidence_items to authenticated;
