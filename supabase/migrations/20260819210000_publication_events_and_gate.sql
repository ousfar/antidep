-- ============================================================================
-- Antidep migrasjon 006 — publiseringshendelser og publiseringsgate
--
-- Formål: gjøre publisering til én kontrollert transaksjon som enten lykkes
-- fullstendig eller ikke endrer noe. Migrasjonen oppretter den append-only
-- publiseringshistorikken og de kontrollerte operasjonene som er den eneste
-- veien til å flytte publiseringspekeren.
--
-- Styrende dokumenter:
--   docs/ANTIDEP_CONSTITUTION.md
--     §4 enhver klinisk relevant påstand skal være etterprøvbar
--     §5 tre kunnskapstyper med ulike valideringsregler
--     §6 gradert usikkerhet
--     §9 motstridende evidens bevares
--     §11 verifikasjon skal forsøke å falsifisere
--     §12 KI foreslår; mennesker har det faglige ansvaret
--     §13 alt publisert innhold har en eksplisitt livssyklus
--     §14 endringer skal være reversible, attribuerte og rapporterbare
--     §17 fravær av registrert evidens er ikke bevist fravær av risiko
--   docs/MVP_IMPLEMENTATION_PLAN.md
--     §15 første admin-workflow, og at systemet skal vise hvorfor et steg er blokkert
--     §23 innholdet i denne migrasjonen
--     §29 Slice 1
--     §41-§42 testpyramide og kritiske negative tester
--     §47-§49 offentlig lesing, admin-skriving gjennom kontrollerte grenser,
--             least privilege for agenter
--   docs/DATABASE_ARCHITECTURE.md
--     §7, §7.1-§7.3 identitet, immutable revisjoner, publiseringspeker, tidsbegreper
--     §15 livssyklus skal ikke skjules i ett muterbart statusfelt
--     §29-§31 verifikasjon og review
--     §36 ingen normal DELETE, §37 RESTRICT
--     §38 publisering er en transaksjon, med listen over hva gaten kontrollerer
--     §39 knowledge.publication_events
--     §40 rollback er ny historikk
--     §46 autorisasjon leses ikke fra brukerredigerbar metadata
--     §50 privilegerte databasefunksjoner
--     §57-§61 deklarative constraints, tverradsregler, snevre triggere, atomisitet
--     §67 databasetesting er en del av funksjonen
--   docs/KNOWLEDGE_MODEL.md
--     §19 revisjonsmodell, §20 standard livssyklus, §21 godkjenningsmatrise
--
-- ----------------------------------------------------------------------------
-- Denne migrasjonen publiserer ingenting, og det er poenget
--
-- Publisering av en evidenssyntese krever menneskelig faglig godkjenning fra en
-- navngitt kvalifisert redaktør (ANTIDEP_CONSTITUTION.md §12,
-- KNOWLEDGE_MODEL.md §21). Migrasjon 005 gjorde dette til en strukturell
-- umulighet uten en reell person: en reviewbeslutning krever en aktør av typen
-- human, knyttet til en brukerkonto, med gyldig reviewer-rolle for
-- innholdsområdet på beslutningstidspunktet. Ingen av delene finnes, og å seede
-- dem ville vært å oppfinne en redaktør.
--
-- Migrasjonen leverer derfor en gate som beviselig nekter, ikke en publisert
-- påstand. De to påstandene fra migrasjon 004 er fortsatt ubekreftede
-- KI-forslag, current_published_revision_id står fortsatt tomt på begge, og
-- publiseringshistorikken er tom. Testpakken viser at gaten avviser hver enkelt
-- manglende forutsetning med en forståelig feil, og at den slipper gjennom når
-- alle kravene faktisk er oppfylt av testdata opprettet inne i transaksjonen.
--
-- ----------------------------------------------------------------------------
-- Avgrensning (MVP_IMPLEMENTATION_PLAN.md §24-§26):
--   Ingen api-views (007), ingen audit.events (008) og ingen ingest (009).
--   Ingen admin-UI. Ingen provenance.agent_runs.
--
-- Kjent arkitekturgjeld som ikke rettes her (dokumentert framfor å utvide
-- scopet, jf. MVP_IMPLEMENTATION_PLAN.md §72):
--   * knowledge.set_evidence_item_content_hash() fra migrasjon 003 skjøter
--     feltene med concat_ws('|', ...) mens fritekstfeltene selv kan inneholde
--     «|», og hashen er UNIQUE. Rettelsen krever at funksjonen byttes og at
--     eksisterende rader rehashes under nytt prefiks, og hører til en egen liten
--     migrasjon. Den har ligget siden migrasjon 004 og bør ikke bli liggende
--     lenger, men den hører ikke hjemme sammen med publiseringsgaten.
--   * Kolonnekommentaren på catalog.drugs.updated_at viser fortsatt til
--     catalog.set_updated_at(), mens funksjonen heter catalog.set_row_timestamps().
--     Samme oppryddingsmigrasjon.
--
-- Konvensjonene fra migrasjon 001 gjelder og håndheves av
-- supabase/tests/030_conventions_test.sql: én databasegenerert uuid som
-- primærnøkkel, timestamptz overalt, created_at med default now(), RLS aktivert
-- og ingen grants til anon/authenticated/service_role/PUBLIC.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Kontrollerte vokabularer
--
-- Som i migrasjon 002-005 håndheves vokabularene som enum, altså på
-- datatypenivå (DATABASE_ARCHITECTURE.md §57). Det åpne spørsmålet om enum
-- kontra oppslagstabell (§72) står fortsatt åpent og vokser til 30 typer her;
-- det bør avgjøres før api-projeksjonene i migrasjon 007 begynner å eksponere
-- verdiene.
-- ----------------------------------------------------------------------------

-- §39 beskriver hendelsen med et polymorft object_type/object_id-par. Som i
-- workflow.review_decisions løses det ikke med en uuid uten fremmednøkkel:
-- publiseringshendelsen har én ekte fremmednøkkel til knowledge.claims, og
-- object_type er avledet av den. Typen finnes fordi §39 navngir feltet og fordi
-- den gjør det lesbart hva hendelsen gjelder — ikke fordi den er en selvstendig
-- sannhet.
--
-- Samme forbehold som workflow.role_scope_type: fordi det bare finnes én
-- objekttype, har hendelsen i dag én ekte fremmednøkkel. Migrasjonen som
-- innfører en andre publiserbar objekttype må legge til sin egen
-- fremmednøkkelkolonne og speil, ikke gjenbruke claim_id som en generisk
-- object_id.
create type knowledge.publication_object_type as enum ('claim');

comment on type knowledge.publication_object_type is
  'Hva en publiseringshendelse gjelder. Avledet av hvilken objektpeker som er satt, og har i dag nøyaktig én verdi fordi bare påstander kan publiseres. En andre objekttype skal legge til sin egen fremmednøkkelkolonne og sitt eget speil, ikke gjenbruke den eksisterende pekeren som en generisk object_id.';

-- De fire handlingene i DATABASE_ARCHITECTURE.md §39. De er ikke synonymer for
-- «pekeren ble flyttet»: hver av dem beskriver en egen tilstandsovergang, med
-- egne krav til hva pekeren skal peke på etterpå.
--
--   publish   ingenting publisert  -> revisjon publisert
--   replace   revisjon publisert   -> nyere revisjon publisert
--   withdraw  revisjon publisert   -> ingenting publisert
--   rollback  revisjon publisert   -> tidligere publisert revisjon publisert
--
-- publish dekker både første publisering og ny publisering etter en
-- avpublisering: begge går fra «ingenting publisert» til «denne revisjonen».
-- Skillet mellom replace og rollback er retningen i revisjonshistorikken, og det
-- er håndhevet deklarativt av speilkolonnene under.
create type knowledge.publication_action as enum (
  'publish',
  'replace',
  'withdraw',
  'rollback'
);

comment on type knowledge.publication_action is
  'Tilstandsovergangen en publiseringshendelse registrerer (DATABASE_ARCHITECTURE.md §39). publish går fra ingenting publisert til en publisert revisjon, replace framover til en nyere revisjon, rollback tilbake til en tidligere publisert revisjon (§40) og withdraw til ingenting publisert. En rollback sletter ikke den problematiske publiseringen; den er en ny hendelse.';

-- Hvorfor ingen egen «avpublisert»-status noe sted: livssyklusen skal ikke
-- skjules i et muterbart statusfelt (DATABASE_ARCHITECTURE.md §15). Etter denne
-- migrasjonen er den avledede livssyklusen i KNOWLEDGE_MODEL.md §20 komplett og
-- kan leses av publiseringspekeren, publiseringshendelsene, verifikasjonene,
-- reviewbeslutningene og retired_at — uten at noen mellomtilstand går tapt.

-- ----------------------------------------------------------------------------
-- 2. Registreringstid eies av databasen også i knowledge
--    (DATABASE_ARCHITECTURE.md §7.3, ANTIDEP_CONSTITUTION.md §14)
--
-- Migrasjon 005 ga databasen eierskap til created_at på de append-only
-- workflow-tabellene etter et reviewfunn, og bandt de kallerstyrte
-- hendelsestidspunktene mot det. De append-only tabellene i knowledge har
-- fortsatt bare en default, og den gjelder bare når kolonnen utelates.
-- Migrasjon 005 dokumenterte gjelden og skrev at den hører hjemme i migrasjonen
-- som rører tabellene neste gang.
--
-- Denne migrasjonen rører dem, og gjelden lukkes her. Regelen er den samme som i
-- workflow: en default gjelder bare når kolonnen utelates, så uten triggeren er
-- created_at en verdi kalleren kan oppgi selv. På rader som ellers ikke kan
-- endres, er registreringstiden det eneste festepunktet mot uavhengig tid, og en
-- oppgitt verdi ville gjort «når ble dette registrert?» til en påstand fra den
-- som skriver framfor en observasjon (ANTIDEP_CONSTITUTION.md §14).
-- knowledge.evidence_assessments.assessed_at bindes mot den, slik verified_at og
-- decided_at er bundet i workflow.
--
-- Hva regelen derimot ikke gjør, og ikke skal se ut som om den gjør:
-- publiseringsgaten bygger ikke sin kontroll av evidensgrunnlaget på en
-- sammenligning av disse tidspunktene. En slik sammenligning ville ikke vært
-- samtidighetssikker uansett hvem som eier verdien, fordi now() er
-- transaksjonens starttidspunkt og ikke committidspunktet. Gaten bruker et
-- avtrykk av selve settet; se avsnitt 5.
--
-- Regelen legges på alle fire append-only tabellene i knowledge. En invariant som
-- holder for én tabell og ikke for søsknene er en invitasjon til å lese feil
-- tidspunkt neste gang, og vaktposten i 080_knowledge_structure_test.sql er
-- formulert uttømmende over schemaet slik at den fanger nye tabeller automatisk.
-- ----------------------------------------------------------------------------
create trigger evidence_items_set_created_at
  before insert on knowledge.evidence_items
  for each row execute function catalog.set_created_at();

