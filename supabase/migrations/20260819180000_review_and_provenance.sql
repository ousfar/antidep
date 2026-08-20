-- ============================================================================
-- Antidep migrasjon 005 — review og proveniens
--
-- Formål: gjøre det etterprøvbart hvem eller hva som produserte et
-- kunnskapsobjekt, og skille generering fra kontroll. Migrasjonen oppretter
-- aktørregisteret, medlemskapsmodellen for roller, de to verifikasjonslagene og
-- reviewbeslutningen — og knytter de eksisterende kunnskapsradene til aktørene
-- som faktisk laget dem.
--
-- Styrende dokumenter:
--   docs/ANTIDEP_CONSTITUTION.md
--     §10 KI-arbeidet skal deles i eksplisitte roller
--     §11 verifikasjon skal forsøke å falsifisere, med tilgang til kildematerialet
--     §12 KI kan foreslå; mennesker har det faglige ansvaret
--     §13 alt publisert innhold har en eksplisitt livssyklus
--     §14 endringer skal være reversible, attribuerte og rapporterbare
--     §15 admin-UX er et kjerneprodukt
--     §20 kunnskapsmodellen skal være leverandøruavhengig
--   docs/MVP_IMPLEMENTATION_PLAN.md
--     §14-§16 admin-MVP, første admin-workflow og roller
--     §22 innholdet i denne migrasjonen
--     §29 Slice 1
--     §41-§42 teststrategi og kritiske negative tester
--     §47-§50 sikkerhet, tilgang og least privilege
--   docs/DATABASE_ARCHITECTURE.md
--     §26 workflow.evidence_work_units, §29 ekstraksjonsverifikasjon,
--     §30 claim-verifikasjon, §31 human review
--     §32 provenance.actors, §33 provenance.agent_runs, §34 proveniens er en graf
--     §36 ingen normal DELETE, §37 RESTRICT på fremmednøkler
--     §45-§50 roller, medlemskap, RLS default deny, least privilege
--     §57-§61 deklarative constraints, tverradsregler, snevre triggere, atomisitet
--     §67 databasetesting er en del av funksjonen
--   docs/KNOWLEDGE_MODEL.md
--     §17 Actor, §18 ProvenanceEvent, §20 standard livssyklus,
--     §21 godkjenningsmatrise
--
-- Avgrensning (MVP_IMPLEMENTATION_PLAN.md §23-§26):
--   Ingen publisering og ingen knowledge.publication_events (006), ingen
--   api-views (007), ingen audit.events (008) og ingen ingest (009).
--   Publiseringsgaten hører til 006; denne migrasjonen etablerer beslutningene
--   gaten skal lese.
--
--   provenance.agent_runs (§33) opprettes ikke. Tabellen skal registrere
--   leverandør, modell, modellversjon, promptversjon, pipelineversjon og
--   inn-/utdatamanifest for én KI-kjøring. Første evidenspipeline finnes ikke i
--   denne slicen: radene i migrasjon 003 og 004 ble skrevet som del av
--   migrasjonsarbeidet under menneskelig instruksjon, ikke av en automatisk
--   kjøring med start- og sluttidspunkt og manifester. Å opprette tabellen nå
--   ville enten gitt et tomt skall uten skrivevei, eller fristet til å seede
--   kjøringer som ikke har funnet sted. Aktøren — hvilken rolle prosessen
--   handlet i — er derimot etterprøvbar og registreres her.
--   provenance.agent_runs hører derfor til migrasjonen som innfører den første
--   automatiske skriveveien, og aktørene under har allerede den
--   fremmednøkkelpekeren kjøringene skal henge på.
--
--   workflow.evidence_work_units (§26), workflow.search_runs (§27) og
--   workflow.source_screening_decisions (§28) opprettes ikke, av samme grunn:
--   de beskriver et søke- og utvelgelsesarbeid som ikke er kjørt som pipeline i
--   denne slicen. Verifikasjonsradene har derfor ingen work_unit_id ennå;
--   kolonnen legges til sammen med tabellen den skal peke på.
--
--   Ingen RLS-policies. Se avsnitt 10 for begrunnelsen.
--
-- Kjent arkitekturgjeld som ikke rettes her (dokumentert framfor å utvide
-- scopet, jf. MVP_IMPLEMENTATION_PLAN.md §72):
--   * knowledge.set_evidence_item_content_hash() fra migrasjon 003 skjøter
--     feltene med concat_ws('|', ...) mens fritekstfeltene selv kan inneholde
--     «|». Hashen er UNIQUE, så en serialiseringskollisjon ville avvist et
--     legitimt distinkt evidensfunn som dublett. Migrasjon 004 rettet samme feil
--     i sitt eget lag med lengdeprefikset kanonisering. Rettelsen krever at
--     funksjonen byttes og at eksisterende rader rehashes under nytt prefiks,
--     og hører til en egen liten migrasjon framfor å bli blandet inn i review og
--     proveniens.
--   * De append-only tabellene i knowledge (evidence_items, claim_revisions,
--     claim_evidence_links, evidence_assessments) har fortsatt created_at med
--     bare en default, ikke databaseeid registreringstid, og
--     evidence_assessments.assessed_at er ikke bundet mot created_at slik
--     verified_at og decided_at er her. Ingen gate leser de tidspunktene ennå,
--     så det er ikke sikkerhetskritisk i dag, men samme invariant hører hjemme
--     der og bør komme i migrasjonen som rører de tabellene neste gang.
--   * catalog.set_row_timestamps() og knowledge.reject_append_only_mutation()
--     brukes fra og med denne migrasjonen fra tre schemaer hver. Et felles
--     hjelpeschema ville vært den ryddige plasseringen, men et sjuende schema
--     endrer DATABASE_ARCHITECTURE.md §6 og hver eneste schemauttømmende
--     vaktpost i testpakken. Det er en egen beslutning, ikke en bivirkning av
--     denne migrasjonen. Funksjonene gjenbrukes derfor der de ligger.
--
-- Konvensjonene fra migrasjon 001 gjelder og håndheves av
-- supabase/tests/030_conventions_test.sql: én databasegenerert uuid som
-- primærnøkkel, timestamptz overalt, created_at med default now(), RLS aktivert
-- og ingen grants til anon/authenticated/service_role/PUBLIC.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Extensions
--
-- btree_gist gir GiST-operatorklasser for uuid og enum, slik at
-- workflow.user_roles kan bruke en exclusion constraint til å hindre
-- overlappende rolletildelinger (avsnitt 6). Uten den finnes ingen deklarativ
-- måte å uttrykke regelen på, og alternativet ville vært en trigger for noe
-- PostgreSQL kan håndheve selv (DATABASE_ARCHITECTURE.md §57).
--
-- Extensionen legges i extensions-schemaet, som i denne plattformen er stedet
-- for extensions, og ikke i public. if not exists er med fordi et hostet
-- prosjekt kan ha den installert fra før; operatorklassene slås opp per datatype
-- og ikke via search_path, så migrasjonen virker uansett hvilket schema den
-- eksisterende installasjonen ligger i.
-- ----------------------------------------------------------------------------
create extension if not exists btree_gist with schema extensions;

-- ----------------------------------------------------------------------------
-- 2. Kontrollerte vokabularer
--
-- Som i migrasjon 002, 003 og 004 håndheves vokabularene som enum, altså på
-- datatypenivå (DATABASE_ARCHITECTURE.md §57). Det åpne spørsmålet om enum
-- kontra oppslagstabell (§72) vokser med ti typer her, til 35 etter denne
-- migrasjonen, og bør avgjøres før api-projeksjonene i migrasjon 007 begynner å
-- eksponere verdiene.
--
-- Null/ukjent-semantikk: ingen av typene under bruker
-- knowledge.value_availability. Den forklarer hvorfor en verdi Antidep forsøkte
-- å hente ut av en kilde mangler. Verdiene her er derimot resultater av
-- vurderinger Antidep selv har gjort — «kunne ikke bedømmes» er et funn, ikke en
-- manglende uthenting — og hører derfor til egne vokabularer, på samme måte som
-- knowledge.certainty_level har no_assessable_evidence framfor en
-- availability-status (ANTIDEP_CONSTITUTION.md §6).
-- ----------------------------------------------------------------------------

create type provenance.actor_type as enum (
  'human',
  'agent',
  'deterministic_process',
  'external_import',
  'system'
);

comment on type provenance.actor_type is
  'Hva slags aktør som utførte en kunnskapsoperasjon (DATABASE_ARCHITECTURE.md §32, KNOWLEDGE_MODEL.md §17): human (en navngitt person), agent (en KI-prosess i en definert rolle), deterministic_process (en regelstyrt jobb uten språkmodell), external_import (en import fra et eksternt system) og system (en teknisk plattformoperasjon). Typen er avgjørende og ikke kosmetisk: bare en human kan registrere en reviewbeslutning (ANTIDEP_CONSTITUTION.md §12), og skillet håndheves deklarativt av workflow.review_decisions.';

create type provenance.agent_role as enum (
  'source_discovery',
  'source_quality_assessment',
  'evidence_extraction',
  'claim_synthesis',
  'adversarial_review',
  'citation_support_verification',
  'editorial_compression'
);

comment on type provenance.agent_role is
  'De eksplisitte agentrollene ANTIDEP_CONSTITUTION.md §10 krever at KI-arbeidet deles i: kildesøk, kildekvalitetsvurdering, data- og evidensekstraksjon, påstandsformulering og syntese, motargumenterende kontroll, sitat- og kildestøtteverifikasjon og redaksjonell komprimering. Rollen ligger på aktøren fordi den er stabil på tvers av modellversjoner; leverandør, modell og promptversjon hører til den enkelte kjøringen (provenance.agent_runs, utsatt) og skal aldri bli en egenskap ved kunnskapsobjektet (ANTIDEP_CONSTITUTION.md §20).';

create type workflow.role_scope_type as enum ('clinical_concept');

comment on type workflow.role_scope_type is
  'Hva en rolletildeling eventuelt er avgrenset til (DATABASE_ARCHITECTURE.md §47). Foreløpig bare clinical_concept, som er akkurat det §47 bruker som eksempel: en reviewer godkjent for et bestemt innholdsområde. Andre scopetyper legges til av migrasjonen som trenger dem, og den migrasjonen må samtidig erstatte den enkle fremmednøkkelen på scope_id, som i dag kan peke direkte på catalog.clinical_concepts nettopp fordi det bare finnes én scopetype.';

