-- ============================================================================
-- Migrasjon 007e — den kontrollerte skriveveien for å registrere et EvidenceItem
--
-- Steg 3 av «manuell adminflyt» (MVP_IMPLEMENTATION_PLAN.md §29): «Editor
-- registrerer EvidenceItem» (§15), leddet etter «Editor oppretter Source»
-- (migrasjon 007c). Steg 4 og utover — verifikasjon av ekstraksjonen,
-- ClaimRevision, claim-evidenslenker, review og publisering — hører til senere
-- PR-er, én om gangen (§51). Ingenting her rører dem.
--
-- Utvider api-lesemodellen fra migrasjon 007 (§24) med dens andre skrivbare
-- medlem, slik 007c ga den det første, og følger derfor bokstavkonvensjonen
-- videre: 007 → 007a → 007b → 007c → 007d → 007e. Nummeret 009 er fortsatt
-- reservert for DrugProduct-/importfundamentet (§26).
--
-- Styrende dokumenter:
--   docs/ANTIDEP_CONSTITUTION.md
--     §5  tre kunnskapstyper med ulik epistemisk status
--     §6  usikkerhet skal graderes, aldri erstattes av falsk presisjon
--     §8  evidens og proveniens er førsteklasses data
--     §9  motstridende evidens bevares
--     §10 generering og verifikasjon er separate operasjoner
--     §14 attribusjon
--   docs/DATABASE_ARCHITECTURE.md
--     §19, §19.1  knowledge.evidence_items og null/ukjent-semantikken
--     §20  rå ekstraksjon og kanoniske felt
--     §35-§36  audit.events, og at fysisk sletting krever særskilt audit
--     §38  en kontrollert operasjon er én transaksjon
--     §43  klienten skal ikke skrive direkte til kanoniske tabeller
--     §44  Data API-kontrakten skal være eksplisitt
--     §50  privilegerte databasefunksjoner
--   docs/EVIDENCE_PIPELINE.md
--     §19  ekstraksjonen skal ligge tett på kilden
--     §20  råverdi og normalisert verdi
--     §24  manglende data er et eksplisitt resultat
--   docs/KNOWLEDGE_MODEL.md §11, §11.1, §11.2
--
-- ----------------------------------------------------------------------------
-- Ett inngangspunkt, samme mønster som api.create_source(...)
--
-- api.create_evidence_item(...) er hele skriveveien: klienten kaller den ene
-- funksjonen, den validerer kalleren, setter inn raden, og lar
-- audit.record_evidence_item_event() (avsnitt 3) registrere hendelsen i samme
-- transaksjon som en trigger — ikke fordi funksjonen kunne glemt å skrive
-- auditraden, men fordi plikten skal ligge på INSERT på tabellen, uansett
-- hvilken skrivevei som senere fører dit (§35, §60).
--
-- SECURITY DEFINER, tomt search_path, schemakvalifiserte navn, EXECUTE revokert
-- fra PUBLIC og gitt bare til authenticated. Aktøren utledes av auth.uid() og
-- oppgis ikke som parameter, av nøyaktig samme grunn som i 007c: attribusjonen
-- for et nytt evidensfunn kan aldri være noe annet enn kallerens egen aktør.
--
-- ----------------------------------------------------------------------------
-- Scope: her måtte spørsmålet 007c utsatte, faktisk besvares
--
-- 007c lot en avgrenset editor-tildeling opprette en Source, fordi en kilde
-- ikke selv er avgrenset til noe klinisk begrep — og skrev eksplisitt at «en
-- senere skrivevei som OPPRETTER et avgrenset objekt (EvidenceItem knyttet til
-- et endepunkt …) skal ta stilling til scope på nytt».
--
-- Et evidensfunn *er* avgrenset: outcome_concept_id peker på nøyaktig den
-- typen begrep workflow.user_roles.scope_id avgrenser en tildeling til. Svaret
-- er derfor det samme som for publisering (migrasjon 006): en uavgrenset
-- editor-tildeling gjelder alt, og en avgrenset gjelder sitt eget begrep. En
-- editor avgrenset til «vektendring» kan registrere funn om vektendring, og
-- ikke funn om noe annet.
--
-- Sammenligningen er nøyaktig likhet og ikke et hierarki, som i
-- knowledge.assert_publisher_authorized(uuid, uuid). catalog.clinical_concepts
-- har en parent_concept_id, så en avgrensning *kunne* vært lest som «begrepet
-- og alt under det» — men da ville rekkevidden av en tildeling endret seg hver
-- gang noen la til et underbegrep, uten at noen tildelte noe. Det er en
-- utvidelse som skjer i det stille, og den hører til den PR-en som eventuelt
-- innfører hierarkisk scope for alle rollene samtidig, ikke til denne.
--
-- knowledge.assert_editor_authorized() bygges derfor om til å ta et valgfritt
-- begrep. Uten argument betyr den nøyaktig det den betydde før (enhver gyldig
-- editor-tildeling), så api.create_source(...) er uendret i oppførsel. Med
-- argument kreves i tillegg at en avgrenset tildeling dekker begrepet.
--
-- ----------------------------------------------------------------------------
-- Hvorfor extraction_method ikke er en parameter
--
-- Den er hardkodet til 'manual'. En registrering gjennom denne veien *er* en
-- menneskelig ekstraksjon: en innlogget editor fyller ut skjemaet, og raden
-- attribueres til hens egen aktør. 'ai_assisted' og 'deterministic_import'
-- beskriver skriveveier som ikke finnes ennå — agentekstraksjon og maskinell
-- import — og de skal ha sine egne aktører og sine egne inngangspunkter
-- (ANTIDEP_CONSTITUTION.md §12, MVP_IMPLEMENTATION_PLAN.md §49). Å la klienten
-- oppgi verdien ville gjort det mulig å merke en håndskrevet rad som maskinelt
-- importert, altså å skrive en usann påstand om radens opphav, uten at noe
-- kunne motsi den. Samme resonnement som at source_status ikke er parameter i
-- 007c.
--
-- ----------------------------------------------------------------------------
-- Hvorfor raw_extraction tas imot som ett sitat og ikke som fri jsonb
--
-- §20 krever at kildens egne formuleringer og tall bevares ordrett ved siden av
-- den normaliserte representasjonen, og §25 sin verifikator kontrollerer
-- nettopp det ordrette mot originalen. Kolonnen er jsonb fordi variasjonen
-- mellom kildetyper er reell.
--
-- Denne skriveveien tar likevel imot ett tekstfelt, p_source_quote, og bygger
-- objektet selv. En jsonb-parameter ville latt klienten bestemme formen på et
-- kanonisk felt, og formen ville da vært definert i skjemakoden framfor i
-- databasen. Det ene nøkkelnavnet står her, i migrasjonen, der resten av
-- feltdefinisjonene står. En senere skrivevei med rikere råstruktur (en agent
-- som bevarer tabellrader) definerer sin egen form, i sin egen migrasjon.
--
-- ----------------------------------------------------------------------------
-- Hva funksjonen IKKE validerer
--
-- Ingenting av det knowledge.evidence_items allerede håndhever. Null/ukjent-
-- semantikken (en verdi finnes hvis og bare hvis dens `*_availability` sier
-- det), paringen av tidsrom og konfidensintervall, enheten som følger
-- effektmålet, komparatoren som ikke kan være intervensjonen selv, kravet om at
-- kildeversjonen tilhører samme kilde, og at endepunktet er et begrep av typen
-- outcome — alt dette er deklarative constraints fra migrasjon 003, og de er
-- fasiten (§57). En avvisning derfra propageres til klienten som den er.
--
-- Ett unntak, og det er ikke validering: en dublett fanges av
-- evidence_items_content_hash_key og oversettes til en setning på norsk. Den
-- avvisningen er den eneste her som er en *forventet* utgang av en riktig
-- utfylt form — det samme funnet registrert to ganger — og databasens egen
-- tekst («duplicate key value violates unique constraint …») navngir en
-- mekanisme framfor å si hva som skjedde. Regelen er uendret; bare ordlyden er
-- ny.
--
-- ----------------------------------------------------------------------------
-- Parameterrekkefølgen
--
-- PostgreSQL krever at en parameter uten standardverdi ikke kan stå etter en
-- med. Listen er derfor delt i to blokker — først de fjorten kolonnene
-- knowledge.evidence_items krever, så de seksten valgfrie — framfor å følge
-- tabellens egen rekkefølge. Klienten kaller med navngitte argumenter gjennom
-- PostgREST, så rekkefølgen er ikke en del av kontrakten utad.
--
-- Enum-verdier tas imot som `text` og castes inne i funksjonskroppen, av samme
-- grunn som i 007c: PostgREST caster en parameter til dens deklarerte type i
-- kallerens egen sesjon, og authenticated har ingen usage på knowledge, så en
-- enum-typet parameter ville gjort funksjonen ukjørbar for klientrollen. Det
-- gjelder også `interval`: den typen ligger i pg_catalog og ville teknisk sett
-- gått, men å ha én regel for alle vokabular- og verdiparametre er lettere å
-- lese som sikkerhetskritisk kode enn to.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. audit.events utvides til å kunne peke på knowledge.evidence_items
--
-- Samme ombygging som i 007c, og av samme grunn: PostgreSQL har ingen ALTER
-- COLUMN som endrer uttrykket til en generert kolonne, og en CHECK kan bare
-- endres ved DROP/ADD. Indeksen som bruker begge kolonnene tas ned og opp
-- igjen rundt det. Operasjonen er trygg på levende rader: CASE-uttrykkene
-- dekker hver eksisterende verdi uendret.
-- ----------------------------------------------------------------------------
drop index audit.events_object_occurred_at_idx;