create trigger claim_revisions_set_created_at
  before insert on knowledge.claim_revisions
  for each row execute function catalog.set_created_at();

create trigger claim_evidence_links_set_created_at
  before insert on knowledge.claim_evidence_links
  for each row execute function catalog.set_created_at();

create trigger evidence_assessments_set_created_at
  before insert on knowledge.evidence_assessments
  for each row execute function catalog.set_created_at();

-- Hendelsestidspunktet bindes mot det databaseeide referansepunktet, samme
-- invariant som verified_at og decided_at har i workflow. En vurdering kan
-- registreres i etterkant, men ikke dateres til framtiden.
alter table knowledge.evidence_assessments
  add constraint evidence_assessments_assessed_at_not_future_check
  check (assessed_at <= created_at);

comment on column knowledge.evidence_assessments.created_at is
  'Når Antidep registrerte vurderingen. Eies av databasen (catalog.set_created_at()) og er referansepunktet det kallerstyrte assessed_at måles mot.';

-- ----------------------------------------------------------------------------
-- 3. knowledge.publication_events — publiseringshistorikken
--    (DATABASE_ARCHITECTURE.md §39, §40, ANTIDEP_CONSTITUTION.md §13, §14)
--
-- Alle publiseringer og avpubliseringer registreres append-only. Historikken er
-- det som gjør at Antidep i ettertid kan svare på både «hva sier vi nå?» og
-- «hva sa vi på dato X, og hvorfor?» (§40).
--
-- Speilkolonnene revision_number og previous_revision_number finnes for at
-- skillet mellom replace og rollback skal kunne håndheves deklarativt på raden
-- selv. Uten dem ville «en rollback peker bakover i revisjonshistorikken» vært
-- en regel som måtte lese knowledge.claim_revisions, altså en tverradsregel som
-- verken CHECK eller enkel fremmednøkkel kan uttrykke
-- (DATABASE_ARCHITECTURE.md §59). Med speilene låst til revisjonsraden av en
-- sammensatt fremmednøkkel blir den en radlokal CHECK. Samme mønster som
-- speilkolonnene i migrasjon 004 og 005.
--
-- previous_event_id er ikke i §39 sitt minimum og er lagt til med to konkrete
-- formål. Det gjør historikken til en kjede som kan gås bakover uten å sortere
-- på tid, og det er det deklarative samtidighetsvernet: se kommentaren på
-- unikhetsregelen under.
--
-- Bevisst utelatt: en kolonne for «hvem ba om publiseringen» ved siden av hvem
-- som utførte den. Den skiller først når admin-flyten har en køfunksjon, og kan
-- legges til uten å endre modellen her.
-- ----------------------------------------------------------------------------

-- Gjør (id, claim_id, revision_number) refererbar, slik at speilkolonnene på
-- hendelsen kan låses til både riktig påstand og riktig revisjonsnummer i én
-- fremmednøkkel.
alter table knowledge.claim_revisions
  add constraint claim_revisions_id_claim_number_key
  unique (id, claim_id, revision_number);

create table knowledge.publication_events (
  id uuid primary key default gen_random_uuid(),

  claim_id uuid not null
    references knowledge.claims (id) on update restrict on delete restrict,

  action knowledge.publication_action not null,

  -- Hva som er publisert etter hendelsen. NULL betyr at ingenting er publisert,
  -- altså etter en avpublisering.
  revision_id uuid,
  revision_number integer,

  -- Hva som var publisert før hendelsen. NULL betyr at ingenting var publisert.
  previous_revision_id uuid,
  previous_revision_number integer,

  -- Forrige hendelse for den samme påstanden. NULL bare på den aller første.
  previous_event_id uuid
    references knowledge.publication_events (id) on update restrict on delete restrict,

  published_by_actor_id uuid not null
    references provenance.actors (id) on update restrict on delete restrict,
  published_by_actor_type provenance.actor_type not null,

  reason text not null,
  published_at timestamptz not null,
  created_at timestamptz not null default now(),

  object_type knowledge.publication_object_type
    generated always as ('claim'::knowledge.publication_object_type) stored,

  -- Speilene er låst til revisjonsradene, og fremmednøklene binder dem i tillegg
  -- til den påstanden hendelsen gjelder. En hendelse kan derfor ikke peke på en
  -- revisjon av en annen påstand — invarianten DATABASE_ARCHITECTURE.md §58
  -- kaller «publiseringspeker peker på revisjon av riktig identity», her på
  -- historikken framfor på pekeren.
  --
  -- MATCH SIMPLE gjør at en NULL slår av kravet, hvilket er riktig: en
  -- avpublisering har ingen etterfølgende revisjon, og en førstegangspublisering
  -- ingen forutgående.
  constraint publication_events_revision_pairing_check
    check ((revision_id is null) = (revision_number is null)),
  constraint publication_events_previous_revision_pairing_check
    check ((previous_revision_id is null) = (previous_revision_number is null)),
  constraint publication_events_revision_fkey
    foreign key (revision_id, claim_id, revision_number)
    references knowledge.claim_revisions (id, claim_id, revision_number)
    on update restrict on delete restrict,
  constraint publication_events_previous_revision_fkey
    foreign key (previous_revision_id, claim_id, previous_revision_number)
    references knowledge.claim_revisions (id, claim_id, revision_number)
    on update restrict on delete restrict,

  -- Forrige hendelse må gjelde den samme påstanden. Den sammensatte
  -- fremmednøkkelen peker tilbake på tabellen selv, og unikhetsregelen den
  -- trenger står rett over den.
  constraint publication_events_id_claim_key unique (id, claim_id),
  constraint publication_events_previous_event_fkey
    foreign key (previous_event_id, claim_id)
    references knowledge.publication_events (id, claim_id)
    on update restrict on delete restrict,

  -- Samtidighetsvernet, og det er deklarativt (DATABASE_ARCHITECTURE.md §57, §61).
  --
  -- Hver hendelse navngir hendelsen den følger etter. To hendelser for samme
  -- påstand kan derfor ikke ha samme forgjenger: historikken er en kjede uten
  -- forgreninger. To samtidige publiseringer av samme påstand leser den samme
  -- tilstanden, beregner den samme forgjengeren og skriver den samme verdien —
  -- og den andre avvises av unikhetsregelen framfor å legge igjen en andre
  -- «gjeldende» revisjon. NULLS NOT DISTINCT er nødvendig fordi nettopp
  -- førstegangspubliseringen har NULL som forgjenger, og to NULL-er ville ellers
  -- ikke kollidert.
  --
  -- Regelen holder også for ny publisering etter en avpublisering: den hendelsen
  -- har avpubliseringen som forgjenger, ikke NULL, og kolliderer derfor ikke med
  -- den opprinnelige førstegangspubliseringen.
  --
  -- Publiseringsfunksjonene tar i tillegg radlås på påstanden, slik at den andre
  -- transaksjonen venter og deretter ser den nye tilstanden framfor å feile. Låsen
  -- gir riktig oppførsel; unikhetsregelen gjør feil oppførsel umulig.
  constraint publication_events_no_forked_history_key
    unique nulls not distinct (claim_id, previous_event_id),

  -- Hver handling er en bestemt tilstandsovergang, og hvilke pekere som skal
  -- være satt følger av den. Regelen er uttømmende over vokabularet, slik at en
  -- ny handling ikke kan legges til uten at det tas stilling til hva pekeren
  -- skal peke på etterpå.
  constraint publication_events_action_pointer_check
    check (
      case action
        when 'publish' then revision_id is not null and previous_revision_id is null
        when 'replace' then revision_id is not null and previous_revision_id is not null
                             and revision_number > previous_revision_number
        when 'withdraw' then revision_id is null and previous_revision_id is not null
        when 'rollback' then revision_id is not null and previous_revision_id is not null
                              and revision_number < previous_revision_number
        -- En handling regelen ikke kjenner, er ikke en tilstandsovergang noen har
        -- tatt stilling til. Uten denne grenen ville CASE gitt NULL for en ny
        -- enum-verdi, og en NULL passerer en CHECK — regelen ville stilltiende
        -- sluttet å gjelde for nettopp den handlingen som er ny.
        else false
      end
    ),

  -- Den aller første hendelsen for en påstand må være en publisering: det finnes
  -- ingenting å erstatte, rulle tilbake eller trekke tilbake før den.
  constraint publication_events_first_event_is_publish_check
    check (previous_event_id is not null or action = 'publish'),

  -- Publisering utføres av et menneske. Aktørtypen er speilet av aktørraden og
  -- låst av den sammensatte fremmednøkkelen, slik at kravet er strukturelt og
  -- ikke en konvensjon. MVP_IMPLEMENTATION_PLAN.md §49: en ekstraksjonsagent
  -- skal ikke kunne publisere — her finnes det ingen skrivevei der den kan.
  constraint publication_events_publisher_fkey
    foreign key (published_by_actor_id, published_by_actor_type)
    references provenance.actors (id, actor_type)
    on update restrict on delete restrict,
  constraint publication_events_publisher_is_human_check
    check (published_by_actor_type = 'human'),

  -- Publiseringstidspunktet er kallerstyrt og created_at databaseeid, med samme
  -- binding som verified_at og decided_at har i workflow: en hendelse kan
  -- registreres i etterkant, men ikke dateres til framtiden.
  constraint publication_events_published_at_not_future_check
    check (published_at <= created_at),

  constraint publication_events_reason_check
    check (reason = btrim(reason) and length(reason) between 1 and 2000)
);