create type workflow.verification_outcome as enum (
  'verified',
  'needs_correction',
  'rejected',
  'uncertain'
);

comment on type workflow.verification_outcome is
  'Resultatet av en kontroll (DATABASE_ARCHITECTURE.md §29): verified (kontrollen fant ingen avvik), needs_correction (objektet er i hovedsak riktig, men noe må rettes), rejected (objektet holder ikke) og uncertain (kontrollen kunne ikke konkludere). uncertain er en egen tilstand og skal aldri leses som verified: at en kontroll ikke klarte å avkrefte noe er ikke det samme som at den bekreftet det (ANTIDEP_CONSTITUTION.md §6, §11).';

create type workflow.verification_source_access as enum (
  'original_source',
  'verifiable_representation',
  'derived_summary'
);

comment on type workflow.verification_source_access is
  'Hva verifikatoren faktisk hadde tilgang til (ANTIDEP_CONSTITUTION.md §11): original_source (originalkilden selv), verifiable_representation (et lagret og etterprøvbart øyeblikksbilde av kildeversjonen) eller derived_summary (bare et sammendrag laget av et annet ledd). §11 forbyr å godkjenne på grunnlag av andre agenters sammendrag alene, og kombinasjonen verified + derived_summary er derfor avvist av en CHECK i begge verifikasjonstabellene.';

create type workflow.verification_check_result as enum (
  'ok',
  'deviation',
  'not_assessable'
);

comment on type workflow.verification_check_result is
  'Utfallet av ett enkelt kontrollpunkt i en claim-verifikasjon: ok (kontrollpunktet holder), deviation (verifikatoren fant et avvik) eller not_assessable (kontrollpunktet lot seg ikke bedømme på det tilgjengelige grunnlaget). not_assessable er bevisst ikke det samme som ok — et ubedømt punkt er ikke et bestått punkt — og en verifikasjon kan derfor ikke konkluderes som verified med et eneste punkt som ikke er ok (ANTIDEP_CONSTITUTION.md §6, §11).';

create type workflow.evidence_check_field as enum (
  'population',
  'sample_size',
  'intervention_arm',
  'comparator_arm',
  'outcome',
  'timepoint',
  'reported_direction',
  'effect_measure',
  'estimate',
  'confidence_interval',
  'availability_semantics',
  'limitations',
  'source_locator',
  'raw_extraction'
);

comment on type workflow.evidence_check_field is
  'Kontrollerbare felter på et evidensfunn, brukt til å registrere hvilke felter en ekstraksjonsverifikasjon faktisk gikk gjennom (DATABASE_ARCHITECTURE.md §29). Vokabularet følger kolonnene i knowledge.evidence_items. availability_semantics dekker kontrollen av at not_measured, not_reported, not_extractable og uncertain_extraction er brukt riktig, som er en av de enkleste måtene en ekstraksjon kan være feil på uten at noe tall ser galt ut.';

create type workflow.review_object_type as enum ('claim_revision', 'evidence_item');

comment on type workflow.review_object_type is
  'Hvilken type kunnskapsobjekt en reviewbeslutning gjelder (DATABASE_ARCHITECTURE.md §31). Kolonnen som bruker typen er avledet av hvilken fremmednøkkel som er satt, slik at objekttypen aldri kan si noe annet enn objektpekeren.';

create type workflow.review_type as enum (
  'publication_approval',
  'extraction_withdrawal'
);

comment on type workflow.review_type is
  'Hva slags faglig beslutning som ble tatt: publication_approval (menneskelig faglig godkjenning av en påstandsrevisjon før publisering, ANTIDEP_CONSTITUTION.md §12) eller extraction_withdrawal (avgjørelsen av om et evidensfunn skal trekkes tilbake eller står ved lag, DATABASE_ARCHITECTURE.md §29). Migrasjon 003 lot spørsmålet om tilbaketrukket ekstraksjon stå åpent; det avgjøres her som en beslutning i workflow, ikke som en muterbar statuskolonne på evidensfunnet.';

create type workflow.review_outcome as enum (
  'approved',
  'rejected',
  'changes_requested',
  'extraction_withdrawn',
  'extraction_upheld'
);

comment on type workflow.review_outcome is
  'Selve beslutningen. approved, rejected og changes_requested hører til publication_approval; extraction_withdrawn og extraction_upheld hører til extraction_withdrawal. Koblingen mellom reviewtype og lovlige beslutninger håndheves av en CHECK, slik at en godkjenning ikke kan registreres som utfall av en tilbaketrekkingsvurdering eller omvendt. Avslag og senere omgjøringer bevares som egne rader; ingenting overskrives (DATABASE_ARCHITECTURE.md §31).';

-- PUBLIC har som standard usage på nye typer. Antidep gir privilegier eksplisitt
-- (DATABASE_ARCHITECTURE.md §5), som i migrasjon 001, 002, 003 og 004.
revoke usage on type
  provenance.actor_type,
  provenance.agent_role,
  workflow.role_scope_type,
  workflow.verification_outcome,
  workflow.verification_source_access,
  workflow.verification_check_result,
  workflow.evidence_check_field,
  workflow.review_object_type,
  workflow.review_type,
  workflow.review_outcome
  from public;

-- catalog.set_row_timestamps() fra migrasjon 002 gjenbrukes av de tabellene her
-- som har updated_at. Kommentaren oppdateres slik at den beskriver den faktiske
-- bruken, som i migrasjon 003.
comment on function catalog.set_row_timestamps() is
  'Trigger-funksjon som gir databasen eierskap til created_at og updated_at, ved INSERT og UPDATE. Brukes av katalogtabellene, av kildetabellene i knowledge og av aktør- og rolletabellene i provenance og workflow. Teknisk metadata; endrer ingen klinisk verdi.';

-- De append-only tabellene i denne migrasjonen har ingen updated_at, og
-- catalog.set_row_timestamps() kan ikke brukes på dem: den skriver til en kolonne
-- de bevisst ikke har. De trenger likevel databaseeid registreringstid, og av en
-- sterkere grunn enn ryddighet.
--
-- En default alene gjelder bare når kolonnen utelates. created_at ville derfor
-- vært oppgivbar av kalleren — og på disse tabellene er created_at ikke teknisk
-- metadata, men det eneste festepunktet mot uavhengig tid. Verifikasjons- og
-- beslutningsradene bærer i tillegg et hendelsestidspunkt kalleren selv oppgir
-- (verified_at, decided_at), og uten en databaseeid created_at å måle det mot
-- kunne både hendelsen og registreringen av den dateres fritt. Da ville
-- «når skjedde dette?» vært en påstand fra den som skriver, ikke en observasjon
-- (ANTIDEP_CONSTITUTION.md §14, DATABASE_ARCHITECTURE.md §7.3).
--
-- Funksjonen ligger ved siden av catalog.set_row_timestamps(), som er den
-- etablerte plasseringen for tidsstempeleierskap på tvers av schemaene. Samme
-- forbehold gjelder som for søsterfunksjonen: et felles hjelpeschema ville vært
-- ryddigere, men er en egen beslutning (se avgrensningen øverst).
create function catalog.set_created_at()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  new.created_at := now();
  return new;
end;
$$;

comment on function catalog.set_created_at() is
  'Trigger-funksjon som gir databasen eierskap til created_at ved INSERT på append-only tabeller uten updated_at. Brukes av verifikasjons- og beslutningstabellene i workflow, der created_at er referansepunktet et kallerstyrt hendelsestidspunkt måles mot.';

revoke execute on function catalog.set_created_at() from public;

-- ----------------------------------------------------------------------------
-- 3. provenance.actors — hvem eller hva som utførte handlingen
--    (DATABASE_ARCHITECTURE.md §32, KNOWLEDGE_MODEL.md §17)
--
-- Alle betydningsfulle handlinger skal peke til en normalisert aktør. Raden er
-- en stabil identitet: den overlever at en brukerkonto deaktiveres, at en
-- agentprosess byttes ut og at en modellversjon oppgraderes. Nettopp derfor
-- bærer den ikke leverandør, modell eller promptversjon — det er egenskaper ved
-- den enkelte kjøringen (provenance.agent_runs, utsatt), ikke ved aktøren, og
-- kanoniske kunnskapsobjekter skal ikke avhenge av én leverandørs
-- identifikatorer (ANTIDEP_CONSTITUTION.md §20).
--
-- auth_user_id er valgfri. §32 sier at en menneskelig aktør kan kobles til
-- auth.users, men at faglig historikk ikke skal forsvinne dersom brukerprofilen
-- deaktiveres. Fremmednøkkelen er derfor RESTRICT: en brukerrad kan ikke slettes
-- bort under en aktør som står oppført på faglige beslutninger. Deaktivering
-- gjøres ved å avslutte rolletildelingene (avsnitt 6) og eventuelt sette
-- retired_at her, ikke ved å slette rader (DATABASE_ARCHITECTURE.md §36).
-- ----------------------------------------------------------------------------
create table provenance.actors (
  id uuid primary key default gen_random_uuid(),
  actor_type provenance.actor_type not null,
  actor_key text not null,
  display_name text not null,
  description text not null,
  auth_user_id uuid
    references auth.users (id) on update restrict on delete restrict,
  agent_role provenance.agent_role,
  retired_at timestamptz,
  retirement_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint actors_actor_key_key unique (actor_key),
  -- Én aktør per brukerkonto. Uten regelen kunne samme person opptre som to
  -- aktører, og kravet om at godkjenner og forfatter er forskjellige ville vært
  -- omgåelig ved å opprette en aktør til.
  constraint actors_auth_user_key unique (auth_user_id),
  -- Gjør (id, actor_type) refererbar, slik at workflow.review_decisions kan
  -- kreve deklarativt at en reviewer er et menneske. Cross-row-regel løst med
  -- sammensatt fremmednøkkel, ikke med CHECK (DATABASE_ARCHITECTURE.md §59).
  constraint actors_id_type_key unique (id, actor_type),

  -- Bare mennesker kan ha en brukerkonto. En agent som «logger inn» ville vært
  -- en menneskelig identitet brukt av en maskin, og agentbrukere skal ikke
  -- representeres som vanlige menneskelige brukere
  -- (MVP_IMPLEMENTATION_PLAN.md §16).
  constraint actors_auth_user_is_human_check
    check (actor_type = 'human' or auth_user_id is null),
  -- En agent uten eksplisitt rolle ville vært nettopp den udifferensierte
  -- KI-aktøren ANTIDEP_CONSTITUTION.md §10 forbyr. Rollen er derfor påkrevd for
  -- agenter og forbudt for alle andre aktørtyper.
  constraint actors_agent_role_check
    check ((actor_type = 'agent') = (agent_role is not null)),

  -- En aktør som tas ut av bruk skal ikke kunne bli det stille, som ved
  -- tilbaketrekking av en påstand (ANTIDEP_CONSTITUTION.md §14).
  constraint actors_retirement_note_required_check
    check ((retired_at is null) = (retirement_note is null)),
  constraint actors_retirement_note_not_blank_check
    check (retirement_note is null
           or (retirement_note = btrim(retirement_note)
               and length(retirement_note) between 1 and 1000)),

  -- Nøkkelen er maskinlesbar, språkuavhengig og stabil: «type:navn», små
  -- bokstaver. Visningsnavnet kan endres uten at referanser i konfigurasjon,
  -- tester eller senere migrasjoner mister betydning.
  constraint actors_actor_key_format_check
    check (actor_key ~ '^[a-z0-9]+(?:[-.][a-z0-9]+)*:[a-z0-9]+(?:[-.][a-z0-9]+)*$'),
  constraint actors_display_name_check
    check (display_name = btrim(display_name)
           and length(display_name) between 1 and 200),
  constraint actors_description_check
    check (description = btrim(description)
           and length(description) between 1 and 2000)
);