alter table audit.events drop column object_schema;
alter table audit.events drop column object_table;

alter table audit.events add column object_schema text not null generated always as (
  case operation
    when 'claim_published' then 'knowledge'
    when 'claim_publication_replaced' then 'knowledge'
    when 'claim_publication_withdrawn' then 'knowledge'
    when 'claim_publication_rolled_back' then 'knowledge'
    when 'role_granted' then 'workflow'
    when 'role_ended' then 'workflow'
    when 'source_created' then 'knowledge'
    when 'evidence_item_created' then 'knowledge'
  end
) stored;

alter table audit.events add column object_table text not null generated always as (
  case operation
    when 'claim_published' then 'claims'
    when 'claim_publication_replaced' then 'claims'
    when 'claim_publication_withdrawn' then 'claims'
    when 'claim_publication_rolled_back' then 'claims'
    when 'role_granted' then 'user_roles'
    when 'role_ended' then 'user_roles'
    when 'source_created' then 'sources'
    when 'evidence_item_created' then 'evidence_items'
  end
) stored;

comment on column audit.events.object_schema is
  'Schemaet objektet ligger i (DATABASE_ARCHITECTURE.md §35). Avledet av operasjonen, ikke oppgitt ved siden av den, slik at de to ikke kan komme i utakt. NOT NULL på en generert kolonne gjør at en ny enum-verdi uten tilhørende gren feiler ved innsetting framfor å gi en tom kolonne.';