comment on table knowledge.publication_events is
  'Append-only historikk over hver publisering og avpublisering (DATABASE_ARCHITECTURE.md §39). Sammen med publiseringspekeren på knowledge.claims gjør den det mulig å svare både på hva Antidep sier nå og på hva Antidep sa på et tidligere tidspunkt, og hvorfor. En rollback sletter ingenting; den er en ny hendelse som flytter pekeren tilbake (§40). Raden kan verken endres eller slettes etter innsetting.';
comment on column knowledge.publication_events.claim_id is
  'Påstanden hendelsen gjelder. Ekte fremmednøkkel framfor en generisk object_id, slik at referansen er noe databasen kan garantere (DATABASE_ARCHITECTURE.md §37, §57).';
comment on column knowledge.publication_events.action is
  'Tilstandsovergangen hendelsen registrerer. Bestemmer hvilke pekere som skal være satt, håndhevet av publication_events_action_pointer_check.';
comment on column knowledge.publication_events.revision_id is
  'Revisjonen som er publisert etter hendelsen, eller NULL når ingenting er publisert etter den. Verdien skal til enhver tid stemme med knowledge.claims.current_published_revision_id for den siste hendelsen på påstanden.';
comment on column knowledge.publication_events.revision_number is
  'Speil av revisjonsnummeret, låst av den sammensatte fremmednøkkelen. Finnes for at skillet mellom replace framover og rollback bakover skal kunne håndheves deklarativt på raden selv. Ikke en selvstendig sannhet.';
comment on column knowledge.publication_events.previous_revision_id is
  'Revisjonen som var publisert før hendelsen, eller NULL når ingenting var publisert. §39 sitt previous_revision_id.';
comment on column knowledge.publication_events.previous_revision_number is
  'Speil av revisjonsnummeret på den forrige publiserte revisjonen, med samme formål og samme låsing som revision_number.';
comment on column knowledge.publication_events.previous_event_id is
  'Hendelsen denne følger etter for den samme påstanden. NULL bare på den første hendelsen. Gjør historikken til en kjede uten forgreninger, og er samtidighetsvernet: to samtidige publiseringer ville skrevet den samme forgjengeren og kollidert.';
comment on column knowledge.publication_events.published_by_actor_id is
  'Aktøren som utførte publiseringen. Må være et menneske med gyldig publisher-rolle; kravet håndheves av publiseringsfunksjonene og av speilkolonnen under (ANTIDEP_CONSTITUTION.md §14, MVP_IMPLEMENTATION_PLAN.md §49).';
comment on column knowledge.publication_events.published_by_actor_type is
  'Speil av aktørtypen, låst av den sammensatte fremmednøkkelen og begrenset til human av en CHECK. Gjør det strukturelt umulig at en KI-aktør står oppført som den som publiserte.';
comment on column knowledge.publication_events.reason is
  'Hvorfor handlingen ble utført. Alltid utfylt: en publisering eller avpublisering uten begrunnelse er ikke etterprøvbar (ANTIDEP_CONSTITUTION.md §14).';
comment on column knowledge.publication_events.published_at is
  'Når publiseringen fant sted (DATABASE_ARCHITECTURE.md §7.3). Et hendelsestidspunkt, ikke registreringstidspunktet for raden; det siste er created_at. Kan ligge før created_at, men aldri etter.';
comment on column knowledge.publication_events.created_at is
  'Når Antidep registrerte hendelsen. Eies av databasen (catalog.set_created_at()) og er referansepunktet det kallerstyrte published_at måles mot.';
comment on column knowledge.publication_events.object_type is
  'Avledet av at hendelsen gjelder en påstand. Gir §39 sitt object_type som lesbart felt uten at det kan si noe annet enn fremmednøkkelen gjør.';

-- «Hva sa vi om denne påstanden, og når?» er hovedoppslaget mot historikken.
create index publication_events_claim_published_at_idx
  on knowledge.publication_events (claim_id, published_at desc);
-- «Har denne revisjonen noen gang vært publisert?» — brukes av forseglingen
-- under og av rollback-kontrollen.
create index publication_events_revision_id_idx
  on knowledge.publication_events (revision_id);
create index publication_events_published_by_actor_id_idx
  on knowledge.publication_events (published_by_actor_id);

create trigger publication_events_set_created_at
  before insert on knowledge.publication_events
  for each row execute function catalog.set_created_at();

-- Ingen normal DELETE på kanonisk historikk (DATABASE_ARCHITECTURE.md §36).
-- En feilaktig publisering rettes ved en ny hendelse, ikke ved at den gamle
-- fjernes; det er nettopp det §40 slår fast om rollback.
create trigger publication_events_reject_mutation
  before update or delete on knowledge.publication_events
  for each row execute function knowledge.reject_append_only_mutation(
    'Registrer en ny publiseringshendelse. En rollback eller avpublisering er ny historikk og skal aldri fjerne den hendelsen den korrigerer (DATABASE_ARCHITECTURE.md §40).'
  );

-- ----------------------------------------------------------------------------
-- 4. Publisering forsegler evidensgrunnlaget
--    (KNOWLEDGE_MODEL.md §19.2, DATABASE_ARCHITECTURE.md §7.1)
--
-- Migrasjon 004 forseglet evidenssettet ved evidensvurderingen: etter at en
-- revisjon har fått sin vurdering, kan den ikke få flere lenker, fordi
-- vurderingen ellers ville beskrevet et annet grunnlag enn det som står
-- registrert. Et deterministisk faktum får ingen evidensvurdering og er derfor
-- uforseglet av den regelen. Kommentaren i 004 sier eksplisitt at publisering er
-- forseglingen for den typen, og at migrasjon 006 uansett må hindre at en
-- publisert revisjon får nye lenker.
--
-- Regelen her er formulert på hele publiseringshistorikken og ikke bare på
-- pekeren: en revisjon som *har vært* publisert forblir forseglet også etter at
-- den er erstattet eller avpublisert. Ellers ville «hva sa vi på dato X, og
-- hvorfor?» (§40) kunne besvares med et evidensgrunnlag som ikke fantes den
-- gangen.
--
-- Cross-row-regel som ikke kan uttrykkes deklarativt: en CHECK kan ikke lese en
-- annen tabell (§59), og en fremmednøkkel kan kreve at en rad finnes, ikke at
-- den ikke finnes. Dette er en av tverradsinvariantene §60 navngir som legitim
-- triggerbruk.
--
-- Samtidighet og låserekkefølge: revisjonsraden låses med FOR UPDATE før
-- kontrollen, slik at en publisering ikke kan commite i vinduet mellom
-- kontrollen og innsettingen. Publiseringsfunksjonene tar de samme to låsene i
-- rekkefølgen påstand, deretter revisjon; denne triggeren og forseglingen fra
-- migrasjon 004 tar bare revisjonslåsen. Ingen kodevei tar dem i motsatt
-- rekkefølge, så låsene kan ikke danne en syklus.
-- ----------------------------------------------------------------------------
create function knowledge.reject_evidence_link_after_publication()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  perform 1
  from knowledge.claim_revisions r
  where r.id = new.claim_revision_id
  for update;

  if exists (
    select 1
    from knowledge.publication_events e
    where e.revision_id = new.claim_revision_id
  ) then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Revisjon %L har vært publisert, og evidensgrunnlaget er forseglet.',
        new.claim_revision_id
      ),
      hint = 'Opprett en ny revisjon av påstanden med det fullstendige evidenssettet, og publiser den. Grunnlaget under en revisjon som har vært publisert skal aldri endres i ettertid, slik at det alltid er mulig å rekonstruere hva Antidep sa på et gitt tidspunkt og hva det hvilte på.';
  end if;

  return new;
end;
$$;

comment on function knowledge.reject_evidence_link_after_publication() is
  'Tverradsinvariant: hindrer at evidenssettet til en påstandsrevisjon utvides etter at revisjonen har vært publisert. Supplerer forseglingen ved evidensvurderingen fra migrasjon 004, som ikke omfatter deterministiske fakta, og gjelder også etter at revisjonen er erstattet eller avpublisert.';

revoke execute on function knowledge.reject_evidence_link_after_publication() from public;

create trigger claim_evidence_links_reject_after_publication
  before insert on knowledge.claim_evidence_links
  for each row execute function knowledge.reject_evidence_link_after_publication();

-- ----------------------------------------------------------------------------
-- 5. Godkjenningen bindes til det evidenssettet den faktisk gjaldt
--    (KNOWLEDGE_MODEL.md §19.2, ANTIDEP_CONSTITUTION.md §12,
--     DATABASE_ARCHITECTURE.md §38, §61)
--
-- Kravet er at en publisering ikke skal kunne hvile på et annet evidensgrunnlag
-- enn det godkjenningen ble gitt for (MVP_IMPLEMENTATION_PLAN.md §42: «review av
-- en revisjon som senere er endret uten nytt review»).
--
-- Hvorfor dette ikke kan løses med tidsstempler:
--
--   Den nærliggende regelen — «ingen evidenslenke registrert etter
--   godkjenningstidspunktet» — er ikke samtidighetssikker. now() er
--   transaksjonens starttidspunkt, ikke committidspunktet. En transaksjon som
--   registrerer en lenke kan derfor starte før godkjenningen, commite etter den,
--   og likevel bære en created_at som ligger foran decided_at. Reviewer kan
--   umulig ha sett lenken, men en tidssammenligning ville sagt at
--   godkjenningen dekker den. clock_timestamp() hjelper ikke: også den måler når
--   raden ble skrevet, ikke når den ble synlig for andre. Det er commitrekkefølgen
--   som avgjør hva reviewer kunne se, og den er ikke lesbar fra radene.
--
-- Løsningen er derfor ikke en tidsregel, men et avtrykk av selve settet.
-- Godkjenningen bærer et fingeravtrykk av evidenssettet slik det var da
-- beslutningen ble registrert, og publiseringsgaten beregner avtrykket på nytt
-- fra det settet som faktisk finnes ved publisering. Avviker de, nektes
-- publisering — uansett hvilken rekkefølge transaksjonene startet, commitet eller
-- ble datert i. Regelen er dermed uavhengig av tid, og det er hele poenget.
--
-- Publisering og lenkeregistrering serialiseres i tillegg av radlåsen på
-- revisjonen (avsnitt 4 og 8), slik at en lenke ikke kan commite i vinduet mellom
-- at gaten beregner avtrykket og at publiseringen commiter.
--
-- Det som ikke lukkes her, og som ikke skal se ut som om det er lukket: en lenke
-- som commiter mellom at reviewer leste skjermbildet og at beslutningen ble
-- skrevet, havner i avtrykket. Databasen kan ikke vite hva reviewer faktisk så —
-- bare hva som var registrert da beslutningen ble lagret. Den siste luken lukkes
-- når admin-flyten kan oppgi avtrykket den viste reviewer, og kolonnen er
-- utformet for å kunne ta imot det: den er en verdi om beslutningen, ikke en
-- avledning av nåtilstanden.
-- ----------------------------------------------------------------------------
create function knowledge.claim_evidence_set_digest(p_claim_revision_id uuid)
  returns text
  language sql
  stable
  set search_path = ''
