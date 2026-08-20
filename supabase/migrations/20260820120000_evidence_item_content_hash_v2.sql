-- ============================================================================
-- Antidep korreksjonsmigrasjon 006a — entydig serialisering av content_hash på
-- evidensfunn
--
-- Formål: rette en registrert arkitekturgjeld fra migrasjon 003
-- (MVP_IMPLEMENTATION_PLAN.md §74.7). Migrasjonen innfører ingen nye objekter i
-- kunnskapsmodellen og flytter ingen grense; den bytter ut definisjonen av ett
-- teknisk felt og retter én uriktig kolonnekommentar fra migrasjon 002.
--
-- Nummerering: migrasjonsnumrene i MVP_IMPLEMENTATION_PLAN.md §18-§27 navngir
-- planlagt innhold, ikke filrekkefølge. Denne migrasjonen står ikke i den
-- rekken. Den kalles derfor 006a og tar ikke nummeret 007, slik at «migrasjon
-- 007 — API-lesemodell» (§24) fortsatt betyr det samme i plan, migrasjoner og
-- tester.
--
-- Styrende dokumenter:
--   docs/ANTIDEP_CONSTITUTION.md
--     §4 enhver klinisk relevant påstand skal være etterprøvbar
--     §9 motstridende evidens bevares
--   docs/MVP_IMPLEMENTATION_PLAN.md
--     §20 EvidenceItem og immutabilitetsstrategien
--     §41-§42 testpyramide og kritiske negative tester
--     §72 arkitekturgjeld skal være eksplisitt, §74.7 den registrerte gjelden
--   docs/DATABASE_ARCHITECTURE.md
--     §20 kanoniske felter skal ikke bare finnes i raw_extraction
--     §36 ingen normal DELETE på kanonisk kunnskap
--     §57 integritet håndheves deklarativt, §60 triggere skal være snevre
--     §67 databasetesting er en del av funksjonen
--
-- ----------------------------------------------------------------------------
-- Hva som var galt
--
-- knowledge.set_evidence_item_content_hash() fra migrasjon 003 bygde den
-- kanoniske strengen med concat_ws('|', …). Skilletegnet er ikke reservert:
-- limitations_text og source_locator er nabofelter, og begge er fritekst som
-- lovlig kan inneholde «|». To *forskjellige* evidensfunn kunne derfor gi
-- nøyaktig samme kanoniske streng — for eksempel
--
--     limitations_text = 'X|Y',  source_locator = 'Z'
--     limitations_text = 'X',    source_locator = 'Y|Z'
--
-- som begge serialiseres til «…|X|Y|Z|…».
--
-- Fordi content_hash er UNIQUE på knowledge.evidence_items, var konsekvensen
-- ikke en stille sammenblanding, men en avvisning: det andre, legitimt
-- distinkte funnet ville blitt nektet innsatt som dublett (23505). Feilen
-- rammer altså tilgjengeligheten av evidens, ikke integriteten til det som
-- allerede er registrert — men den rammer den i den retningen som betyr mest,
-- fordi et evidensfunn som ikke slipper inn, heller ikke kan motsi et annet
-- (ANTIDEP_CONSTITUTION.md §9).
--
-- Samme skjøt gjorde dessuten NULL og tom streng likeverdige, siden nullbare
-- felter ble coalesce-et til ''. Den delen er i dag ikke nåbar — hvert nullbart
-- fritekstfelt har en CHECK som krever minst ett tegn — men den skal ikke
-- overleve som en felle for neste kolonne som legges til.
--
-- ----------------------------------------------------------------------------
-- Rettingen
--
-- Kanoniseringen byttes til det lengdeprefiksede formatet «lengde:verdi», som
-- allerede er husstandard to andre steder: knowledge.set_claim_revision_content_hash()
-- (migrasjon 004) og knowledge.claim_evidence_set_digest() (migrasjon 006).
-- Skjøten blir entydig fordi hvert felt oppgir sin egen lengde før innholdet,
-- og «~» som lengdemarkør skiller NULL fra tom streng.
--
-- Definisjonen versjoneres til sha256-v2, slik migrasjon 003 selv forutsatte at
-- en endring skulle gjøres: prefikset finnes nettopp for at gamle verdier ikke
-- skal bli stille uforenlige med nye. CHECK-en på formatet
-- (^sha256-v[0-9]+:[0-9a-f]{64}$) er allerede skrevet for dette og trenger
-- ingen endring.
--
-- Feltlisten, feltrekkefølgen og normaliseringen av tall og tidsrom er uendret.
-- Bare skjøten mellom feltene er ny. En rad får dermed en annen hashverdi enn
-- før, men fingeravtrykket dekker nøyaktig det samme innholdet.
--
-- Selve kanoniseringen legges i en egen funksjon i stedet for å stå inne i
-- triggerfunksjonen. Grunnen er konkret og ikke abstraksjon for sin egen skyld:
-- backfillen under må hashe eksisterende rader på nytt, og en andre kopi av 31
-- feltuttrykk som kunne komme fra hverandre er nøyaktig den klassen feil denne
-- migrasjonen retter.
-- ----------------------------------------------------------------------------

-- 1. Kanoniseringen som verdi-funksjon.
--
-- Tar hele raden, slik at kallstedet ikke kan utelate et felt. IMMUTABLE: den
-- leser ingenting utenfor argumentet og har ingen sideeffekter.
create function knowledge.evidence_item_content_hash(item knowledge.evidence_items)
  returns text
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  fields text[];
  field text;
  canonical text := 'sha256-v2';