comment on column audit.events.object_table is
  'Tabellen objektet ligger i (DATABASE_ARCHITECTURE.md §35). Avledet av operasjonen, med samme begrunnelse som object_schema.';

create index events_object_occurred_at_idx
  on audit.events (object_schema, object_table, object_id, occurred_at desc);

alter table audit.events drop constraint events_snapshot_shape_check;
alter table audit.events add constraint events_snapshot_shape_check
  check (
    case operation
      when 'claim_published' then
        old_revision_or_snapshot is not null and new_revision_or_snapshot is not null
      when 'claim_publication_replaced' then
        old_revision_or_snapshot is not null and new_revision_or_snapshot is not null
      when 'claim_publication_withdrawn' then
        old_revision_or_snapshot is not null and new_revision_or_snapshot is not null
      when 'claim_publication_rolled_back' then
        old_revision_or_snapshot is not null and new_revision_or_snapshot is not null
      when 'role_granted' then
        old_revision_or_snapshot is null and new_revision_or_snapshot is not null
      when 'role_ended' then
        old_revision_or_snapshot is not null and new_revision_or_snapshot is not null
      when 'source_created' then
        old_revision_or_snapshot is null and new_revision_or_snapshot is not null
      -- En opprettelse, som source_created og role_granted: raden fantes ikke
      -- før, så det er ikke noe old-snapshot å vise. Raden kan heller aldri få
      -- et: knowledge.evidence_items er append-only.
      when 'evidence_item_created' then
        old_revision_or_snapshot is null and new_revision_or_snapshot is not null
      else false
    end
  );

comment on constraint events_snapshot_shape_check on audit.events is
  'Hvilke av de to snapshotene som skal være satt, følger av operasjonen. Uttømmende over audit.event_operation: en ny verdi uten egen gren gir ELSE false, altså en avvist innsetting framfor en stille tom kolonne.';