as $$
  -- Samme lengdeprefiksede kanonisering og versjonerte prefiks som
  -- content_hash i migrasjon 003 og 004: «lengde:verdi», og «~» skiller NULL fra
  -- tom streng. Sorteringen på id gjør avtrykket uavhengig av innsettingsrekkefølge.
  --
  -- Avtrykket dekker lenkenes identitet og ikke innholdet deres. Lenkene er
  -- append-only og uforanderlige, så et endret sett er alltid et endret sett av
  -- id-er. En ren telling ville dekket det samme så lenge lenker bare kan komme
  -- til, men ikke overlevd den unntaksvise vedlikeholdsveien
  -- DATABASE_ARCHITECTURE.md §36 åpner for, der en feilopprettet rad slettes
  -- fysisk: da ville sletting pluss innsetting holdt tellingen uendret og endret
  -- settet.
  select 'sha256-v1:' || encode(
    sha256(convert_to(
      coalesce(
        (select string_agg('|' || length(l.id::text)::text || ':' || l.id::text,
                           '' order by l.id::text)
         from knowledge.claim_evidence_links l
         where l.claim_revision_id = p_claim_revision_id),
        '|~:'
      ),
      'UTF8'
    )),
    'hex'
  );
$$;

comment on function knowledge.claim_evidence_set_digest(uuid) is
  'Fingeravtrykk av evidenssettet til én påstandsrevisjon. Brukes til å binde en godkjenning til det grunnlaget den ble gitt for, slik at publiseringsgaten kan oppdage at settet er endret uten å måtte sammenligne tidsstempler — en sammenligning som ikke er samtidighetssikker, fordi now() er transaksjonens starttidspunkt og ikke committidspunktet. Et tomt sett har sitt eget avtrykk og kan ikke forveksles med en manglende verdi.';

revoke execute on function knowledge.claim_evidence_set_digest(uuid) from public;

-- Kolonnen ligger på beslutningen fordi det er beslutningen som gjelder et
-- bestemt grunnlag. En avledning fra nåtilstanden ville ikke kunnet svare på hva
-- reviewer sa ja til.
alter table workflow.review_decisions
  add column approved_evidence_set_digest text;

comment on column workflow.review_decisions.approved_evidence_set_digest is
  'Fingeravtrykk av evidenssettet til revisjonen slik det var registrert da beslutningen ble lagret. Publiseringsgaten sammenligner det med settet ved publisering og nekter dersom grunnlaget er endret (KNOWLEDGE_MODEL.md §19.2). Erstatter en tidssammenligning, som ikke er samtidighetssikker. Bare på publiseringsgodkjenninger; en tilbaketrekking av en ekstraksjon gjelder ikke et lenkesett.';

alter table workflow.review_decisions
  add constraint review_decisions_evidence_digest_pairing_check
  check ((approved_evidence_set_digest is not null) = (review_type = 'publication_approval'));

alter table workflow.review_decisions
  add constraint review_decisions_evidence_digest_format_check
  check (approved_evidence_set_digest is null
         or approved_evidence_set_digest ~ '^sha256-v[0-9]+:[0-9a-f]{64}$');

-- Avtrykket eies av databasen, som created_at. Var det kallerstyrt, kunne den som
-- registrerer godkjenningen oppgi avtrykket av et annet sett enn det som fantes,
-- og gaten ville sammenlignet mot et tall den kontrollerte parten selv valgte.
--
-- SECURITY DEFINER av samme grunn som kvalifikasjonskontrollen ved siden av:
-- knowledge.claim_evidence_links har RLS og default deny, og avtrykket må kunne
-- beregnes uavhengig av hvem som skriver beslutningen. Funksjonen har tomt
-- search_path, schemakvalifiserte navn, er ikke kjørbar for PUBLIC, og skriver
-- bare til raden som settes inn (DATABASE_ARCHITECTURE.md §50).
create function workflow.set_review_evidence_set_digest()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if new.review_type = 'publication_approval' then
    -- Radlås på revisjonen, av samme grunn som forseglingstriggerne i migrasjon
    -- 004 og avsnitt 4: uten den kunne en lenke commite mellom beregningen og
    -- commit, og avtrykket ville beskrevet et sett som aldri fantes samtidig.
    perform 1
    from knowledge.claim_revisions r
    where r.id = new.claim_revision_id
    for update;

    new.approved_evidence_set_digest :=
      knowledge.claim_evidence_set_digest(new.claim_revision_id);
  else
    new.approved_evidence_set_digest := null;
  end if;

  return new;
end;
$$;

comment on function workflow.set_review_evidence_set_digest() is
  'Gir databasen eierskap til fingeravtrykket av evidenssettet en publiseringsgodkjenning gjelder, og låser revisjonsraden mens det beregnes slik at settet ikke kan endres i vinduet. SECURITY DEFINER fordi evidenslenkene ligger bak RLS med default deny; funksjonen leser bare og skriver bare til raden som settes inn.';

revoke execute on function workflow.set_review_evidence_set_digest() from public;

-- Navnet er valgt slik at triggeren fyrer etter kvalifikasjonskontrollen og før
-- catalog.set_created_at(); rekkefølgen er alfabetisk, og ingen av dem avhenger
-- av de andres resultat.
create trigger review_decisions_set_evidence_set_digest
  before insert on workflow.review_decisions
  for each row execute function workflow.set_review_evidence_set_digest();

-- ----------------------------------------------------------------------------
-- 6. Publiseringsgaten (DATABASE_ARCHITECTURE.md §38, §58)
--
-- §38 lister eksplisitt hva operasjonen skal kontrollere for en
-- evidence_synthesis. Hvert punkt er tatt stilling til, og ingen er stille
-- utelatt:
--
--   claim-revisjonen finnes                  håndheves (G1)
--   revisjonen er immutable og komplett      håndheves (G2), se under
--   nødvendige EvidenceItems finnes          håndheves (G3)
--   relevante EvidenceItems er verifisert    håndheves (G4, G5)
--   ClaimEvidenceLinks er kontrollert        håndheves (G8, G9)
--   EvidenceAssessment finnes                håndheves (G10)
--   ingen blokkerende verifikasjonsfunn åpne håndheves (G5, G6, G7, G9)
--   nødvendig menneskelig review er godkjent håndheves (G11, G12)
--   review ikke er utløpt                    delvis håndhevet (G13), delvis utsatt
--
-- G13 er samtidighetssikker og bygger ikke på tidsstempler; se avsnitt 5.
--
-- «Immutable og komplett»: immutabiliteten er strukturell og trenger ingen
-- kontroll her — knowledge.claim_revisions er append-only, og en revisjon kan
-- ikke endres etter innsetting. Kompletthet håndheves av NOT NULL og CHECK i
-- migrasjon 004 ved innsetting, blant annet kravet om eksplisitt
-- usikkerhetstekst for evidenssynteser og kliniske anbefalinger
-- (ANTIDEP_CONSTITUTION.md §6). Det gaten legger til er tilstanden rundt
-- revisjonen: en revisjon av en tilbaketrukket påstand er ikke publiserbar
-- (G2).
--
-- «Review ikke er utløpt» er delt i to. Den delen som kan kontrolleres nå, er at
-- godkjenningen fortsatt er den gjeldende beslutningen (G12) og at
-- evidensgrunnlaget er det samme som godkjenningen ble gitt for (G13) — som er
-- den kritiske negative testen i MVP_IMPLEMENTATION_PLAN.md §42 om «review av en
-- revisjon som senere er endret uten nytt review». G13 sammenligner avtrykk og
-- ikke tidspunkter, nettopp fordi en tidssammenligning ikke er
-- samtidighetssikker (avsnitt 5). Den delen som er utsatt, er
-- tidsbasert utløp: KNOWLEDGE_MODEL.md §20.5 og DATABASE_ARCHITECTURE.md §7.3
-- forutsetter et review_due_at, og §15 nevner workflow.review_requirements.
-- Ingen av delene finnes, og en frist kan ikke utledes av dataene som finnes:
-- hvor lenge en godkjenning er gyldig avhenger av kunnskapstype og risiko, og
-- det er en klinisk policybeslutning, ikke en implementasjonsdetalj. Å velge et
-- tall her ville vært å oppfinne den policyen. Kontrollen hører derfor til
-- migrasjonen som innfører review-kravobjektet, og gaten er skrevet slik at det
-- blir ett nytt punkt i denne funksjonen.
--
-- Kunnskapstypene har ulike terskler (ANTIDEP_CONSTITUTION.md §5,
-- KNOWLEDGE_MODEL.md §21):
--
--   deterministic_fact       alle punkter unntatt evidensvurderingen, som
--                            migrasjon 004 ikke tillater for typen
--   evidence_synthesis       alle punkter
--   clinical_recommendation  alle punkter
--
-- DATABASE_ARCHITECTURE.md §38 krever at terskelen for en clinical_recommendation
-- er «minst like streng» som for en evidence_synthesis. Den er nøyaktig like
-- streng, og det er et bevisst valg framfor en teknisk forskjell som ikke er
-- definert som policy noe sted.
--
-- KNOWLEDGE_MODEL.md §21 skiller mellom «ja» og «ja, eksplisitt» for menneskelig
-- godkjenning. «Eksplisitt» forstås her som at en navngitt kvalifisert redaktør
-- uttrykkelig godkjenner den konkrete revisjonen for publisering — ikke som et
-- krav om en egen temaavgrenset reviewer-tildeling. Modellen gir allerede det
-- første: en godkjenning peker på en eksakt revisjon, kommer fra et navngitt
-- menneske med gyldig reviewer-rolle, og kan ikke gis av den som skrev
-- revisjonen (migrasjon 005).
--
-- Scoped reviewer-roller respekteres fortsatt, men det kravet ligger der det
-- hører hjemme: workflow.enforce_reviewer_qualification() krever at en
-- tildeling som *er* avgrenset til et klinisk tema dekker påstandens tema. En
-- tildeling uten scope betyr generell reviewer-kompetanse, ikke utilstrekkelig
-- godkjenning. Reglene er dermed de samme for alle tre kunnskapstypene, og
-- kontrollen skjer når beslutningen registreres framfor å gjentas her.
--
-- Skulle særskilt spesialist- eller temakompetanse for kliniske anbefalinger bli
-- ønsket senere, skal det først defineres eksplisitt som policy i de styrende
-- dokumentene og deretter håndheves — ikke utledes av gaten.
--
-- Menneskelig godkjenning kreves også for deterministic_fact i dette steget.
-- KNOWLEDGE_MODEL.md §21 åpner for at et enkeltdatapunkt fra en autoritativ
-- strukturert kilde ikke nødvendigvis trenger egen godkjenning «dersom importen
-- som system er validert». Den forutsetningen er ikke innfridd: det finnes
-- ingen import, ingen ingest-karantene og ingen validert importvei
-- (migrasjon 009). Unntaket hører derfor til den migrasjonen, og fram til da er
-- den strengere regelen både den ærlige og den trygge.
--
-- Funksjonen er SECURITY INVOKER med tomt search_path. Den leser tabeller i
-- workflow som har RLS og default deny, og kalles fra de SECURITY DEFINER-eide
-- publiseringsfunksjonene under — der kjører den med definerens rettigheter og
-- får lest det den skal. Kalles den derimot direkte av noen andre, kjører den
-- med den kallerens rettigheter og kan ikke lekke noe kalleren ikke allerede
-- kunne lese. Det holder DEFINER-flaten så liten som mulig
-- (DATABASE_ARCHITECTURE.md §50).
--
-- Funksjonen returnerer ingenting og kan bare avvise. Feilmeldingene navngir det
-- konkrete objektet som blokkerer, slik at admin-flyten kan vise hvorfor et steg
-- er blokkert framfor bare at det er det (MVP_IMPLEMENTATION_PLAN.md §15).
-- ----------------------------------------------------------------------------
create function knowledge.assert_claim_revision_publishable(p_claim_revision_id uuid)
  returns void
  language plpgsql
  set search_path = ''