comment on table provenance.actors is
  'Normalisert aktør: hvem eller hva som utførte en kunnskapsoperasjon (DATABASE_ARCHITECTURE.md §32, KNOWLEDGE_MODEL.md §17). Stabil identitet som overlever at en brukerkonto deaktiveres eller en modellversjon byttes. Leverandør, modell og promptversjon hører til den enkelte agentkjøringen, ikke hit.';
comment on column provenance.actors.actor_type is
  'Aktørtypen. Bestemmer hva aktøren kan gjøre i modellen: bare human kan registrere en reviewbeslutning, og bare agent kan ha en agentrolle.';
comment on column provenance.actors.actor_key is
  'Stabil, språkuavhengig maskinnøkkel på formen «type:navn». Brukes av seed, tester og senere konfigurasjon, slik at ingen av dem trenger å låse seg til en uuid eller til et visningsnavn som kan endres.';
comment on column provenance.actors.display_name is
  'Navnet aktøren vises med i admin-UI og i provenienskjeden. Kan endres uten at identiteten endres.';
comment on column provenance.actors.description is
  'Hva denne aktøren faktisk er, konkret nok til å være etterprøvbar. Alltid utfylt: en aktørrad uten beskrivelse ville gjort attribusjonen til en etikett i stedet for en forklaring (ANTIDEP_CONSTITUTION.md §14).';
comment on column provenance.actors.auth_user_id is
  'Brukerkontoen aktøren eventuelt er knyttet til. NULL betyr at aktøren ikke har en konto i dette systemet, ikke at aktøren er ukjent. Fremmednøkkelen er RESTRICT, slik at faglig historikk ikke kan forsvinne ved at en brukerrad slettes (DATABASE_ARCHITECTURE.md §32, §36).';
comment on column provenance.actors.agent_role is
  'Hvilken av de eksplisitte agentrollene i ANTIDEP_CONSTITUTION.md §10 prosessen handler i. Påkrevd for agenter, forbudt for andre aktørtyper.';
comment on column provenance.actors.retired_at is
  'Når aktøren ble tatt ut av bruk. Tilbaketrekking er en statusendring, ikke en sletting: alle rader aktøren står oppført på består.';

create index actors_actor_type_idx on provenance.actors (actor_type);

create trigger actors_set_row_timestamps
  before insert or update on provenance.actors
  for each row execute function catalog.set_row_timestamps();

-- Aktøridentiteten er uforanderlig, etter samme mønster som
-- catalog.freeze_population_definition() og knowledge.freeze_claim_identity()
-- (DATABASE_ARCHITECTURE.md §7, §60).
--
-- Kunne aktørtype, nøkkel, agentrolle eller brukerkobling endres i ettertid,
-- ville hele attribusjonshistorikken stille fått et annet innhold: en
-- agentaktør kunne blitt gjort om til et menneske, og reviewbeslutninger som
-- databasen har godtatt fordi aktøren var human, ville plutselig stått i navnet
-- til en KI-prosess. Det er nøyaktig det ANTIDEP_CONSTITUTION.md §12 skal
-- hindre.
--
-- Visningsnavn, beskrivelse og tilbaketrekking er bevisst utenfor vernet: de er
-- presentasjon og livssyklus, ikke identitet. auth_user_id kan settes én gang
-- fra NULL, fordi en menneskelig aktør kan bli registrert før kontoen finnes,
-- men aldri endres eller fjernes etterpå.
create function provenance.freeze_actor_identity()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  if new.actor_type is distinct from old.actor_type
    or new.actor_key is distinct from old.actor_key
    or new.agent_role is distinct from old.agent_role
    or (old.auth_user_id is not null
        and new.auth_user_id is distinct from old.auth_user_id)
  then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Identiteten til aktør %L er uforanderlig og kan ikke endres.', old.id
      ),
      hint = 'Opprett en ny aktør for den nye rollen eller identiteten, og trekk den gamle tilbake med retired_at og en begrunnelse. Handlinger som allerede er attribuert til aktøren skal beholde sin opprinnelige betydning. Visningsnavn og beskrivelse kan endres fritt.';
  end if;

  return new;
end;
$$;

comment on function provenance.freeze_actor_identity() is
  'Immutable-row guard: hindrer at aktørtype, maskinnøkkel, agentrolle og en allerede satt brukerkobling endres etter innsetting, slik at attribusjonshistorikken beholder sin opprinnelige betydning. Visningsnavn, beskrivelse og tilbaketrekking kan endres.';

revoke execute on function provenance.freeze_actor_identity() from public;

create trigger actors_freeze_identity
  before update on provenance.actors
  for each row execute function provenance.freeze_actor_identity();

-- ============================================================================
-- 4. Aktørene bak de radene som allerede finnes
--    (ANTIDEP_CONSTITUTION.md §10, §12, §14, MVP_IMPLEMENTATION_PLAN.md §29)
--
-- Hva som kan seedes ærlig i dette steget, og hvor grensen går:
--
--   Aktørrader for KI-prosessene som faktisk produserte de eksisterende radene
--   er etterprøvbare. Radene finnes, de ble laget av en KI-assistert prosess i
--   en bestemt rolle, og det er akkurat det aktørraden sier.
--
--   Verifikasjonsrader seedes ikke. En verifikasjon er en utført handling: en
--   separat kontrollfase som har lest kildematerialet og forsøkt å falsifisere
--   ekstraksjonen eller påstanden (ANTIDEP_CONSTITUTION.md §11). Ingen slik
--   kontroll er kjørt. Å registrere «verified» ville vært å påstå at en kontroll
--   har funnet sted, og ville gjort verifikasjonstabellene til det motsatte av
--   det de er til for.
--
--   Reviewbeslutninger seedes ikke. ANTIDEP_CONSTITUTION.md §12 krever eksplisitt
--   godkjenning fra en navngitt kvalifisert redaktør for innhold som kan påvirke
--   behandling. Det finnes ingen slik redaktør i systemet ennå, og en seedet
--   godkjenning ville vært nøyaktig den fiktive godkjenningen §12 forbyr.
--   Modellen gjør det umulig å skrive den ved et uhell: en reviewbeslutning må ha
--   en menneskelig aktør knyttet til en brukerkonto med gyldig reviewer-rolle,
--   og ingen av delene finnes.
--
--   Rolletildelinger seedes ikke, av samme grunn: det finnes ingen brukerkontoer,
--   og en tildeling til en oppdiktet konto ville vært en autorisasjonspåstand
--   uten dekning.
--
-- Konsekvensen er reell og skal ikke pyntes over: de to påstandene er fortsatt
-- ubekreftede KI-forslag. Etter denne migrasjonen kan databasen si hvem som
-- laget dem, og den kan si at ingen har verifisert eller godkjent dem — som er
-- to forskjellige og like viktige svar.
--
-- Radene får databasegenererte uuid-er. Tester og senere migrasjoner slår dem
-- opp via actor_key.
-- ============================================================================

insert into provenance.actors (actor_type, actor_key, display_name, description, agent_role)
values
  (
    'agent',
    'agent:evidence-extraction',
    'Antidep ekstraksjonsagent',
    'KI-assistert prosess i ekstraksjonsrollen. Produserte kildene, kildeversjonene og evidensfunnene i migrasjon 003. Kjørt som del av migrasjonsarbeidet under menneskelig instruksjon og med menneskelig gjennomgang av migrasjonen, ikke som en automatisk pipeline; det finnes derfor ingen registrert agentkjøring med modell- og promptversjon.',
    'evidence_extraction'
  ),
  (
    'agent',
    'agent:claim-synthesis',
    'Antidep synteseagent',
    'KI-assistert prosess i synteserollen. Formulerte påstandene og revisjonene, registrerte evidenslenkene og satte GRADE-vurderingene i migrasjon 004. Kjørt som del av migrasjonsarbeidet under menneskelig instruksjon og med menneskelig gjennomgang av migrasjonen, ikke som en automatisk pipeline; det finnes derfor ingen registrert agentkjøring med modell- og promptversjon. Ingen av radene er verifisert av en separat kontrollfase eller godkjent av en kvalifisert redaktør.',
    'claim_synthesis'
  );