-- ----------------------------------------------------------------------------
-- 2. knowledge.assert_editor_authorized(uuid) — kontrollen, nå med scope
--
-- Bygges om framfor at en andre kontroll legges ved siden av: to funksjoner
-- med hver sin kopi av de tre kravene ville kunne drive fra hverandre, og et
-- avvik mellom dem ville vært en autorisasjonsforskjell ingen leste som en
-- forskjell. Signaturen endres, så funksjonen må slippes og opprettes på nytt;
-- api.create_source(...) kaller den fortsatt uten argument og får nøyaktig den
-- oppførselen den hadde.
--
-- SECURITY INVOKER (standard), som før: den kalles alltid fra innsiden av en
-- SECURITY DEFINER-funksjon og arver den elevated konteksten derfra. Tomt
-- search_path og schemakvalifiserte navn likevel (§50).
--
-- Ordlyden i den ene meldingen er gjort innholdsnøytral. Den sa «kan ikke
-- opprette kilder», som nå ville vært feil for halvparten av kallstedene.
-- ----------------------------------------------------------------------------
drop function knowledge.assert_editor_authorized();

create function knowledge.assert_editor_authorized(p_scope_concept_id uuid default null)
  returns uuid
  language plpgsql
  set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_retired_at timestamptz;
begin
  select a.id, a.retired_at into v_actor_id, v_retired_at
  from provenance.actors a
  where a.auth_user_id = auth.uid();

  -- KI-aktørene har auth_user_id NULL (actors_auth_user_is_human_check), så et
  -- treff her er alltid et menneske; ingen egen actor_type-kontroll trengs,
  -- samme resonnement som api.my_actor (migrasjon 007b) bygger på.
  if v_actor_id is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Kontoen din er ikke knyttet til en aktør i Antidep.',
      hint = 'Redaksjonelt innhold skal attribueres til en registrert aktør (ANTIDEP_CONSTITUTION.md §14). En kaller uten aktørrad kan ikke opprette noe i sitt eget navn. Ta kontakt med en administrator for å få kontoen din knyttet til en aktør.';
  end if;

  if v_retired_at is not null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Aktøren er trukket tilbake og kan ikke registrere nytt innhold.',
      hint = 'En tilbaketrukket aktør beholder sin historikk, men kan ikke utføre nye handlinger.';
  end if;

  if not exists (
    select 1
    from workflow.user_roles ur
    where ur.user_id = auth.uid()
      and ur.role_code = 'editor'
      and ur.valid_from <= statement_timestamp()
      and (ur.valid_to is null or ur.valid_to > statement_timestamp())
      -- Uten et begrep å kontrollere mot gjelder enhver gyldig tildeling. Med
      -- et begrep gjelder en uavgrenset tildeling fortsatt alt, mens en
      -- avgrenset må dekke nøyaktig det begrepet.
      and (
        p_scope_concept_id is null
        or ur.scope_id is null
        or ur.scope_id = p_scope_concept_id
      )
  ) then
    if p_scope_concept_id is null then
      raise exception using
        errcode = 'insufficient_privilege',
        message = 'Brukeren har ikke gyldig editor-rolle.',
        hint = 'Rollen leses fra workflow.user_roles, ikke fra en JWT-claim (DATABASE_ARCHITECTURE.md §46). En avgrenset editor-tildeling er tilstrekkelig for et objekt som ikke selv er avgrenset til et klinisk begrep.';
    else
      raise exception using
        errcode = 'insufficient_privilege',
        message = 'Brukeren har ikke gyldig editor-rolle for dette innholdsområdet.',
        hint = 'Rollen leses fra workflow.user_roles, ikke fra en JWT-claim (DATABASE_ARCHITECTURE.md §46). En avgrenset editor-tildeling må dekke det kliniske begrepet objektet hører under — for et evidensfunn er det endepunktet funnet måler.';
    end if;
  end if;

  return v_actor_id;
end;
$$;