as $$
declare
  v_claim_id uuid;
  v_knowledge_type knowledge.knowledge_type;
  v_retired_at timestamptz;
  v_offenders text;
  v_latest_decision workflow.review_outcome;
  v_approved_digest text;
begin
  -- G1: revisjonen finnes.
  select r.claim_id, r.knowledge_type, c.retired_at
    into v_claim_id, v_knowledge_type, v_retired_at
  from knowledge.claim_revisions r
  join knowledge.claims c on c.id = r.claim_id
  where r.id = p_claim_revision_id;

  if not found then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = format('Påstandsrevisjon %L finnes ikke.', p_claim_revision_id),
      hint = 'Publisering peker på en eksakt revisjon, ikke på påstandsidentiteten (KNOWLEDGE_MODEL.md §19.3). Kontroller revisjons-ID-en.';
  end if;

  -- G2: påstanden er ikke trukket tilbake.
  if v_retired_at is not null then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Påstanden bak revisjon %L er trukket tilbake og kan ikke publiseres.',
        p_claim_revision_id
      ),
      hint = 'En tilbaketrukket påstand er tatt ut av bruk. Opprett en ny påstand dersom temaet fortsatt skal dekkes; historikken til den gamle bevares (DATABASE_ARCHITECTURE.md §36).';
  end if;

  -- G3: nødvendige EvidenceItems finnes.
  -- ANTIDEP_CONSTITUTION.md §4: ingen publisert klinisk relevant påstand skal
  -- eksistere uten eksplisitt kobling til én eller flere identifiserbare kilder.
  -- Kravet gjelder alle tre kunnskapstypene; også et deterministisk faktum skal
  -- kunne spores til kilden sin.
  if not exists (
    select 1
    from knowledge.claim_evidence_links l
    where l.claim_revision_id = p_claim_revision_id
  ) then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Revisjon %L har ingen registrerte evidenslenker og kan ikke publiseres.',
        p_claim_revision_id
      ),
      hint = 'Registrer minst ett evidensfunn med en begrunnet relasjon til revisjonen. En publisert påstand uten kobling til en identifiserbar kilde er ikke etterprøvbar (ANTIDEP_CONSTITUTION.md §4).';
  end if;

  -- G4: hvert lenket evidensfunn er faktisk kontrollert av noen.
  select string_agg(distinct l.evidence_item_id::text, ', ' order by l.evidence_item_id::text)
    into v_offenders
  from knowledge.claim_evidence_links l
  where l.claim_revision_id = p_claim_revision_id
    and not exists (
      select 1
      from workflow.evidence_verifications ev
      where ev.evidence_item_id = l.evidence_item_id
    );

  if v_offenders is not null then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Evidensfunn uten registrert ekstraksjonsverifikasjon: %s.', v_offenders
      ),
      hint = 'En separat kontrollfase skal ha gått gjennom ekstraksjonen mot kildematerialet før påstanden publiseres (ANTIDEP_CONSTITUTION.md §11, DATABASE_ARCHITECTURE.md §29). Registrer verifikasjonen i workflow.evidence_verifications.';
  end if;

  -- G5: den gjeldende ekstraksjonsverifikasjonen bekrefter funnet.
  -- Den siste kontrollen er den gjeldende: et senere needs_correction, rejected
  -- eller uncertain er et åpent blokkerende verifikasjonsfunn, uansett hvor mange
  -- bekreftelser som ligger foran det.
  select string_agg(distinct l.evidence_item_id::text, ', ' order by l.evidence_item_id::text)
    into v_offenders
  from knowledge.claim_evidence_links l
  where l.claim_revision_id = p_claim_revision_id
    and (
      select ev.outcome
      from workflow.evidence_verifications ev
      where ev.evidence_item_id = l.evidence_item_id
      order by ev.verified_at desc, ev.created_at desc, ev.id desc
      limit 1
    ) <> 'verified';

  if v_offenders is not null then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Evidensfunn med åpent verifikasjonsfunn: %s.', v_offenders
      ),
      hint = 'Den siste registrerte ekstraksjonsverifikasjonen konkluderer ikke med verified. Rett ekstraksjonen i et nytt evidensfunn og registrer en ny kontroll; en tidligere bekreftelse opphever ikke et senere avvik.';
  end if;

  -- G6: ingen lenket ekstraksjon er trukket tilbake.
  -- Overlevert eksplisitt fra migrasjon 005: «er dette evidensfunnet trukket
  -- tilbake?» er ikke en statuskolonne, men en avledet tilstand — den siste
  -- beslutningen av typen extraction_withdrawal for funnet.
  select string_agg(distinct l.evidence_item_id::text, ', ' order by l.evidence_item_id::text)
    into v_offenders
  from knowledge.claim_evidence_links l
  where l.claim_revision_id = p_claim_revision_id
    and (
      select rd.decision
      from workflow.review_decisions rd
      where rd.evidence_item_id = l.evidence_item_id
        and rd.review_type = 'extraction_withdrawal'
      order by rd.decided_at desc, rd.created_at desc, rd.id desc
      limit 1
    ) = 'extraction_withdrawn';

  if v_offenders is not null then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Evidensfunn med tilbaketrukket ekstraksjon: %s.', v_offenders
      ),
      hint = 'En tilbaketrukket ekstraksjon skal ikke bære en publisert påstand. Opprett en ny revisjon uten det tilbaketrukne funnet, eller registrer en ny beslutning som opprettholder ekstraksjonen dersom tilbaketrekkingen var feil (DATABASE_ARCHITECTURE.md §29).';
  end if;

  -- G7: ingen lenket kilde er trukket tilbake eller tilbakekalt.
  -- DATABASE_ARCHITECTURE.md §58, siste kulepunkt: en withdrawn eller retracted
  -- kilde skal ikke ubemerket tilfredsstille en gate som om statusen var normal.
  select string_agg(distinct s.id::text, ', ' order by s.id::text)
    into v_offenders
  from knowledge.claim_evidence_links l
  join knowledge.evidence_items e on e.id = l.evidence_item_id
  join knowledge.sources s on s.id = e.source_id
  where l.claim_revision_id = p_claim_revision_id
    and s.source_status in ('retracted', 'withdrawn');

  if v_offenders is not null then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Kilder med statusen retracted eller withdrawn i grunnlaget: %s.', v_offenders
      ),
      hint = 'En tilbaketrukket eller tilbakekalt kilde kan ikke bære en publisert påstand. Vurder grunnlaget på nytt i en ny revisjon (DATABASE_ARCHITECTURE.md §58).';
  end if;

  -- G8: påstanden er kontrollert mot grunnlaget.
  -- DATABASE_ARCHITECTURE.md §38 sitt «ClaimEvidenceLinks er kontrollert» er
  -- nettopp claim-verifikasjonen fra §30: den kontrollerer om grunnlaget faktisk
  -- støtter ordlyden, om populasjon, komparator, tidsramme, retning og størrelse
  -- stemmer, om vesentlige forbehold mangler og om motstridende evidens er
  -- representert. Migrasjon 005 håndhever allerede at en verifikasjon ikke kan
  -- konkludere med verified uten at alle sju punktene er bedømt og holder.
  if not exists (
    select 1
    from workflow.claim_verifications cv
    where cv.claim_revision_id = p_claim_revision_id
  ) then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Revisjon %L har ingen registrert claim-verifikasjon.', p_claim_revision_id
      ),
      hint = 'En separat kontrollfase skal ha forsøkt å falsifisere påstanden mot det registrerte grunnlaget før den publiseres (ANTIDEP_CONSTITUTION.md §11, DATABASE_ARCHITECTURE.md §30). Registrer kontrollen i workflow.claim_verifications.';
  end if;

  -- G9: den gjeldende claim-verifikasjonen bekrefter påstanden.
  if (
    select cv.outcome
    from workflow.claim_verifications cv
    where cv.claim_revision_id = p_claim_revision_id
    order by cv.verified_at desc, cv.created_at desc, cv.id desc
    limit 1
  ) <> 'verified' then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Den gjeldende claim-verifikasjonen for revisjon %L konkluderer ikke med verified.',
        p_claim_revision_id
      ),
      hint = 'Den siste registrerte kontrollen er den gjeldende. Rett påstanden i en ny revisjon og få den kontrollert på nytt; en tidligere bekreftelse opphever ikke et senere avvik.';
  end if;

  -- G10: evidensvurderingen finnes for de typene som skal ha en.
  -- ANTIDEP_CONSTITUTION.md §6: en evidensbasert syntese skal ha en eksplisitt
  -- vurdering av sikkerheten i kunnskapsgrunnlaget. Migrasjon 004 tillater ikke
  -- en vurdering på et deterministisk faktum, så kravet gjelder de to typene som
  -- kan ha en.
  if v_knowledge_type in ('evidence_synthesis', 'clinical_recommendation')
     and not exists (
       select 1
       from knowledge.evidence_assessments a
       where a.claim_revision_id = p_claim_revision_id
     ) then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Revisjon %L mangler evidensvurdering og kan ikke publiseres som %s.',
        p_claim_revision_id, v_knowledge_type
      ),
      hint = 'En evidenssyntese eller klinisk anbefaling skal ha en eksplisitt vurdering av sikkerheten i kunnskapsgrunnlaget, med de fem GRADE-domenene vurdert (ANTIDEP_CONSTITUTION.md §6). Registrer vurderingen i knowledge.evidence_assessments.';
  end if;

  -- G11: menneskelig faglig godkjenning finnes.
  select rd.decision, rd.approved_evidence_set_digest
    into v_latest_decision, v_approved_digest
  from workflow.review_decisions rd
  where rd.claim_revision_id = p_claim_revision_id
    and rd.review_type = 'publication_approval'
  order by rd.decided_at desc, rd.created_at desc, rd.id desc
  limit 1;

  if not found then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Revisjon %L er ikke godkjent av en kvalifisert redaktør og kan ikke publiseres.',
        p_claim_revision_id
      ),
      hint = 'KI kan foreslå, men mennesker har det faglige ansvaret (ANTIDEP_CONSTITUTION.md §12). Registrer en publication_approval i workflow.review_decisions fra en navngitt kvalifisert redaktør.';
  end if;

  -- G12: godkjenningen er fortsatt den gjeldende beslutningen.
  if v_latest_decision <> 'approved' then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Den gjeldende reviewbeslutningen for revisjon %L er %s, ikke approved.',
        p_claim_revision_id, v_latest_decision
      ),
      hint = 'En senere beslutning gjelder foran en tidligere. Rett revisjonen slik reviewer ba om, i en ny revisjon, og be om ny godkjenning. Både godkjenningen og omgjøringen bevares (DATABASE_ARCHITECTURE.md §31).';
  end if;

  -- G13: evidensgrunnlaget er det samme som godkjenningen ble gitt for.
  -- MVP_IMPLEMENTATION_PLAN.md §42: systemet skal nekte «review av en revisjon
  -- som senere er endret uten nytt review». Selve revisjonsraden kan ikke endres
  -- — den er append-only — men betydningen av en revisjon omfatter
  -- evidensgrunnlaget den hviler på (KNOWLEDGE_MODEL.md §19.2). Et grunnlag som
  -- er endret etter at reviewer sa ja, er nettopp en endring reviewer ikke har
  -- sett.
  --
  -- Kontrollen sammenligner avtrykk, ikke tidspunkter. Begrunnelsen står i
  -- avsnitt 5: en tidssammenligning er ikke samtidighetssikker, fordi now() er
  -- transaksjonens starttidspunkt og ikke committidspunktet, og en lenke derfor
  -- kan bære en created_at foran godkjenningen selv om den ble synlig etter den.
  -- Avtrykket er uavhengig av rekkefølge: er settet et annet nå enn da
  -- beslutningen ble lagret, avvises publiseringen.
  if knowledge.claim_evidence_set_digest(p_claim_revision_id)
     is distinct from v_approved_digest then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Evidensgrunnlaget for revisjon %L er endret etter godkjenningen.',
        p_claim_revision_id
      ),
      hint = 'Godkjenningen gjelder et annet evidenssett enn det som er registrert nå, og dekker derfor ikke grunnlaget påstanden ville blitt publisert på. Opprett en ny revisjon med det fullstendige evidenssettet og be om ny godkjenning, eller registrer en ny godkjenning som dekker det utvidede grunnlaget (KNOWLEDGE_MODEL.md §19.2).';
  end if;