-- ----------------------------------------------------------------------------
-- 5. created_by_actor_id på kunnskapsobjektene
--    (DATABASE_ARCHITECTURE.md §13, §14, §19, §21, §22,
--     ANTIDEP_CONSTITUTION.md §14)
--
-- Kolonnene ble utsatt i migrasjon 003 og 004 fordi provenance.actors ikke
-- fantes. Nå finnes den, og attribusjonen legges på plass.
--
-- Backfill av eksisterende rader: valgt framfor å la gamle rader stå med NULL.
--
--   Alternativet ville vært å kreve kolonnen bare framover. Det har to
--   problemer. For det første kan «bare framover» ikke uttrykkes deklarativt:
--   en NOT NULL ville feilet på de gamle radene, og alternativet er en
--   datoavhengig CHECK eller ren applikasjonsvalidering — begge svakere enn
--   PostgreSQL kan gjøre det (DATABASE_ARCHITECTURE.md §57). For det andre er
--   det nettopp disse radene golden slice skal publisere. En publisert påstand
--   uten opphav er direkte i strid med ANTIDEP_CONSTITUTION.md §14, og
--   proveniensgrafen i §34 ville hatt et hull akkurat der den betyr mest.
--
--   Backfillen er sann: radene ble laget av de to aktørene over, og det er
--   dokumentert i migrasjon 003 og 004 hvilken migrasjon som laget hva.
--
-- De append-only tabellene avviser UPDATE også for tabelleieren. Triggerne slås
-- derfor av eksplisitt rundt backfillen, som en synlig og reviewbar handling —
-- slik kommentarene i 003 og 004 forutsetter at en reell vedlikeholdsoperasjon
-- skal gjøres. Vinduet er så smalt som mulig: én UPDATE per tabell, ingen annen
-- setning mellom disable og enable, og kolonnen settes NOT NULL etterpå slik at
-- tilstanden er maskinelt kontrollerbar.
--
-- knowledge.claims er ikke append-only og trenger ingen slik avslåing. Radens
-- updated_at bumpes av tidsstempeltriggeren, hvilket er riktig: raden ble
-- faktisk endret av denne migrasjonen.
-- ----------------------------------------------------------------------------

alter table knowledge.evidence_items
  add column created_by_actor_id uuid
    references provenance.actors (id) on update restrict on delete restrict;
alter table knowledge.claims
  add column created_by_actor_id uuid
    references provenance.actors (id) on update restrict on delete restrict;
alter table knowledge.claim_revisions
  add column created_by_actor_id uuid
    references provenance.actors (id) on update restrict on delete restrict;
alter table knowledge.claim_evidence_links
  add column created_by_actor_id uuid
    references provenance.actors (id) on update restrict on delete restrict;
alter table knowledge.evidence_assessments
  add column created_by_actor_id uuid
    references provenance.actors (id) on update restrict on delete restrict;

alter table knowledge.evidence_items disable trigger evidence_items_reject_mutation;
update knowledge.evidence_items
set created_by_actor_id = (
  select a.id from provenance.actors a where a.actor_key = 'agent:evidence-extraction'
);
alter table knowledge.evidence_items enable trigger evidence_items_reject_mutation;

update knowledge.claims
set created_by_actor_id = (
  select a.id from provenance.actors a where a.actor_key = 'agent:claim-synthesis'
);

alter table knowledge.claim_revisions disable trigger claim_revisions_reject_mutation;
update knowledge.claim_revisions
set created_by_actor_id = (
  select a.id from provenance.actors a where a.actor_key = 'agent:claim-synthesis'
);
alter table knowledge.claim_revisions enable trigger claim_revisions_reject_mutation;

alter table knowledge.claim_evidence_links disable trigger claim_evidence_links_reject_mutation;
update knowledge.claim_evidence_links
set created_by_actor_id = (
  select a.id from provenance.actors a where a.actor_key = 'agent:claim-synthesis'
);
alter table knowledge.claim_evidence_links enable trigger claim_evidence_links_reject_mutation;

alter table knowledge.evidence_assessments disable trigger evidence_assessments_reject_mutation;
update knowledge.evidence_assessments
set created_by_actor_id = (
  select a.id from provenance.actors a where a.actor_key = 'agent:claim-synthesis'
);
alter table knowledge.evidence_assessments enable trigger evidence_assessments_reject_mutation;

alter table knowledge.evidence_items
  alter column created_by_actor_id set not null;
alter table knowledge.claims
  alter column created_by_actor_id set not null;
alter table knowledge.claim_revisions
  alter column created_by_actor_id set not null;
alter table knowledge.claim_evidence_links
  alter column created_by_actor_id set not null;
alter table knowledge.evidence_assessments
  alter column created_by_actor_id set not null;

comment on column knowledge.evidence_items.created_by_actor_id is
  'Aktøren som produserte ekstraksjonen (DATABASE_ARCHITECTURE.md §19, ANTIDEP_CONSTITUTION.md §14). Sier hvem eller hva som laget raden, ikke om den er kontrollert; kontrollen er en egen hendelse i workflow.evidence_verifications.';
comment on column knowledge.claims.created_by_actor_id is
  'Aktøren som opprettet påstandsidentiteten (DATABASE_ARCHITECTURE.md §13).';
comment on column knowledge.claim_revisions.created_by_actor_id is
  'Aktøren som formulerte revisjonen (DATABASE_ARCHITECTURE.md §14). Verifikasjon og godkjenning er egne handlinger av andre aktører; modellen krever eksplisitt at verifikator og godkjenner er en annen aktør enn denne.';
comment on column knowledge.claim_evidence_links.created_by_actor_id is
  'Aktøren som vurderte hvordan evidensfunnet forholder seg til revisjonen (DATABASE_ARCHITECTURE.md §21).';
comment on column knowledge.evidence_assessments.created_by_actor_id is
  'Aktøren som gjorde evidensvurderingen (DATABASE_ARCHITECTURE.md §22). En KI-vurdering er et forslag inntil den er godkjent av en kvalifisert redaktør (ANTIDEP_CONSTITUTION.md §12).';

create index evidence_items_created_by_actor_id_idx
  on knowledge.evidence_items (created_by_actor_id);
create index claims_created_by_actor_id_idx
  on knowledge.claims (created_by_actor_id);
create index claim_revisions_created_by_actor_id_idx
  on knowledge.claim_revisions (created_by_actor_id);
create index claim_evidence_links_created_by_actor_id_idx
  on knowledge.claim_evidence_links (created_by_actor_id);
create index evidence_assessments_created_by_actor_id_idx
  on knowledge.evidence_assessments (created_by_actor_id);

-- Gjør (id, created_by_actor_id) refererbar. Det er dette som lar
-- verifikasjons- og reviewtabellene kreve deklarativt, på sin egen rad, at
-- kontrolløren er en annen aktør enn den som laget objektet — uten at en CHECK
-- må lese en annen tabell (DATABASE_ARCHITECTURE.md §59). Samme mønster som
-- speilkolonnene i migrasjon 004.
alter table knowledge.evidence_items
  add constraint evidence_items_id_creator_key unique (id, created_by_actor_id);
alter table knowledge.claim_revisions
  add constraint claim_revisions_id_creator_key unique (id, created_by_actor_id);

-- Opphavet er en del av identiteten og skal ikke kunne omskrives i ettertid.
-- På de append-only tabellene følger det allerede av at raden ikke kan endres.
-- knowledge.claims er derimot muterbar, så vernet der utvides til den nye
-- kolonnen. Funksjonen fra migrasjon 004 erstattes framfor at det legges en
-- trigger nummer to på samme tabell med samme formål.
create or replace function knowledge.freeze_claim_identity()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  if new.knowledge_type is distinct from old.knowledge_type
    or new.topic_concept_id is distinct from old.topic_concept_id
    or new.subject_drug_id is distinct from old.subject_drug_id
    or new.created_by_actor_id is distinct from old.created_by_actor_id
  then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Identiteten til påstand %L er uforanderlig og kan ikke endres.', old.id
      ),
      hint = 'Opprett en ny påstand for det endrede temaet, virkestoffet eller kunnskapstypen, og trekk den gamle tilbake med retired_at og en begrunnelse. Revisjoner, evidenslenker og publiseringshistorikk som peker på den gamle påstanden skal beholde sin opprinnelige betydning. Opphavet til en påstand kan ikke skrives om i ettertid.';
  end if;

  return new;
end;
$$;

comment on function knowledge.freeze_claim_identity() is
  'Immutable-row guard: hindrer at kunnskapstype, tema, virkestoff og opphav på en påstand endres etter innsetting, slik at revisjoner, publiseringshistorikk og attribusjon som peker på identiteten beholder sin opprinnelige betydning. Publiseringspeker, tilbaketrekking og tidsstempler kan endres.';