comment on function knowledge.assert_editor_authorized(uuid) is
  'Kontrollerer at den innloggede brukeren har en registrert, ikke-tilbaketrukket aktør og en gyldig editor-rolle på kallets eget tidspunkt (statement_timestamp(), ikke transaksjonens starttidspunkt, slik at en tilbakekalling virker umiddelbart — MVP_IMPLEMENTATION_PLAN.md §74.6), og returnerer aktørens id. Avviser aldri stille: hvert krav har sin egen feilmelding. Uten argument godtas enhver gyldig editor-tildeling, avgrenset eller ikke — det er riktig for et objekt som ikke selv er avgrenset til et klinisk begrep, slik en Source ikke er. Med et begrep som argument må en avgrenset tildeling dekke nøyaktig det begrepet, som for publisering (knowledge.assert_publisher_authorized(uuid, uuid)); avgrensningen leses ikke hierarkisk, se migrasjonens hodekommentar. Kalles fra innsiden av en SECURITY DEFINER-funksjon og trenger derfor ikke være det selv.';

revoke execute on function knowledge.assert_editor_authorized(uuid) from public;

-- De to kommentarene som navngir kontrollen, følger signaturen. Det er ikke
-- kosmetikk: 280_content_hash_serialization_test.sql slår opp hver funksjon en
-- kommentar i de kanoniske schemaene navngir på kallform, og en referanse til
-- den gamle nullargumentsformen ville pekt på noe som ikke lenger finnes.
comment on function api.create_source(
  text, text, text, text, text, text, text, date, text
) is
  'Den kontrollerte skriveveien for å opprette en Source (DATABASE_ARCHITECTURE.md §43, MVP_IMPLEMENTATION_PLAN.md §15, §29). Kontrollerer at kalleren har en registrert, aktiv aktør og en gyldig editor-rolle (knowledge.assert_editor_authorized(uuid), kalt uten begrep: en Source er ikke selv avgrenset til noe klinisk begrep), setter inn raden attribuert til kallerens egen aktør, og returnerer den nye kildens id. SECURITY DEFINER fordi knowledge.sources, workflow.user_roles og provenance.actors har RLS med default deny for authenticated; funksjonen har tomt search_path og validerer kalleren selv, på sitt eget kall (§50). p_source_type og p_publication_date_precision er text og castes til de kanoniske enum-typene inne i funksjonskroppen, ikke i parameterlisten — se migrasjon 007c sin hodekommentar for hvorfor. source_status, status_note og superseded_by_source_id er ikke parametre: en ny kilde er alltid active, og livssyklusendringer hører til en egen, senere skrivevei.';

comment on function workflow.ensure_editor_role_grant() is
  'Idempotent tildeling av `editor`-rollen til den navngitte kvalifiserte redaktørens brukerkonto, altså retten til å registrere kilder og evidens som forslag (CONTENT_GOVERNANCE.md §8). Åpner de kontrollerte skriveveiene api.create_source(text, text, text, text, text, text, text, date, text) fra migrasjon 007c og api.create_evidence_item(uuid, text, text, text, text, uuid, text, uuid, text, text, text, text, text, text, uuid, uuid, integer, text, uuid, text, text, text, text, numeric, text, numeric, numeric, numeric, text, text) fra migrasjon 007e, som begge krever en gyldig editor-tildeling gjennom knowledge.assert_editor_authorized(uuid). Gir verken faglig godkjenningsrett (reviewer) eller publiseringsrett (publisher): de tre er forskjellige rettigheter med hver sin rad. Forutsetter at aktørraden er knyttet til kontoen av workflow.ensure_named_editor_authorization() (migrasjon 005b) og setter ikke koblingen selv. Returnerer account_missing (ingen rad i auth.users), authorized (tildelingen ble skrevet), already_authorized (en tildeling er gyldig nå), role_not_yet_valid (en tildeling begynner å gjelde senere) eller role_ended (en tildeling er avsluttet). Bare authorized skriver noe. Gyldighet måles med statement_timestamp() fordi predikatet avgjør noe (MVP_IMPLEMENTATION_PLAN.md §74.6). En avsluttet tildeling gjeninnføres aldri: en tilbakekalling som en migrasjonskjøring omgjør, er ingen tilbakekalling (DATABASE_ARCHITECTURE.md §46). Konto og aktørnøkkel er konstanter i kroppen, og rollen er det også: funksjonen kan bare gjøre denne ene tildelingen, aldri en vilkårlig.';