end;
$$;

comment on function knowledge.assert_claim_revision_publishable(uuid) is
  'Publiseringsgaten (DATABASE_ARCHITECTURE.md §38): kontrollerer at en påstandsrevisjon oppfyller kravene for sin kunnskapstype før publiseringspekeren flyttes. Kan bare avvise, og returnerer ingen data. Feilmeldingene navngir det konkrete objektet som blokkerer, slik at admin-flyten kan vise hvorfor et steg er blokkert (MVP_IMPLEMENTATION_PLAN.md §15). Tidsbasert utløp av review er bevisst utsatt til review-kravobjektet finnes; se kommentaren i migrasjonen.';

revoke execute on function knowledge.assert_claim_revision_publishable(uuid) from public;

-- ----------------------------------------------------------------------------
-- 7. Hvem får publisere (DATABASE_ARCHITECTURE.md §45-§46, §50,
--    MVP_IMPLEMENTATION_PLAN.md §16, §48, §49)
--
-- publisher er rollen som publiserer; reviewer er rollen som godkjenner. De er
-- bevisst ikke slått sammen: å la den som publiserer også kunne godkjenne ville
-- gjort publisering til en vei rundt det faglige kravet i
-- ANTIDEP_CONSTITUTION.md §12. Migrasjon 005 håndhever den andre halvdelen —
-- publisher, editor og admin gir ikke faglig godkjenningsrett — og denne
-- funksjonen håndhever den første: å ha godkjent noe gir ikke i seg selv rett
-- til å publisere det.
--
-- To ting kontrolleres, og begge må holde:
--
--   1. Sesjonen er den aktøren den utgir seg for å være. Uten dette ville en
--      hvilken som helst kaller kunnet publisere «som» en kvalifisert publisher
--      ved å oppgi aktør-ID-en, og attribusjonen i ANTIDEP_CONSTITUTION.md §14
--      ville vært en påstand fra den som skriver.
--   2. Den brukerkontoen har publisher-rollen for innholdsområdet nå.
--
-- Rollen leses fra workflow.user_roles, aldri fra en JWT-claim
-- (DATABASE_ARCHITECTURE.md §46). auth.uid() brukes bare til å identifisere
-- hvilken bruker sesjonen tilhører — altså til identitet, ikke til autorisasjon.
-- Skillet er poenget i §46: brukeren kan ikke gi seg selv en rolle ved å endre
-- metadata, fordi rollen slås opp i en tabell brukeren ikke kan skrive i.
--
-- I motsetning til kvalifikasjonskravet for review, som måles på
-- beslutningstidspunktet, måles publiseringsretten på nåtidspunktet. Det er
-- riktig vei: en godkjenning er en datert faglig vurdering som ikke skal
-- ugyldiggjøres av at reviewer senere slutter, mens en publisering er en handling
-- som utføres nå og krever rett nå. En tilbakekalt publisher-rolle skal virke
-- umiddelbart (§46).
-- ----------------------------------------------------------------------------
create function knowledge.assert_publisher_authorized(
  p_publisher_actor_id uuid,
  p_topic_concept_id uuid
)
  returns void
  language plpgsql
  set search_path = ''
as $$
declare
  v_actor_type provenance.actor_type;
  v_auth_user_id uuid;
  v_retired_at timestamptz;
begin
  select a.actor_type, a.auth_user_id, a.retired_at
    into v_actor_type, v_auth_user_id, v_retired_at
  from provenance.actors a
  where a.id = p_publisher_actor_id;

  if not found then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = format('Aktør %L finnes ikke.', p_publisher_actor_id),
      hint = 'Publisering skal attribueres til en registrert aktør (ANTIDEP_CONSTITUTION.md §14).';
  end if;

  if v_actor_type <> 'human' or v_auth_user_id is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Publisering krever en menneskelig aktør knyttet til en brukerkonto.',
      hint = 'En KI-aktør kan ikke publisere (MVP_IMPLEMENTATION_PLAN.md §49). Knytt en menneskelig aktør til brukerkontoen sin i provenance.actors.';
  end if;

  if v_retired_at is not null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Aktøren er trukket tilbake og kan ikke publisere.',
      hint = 'En tilbaketrukket aktør beholder sin historikk, men kan ikke utføre nye handlinger.';
  end if;

  if auth.uid() is null or auth.uid() <> v_auth_user_id then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Den innloggede brukeren er ikke den aktøren publiseringen attribueres til.',
      hint = 'Publisering kan bare attribueres til den innloggede brukerens egen aktør. Uten det ville attribusjonen vært en påstand fra den som skriver, ikke en observasjon (ANTIDEP_CONSTITUTION.md §14).';
  end if;

  if not exists (
    select 1
    from workflow.user_roles ur
    where ur.user_id = v_auth_user_id
      and ur.role_code = 'publisher'
      and ur.valid_from <= now()
      and (ur.valid_to is null or ur.valid_to > now())
      and (ur.scope_id is null or ur.scope_id = p_topic_concept_id)
  ) then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Brukeren har ikke gyldig publisher-rolle for dette innholdsområdet.',
      hint = 'Rollen leses fra workflow.user_roles, ikke fra en JWT-claim (DATABASE_ARCHITECTURE.md §46). En scoped tildeling må dekke påstandens kliniske tema. reviewer-rollen gir ikke publiseringsrett: å godkjenne og å publisere er to forskjellige handlinger (MVP_IMPLEMENTATION_PLAN.md §15).';
  end if;