-- ----------------------------------------------------------------------------
-- 6. workflow.user_roles — medlemskapsmodellen
--    (DATABASE_ARCHITECTURE.md §45-§48, MVP_IMPLEMENTATION_PLAN.md §16)
--
-- §46 er utgangspunktet: autorisasjonsdata skal ikke komme fra brukerredigerbar
-- metadata, og rettigheter som må kunne tilbakekalles umiddelbart skal leses fra
-- en databasebasert medlemskapstabell framfor fra en JWT-claim. Denne tabellen
-- er den kilden. Ingenting i migrasjonen leser en rolle fra en claim.
--
-- workflow.app_role finnes allerede fra migrasjon 001 og gjenbrukes.
--
-- Gyldighetsperioden er halvåpen: [valid_from, valid_to). En tilbakekalling
-- setter valid_to og bevarer dermed at rollen var gyldig fram til da; historikken
-- skal ikke kunne viskes ut (ANTIDEP_CONSTITUTION.md §14).
--
-- Exclusion constraint framfor unik indeks: to overlappende tildelinger av samme
-- rolle til samme bruker er ikke bare redundante, de gjør tilbakekalling
-- tvetydig. Lukker man den ene, dekker den andre fortsatt, og «rettigheten skal
-- kunne tilbakekalles umiddelbart» (§46) holder ikke lenger. En unik indeks over
-- åpne tildelinger ville bare fanget det ene tilfellet der begge står uten
-- sluttdato. Exclusion constraint er riktig mekanisme og ligger på plass 6 i
-- prioriteringsrekkefølgen i §57, altså foran trigger.
--
-- coalesce på scope_id er nødvendig: en exclusion constraint sammenligner med =,
-- og NULL = NULL er ukjent. Uten den ville nettopp de mest privilegerte
-- tildelingene — de uten scope — sluppet unna regelen.
-- ----------------------------------------------------------------------------
create table workflow.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    references auth.users (id) on update restrict on delete restrict,
  role_code workflow.app_role not null,
  scope_id uuid
    references catalog.clinical_concepts (id) on update restrict on delete restrict,
  valid_from timestamptz not null default now(),
  valid_to timestamptz,
  granted_by_actor_id uuid not null
    references provenance.actors (id) on update restrict on delete restrict,
  grant_reason text not null,
  ended_by_actor_id uuid
    references provenance.actors (id) on update restrict on delete restrict,
  end_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Scopetypen er avledet av pekeren, ikke oppgitt ved siden av den. Da kan de
  -- to ikke komme i utakt, og §47 sitt scope_type finnes likevel som lesbart
  -- felt for admin-UI og senere projeksjoner.
  scope_type workflow.role_scope_type
    generated always as (
      case when scope_id is null then null
           else 'clinical_concept'::workflow.role_scope_type end
    ) stored,

  -- Gyldighetsperioden er et intervall, og et invertert eller tomt intervall er
  -- en feil (DATABASE_ARCHITECTURE.md §58).
  constraint user_roles_validity_interval_check
    check (valid_to is null or valid_to > valid_from),

  -- Enhver avgrensning av gyldigheten skal si hvem som avgrenset den og hvorfor,
  -- enten den er en planlagt utløpsdato satt ved tildeling eller en senere
  -- tilbakekalling (ANTIDEP_CONSTITUTION.md §14).
  constraint user_roles_end_actor_pairing_check
    check ((valid_to is null) = (ended_by_actor_id is null)),
  constraint user_roles_end_reason_pairing_check
    check ((valid_to is null) = (end_reason is null)),

  constraint user_roles_grant_reason_check
    check (grant_reason = btrim(grant_reason)
           and length(grant_reason) between 1 and 1000),
  constraint user_roles_end_reason_format_check
    check (end_reason is null
           or (end_reason = btrim(end_reason) and length(end_reason) between 1 and 1000)),

  constraint user_roles_no_overlapping_grant_excl
    exclude using gist (
      user_id with =,
      role_code with =,
      coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid) with =,
      tstzrange(valid_from, valid_to, '[)') with &&
    )
);

comment on table workflow.user_roles is
  'Medlemskapsmodellen (DATABASE_ARCHITECTURE.md §47): hvilken applikasjonsrolle en bruker har, eventuelt avgrenset til et innholdsområde, og i hvilket tidsrom. Dette er den autoritative kilden for autorisasjon; roller skal aldri leses fra en JWT-claim brukeren kan påvirke (§46). Tildelinger av samme rolle til samme bruker og samme scope kan ikke overlappe i tid, slik at tilbakekalling er entydig.';
comment on column workflow.user_roles.user_id is
  'Brukerkontoen tildelingen gjelder. RESTRICT på fremmednøkkelen, slik at en brukerrad ikke kan slettes bort under en tildeling som ligger til grunn for faglige beslutninger.';
comment on column workflow.user_roles.role_code is
  'Applikasjonsrollen (MVP_IMPLEMENTATION_PLAN.md §16). admin er bruker- og systemforvaltning og gir ikke faglig godkjenningsrett; klinisk godkjenning krever reviewer (DATABASE_ARCHITECTURE.md §45).';
comment on column workflow.user_roles.scope_id is
  'Innholdsområdet tildelingen eventuelt er avgrenset til, som et klinisk begrep. NULL betyr at tildelingen gjelder uten avgrensning, ikke at avgrensningen er ukjent.';
comment on column workflow.user_roles.scope_type is
  'Avledet av scope_id. Finnes som lesbart felt i tråd med DATABASE_ARCHITECTURE.md §47, men kan ikke si noe annet enn pekeren gjør.';
comment on column workflow.user_roles.valid_from is
  'Når tildelingen begynner å gjelde. Sammen med valid_to danner den et halvåpent intervall, slik at «hvilken rolle hadde denne brukeren da beslutningen ble tatt?» har ett entydig svar.';
comment on column workflow.user_roles.valid_to is
  'Når tildelingen slutter å gjelde, eller NULL når den er løpende. Tilbakekalling settes her framfor å slette raden, slik at det bevares at rollen faktisk var gyldig i perioden (ANTIDEP_CONSTITUTION.md §14).';
comment on column workflow.user_roles.granted_by_actor_id is
  'Aktøren som tildelte rollen.';
comment on column workflow.user_roles.grant_reason is
  'Hvorfor rollen ble tildelt. Alltid utfylt: en rettighet uten begrunnelse er ikke etterprøvbar.';
comment on column workflow.user_roles.ended_by_actor_id is
  'Aktøren som avgrenset eller tilbakekalte tildelingen. Påkrevd når valid_to er satt, også når sluttdatoen ble satt allerede ved tildeling.';
comment on column workflow.user_roles.end_reason is
  'Hvorfor tildelingen ble avgrenset eller tilbakekalt. Påkrevd når valid_to er satt.';

create index user_roles_user_role_idx on workflow.user_roles (user_id, role_code);
create index user_roles_scope_id_idx on workflow.user_roles (scope_id);
create index user_roles_granted_by_actor_id_idx on workflow.user_roles (granted_by_actor_id);
create index user_roles_ended_by_actor_id_idx on workflow.user_roles (ended_by_actor_id);

create trigger user_roles_set_row_timestamps
  before insert or update on workflow.user_roles
  for each row execute function catalog.set_row_timestamps();

-- Selve tildelingen er uforanderlig; bare avslutningen kan skrives, og bare én
-- gang.
--
-- Uten dette vernet ville en tilbakekalling kunne gjøres om til noe helt annet:
-- man kunne endret user_id eller role_code på en eksisterende rad og dermed
-- flyttet en rettighet uten spor, eller nullstilt valid_to og gjenopplivet en
-- tilbakekalt rolle. Begge deler ville undergravd at
-- workflow.review_decisions kan slå opp hvilken rolle en bruker hadde på
-- beslutningstidspunktet.
--
-- En gjeninnføring av en tilbakekalt rolle er en ny tildeling med sin egen
-- begrunnelse og sitt eget tidsrom, ikke en redigering av den gamle.
create function workflow.freeze_role_grant()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  if new.user_id is distinct from old.user_id
    or new.role_code is distinct from old.role_code
    or new.scope_id is distinct from old.scope_id
    or new.valid_from is distinct from old.valid_from
    or new.granted_by_actor_id is distinct from old.granted_by_actor_id
    or new.grant_reason is distinct from old.grant_reason
    or new.created_at is distinct from old.created_at
  then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Rolletildeling %L er uforanderlig; bare avslutningen kan registreres.', old.id
      ),
      hint = 'Avslutt den eksisterende tildelingen ved å sette valid_to, ended_by_actor_id og end_reason, og opprett en ny tildeling for den endrede rettigheten.';
  end if;

  if old.valid_to is not null
    and (new.valid_to is distinct from old.valid_to
         or new.ended_by_actor_id is distinct from old.ended_by_actor_id
         or new.end_reason is distinct from old.end_reason)
  then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Rolletildeling %L er allerede avsluttet og kan ikke gjenåpnes eller omskrives.', old.id
      ),
      hint = 'Opprett en ny rolletildeling dersom rettigheten skal gjeninnføres. At rollen var gyldig i den opprinnelige perioden skal bevares.';
  end if;

  return new;
end;
$$;

comment on function workflow.freeze_role_grant() is
  'Immutable-row guard: låser hvem, hvilken rolle, hvilket scope og hvilket starttidspunkt en rolletildeling gjelder, og tillater at avslutningen skrives nøyaktig én gang. Gjeninnføring av en tilbakekalt rolle er en ny tildeling.';

revoke execute on function workflow.freeze_role_grant() from public;

create trigger user_roles_freeze_grant
  before update on workflow.user_roles
  for each row execute function workflow.freeze_role_grant();