-- ----------------------------------------------------------------------------
-- 3. audit.record_evidence_item_event() — produsenten for INSERT på
--    knowledge.evidence_items
--
-- Samme mønster som audit.record_source_event() (migrasjon 007c) og
-- audit.record_user_role_event() (migrasjon 008): ikke SECURITY DEFINER, slik
-- at auditskriveren aldri er mer privilegert enn operasjonen den registrerer
-- (§35, §60). Hele raden er snapshotet: knowledge.evidence_items er
-- append-only og har ingen egen hendelsestabell under seg, så snapshotet er
-- det eneste som bevarer hva som ble registrert.
-- ----------------------------------------------------------------------------
create function audit.record_evidence_item_event()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  insert into audit.events (
    operation, object_id, actor_id,
    old_revision_or_snapshot, new_revision_or_snapshot,
    occurred_at
  )
  values (
    'evidence_item_created'::audit.event_operation,
    new.id,
    new.created_by_actor_id,
    null,
    to_jsonb(new),
    now()
  );

  return null;
end;
$$;

comment on function audit.record_evidence_item_event() is
  'Auditskriver for evidenslaget: registrerer at et evidensfunn ble registrert, med hele raden som snapshot. Kjører med kallerens rettigheter, ikke som SECURITY DEFINER, slik at en auditrad aldri kan skrives av noen som ikke kunne utført operasjonen selv (samme begrunnelse som audit.record_source_event() og audit.record_user_role_event()).';

revoke execute on function audit.record_evidence_item_event() from public;

create trigger evidence_items_record_creation_audit_event
  after insert on knowledge.evidence_items
  for each row execute function audit.record_evidence_item_event();

-- ----------------------------------------------------------------------------
-- 4. api.create_evidence_item(...) — den eneste skriveveien
--
-- Parametrene speiler de skrivbare feltene på knowledge.evidence_items ved
-- registrering. Fire kolonner er bevisst ikke parametre:
--
--   created_by_actor_id  utledes av auth.uid(); se hodekommentaren
--   content_hash         eies av databasen (knowledge.evidence_item_content_hash),
--                        og en hash kalleren kunne oppgi ville sett ut som en
--                        garanti uten å være det
--   extraction_method    hardkodet til 'manual'; se hodekommentaren
--   raw_extraction       bygges av p_source_quote; se hodekommentaren
-- ----------------------------------------------------------------------------
create function api.create_evidence_item(
  -- Påkrevd: nøyaktig de kolonnene knowledge.evidence_items krever.
  p_source_id uuid,
  p_design_code text,
  p_population_availability text,
  p_population_detail text,
  p_sample_size_availability text,
  p_intervention_drug_id uuid,
  p_comparator_kind text,
  p_outcome_concept_id uuid,
  p_outcome_detail text,
  p_timepoint_availability text,
  p_reported_direction text,
  p_estimate_availability text,
  p_confidence_interval_availability text,
  p_source_locator text,
  -- Valgfritt. Utelatt betyr NULL, og NULL betyr det den ledsagende
  -- `*_availability`-kolonnen sier at det betyr — aldri null og aldri
  -- «ingen effekt» (ANTIDEP_CONSTITUTION.md §6, DATABASE_ARCHITECTURE.md §19.1).
  p_source_version_id uuid default null,
  p_population_id uuid default null,
  p_sample_size integer default null,
  p_intervention_detail text default null,
  p_comparator_drug_id uuid default null,
  p_comparator_detail text default null,
  p_timepoint_min text default null,
  p_timepoint_max text default null,
  p_effect_measure text default null,
  p_estimate numeric default null,
  p_estimate_unit text default null,
  p_ci_lower numeric default null,
  p_ci_upper numeric default null,
  p_ci_level_percent numeric default null,
  p_limitations_text text default null,
  p_source_quote text default null
)
  returns uuid
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_evidence_item_id uuid;
begin
  -- Endepunktet er innholdsområdet et evidensfunn hører under, og det er derfor
  -- det en avgrenset editor-tildeling kontrolleres mot.
  v_actor_id := knowledge.assert_editor_authorized(p_outcome_concept_id);

  insert into knowledge.evidence_items (
    source_id, source_version_id, design_code,
    population_id, population_availability, population_detail,
    sample_size, sample_size_availability,
    intervention_drug_id, intervention_detail,
    comparator_kind, comparator_drug_id, comparator_detail,
    outcome_concept_id, outcome_detail,
    timepoint_min, timepoint_max, timepoint_availability,
    reported_direction, effect_measure, estimate, estimate_unit, estimate_availability,
    ci_lower, ci_upper, ci_level_percent, confidence_interval_availability,
    limitations_text, source_locator, extraction_method, raw_extraction,
    created_by_actor_id
  )
  values (
    p_source_id,
    p_source_version_id,
    p_design_code::knowledge.study_design,
    p_population_id,
    p_population_availability::knowledge.value_availability,
    p_population_detail,
    p_sample_size,
    p_sample_size_availability::knowledge.value_availability,
    p_intervention_drug_id,
    p_intervention_detail,
    p_comparator_kind::knowledge.comparator_kind,
    p_comparator_drug_id,
    p_comparator_detail,
    p_outcome_concept_id,
    p_outcome_detail,
    p_timepoint_min::interval,
    p_timepoint_max::interval,
    p_timepoint_availability::knowledge.value_availability,
    p_reported_direction::knowledge.effect_direction,
    p_effect_measure::knowledge.effect_measure,
    p_estimate,
    p_estimate_unit::knowledge.estimate_unit,
    p_estimate_availability::knowledge.value_availability,
    p_ci_lower,
    p_ci_upper,
    p_ci_level_percent,
    p_confidence_interval_availability::knowledge.value_availability,
    p_limitations_text,
    p_source_locator,
    'manual'::knowledge.extraction_method,
    -- Et tomt sitatfelt er et fravær, ikke et tomt sitat. Ingen validering av
    -- innholdet: et sitat er ordrett tekst fra kilden, og det er ikke noe her
    -- som kan avgjøre om det er riktig gjengitt — det er verifikatorens
    -- oppgave (ANTIDEP_CONSTITUTION.md §11).
    case
      when nullif(btrim(coalesce(p_source_quote, '')), '') is null then null
      else jsonb_build_object('sitat', btrim(p_source_quote))
    end,
    v_actor_id
  )
  returning id into v_evidence_item_id;

  return v_evidence_item_id;