end;
$$;

comment on function knowledge.assert_publisher_authorized(uuid, uuid) is
  'Kontrollerer at den innloggede brukeren er den menneskelige aktøren publiseringen attribueres til, og at brukeren har gyldig publisher-rolle for innholdsområdet nå. Rollen leses fra workflow.user_roles og aldri fra en JWT-claim (DATABASE_ARCHITECTURE.md §46); auth.uid() brukes bare til identitet. Kan bare avvise, og returnerer ingen data.';

revoke execute on function knowledge.assert_publisher_authorized(uuid, uuid) from public;

-- ----------------------------------------------------------------------------
-- 8. De kontrollerte publiseringsoperasjonene
--    (DATABASE_ARCHITECTURE.md §38, §40, §50, §61,
--     MVP_IMPLEMENTATION_PLAN.md §23, §48)
--
-- §38 krever én kontrollert operasjon som enten lykkes fullstendig eller ikke
-- gjør noen endring. Det er tre inngangspunkter og ikke ett, fordi de fire
-- handlingene i §39 har genuint forskjellige forutsetninger: å publisere krever
-- at gaten er passert, å avpublisere krever bare at noe er publisert, og å rulle
-- tilbake krever i tillegg at målet faktisk har vært publisert før. Ett felles
-- inngangspunkt med en handlingsparameter ville skjult de forskjellene bak en
-- streng kalleren velger, og gjort hver enkelt funksjon vanskeligere å lese som
-- sikkerhetskritisk kode (§50). publish og replace deler derimot inngangspunkt:
-- kalleren ber om at én bestemt revisjon skal være den publiserte, og databasen
-- avgjør ut fra tilstanden om det er en førstegangspublisering eller en
-- erstatning. Hvilken av dem det var, står i hendelsen.
--
-- Alle tre er SECURITY DEFINER (§50): de må kunne lese workflow.user_roles og
-- workflow.review_decisions, som har RLS og default deny, uavhengig av hvem som
-- kaller. De har tomt search_path, schemakvalifiserte navn, EXECUTE revokert fra
-- PUBLIC, og de validerer både caller og input selv.
--
-- Atomisitet og samtidighet (§61): hele operasjonen skjer i én transaksjon.
-- Påstandsraden låses med FOR UPDATE først, deretter revisjonen. To samtidige
-- publiseringer av samme påstand serialiseres derfor mot hverandre, og den andre
-- leser den nye tilstanden framfor den gamle. Skulle låsen falle bort, fanges
-- feilen likevel av unikhetsregelen publication_events_no_forked_history_key.
-- Låserekkefølgen påstand → revisjon er den samme overalt; se kommentaren på
-- forseglingstriggeren i avsnitt 4.
-- ----------------------------------------------------------------------------
create function knowledge.publish_claim_revision(
  p_claim_revision_id uuid,
  p_publisher_actor_id uuid,
  p_reason text
)
  returns uuid
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_claim_id uuid;
  v_topic_concept_id uuid;
  v_revision_number integer;
  v_current_revision_id uuid;
  v_current_revision_number integer;
  v_previous_event_id uuid;
  v_action knowledge.publication_action;
  v_event_id uuid;
begin
  select r.claim_id, r.revision_number
    into v_claim_id, v_revision_number
  from knowledge.claim_revisions r
  where r.id = p_claim_revision_id;

  if not found then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = format('Påstandsrevisjon %L finnes ikke.', p_claim_revision_id),
      hint = 'Publisering peker på en eksakt revisjon, ikke på påstandsidentiteten (KNOWLEDGE_MODEL.md §19.3).';
  end if;

  -- Låsene, i den faste rekkefølgen påstand → revisjon.
  select c.topic_concept_id, c.current_published_revision_id
    into v_topic_concept_id, v_current_revision_id
  from knowledge.claims c
  where c.id = v_claim_id
  for update;

  perform 1 from knowledge.claim_revisions r where r.id = p_claim_revision_id for update;

  perform knowledge.assert_publisher_authorized(p_publisher_actor_id, v_topic_concept_id);
  perform knowledge.assert_claim_revision_publishable(p_claim_revision_id);

  if v_current_revision_id is null then
    v_action := 'publish';
  elsif v_current_revision_id = p_claim_revision_id then
    raise exception using
      errcode = 'restrict_violation',
      message = format('Revisjon %L er allerede den publiserte.', p_claim_revision_id),
      hint = 'Publiseringshistorikken skal registrere reelle tilstandsendringer. En publisering som ikke endrer noe er ikke en hendelse.';
  else
    select r.revision_number into v_current_revision_number
    from knowledge.claim_revisions r
    where r.id = v_current_revision_id;

    if v_revision_number < v_current_revision_number then
      raise exception using
        errcode = 'restrict_violation',
        message = format(
          'Revisjon %L er eldre enn den publiserte revisjonen og kan ikke erstatte den.',
          p_claim_revision_id
        ),
        hint = 'Å gå tilbake til en tidligere revisjon er en rollback, ikke en erstatning, og skal registreres som det (DATABASE_ARCHITECTURE.md §40). Bruk knowledge.rollback_claim_publication().';
    end if;

    v_action := 'replace';
  end if;

  -- Siste hendelse i kjeden er den ingen annen hendelse peker tilbake på.
  -- Oppslaget er entydig fordi påstandsraden er låst.
  select e.id into v_previous_event_id
  from knowledge.publication_events e
  where e.claim_id = v_claim_id
    and not exists (
      select 1
      from knowledge.publication_events successor
      where successor.previous_event_id = e.id
    );

  update knowledge.claims
  set current_published_revision_id = p_claim_revision_id
  where id = v_claim_id;

  insert into knowledge.publication_events (
    claim_id, action, revision_id, revision_number,
    previous_revision_id, previous_revision_number, previous_event_id,
    published_by_actor_id, published_by_actor_type, reason, published_at
  )
  select
    v_claim_id, v_action, p_claim_revision_id, v_revision_number,
    v_current_revision_id, v_current_revision_number, v_previous_event_id,
    p_publisher_actor_id, a.actor_type, p_reason, now()
  from provenance.actors a
  where a.id = p_publisher_actor_id
  returning id into v_event_id;

  return v_event_id;
end;
$$;

comment on function knowledge.publish_claim_revision(uuid, uuid, text) is
  'Den kontrollerte publiseringsoperasjonen (DATABASE_ARCHITECTURE.md §38): validerer caller og publisher-rolle, kjører publiseringsgaten, flytter publiseringspekeren og registrerer hendelsen i én transaksjon. Registrerer publish når ingenting var publisert og replace ellers. SECURITY DEFINER fordi rollemodellen og reviewbeslutningene ligger bak RLS med default deny; funksjonen har tomt search_path og er ikke kjørbar for PUBLIC (§50).';

revoke execute on function knowledge.publish_claim_revision(uuid, uuid, text) from public;

-- Avpublisering. Ingen gate: å ta noe ut av visning er en sikkerhetshandling, og
-- den skal aldri kunne blokkeres av at grunnlaget under er blitt utilstrekkelig.
-- Det er nettopp da den trengs. Begrunnelsen er påkrevd, som for alle
-- hendelsene, slik at det i ettertid er mulig å se hvorfor Antidep sluttet å si
-- noe (ANTIDEP_CONSTITUTION.md §14).
create function knowledge.withdraw_claim_publication(
  p_claim_id uuid,
  p_publisher_actor_id uuid,
  p_reason text
)
  returns uuid
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_topic_concept_id uuid;
  v_current_revision_id uuid;
  v_current_revision_number integer;
  v_previous_event_id uuid;
  v_event_id uuid;
begin
  select c.topic_concept_id, c.current_published_revision_id
    into v_topic_concept_id, v_current_revision_id
  from knowledge.claims c
  where c.id = p_claim_id
  for update;

  if not found then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = format('Påstand %L finnes ikke.', p_claim_id),
      hint = 'Kontroller påstands-ID-en.';
  end if;

  if v_current_revision_id is null then
    raise exception using
      errcode = 'restrict_violation',
      message = format('Påstand %L har ingen publisert revisjon å trekke tilbake.', p_claim_id),
      hint = 'Publiseringshistorikken skal registrere reelle tilstandsendringer. En avpublisering av noe som ikke er publisert er ikke en hendelse.';
  end if;

  perform 1 from knowledge.claim_revisions r where r.id = v_current_revision_id for update;

  perform knowledge.assert_publisher_authorized(p_publisher_actor_id, v_topic_concept_id);

  select r.revision_number into v_current_revision_number
  from knowledge.claim_revisions r
  where r.id = v_current_revision_id;

  select e.id into v_previous_event_id
  from knowledge.publication_events e
  where e.claim_id = p_claim_id
    and not exists (
      select 1
      from knowledge.publication_events successor
      where successor.previous_event_id = e.id
    );

  update knowledge.claims
  set current_published_revision_id = null
  where id = p_claim_id;

  insert into knowledge.publication_events (
    claim_id, action, revision_id, revision_number,
    previous_revision_id, previous_revision_number, previous_event_id,
    published_by_actor_id, published_by_actor_type, reason, published_at
  )
  select
    p_claim_id, 'withdraw', null, null,
    v_current_revision_id, v_current_revision_number, v_previous_event_id,
    p_publisher_actor_id, a.actor_type, p_reason, now()
  from provenance.actors a
  where a.id = p_publisher_actor_id
  returning id into v_event_id;

  return v_event_id;
end;
$$;

comment on function knowledge.withdraw_claim_publication(uuid, uuid, text) is
  'Avpublisering: fjerner publiseringspekeren og registrerer hendelsen i én transaksjon. Kjører bevisst ikke publiseringsgaten — å ta innhold ut av visning skal aldri kunne blokkeres av at grunnlaget er blitt utilstrekkelig. Revisjonene og historikken bevares (DATABASE_ARCHITECTURE.md §36).';