begin
  -- Samme felter, samme rekkefølge og samme normalisering som i migrasjon 003:
  -- numeriske verdier gjennom trim_scale, slik at 0.80 og 0.8 er samme verdi,
  -- og tidsrom som sekunder, slik at «8 uker» skrevet på to måter er det.
  fields := array[
    item.source_id::text,
    item.source_version_id::text,
    item.design_code::text,
    item.population_id::text,
    item.population_availability::text,
    item.population_detail,
    item.sample_size::text,
    item.sample_size_availability::text,
    item.intervention_drug_id::text,
    item.intervention_detail,
    item.comparator_kind::text,
    item.comparator_drug_id::text,
    item.comparator_detail,
    item.outcome_concept_id::text,
    item.outcome_detail,
    extract(epoch from item.timepoint_min)::text,
    extract(epoch from item.timepoint_max)::text,
    item.timepoint_availability::text,
    item.reported_direction::text,
    item.effect_measure::text,
    trim_scale(item.estimate)::text,
    item.estimate_unit::text,
    item.estimate_availability::text,
    trim_scale(item.ci_lower)::text,
    trim_scale(item.ci_upper)::text,
    trim_scale(item.ci_level_percent)::text,
    item.confidence_interval_availability::text,
    item.limitations_text,
    item.source_locator,
    item.extraction_method::text,
    item.raw_extraction::text
  ];

  foreach field in array fields loop
    -- Lengdeprefiks gjør skjøten entydig; «~» skiller NULL fra tom streng.
    canonical := canonical || '|' || coalesce(length(field)::text, '~') || ':'
                 || coalesce(field, '');
  end loop;

  return 'sha256-v2:' || encode(sha256(convert_to(canonical, 'UTF8')), 'hex');
end;
$$;

comment on function knowledge.evidence_item_content_hash(knowledge.evidence_items) is
  'Beregner fingeravtrykket av et evidensfunn fra radens egne kanoniske felter. Feltene kanoniseres lengdeprefikset, slik at to ulike funn ikke kan gi samme kanoniske streng selv om fritekstfeltene inneholder skilletegnet, og «~» skiller NULL fra tom streng. Felles definisjon for innsettingstriggeren og for rehashing i vedlikeholdsmigrasjoner, slik at det bare finnes ett sted å endre.';

revoke execute on function knowledge.evidence_item_content_hash(knowledge.evidence_items) from public;

-- 2. Triggerfunksjonen delegerer nå, og gjør ellers det den gjorde.
--
-- Fortsatt en bevisst og snever trigger (DATABASE_ARCHITECTURE.md §60): den
-- utleder ett teknisk felt fra radens egne kolonner og inneholder ingen klinisk
-- logikk og ingen arbeidsflyt. Databasen eier fortsatt verdien; en hash oppgitt
-- av kalleren blir overskrevet.
create or replace function knowledge.set_evidence_item_content_hash()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  new.content_hash := knowledge.evidence_item_content_hash(new);
  return new;
end;
$$;

comment on function knowledge.set_evidence_item_content_hash() is
  'Trigger-funksjon som utleder content_hash fra de kanoniske feltene på et evidensfunn ved innsetting, gjennom knowledge.evidence_item_content_hash(knowledge.evidence_items). Gir databasen eierskap til fingeravtrykket, slik at det ikke kan oppgis av kalleren. Teknisk metadata; endrer ingen klinisk verdi.';

-- 3. Rehashing av eksisterende rader.
--
-- knowledge.evidence_items er append-only og avviser UPDATE også for
-- tabelleieren. Triggeren slås derfor av eksplisitt rundt backfillen, som en
-- synlig og reviewbar handling — samme mønster som migrasjon 005, og slik
-- kommentaren i migrasjon 003 forutsetter at en reell vedlikeholdsoperasjon
-- skal gjøres. Vinduet er så smalt som mulig: én UPDATE, ingen annen setning
-- mellom disable og enable.
--
-- Dette er ikke en redigering av klinisk innhold. Ingen kanonisk kolonne røres;
-- content_hash er teknisk metadata som databasen selv eier, og fingeravtrykket
-- dekker etterpå nøyaktig det samme innholdet som før. Radene forblir de samme
-- registreringene av hva kildene rapporterte.
--
-- UNIQUE-en kan ikke slå til underveis: eksisterende rader har distinkte
-- v1-hasher, altså distinkte feltverdier, og den lengdeprefiksede
-- kanoniseringen er injektiv på feltverdiene. Distinkte feltverdier gir dermed
-- distinkte v2-hasher.
alter table knowledge.evidence_items disable trigger evidence_items_reject_mutation;
update knowledge.evidence_items e
set content_hash = knowledge.evidence_item_content_hash(e.*);
alter table knowledge.evidence_items enable trigger evidence_items_reject_mutation;

-- Etter backfillen skal ingen rad ligge igjen på den gamle definisjonen.
-- Kontrollen står her, ikke bare i testpakken, fordi en delvis migrert tabell
-- ikke skal kunne commite.
do $$
begin
  if exists (
    select 1 from knowledge.evidence_items
    where content_hash !~ '^sha256-v2:[0-9a-f]{64}$'
  ) then
    raise exception
      'Rehashing av knowledge.evidence_items er ufullstendig; rader står igjen med en eldre hashdefinisjon.';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. Rettelse av kolonnekommentar fra migrasjon 002
--
-- Kommentaren viste til catalog.set_updated_at(), som aldri har eksistert.
-- Funksjonen heter catalog.set_row_timestamps() og setter begge tidsstemplene
-- ved både INSERT og UPDATE (DATABASE_ARCHITECTURE.md §7.3). En kommentar som
-- navngir feil funksjon er en feilaktig opplysning databasen gir om seg selv,
-- og den rettes derfor der den står.
-- ----------------------------------------------------------------------------
comment on column catalog.drugs.updated_at is
  'Tidspunkt for siste metadataendring på identitetsraden. Settes av catalog.set_row_timestamps().';