-- ----------------------------------------------------------------------------
-- 7. workflow.evidence_verifications — kontroll av ekstraksjonen
--    (DATABASE_ARCHITECTURE.md §29, ANTIDEP_CONSTITUTION.md §10, §11)
--
-- Ekstraksjon og verifikasjon er separate hendelser. Verifikatoren skriver et
-- resultat ved siden av evidensfunnet og rører aldri funnet selv
-- (MVP_IMPLEMENTATION_PLAN.md §49). Det er ikke bare en konvensjon her:
-- knowledge.evidence_items er append-only, så det finnes ingen skrivevei å
-- blande de to gjennom.
--
-- To regler gjør skillet håndhevbart framfor bare dokumentert:
--
--   1. Verifikatoren kan ikke være aktøren som laget ekstraksjonen. Regelen er
--      en cross-row-regel, men den er løst deklarativt med en speilkolonne som
--      er låst til foreldreraden av en sammensatt fremmednøkkel, slik at en
--      radlokal CHECK kan uttrykke den (DATABASE_ARCHITECTURE.md §59). Samme
--      mønster som speilkolonnene i migrasjon 004.
--   2. En verifikasjon kan ikke konkluderes som verified hvis verifikatoren bare
--      hadde et avledet sammendrag å gå på (ANTIDEP_CONSTITUTION.md §11).
--
-- En verifikasjon er en datert observasjon og er append-only. En ny kontroll er
-- en ny rad; flere verifikasjoner av samme evidensfunn er normalt og ønsket, og
-- den siste opphever ikke de tidligere.
-- ----------------------------------------------------------------------------
create table workflow.evidence_verifications (
  id uuid primary key default gen_random_uuid(),
  evidence_item_id uuid not null
    references knowledge.evidence_items (id) on update restrict on delete restrict,
  verified_item_creator_actor_id uuid not null,
  verifier_actor_id uuid not null
    references provenance.actors (id) on update restrict on delete restrict,
  outcome workflow.verification_outcome not null,
  source_access workflow.verification_source_access not null,
  checked_fields workflow.evidence_check_field[] not null,
  findings text,
  rationale text not null,
  verified_at timestamptz not null,
  created_at timestamptz not null default now(),

  -- Speilet er låst til evidensfunnet, slik at regelen under er sann og ikke
  -- bare påstått.
  constraint evidence_verifications_item_fkey
    foreign key (evidence_item_id, verified_item_creator_actor_id)
    references knowledge.evidence_items (id, created_by_actor_id)
    on update restrict on delete restrict,

  -- Generering og verifikasjon er atskilte operasjoner.
  constraint evidence_verifications_separate_actor_check
    check (verifier_actor_id <> verified_item_creator_actor_id),

  -- Verifikatoren skal ikke godkjenne ut fra andre ledds sammendrag alene.
  constraint evidence_verifications_source_access_check
    check (outcome <> 'verified' or source_access <> 'derived_summary'),

  -- En kontroll som ikke kontrollerte noe er ikke en kontroll.
  constraint evidence_verifications_checked_fields_check
    check (cardinality(checked_fields) >= 1
           and array_position(checked_fields, null) is null),
  -- En bekreftet ekstraksjon forutsetter at kildepekeren selv er kontrollert:
  -- er den feil, peker alle de andre kontrollene på feil sted i kilden.
  constraint evidence_verifications_locator_checked_check
    check (outcome <> 'verified' or 'source_locator' = any (checked_fields)),

  -- Et annet utfall enn verified skal si hva som er galt, ellers er det ikke
  -- til å handle på (ANTIDEP_CONSTITUTION.md §11, §14).
  constraint evidence_verifications_findings_required_check
    check (outcome = 'verified' or (findings is not null and btrim(findings) <> '')),

  -- En kontroll kan ikke ha funnet sted i framtiden. created_at er databaseeid
  -- (se catalog.set_created_at()), så dette er en sammenligning mot uavhengig tid
  -- og ikke mot et annet tall kalleren selv har oppgitt. En kontroll som
  -- registreres i etterkant er fortsatt lovlig; det er bare den framtidsdaterte
  -- som avvises.
  constraint evidence_verifications_verified_at_not_future_check
    check (verified_at <= created_at),

  constraint evidence_verifications_findings_format_check
    check (findings is null
           or (findings = btrim(findings) and length(findings) between 1 and 4000)),
  constraint evidence_verifications_rationale_check
    check (rationale = btrim(rationale) and length(rationale) between 1 and 4000)
);

comment on table workflow.evidence_verifications is
  'Kontroll av at et evidensfunn faktisk gjengir det kilden rapporterer (DATABASE_ARCHITECTURE.md §29). Ekstraksjon og verifikasjon er separate hendelser: raden ligger ved siden av evidensfunnet og endrer det aldri. Verifikatoren kan ikke være aktøren som laget ekstraksjonen. Raden er append-only; en ny kontroll er en ny rad.';
comment on column workflow.evidence_verifications.verified_item_creator_actor_id is
  'Speil av aktøren som laget evidensfunnet, låst av den sammensatte fremmednøkkelen. Finnes for at kravet om at verifikator og ekstraktør er forskjellige aktører skal kunne håndheves deklarativt på raden selv. Ikke en selvstendig sannhet.';
comment on column workflow.evidence_verifications.outcome is
  'Resultatet av kontrollen. uncertain betyr at kontrollen ikke kunne konkludere, og skal aldri leses som en bekreftelse.';
comment on column workflow.evidence_verifications.source_access is
  'Hva verifikatoren faktisk hadde tilgang til. En bekreftelse basert bare på et avledet sammendrag er avvist av databasen (ANTIDEP_CONSTITUTION.md §11).';
comment on column workflow.evidence_verifications.checked_fields is
  'Hvilke felter kontrollen faktisk gikk gjennom. Gjør det mulig å se at en bekreftelse dekker det den gir inntrykk av å dekke, framfor å måtte tas på ordet.';
comment on column workflow.evidence_verifications.findings is
  'Avvikene kontrollen fant. Påkrevd når utfallet ikke er verified.';
comment on column workflow.evidence_verifications.rationale is
  'Hvordan kontrollen ble gjennomført og hva den bygger på. Alltid utfylt.';
comment on column workflow.evidence_verifications.verified_at is
  'Når kontrollen ble utført. Et hendelsestidspunkt, ikke registreringstidspunktet for raden; det siste er created_at (DATABASE_ARCHITECTURE.md §7.3). Kan ligge før created_at, men aldri etter: en kontroll kan registreres i etterkant, men ikke dateres til framtiden.';

create index evidence_verifications_evidence_item_id_idx
  on workflow.evidence_verifications (evidence_item_id);
create index evidence_verifications_verifier_actor_id_idx
  on workflow.evidence_verifications (verifier_actor_id);

create trigger evidence_verifications_set_created_at
  before insert on workflow.evidence_verifications
  for each row execute function catalog.set_created_at();

create trigger evidence_verifications_reject_mutation
  before update or delete on workflow.evidence_verifications
  for each row execute function knowledge.reject_append_only_mutation(
    'Registrer en ny verifikasjon for det korrigerte resultatet. En utført kontroll dokumenterer hva verifikatoren faktisk fant på det tidspunktet, og skal verken overskrives eller slettes.'
  );

-- ----------------------------------------------------------------------------
-- 8. workflow.claim_verifications — kontroll av påstanden mot grunnlaget
--    (DATABASE_ARCHITECTURE.md §30, ANTIDEP_CONSTITUTION.md §11)
--
-- §30 lister sju spørsmål claim-verifikasjonen minst skal dekke. De ligger som
-- egne kolonner framfor i en fritekst, av samme grunn som GRADE-domenene ligger
-- som egne kolonner i migrasjon 004: da kan databasen håndheve at ingen av dem
-- er hoppet over, og at et ubedømt punkt ikke teller som bestått.
--
-- Det er dette som gjør ANTIDEP_CONSTITUTION.md §11 maskinelt kontrollerbar:
-- verifikasjonen skal forsøke å falsifisere, og et forsøk som ikke har sett på
-- motstridende evidens eller på om vesentlige forbehold mangler, kan ikke
-- registreres som en bekreftelse.
-- ----------------------------------------------------------------------------
create table workflow.claim_verifications (
  id uuid primary key default gen_random_uuid(),
  claim_revision_id uuid not null
    references knowledge.claim_revisions (id) on update restrict on delete restrict,
  verified_revision_creator_actor_id uuid not null,
  verifier_actor_id uuid not null
    references provenance.actors (id) on update restrict on delete restrict,
  outcome workflow.verification_outcome not null,
  source_access workflow.verification_source_access not null,

  -- De sju kontrollpunktene i DATABASE_ARCHITECTURE.md §30.
  source_support workflow.verification_check_result not null,
  population_match workflow.verification_check_result not null,
  comparator_match workflow.verification_check_result not null,
  timeframe_match workflow.verification_check_result not null,
  direction_and_magnitude workflow.verification_check_result not null,
  qualifiers_complete workflow.verification_check_result not null,
  contradictory_evidence_represented workflow.verification_check_result not null,

  findings text,
  rationale text not null,
  verified_at timestamptz not null,
  created_at timestamptz not null default now(),

  constraint claim_verifications_revision_fkey
    foreign key (claim_revision_id, verified_revision_creator_actor_id)
    references knowledge.claim_revisions (id, created_by_actor_id)
    on update restrict on delete restrict,

  -- Generering og verifikasjon er atskilte operasjoner.
  constraint claim_verifications_separate_actor_check
    check (verifier_actor_id <> verified_revision_creator_actor_id),

  constraint claim_verifications_source_access_check
    check (outcome <> 'verified' or source_access <> 'derived_summary'),

  -- En bekreftelse forutsetter at alle sju kontrollpunktene er bedømt og holder.
  -- not_assessable er ikke ok: et punkt som ikke lot seg bedømme er nettopp den
  -- usikkerheten §11 skal fram i lyset, ikke en bestått kontroll.
  constraint claim_verifications_verified_requires_all_ok_check
    check (
      outcome <> 'verified'
      or (source_support = 'ok'
          and population_match = 'ok'
          and comparator_match = 'ok'
          and timeframe_match = 'ok'
          and direction_and_magnitude = 'ok'
          and qualifiers_complete = 'ok'
          and contradictory_evidence_represented = 'ok')
    ),

  constraint claim_verifications_findings_required_check
    check (outcome = 'verified' or (findings is not null and btrim(findings) <> '')),

  -- Samme regel som på ekstraksjonsverifikasjonen: en kontroll kan ikke ha
  -- funnet sted i framtiden.
  constraint claim_verifications_verified_at_not_future_check
    check (verified_at <= created_at),

  constraint claim_verifications_findings_format_check
    check (findings is null
           or (findings = btrim(findings) and length(findings) between 1 and 4000)),
  constraint claim_verifications_rationale_check
    check (rationale = btrim(rationale) and length(rationale) between 1 and 4000)
);

comment on table workflow.claim_verifications is
  'Kontroll av at en påstandsrevisjon faktisk holder mot det registrerte grunnlaget (DATABASE_ARCHITECTURE.md §30). De sju kontrollpunktene ligger som egne kolonner, slik at databasen kan håndheve at ingen av dem er hoppet over og at et ubedømt punkt ikke teller som bestått (ANTIDEP_CONSTITUTION.md §11). Verifikatoren kan ikke være aktøren som formulerte revisjonen. Raden er append-only.';
comment on column workflow.claim_verifications.verified_revision_creator_actor_id is
  'Speil av aktøren som formulerte revisjonen, låst av den sammensatte fremmednøkkelen. Finnes for at kravet om at verifikator og forfatter er forskjellige aktører skal kunne håndheves deklarativt. Ikke en selvstendig sannhet.';
comment on column workflow.claim_verifications.source_support is
  'Støtter det registrerte grunnlaget faktisk ordlyden i påstanden? En kilde som bare handler om samme tema er ikke støtte (ANTIDEP_CONSTITUTION.md §4).';
comment on column workflow.claim_verifications.population_match is
  'Svarer populasjonen påstanden gjelder for til den grunnlaget dekker?';
comment on column workflow.claim_verifications.comparator_match is
  'Er komparatoren i påstanden den samme som i grunnlaget?';
comment on column workflow.claim_verifications.timeframe_match is
  'Er tidsrommet i påstanden dekket av grunnlaget?';