revoke execute on function knowledge.withdraw_claim_publication(uuid, uuid, text) from public;

-- Rollback (DATABASE_ARCHITECTURE.md §40). Sletter ingenting: den oppretter en ny
-- hendelse og flytter pekeren tilbake til en tidligere publisert revisjon.
--
-- Målet må ha vært publisert før. Uten det kravet ville «rollback» vært en
-- vilkårlig flytting bakover i revisjonshistorikken til noe Antidep aldri har
-- sagt, og §40 sitt «hva sa vi på dato X?» ville ikke lenger vært et spørsmål om
-- faktisk historikk.
--
-- Gaten kjøres på nytt på målrevisjonen. Det er ikke overflødig: en revisjon som
-- var publiserbar i fjor kan ha fått et senere avvist verifikasjonsfunn, en
-- tilbaketrukket kilde eller en omgjort godkjenning. Å rulle tilbake til den
-- ville da vært å publisere noe som ikke lenger holder.
create function knowledge.rollback_claim_publication(
  p_claim_id uuid,
  p_target_revision_id uuid,
  p_publisher_actor_id uuid,
  p_reason text
)
  returns uuid
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_topic_concept_id uuid;
  v_current_revision_id uuid;
  v_current_revision_number integer;
  v_target_claim_id uuid;
  v_target_revision_number integer;
  v_previous_event_id uuid;
  v_event_id uuid;
begin
  select c.topic_concept_id, c.current_published_revision_id
    into v_topic_concept_id, v_current_revision_id
  from knowledge.claims c
  where c.id = p_claim_id
  for update;

  if not found then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = format('Påstand %L finnes ikke.', p_claim_id),
      hint = 'Kontroller påstands-ID-en.';
  end if;

  if v_current_revision_id is null then
    raise exception using
      errcode = 'restrict_violation',
      message = format('Påstand %L har ingen publisert revisjon å rulle tilbake fra.', p_claim_id),
      hint = 'En rollback flytter pekeren fra den gjeldende revisjonen tilbake til en tidligere publisert. Er ingenting publisert, er handlingen en publisering.';
  end if;

  select r.claim_id, r.revision_number
    into v_target_claim_id, v_target_revision_number
  from knowledge.claim_revisions r
  where r.id = p_target_revision_id;

  if not found or v_target_claim_id <> p_claim_id then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = format(
        'Revisjon %L finnes ikke eller tilhører en annen påstand enn %L.',
        p_target_revision_id, p_claim_id
      ),
      hint = 'Publiseringspekeren kan bare peke på en revisjon av den samme påstanden (DATABASE_ARCHITECTURE.md §58).';
  end if;

  perform 1 from knowledge.claim_revisions r where r.id = p_target_revision_id for update;

  if p_target_revision_id = v_current_revision_id then
    raise exception using
      errcode = 'restrict_violation',
      message = format('Revisjon %L er allerede den publiserte.', p_target_revision_id),
      hint = 'Publiseringshistorikken skal registrere reelle tilstandsendringer.';
  end if;

  select r.revision_number into v_current_revision_number
  from knowledge.claim_revisions r
  where r.id = v_current_revision_id;

  if v_target_revision_number > v_current_revision_number then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Revisjon %L er nyere enn den publiserte revisjonen og er derfor ikke en rollback.',
        p_target_revision_id
      ),
      hint = 'Å gå framover til en nyere revisjon er en erstatning. Bruk knowledge.publish_claim_revision().';
  end if;

  if not exists (
    select 1
    from knowledge.publication_events e
    where e.revision_id = p_target_revision_id
  ) then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Revisjon %L har aldri vært publisert og kan derfor ikke rulles tilbake til.',
        p_target_revision_id
      ),
      hint = 'En rollback flytter pekeren tilbake til en tidligere publisert revisjon (DATABASE_ARCHITECTURE.md §40). Skal en revisjon som aldri har vært publisert tas i bruk, er det en publisering.';
  end if;

  perform knowledge.assert_publisher_authorized(p_publisher_actor_id, v_topic_concept_id);
  perform knowledge.assert_claim_revision_publishable(p_target_revision_id);

  select e.id into v_previous_event_id
  from knowledge.publication_events e
  where e.claim_id = p_claim_id
    and not exists (
      select 1
      from knowledge.publication_events successor
      where successor.previous_event_id = e.id
    );

  update knowledge.claims
  set current_published_revision_id = p_target_revision_id
  where id = p_claim_id;

  insert into knowledge.publication_events (
    claim_id, action, revision_id, revision_number,
    previous_revision_id, previous_revision_number, previous_event_id,
    published_by_actor_id, published_by_actor_type, reason, published_at
  )
  select
    p_claim_id, 'rollback', p_target_revision_id, v_target_revision_number,
    v_current_revision_id, v_current_revision_number, v_previous_event_id,
    p_publisher_actor_id, a.actor_type, p_reason, now()
  from provenance.actors a
  where a.id = p_publisher_actor_id
  returning id into v_event_id;

  return v_event_id;
end;
$$;

comment on function knowledge.rollback_claim_publication(uuid, uuid, uuid, text) is
  'Rollback (DATABASE_ARCHITECTURE.md §40): flytter publiseringspekeren tilbake til en tidligere publisert revisjon og registrerer det som en ny hendelse. Sletter aldri den problematiske publiseringen. Krever at målrevisjonen faktisk har vært publisert, og kjører publiseringsgaten på nytt — en revisjon som var publiserbar tidligere kan ha fått et senere avvik.';

revoke execute on function knowledge.rollback_claim_publication(uuid, uuid, uuid, text) from public;

-- ----------------------------------------------------------------------------
-- 9. RLS og grants (DATABASE_ARCHITECTURE.md §5, §48, §49, §50,
--    MVP_IMPLEMENTATION_PLAN.md §47-§49)
--
-- RLS aktiveres på den nye tabellen og er default deny.
--
-- Migrasjon 005 utsatte policies og grants med den begrunnelsen at en policy
-- uten grant er en påstand om sikkerhet uten virkning, og at policyene hører
-- sammen med den første kontrollerte skriveveien. Denne migrasjonen *er* den
-- første kontrollerte skriveveien, så begrunnelsen skal prøves på nytt framfor å
-- gjentas.
--
-- Prøvingen gir samme svar, men av en annen og bedre grunn enn sist:
--
--   Den kontrollerte skriveveien er en funksjon, ikke tabelltilgang.
--   MVP_IMPLEMENTATION_PLAN.md §48 sier eksplisitt at admin-klienten ikke skal ha
--   generell tabellskriveadgang til kanoniske data, og at sentrale operasjoner
--   skal gå gjennom kontrollerte grenser som validerer rolle, status og
--   preconditions. Publiseringsfunksjonene er den grensen. De trenger verken
--   INSERT på knowledge.publication_events eller UPDATE på knowledge.claims for
--   noen klientrolle for å virke — de kjører som SECURITY DEFINER. En policy
--   ville derfor fortsatt ikke kunne slippe noen inn eller stenge noen ute, og
--   ville fortsatt bare kunne testes for sin egen eksistens.
--
--   Å gi en klientrolle skrivetilgang til tabellen ville dessuten vært en vei
--   rundt gaten: den som kan skrive i knowledge.publication_events direkte, kan
--   registrere en publisering som aldri passerte noen kontroll.
--
-- Det som ikke er utsatt, er kontrollen av kalleren. §50 krever at en privilegert
-- funksjon validerer caller og input selv, og det gjør de tre funksjonene over:
-- sesjonens identitet må stemme med aktøren handlingen attribueres til, og
-- rollen leses fra workflow.user_roles og aldri fra en JWT-claim (§46).
--
-- EXECUTE er revokert fra PUBLIC på alle de fem nye funksjonene og gitt til
-- ingen. Det er bevisst: knowledge er ikke et eksponert schema i Data API-en
-- ([api].schemas, håndhevet av 020_data_api_boundary_test.sql), så en EXECUTE
-- til authenticated ville ikke gitt noen reell skrivevei — den ville vært den
-- samme virkningsløse påstanden om sikkerhet som en policy uten grant. Den
-- eksponerte RPC-flaten for admin hører til api-schemaet og til migrasjonen som
-- oppretter det, sammen med sin egen trusselvurdering (§42, §68).
--
-- service_role får fortsatt ingenting, og evidenspipelinen har fortsatt ingen
-- egen databaseidentitet (DATABASE_ARCHITECTURE.md §49).
-- ----------------------------------------------------------------------------
alter table knowledge.publication_events enable row level security;

revoke all privileges on all tables in schema knowledge from public;
revoke all privileges on all tables in schema knowledge
  from anon, authenticated, service_role;

-- ============================================================================
-- 10. Ingen seed, og hvorfor
--    (ANTIDEP_CONSTITUTION.md §11, §12, MVP_IMPLEMENTATION_PLAN.md §29, §42)
--
-- Migrasjonen registrerer ingen publiseringshendelse og flytter ingen peker.
--
-- Å publisere de to påstandene fra migrasjon 004 ville krevd en godkjenning fra
-- en navngitt kvalifisert redaktør. Det finnes ingen menneskelig aktør, ingen
-- brukerkonto og ingen rolletildeling i systemet, og migrasjon 005 gjorde det
-- strukturelt umulig å registrere en godkjenning uten alle tre. Å seede dem
-- ville vært å oppfinne redaktøren, godkjenningen og verifikasjonene i samme
-- operasjon — nøyaktig den fiktive kontrollen konstitusjonen forbyr.
--
-- Det gaten leverer i dette steget er derfor et bevis på at den nekter. De
-- kritiske negative testene i MVP_IMPLEMENTATION_PLAN.md §42 — publisering uten
-- evidens, uten menneskelig review, og av en revisjon som er endret etter review
-- — er de egentlige leveransene, sammen med den positive testen som viser at
-- gaten slipper gjennom når alle kravene faktisk er oppfylt av testdata
-- opprettet inne i en transaksjon som rulles tilbake.
--
-- Milepæl B i planen (§58), «første publiserte Claim», er dermed ikke nådd av
-- denne migrasjonen og skal ikke se ut som om den er det. Den nås når en reell
-- redaktør finnes og faktisk godkjenner.
-- ============================================================================