exception
  -- Den eneste oversatte avvisningen. content_hash dekker hele radens faglige
  -- innhold, så en dublett er nøyaktig samme registrering en gang til — og en
  -- korreksjon av et hvilket som helst felt gir en ny hash og slipper inn ved
  -- siden av den gamle (migrasjon 003, 006a).
  when unique_violation then
    raise exception using
      errcode = 'unique_violation',
      message = 'Nøyaktig det samme evidensfunnet er allerede registrert.',
      hint = 'Et evidensfunn identifiseres av hele sitt faglige innhold. Er dette en korreksjon, skal minst ett felt være endret — da registreres den som et nytt funn ved siden av det gamle, og det gamle består (knowledge.evidence_items er append-only).';
end;
$$;

comment on function api.create_evidence_item(
  uuid, text, text, text, text, uuid, text, uuid, text, text, text, text, text, text,
  uuid, uuid, integer, text, uuid, text, text, text, text, numeric, text, numeric,
  numeric, numeric, text, text
) is
  'Den kontrollerte skriveveien for å registrere et EvidenceItem (DATABASE_ARCHITECTURE.md §43, MVP_IMPLEMENTATION_PLAN.md §15, §29). Kontrollerer at kalleren har en registrert, aktiv aktør og en gyldig editor-rolle for endepunktet funnet gjelder (knowledge.assert_editor_authorized(uuid)), setter inn raden attribuert til kallerens egen aktør, og returnerer funnets id. Auditraden skrives av triggeren på tabellen, i samme transaksjon. SECURITY DEFINER fordi knowledge.evidence_items, workflow.user_roles og provenance.actors har RLS med default deny for authenticated; tomt search_path, og kalleren valideres på funksjonens eget kall (§50). extraction_method er ikke parameter og er alltid manual, content_hash eies av databasen, og raw_extraction bygges av p_source_quote — se migrasjonens hodekommentar for hver av dem. Ingen feltvalidering er duplisert her: constraintene på knowledge.evidence_items er fasiten, og deres avvisninger propageres uendret. Unntaket er dubletten, som oversettes til en setning på norsk uten at regelen endres.';

revoke execute on function api.create_evidence_item(
  uuid, text, text, text, text, uuid, text, uuid, text, text, text, text, text, text,
  uuid, uuid, integer, text, uuid, text, text, text, text, numeric, text, numeric,
  numeric, numeric, text, text
) from public;
grant execute on function api.create_evidence_item(
  uuid, text, text, text, text, uuid, text, uuid, text, text, text, text, text, text,
  uuid, uuid, integer, text, uuid, text, text, text, text, numeric, text, numeric,
  numeric, numeric, text, text
) to authenticated;