comment on column workflow.claim_verifications.direction_and_magnitude is
  'Er retning og eventuelle tallstørrelser gjengitt riktig, uten å være mer presise enn grunnlaget?';
comment on column workflow.claim_verifications.qualifiers_complete is
  'Mangler vesentlige forbehold i påstanden?';
comment on column workflow.claim_verifications.contradictory_evidence_represented is
  'Finnes det relevant motstridende evidens som ikke er representert? Punktet er kjernen i at verifikasjonen skal forsøke å falsifisere og ikke bare bekrefte (ANTIDEP_CONSTITUTION.md §9, §11).';
comment on column workflow.claim_verifications.findings is
  'Avvikene kontrollen fant. Påkrevd når utfallet ikke er verified.';
comment on column workflow.claim_verifications.verified_at is
  'Når kontrollen ble utført. Et hendelsestidspunkt, ikke registreringstidspunktet for raden. Kan ligge før created_at, men aldri etter.';

create index claim_verifications_claim_revision_id_idx
  on workflow.claim_verifications (claim_revision_id);
create index claim_verifications_verifier_actor_id_idx
  on workflow.claim_verifications (verifier_actor_id);

create trigger claim_verifications_set_created_at
  before insert on workflow.claim_verifications
  for each row execute function catalog.set_created_at();

create trigger claim_verifications_reject_mutation
  before update or delete on workflow.claim_verifications
  for each row execute function knowledge.reject_append_only_mutation(
    'Registrer en ny claim-verifikasjon for det korrigerte resultatet. En utført kontroll dokumenterer hva verifikatoren faktisk fant på det tidspunktet, og skal verken overskrives eller slettes.'
  );

-- ----------------------------------------------------------------------------
-- 9. workflow.review_decisions — den menneskelige faglige beslutningen
--    (DATABASE_ARCHITECTURE.md §31, ANTIDEP_CONSTITUTION.md §12)
--
-- §31 er tydelig: menneskelig faglig review skal lagres som beslutningsobjekter,
-- ikke som et approved_by-felt på innholdsraden. Det bevarer godkjenninger,
-- avslag og senere omgjøringer side om side.
--
-- Objektpekeren er ikke polymorf. §31 sitt object_type/object_id ville betydd en
-- uuid uten fremmednøkkel, altså en referanse databasen ikke kan garantere
-- (DATABASE_ARCHITECTURE.md §37, §57). I stedet finnes én ekte fremmednøkkel per
-- objekttype, en CHECK som krever at nøyaktig én er satt, og en avledet
-- object_type som ikke kan si noe annet enn pekerne gjør.
--
-- Hvilke objekter kan reviewes nå:
--   * knowledge.claim_revisions — godkjenning før publisering (§12).
--   * knowledge.evidence_items — tilbaketrekking av en ekstraksjon.
--
-- Tilbaketrukket ekstraksjon var det åpne spørsmålet migrasjon 003 utsatte hit:
-- statuskolonne på evidensfunnet, eller beslutning i workflow? Det avgjøres som
-- beslutning i workflow. Tre grunner: knowledge.evidence_items er append-only,
-- så en statuskolonne ville krevd at raden blir muterbar; §15 forbyr å skjule
-- livssyklusen i ett muterbart statusfelt; og §29 plasserer eksplisitt
-- korreksjons- og tilbaketrekkingsbeslutninger i workflow. En tilbaketrekking er
-- dessuten en faglig vurdering med en begrunnelse og en ansvarlig, ikke en flagg.
--
-- Konsekvens som må håndteres i migrasjon 006: «er dette evidensfunnet trukket
-- tilbake?» er en avledet tilstand — den siste beslutningen av typen
-- extraction_withdrawal for funnet. Publiseringsgaten må lese den og nekte å
-- publisere en revisjon som hviler på et tilbaketrukket evidensfunn
-- (DATABASE_ARCHITECTURE.md §58, siste kulepunkt).
--
-- Bevisst utelatt: en eksplisitt supersedes-peker mellom beslutninger. En
-- omgjøring er en ny rad med et senere decided_at, og rekkefølgen er entydig
-- uten pekeren. Den legges til hvis admin-flyten viser at den trengs.
-- ----------------------------------------------------------------------------
create table workflow.review_decisions (
  id uuid primary key default gen_random_uuid(),

  claim_revision_id uuid
    references knowledge.claim_revisions (id) on update restrict on delete restrict,
  claim_revision_creator_actor_id uuid,
  evidence_item_id uuid
    references knowledge.evidence_items (id) on update restrict on delete restrict,
  evidence_item_creator_actor_id uuid,

  review_type workflow.review_type not null,
  decision workflow.review_outcome not null,
  rationale text not null,
  reviewer_actor_id uuid not null
    references provenance.actors (id) on update restrict on delete restrict,
  reviewer_actor_type provenance.actor_type not null,
  decided_at timestamptz not null,
  created_at timestamptz not null default now(),

  object_type workflow.review_object_type
    generated always as (
      case when claim_revision_id is not null
             then 'claim_revision'::workflow.review_object_type
           else 'evidence_item'::workflow.review_object_type end
    ) stored,

  -- Nøyaktig ett objekt per beslutning.
  constraint review_decisions_single_object_check
    check (num_nonnulls(claim_revision_id, evidence_item_id) = 1),
  constraint review_decisions_claim_creator_pairing_check
    check ((claim_revision_id is null) = (claim_revision_creator_actor_id is null)),
  constraint review_decisions_evidence_creator_pairing_check
    check ((evidence_item_id is null) = (evidence_item_creator_actor_id is null)),

  -- Speilene er låst til objektradene.
  constraint review_decisions_claim_revision_fkey
    foreign key (claim_revision_id, claim_revision_creator_actor_id)
    references knowledge.claim_revisions (id, created_by_actor_id)
    on update restrict on delete restrict,
  constraint review_decisions_evidence_item_fkey
    foreign key (evidence_item_id, evidence_item_creator_actor_id)
    references knowledge.evidence_items (id, created_by_actor_id)
    on update restrict on delete restrict,

  -- Reviewer er låst til aktørraden og må være et menneske.
  -- ANTIDEP_CONSTITUTION.md §12: KI skal aldri være endelig faglig autoritet.
  -- Regelen er strukturell og ikke en konvensjon: det finnes ingen skrivevei der
  -- en KI-aktør kan registrere en faglig beslutning.
  constraint review_decisions_reviewer_fkey
    foreign key (reviewer_actor_id, reviewer_actor_type)
    references provenance.actors (id, actor_type)
    on update restrict on delete restrict,
  constraint review_decisions_reviewer_is_human_check
    check (reviewer_actor_type = 'human'),

  -- Den som godkjenner kan ikke være den som laget objektet
  -- (ANTIDEP_CONSTITUTION.md §10, §12, MVP_IMPLEMENTATION_PLAN.md §49). Fordi
  -- nøyaktig én av objektpekerne er satt, gir coalesce den aktuelle forfatteren.
  constraint review_decisions_separate_actor_check
    check (reviewer_actor_id
           <> coalesce(claim_revision_creator_actor_id, evidence_item_creator_actor_id)),

  -- Reviewtypen bestemmer hvilket objekt beslutningen kan gjelde ...
  constraint review_decisions_type_object_check
    check ((review_type = 'publication_approval' and object_type = 'claim_revision')
           or (review_type = 'extraction_withdrawal' and object_type = 'evidence_item')),
  -- ... og hvilke beslutninger som er mulige.
  constraint review_decisions_type_decision_check
    check ((review_type = 'publication_approval'
            and decision in ('approved', 'rejected', 'changes_requested'))
           or (review_type = 'extraction_withdrawal'
               and decision in ('extraction_withdrawn', 'extraction_upheld'))),

  -- En beslutning kan ikke være tatt i framtiden. Regelen er sikkerhetskritisk
  -- og ikke bare ryddig: decided_at er kallerstyrt og styrer hvilken
  -- rolletildeling som teller som gyldig, så uten et databaseeid referansepunkt
  -- kunne en beslutning dateres dit rettighetene tilfeldigvis passet.
  constraint review_decisions_decided_at_not_future_check
    check (decided_at <= created_at),

  constraint review_decisions_rationale_check
    check (rationale = btrim(rationale) and length(rationale) between 1 and 4000)
);

comment on table workflow.review_decisions is
  'Menneskelig faglig beslutning om et kunnskapsobjekt, lagret som et eget beslutningsobjekt og ikke som et approved_by-felt på innholdsraden (DATABASE_ARCHITECTURE.md §31). Godkjenninger, avslag og senere omgjøringer bevares side om side. Bare en menneskelig aktør med gyldig reviewer-rolle kan registrere en beslutning, og aldri om sitt eget arbeid (ANTIDEP_CONSTITUTION.md §12). Raden er append-only.';
comment on column workflow.review_decisions.claim_revision_id is
  'Påstandsrevisjonen beslutningen gjelder, ved publiseringsgodkjenning. Beslutningen peker på en eksakt revisjon, ikke på påstandsidentiteten (KNOWLEDGE_MODEL.md §19.3), slik at en godkjenning ikke kan følge med over på en senere og annerledes formulering.';
comment on column workflow.review_decisions.claim_revision_creator_actor_id is
  'Speil av aktøren som formulerte revisjonen, låst av den sammensatte fremmednøkkelen. Finnes for at kravet om at godkjenner og forfatter er forskjellige aktører skal kunne håndheves deklarativt.';
comment on column workflow.review_decisions.evidence_item_id is
  'Evidensfunnet beslutningen gjelder, ved vurdering av tilbaketrekking av en ekstraksjon.';
comment on column workflow.review_decisions.object_type is
  'Avledet av hvilken objektpeker som er satt. Gir §31 sitt object_type som lesbart felt uten at det kan si noe annet enn pekeren.';
comment on column workflow.review_decisions.review_type is
  'Hva slags faglig beslutning dette er. Bestemmer både hvilket objekt beslutningen kan gjelde og hvilke utfall som er mulige.';
comment on column workflow.review_decisions.decision is
  'Selve beslutningen. Et avslag er like bevaringsverdig som en godkjenning og skal aldri slettes når en senere beslutning går andre veien.';
comment on column workflow.review_decisions.rationale is
  'Den faglige begrunnelsen. Alltid utfylt: en godkjenning uten begrunnelse er ikke etterprøvbar (ANTIDEP_CONSTITUTION.md §14).';
comment on column workflow.review_decisions.reviewer_actor_type is
  'Speil av aktørtypen, låst av den sammensatte fremmednøkkelen og begrenset til human av en CHECK. Gjør ANTIDEP_CONSTITUTION.md §12 til en strukturell umulighet framfor en regel som må håndheves i applikasjonskode.';
comment on column workflow.review_decisions.decided_at is
  'Når beslutningen ble tatt. Rollekontrollen bruker dette tidspunktet, ikke now(): en reviewer som senere mister rollen skal ikke få sine tidligere beslutninger ugyldiggjort. Feltet er kallerstyrt og derfor bundet i begge retninger: det kan ikke ligge etter radens databaseeide created_at, og kvalifikasjonskontrollen krever at selve rolletildelingsraden fantes senest på dette tidspunktet. En rolle tildelt i etterkant kan derfor ikke legitimere en beslutning som allerede var tatt, heller ikke ved å tilbakedatere valid_from.';

create index review_decisions_claim_revision_id_idx
  on workflow.review_decisions (claim_revision_id);
create index review_decisions_evidence_item_id_idx
  on workflow.review_decisions (evidence_item_id);
create index review_decisions_reviewer_actor_id_idx
  on workflow.review_decisions (reviewer_actor_id);

-- Kvalifikasjonskravet i ANTIDEP_CONSTITUTION.md §12: godkjenningen skal komme
-- fra en navngitt kvalifisert redaktør. Databasen kan håndheve at aktøren er et
-- menneske (CHECK over), men ikke at mennesket er kvalifisert — den delen
-- avhenger av en annen tabell og er en tverradsregel som verken CHECK eller
-- fremmednøkkel kan uttrykke, fordi den er tidsavhengig: rollen må ha vært
-- gyldig på beslutningstidspunktet. Dette er en av tverradsinvariantene
-- DATABASE_ARCHITECTURE.md §60 navngir som legitim triggerbruk.
--
-- Kravet er strengt med hensikt:
--   * aktøren må være knyttet til en brukerkonto,
--   * kontoen må ha rollen reviewer,
--   * selve tildelingsraden må ha eksistert senest på decided_at,
--   * tildelingen må ha vært gyldig på decided_at, og
--   * en scoped tildeling må dekke objektets kliniske tema.
--
-- Skillet mellom de to tidskravene er poenget. valid_from er kallerstyrt og kan
-- settes bakover i tid, som er legitimt når en eksisterende rettighet
-- registreres i systemet. Alene ville den likevel gjort kvalifikasjonen
-- konstruerbar i etterkant: en rolle opprettet i dag med valid_from tilbake i
-- 2020 ville legitimert en «godkjenning» datert 2021, som aldri fant sted.
-- workflow.user_roles.created_at er derimot databaseeid (catalog.set_row_timestamps())
-- og kan ikke tilbakedateres. Kontrollen krever derfor begge deler: raden må ha
-- eksistert, og gyldighetsperioden må ha dekket tidspunktet.
--
-- admin kvalifiserer ikke. DATABASE_ARCHITECTURE.md §45 gjør admin til bruker-
-- og systemforvaltning; å la den rollen godkjenne klinisk innhold ville gjort
-- rettighetsforvaltning til en vei rundt det faglige kravet. Det samme gjelder
-- editor og publisher: å skrive og å publisere er andre handlinger enn å
-- godkjenne (MVP_IMPLEMENTATION_PLAN.md §15).
--
-- SECURITY DEFINER er nødvendig og bevisst: workflow.user_roles har RLS og
-- default deny, og kontrollen må kunne lese den uavhengig av hvem som skriver
-- beslutningen. Funksjonen har tomt search_path, schemakvalifiserte navn, er
-- ikke kjørbar for PUBLIC, tar ingen parametere fra kalleren utover raden som
-- settes inn, og kan bare avvise — den gir ingen data tilbake
-- (DATABASE_ARCHITECTURE.md §50).
--
-- Rollen leses fra medlemskapstabellen, aldri fra en JWT-claim (§46).
create function workflow.enforce_reviewer_qualification()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_reviewer_user_id uuid;
  v_topic_concept_id uuid;
begin
  select a.auth_user_id into v_reviewer_user_id
  from provenance.actors a
  where a.id = new.reviewer_actor_id;

  if v_reviewer_user_id is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Reviewaktøren er ikke knyttet til en brukerkonto og kan ikke registrere en faglig beslutning.',
      hint = 'En faglig beslutning krever en navngitt kvalifisert redaktør (ANTIDEP_CONSTITUTION.md §12). Knytt aktøren til brukerkontoen sin i provenance.actors, og tildel reviewer-rollen i workflow.user_roles.';
  end if;

  if new.claim_revision_id is not null then
    select cl.topic_concept_id into v_topic_concept_id
    from knowledge.claim_revisions r
    join knowledge.claims cl on cl.id = r.claim_id
    where r.id = new.claim_revision_id;
  else
    select e.outcome_concept_id into v_topic_concept_id
    from knowledge.evidence_items e
    where e.id = new.evidence_item_id;
  end if;

  if not exists (
    select 1
    from workflow.user_roles ur
    where ur.user_id = v_reviewer_user_id
      and ur.role_code = 'reviewer'
      and ur.created_at <= new.decided_at
      and ur.valid_from <= new.decided_at
      and (ur.valid_to is null or ur.valid_to > new.decided_at)
      and (ur.scope_id is null or ur.scope_id = v_topic_concept_id)
  ) then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Reviewaktøren hadde ikke gyldig reviewer-rolle for dette innholdsområdet på beslutningstidspunktet.',
      hint = 'Rollen leses fra workflow.user_roles, ikke fra en JWT-claim (DATABASE_ARCHITECTURE.md §46). Tildelingsraden må ha eksistert senest på decided_at og ha vært gyldig på det tidspunktet, og en scoped tildeling må dekke det kliniske temaet objektet hører under. En tilbakedatert valid_from er ikke nok: registreringstidspunktet for tildelingen eies av databasen. admin, editor og publisher gir ikke faglig godkjenningsrett.';
  end if;

  return new;
end;
$$;

comment on function workflow.enforce_reviewer_qualification() is
  'Tverradsinvariant: krever at en reviewbeslutning kommer fra en menneskelig aktør med en brukerkonto som hadde gyldig reviewer-rolle for objektets innholdsområde på beslutningstidspunktet, og at selve rolletildelingen fantes senest da (ANTIDEP_CONSTITUTION.md §12). Det siste kravet hindrer at en rolle opprettet i etterkant konstruerer gyldighet retroaktivt ved å tilbakedatere valid_from. SECURITY DEFINER fordi medlemskapstabellen har RLS og default deny; funksjonen leser bare, validerer bare, og returnerer ingen data.';

revoke execute on function workflow.enforce_reviewer_qualification() from public;

create trigger review_decisions_enforce_reviewer_qualification
  before insert on workflow.review_decisions
  for each row execute function workflow.enforce_reviewer_qualification();

create trigger review_decisions_set_created_at
  before insert on workflow.review_decisions
  for each row execute function catalog.set_created_at();

create trigger review_decisions_reject_mutation
  before update or delete on workflow.review_decisions
  for each row execute function knowledge.reject_append_only_mutation(
    'Registrer en ny beslutning dersom vurderingen endres. En omgjøring er en ny rad; både den opprinnelige beslutningen og omgjøringen skal bevares (DATABASE_ARCHITECTURE.md §31).'
  );

-- ----------------------------------------------------------------------------
-- 10. RLS og grants (DATABASE_ARCHITECTURE.md §5, §48, §49,
--     MVP_IMPLEMENTATION_PLAN.md §47-§49)
--
-- RLS aktiveres på alle nye tabeller og er default deny.
--
-- Skrives redaksjonell lesetilgang nå eller senere? Senere, og valget er
-- bevisst framfor en forglemmelse.
--
--   En RLS-policy har bare virkning for en rolle som allerede har et
--   tabellprivilegium. Ingen klientrolle har usage på workflow, provenance eller
--   knowledge, og ingen har SELECT på noen tabell der. En policy skrevet nå ville
--   derfor ikke kunne slippe noen inn, ikke kunne stenge noen ute, og ikke kunne
--   testes for annet enn sin egen eksistens — den ville vært en påstand om
--   sikkerhet uten virkning, og nettopp den slags gir falsk trygghet.
--
--   MVP_IMPLEMENTATION_PLAN.md §48 sier dessuten at admin-klienten ikke skal ha
--   generell tabellskriveadgang: sentrale operasjoner skal gå gjennom
--   kontrollerte server-/RPC-grenser som validerer rolle, status og
--   preconditions. Den første slike grensen er publiseringsoperasjonen i
--   migrasjon 006. Policyene hører sammen med den skriveveien de skal styre, og
--   med grantene som gjør dem virksomme.
--
--   Det som ikke er utsatt, er selve autorisasjonskilden. §46 krever at rollen
--   leses fra medlemskapstabellen og ikke fra en JWT-claim brukeren kan påvirke,
--   og det kravet er innfridd her: workflow.user_roles finnes, og den eneste
--   rollekontrollen migrasjonen inneholder — kvalifikasjonskravet på
--   reviewbeslutninger — leser den tabellen og ingen claim.
--
-- service_role får fortsatt ingenting, og evidenspipelinen har fortsatt ingen
-- egen databaseidentitet. Den opprettes av migrasjonen som innfører den første
-- automatiske skriveveien (DATABASE_ARCHITECTURE.md §49).
-- ----------------------------------------------------------------------------
alter table provenance.actors enable row level security;
alter table workflow.user_roles enable row level security;
alter table workflow.evidence_verifications enable row level security;
alter table workflow.claim_verifications enable row level security;
alter table workflow.review_decisions enable row level security;

revoke all privileges on all tables in schema provenance from public;
revoke all privileges on all tables in schema provenance
  from anon, authenticated, service_role;
revoke all privileges on all tables in schema workflow from public;
revoke all privileges on all tables in schema workflow
  from anon, authenticated, service_role;
