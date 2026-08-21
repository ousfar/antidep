-- ============================================================================
-- Antidep migrasjon 008 — audit.events
--
-- Formål: gi Antidep en append-only auditlogg for sikkerhets- og
-- forvaltningskritiske operasjoner, og koble den til de skriveveiene som
-- allerede finnes, slik at resten av admin-MVP-en bygges med sporbarhet fra
-- starten (MVP_IMPLEMENTATION_PLAN.md §25).
--
-- Styrende dokumenter:
--   docs/ANTIDEP_CONSTITUTION.md
--     §12 KI foreslår; mennesker har det faglige ansvaret
--     §14 endringer skal være reversible, attribuerte og rapporterbare
--   docs/MVP_IMPLEMENTATION_PLAN.md
--     §14-§16 admin- og review-MVP, og rollene som implementeres først
--     §25 innholdet i denne migrasjonen
--     §41-§42 testpyramide og kritiske negative tester
--     §47-§49 offentlig lesing, admin-skriving gjennom kontrollerte grenser,
--             least privilege for agenter
--   docs/DATABASE_ARCHITECTURE.md
--     §6 schemainndeling, §7.3 tidsbegreper, §8 uuid som identitet
--     §35 audit.events og minimumsfeltene
--     §36 ingen normal DELETE, og at fysisk sletting skal ha særskilt audit
--     §37 RESTRICT på fremmednøkler
--     §39 publiseringshendelsen, §46-§47 autorisasjon og medlemskapsmodellen
--     §57-§61 deklarative constraints, snevre triggere, atomisitet
--     §60 «append-only audit» som legitim triggerbruk
--     §67 databasetesting er en del av funksjonen
--
-- ----------------------------------------------------------------------------
-- Auditloggen er et supplement, ikke et andre hjem for faglig historikk
--
-- §35 er eksplisitt: auditloggen skal ikke være eneste sted hvor historiske
-- faglige versjoner finnes. Den kliniske historikken ligger fortsatt i
-- revisjonsmodellen og i knowledge.publication_events, og skal leses derfra.
-- Det auditloggen tilfører, er det tverrgående spørsmålet ingen av dem kan
-- besvare: «hva gjorde denne aktøren, på tvers av objekter og schemaer?»
-- Derfor er den ett smalt spor per operasjon — hvem, hva, hvilket objekt, hvilken
-- tilstand før og etter — og ikke en kopi av innholdet.
--
-- ----------------------------------------------------------------------------
-- Hvorfor object_id ikke har fremmednøkkel
--
-- Alle andre pekere i Antidep er ekte fremmednøkler; det er nettopp poenget i
-- §37 og i kommentaren på knowledge.publication_events.claim_id. Auditloggen er
-- unntaket, og grunnen står i §36: fysisk sletting er reservert for
-- feilopprettede objekter, personvernkrav og administrativt vedlikehold, og
-- «skal i så fall ha særskilt audit». En fremmednøkkel ville gjort nettopp den
-- auditen umulig — enten ville slettingen blitt blokkert av auditraden, eller
-- auditraden ville forsvunnet med objektet den dokumenterer.
--
-- Auditraden skal overleve objektet sitt. Derfor bærer den et snapshot av raden
-- framfor bare en peker: forsvinner objektet, står det fortsatt i loggen hva som
-- ble slettet. 320_audit_operations_test.sql demonstrerer dette framfor å bare
-- påstå det.
--
-- actor_id er derimot en ekte fremmednøkkel med RESTRICT. Der er ikke
-- overlevelse spørsmålet: en aktør som står oppført på en auditrad skal ikke
-- kunne slettes bort under den, og RESTRICT er den sterkere garantien.
--
-- ----------------------------------------------------------------------------
-- Hvorfor det ikke finnes et løpenummer
--
-- Fristelsen i en append-only logg er å gi den en monoton teller og kalle det
-- rekkefølge. Migrasjon 006 slo fast at commitrekkefølgen ikke er lesbar fra
-- radene (§74.6 i planen), og et løpenummer ville tildelt seg selv ved
-- innsetting, ikke ved commit: to transaksjoner kan commite i motsatt rekkefølge
-- av tildelingen, og en rullet tilbake transaksjon etterlater hull. Et slikt
-- felt ville derfor lovet en total orden det ikke kan innfri.
--
-- Rekkefølgespørsmål besvares der de faktisk har et svar: kjeden
-- previous_event_id i knowledge.publication_events, og gyldighetsintervallene i
-- workflow.user_roles. Auditloggen daterer, den ordner ikke.
--
-- ----------------------------------------------------------------------------
-- Avgrensning (MVP_IMPLEMENTATION_PLAN.md §26-§27):
--   Ingen catalog.drug_products og ingen ingest (009). Ingen admin-UI og ingen
--   admin-RPC-er. Ingen provenance.agent_runs, og derfor ingen produsent som
--   fyller request_or_run_id.
--
--   Ingen ny lesevei: auditloggen er ikke eksponert i api, har ingen policy og
--   ingen grants. §47 lister audit blant schemaene den offentlige klinikerflaten
--   aldri skal ha SELECT mot.
--
-- Konvensjonene fra migrasjon 001 gjelder og håndheves av
-- supabase/tests/030_conventions_test.sql: én databasegenerert uuid som
-- primærnøkkel, timestamptz overalt, created_at med default now(), RLS aktivert
-- og ingen grants til anon/authenticated/service_role/PUBLIC.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Kontrollert vokabular
--
-- Som i migrasjon 002-006 håndheves vokabularet som enum (DATABASE_ARCHITECTURE.md
-- §57). Det åpne spørsmålet om enum kontra oppslagstabell (MVP_IMPLEMENTATION_PLAN.md
-- §74.5 punkt 1) står fortsatt åpent og vokser med én type her, til 38.
--
-- Verdiene er domenehandlinger, ikke DML-verb. «update på workflow.user_roles»
-- forteller ikke en som gjennomgår loggen om en rettighet ble utvidet eller
-- tilbakekalt, og det er nettopp det spørsmålet loggen finnes for å besvare.
-- Prisen er at hver ny auditert operasjon krever en migrasjon. Det er en villet
-- pris: en logg som stilltiende utvider seg til nye operasjoner, utvider seg
-- også til operasjoner ingen har tatt stilling til om skal auditeres.
-- ----------------------------------------------------------------------------
create type audit.event_operation as enum (
  -- Publisering. De fire verdiene svarer én-til-én til
  -- knowledge.publication_action, men er navngitt med objektet foran, fordi
  -- vokabularet her spenner over flere objekttyper og «replace» alene ville vært
  -- tvetydig så snart noe annet enn en påstand kan erstattes.
  'claim_published',
  'claim_publication_replaced',
  'claim_publication_withdrawn',
  'claim_publication_rolled_back',

  -- Autorisasjon. Medlemskapsmodellen er den autoritative kilden for hvem som
  -- kan godkjenne og publisere (DATABASE_ARCHITECTURE.md §46, §47), og en
  -- endring der er den mest sikkerhetskritiske skrivingen Antidep har.
  'role_granted',
  'role_ended'
);

comment on type audit.event_operation is
  'Hvilken sikkerhets- eller forvaltningskritisk operasjon en auditrad registrerer (DATABASE_ARCHITECTURE.md §35). Domenehandlinger framfor DML-verb: loggen skal kunne leses uten å slå opp hva en UPDATE på den aktuelle tabellen betyr. Verdien bestemmer også hvilket objekt raden gjelder, gjennom de genererte kolonnene object_schema og object_table.';

-- PUBLIC har som standard usage på nye typer. Antidep gir privilegier eksplisitt
-- (DATABASE_ARCHITECTURE.md §5), som i migrasjon 001-006.
revoke usage on type audit.event_operation from public;

-- ----------------------------------------------------------------------------
-- 2. audit.events
--    (DATABASE_ARCHITECTURE.md §35)
--
-- Feltene i §35 sin minimumsliste finnes alle. Tre valg er verdt å lese før
-- tabellen brukes:
--
--   object_schema og object_table er genererte. §35 lister dem som egne felter,
--   og de er det — men de er avledet av operasjonen framfor oppgitt ved siden av
--   den, etter samme mønster som workflow.user_roles.scope_type og
--   knowledge.publication_events.object_type. En operasjon vet hvilken tabell den
--   gjelder; kunne de to oppgis uavhengig, kunne de komme i utakt, og da ville
--   loggen kunnet påstå at en rolletildeling skjedde i knowledge.
--
--   Kolonnene er NOT NULL. En enum-verdi som legges til uten at CASE-uttrykket
--   utvides, gir NULL og dermed en feilende innsetting framfor en stille tom
--   kolonne. Regelen er, som ellers i Antidep, uttømmende over vokabularet.
--
--   old_revision_or_snapshot og new_revision_or_snapshot bærer §35 sine navn.
--   Antidep lagrer et snapshot av radens tilstand, og «revisjon»-alternativet i
--   navnet uttrykkes gjennom snapshotets egne felter. Snapshotet er alltid et
--   json-objekt som identifiserer raden det er et snapshot av; se
--   events_snapshot_identifies_object_check.
--
-- Betydningen av NULL i de to snapshotkolonnene er presis, og skiller seg fra et
-- snapshot der et *felt* er null: NULL i kolonnen betyr at objektet ikke fantes
-- på den siden av operasjonen. En førstegangspublisering har derfor et
-- old-snapshot — påstanden fantes, men uten publisert revisjon — mens en
-- rolletildeling ikke har det, fordi raden ble til.
-- ----------------------------------------------------------------------------
create table audit.events (
  id uuid primary key default gen_random_uuid(),

  operation audit.event_operation not null,

  object_schema text not null generated always as (
    case operation
      when 'claim_published' then 'knowledge'
      when 'claim_publication_replaced' then 'knowledge'
      when 'claim_publication_withdrawn' then 'knowledge'
      when 'claim_publication_rolled_back' then 'knowledge'
      when 'role_granted' then 'workflow'
      when 'role_ended' then 'workflow'
    end
  ) stored,
  object_table text not null generated always as (
    case operation
      when 'claim_published' then 'claims'
      when 'claim_publication_replaced' then 'claims'
      when 'claim_publication_withdrawn' then 'claims'
      when 'claim_publication_rolled_back' then 'claims'
      when 'role_granted' then 'user_roles'
      when 'role_ended' then 'user_roles'
    end
  ) stored,
  object_id uuid not null,

  actor_id uuid not null
    references provenance.actors (id) on update restrict on delete restrict,

  old_revision_or_snapshot jsonb,
  new_revision_or_snapshot jsonb,

  request_or_run_id uuid,
  reason text,

  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),

  -- Hvilke snapshots som skal være satt følger av operasjonen, og regelen er
  -- uttømmende over vokabularet. Uten else-grenen ville CASE gitt NULL for en ny
  -- enum-verdi, og en NULL passerer en CHECK — regelen ville stilltiende sluttet
  -- å gjelde for nettopp den operasjonen som er ny.
  constraint events_snapshot_shape_check
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
        else false
      end
    ),

  -- Et snapshot skal identifisere raden det er et snapshot av. Uten regelen kunne
  -- en auditrad beskrive én rad og vise fram en annen, og loggen ville løyet uten
  -- at noe fanget det.
  --
  -- jsonb_typeof-kontrollen er ikke overflødig: `'[1,2]'::jsonb ->> 'id'` gir NULL
  -- framfor en feil, og en NULL-sammenligning er ukjent, ikke usann — den ville
  -- passert en CHECK. `is not distinct from` gjør den usann i stedet.
  constraint events_snapshot_identifies_object_check
    check (
      (old_revision_or_snapshot is null
       or (jsonb_typeof(old_revision_or_snapshot) = 'object'
           and old_revision_or_snapshot ->> 'id' is not distinct from object_id::text))
      and (new_revision_or_snapshot is null
       or (jsonb_typeof(new_revision_or_snapshot) = 'object'
           and new_revision_or_snapshot ->> 'id' is not distinct from object_id::text))
    ),

  -- Samme binding mellom hendelsestidspunkt og registreringstidspunkt som
  -- workflow.review_decisions og knowledge.publication_events har
  -- (DATABASE_ARCHITECTURE.md §7.3): en operasjon kan registreres i etterkant,
  -- men ikke dateres til framtiden.
  constraint events_occurred_at_not_future_check
    check (occurred_at <= created_at),

  constraint events_reason_check
    check (reason is null
           or (reason = btrim(reason) and length(reason) between 1 and 2000))
);

comment on table audit.events is
  'Append-only logg over sikkerhets- og forvaltningskritiske operasjoner (DATABASE_ARCHITECTURE.md §35). Supplement til revisjons- og publiseringsmodellen, ikke et andre hjem for faglig historikk: den svarer på det tverrgående spørsmålet «hva gjorde denne aktøren?», som verken revisjonene eller publiseringshistorikken kan besvare. Raden kan verken endres eller slettes etter innsetting, og den overlever objektet den beskriver.';
comment on column audit.events.operation is
  'Hvilken operasjon raden registrerer. Bestemmer både hvilket objekt raden gjelder, gjennom de genererte kolonnene object_schema og object_table, og hvilke snapshots som skal være satt, gjennom events_snapshot_shape_check.';
comment on column audit.events.object_schema is
  'Schemaet objektet ligger i (DATABASE_ARCHITECTURE.md §35). Avledet av operasjonen, ikke oppgitt ved siden av den, slik at de to ikke kan komme i utakt. NOT NULL på en generert kolonne gjør at en ny enum-verdi uten tilhørende gren feiler ved innsetting framfor å gi en tom kolonne.';
comment on column audit.events.object_table is
  'Tabellen objektet ligger i (DATABASE_ARCHITECTURE.md §35). Avledet av operasjonen, med samme begrunnelse som object_schema.';
comment on column audit.events.object_id is
  'Raden operasjonen gjaldt. Bevisst uten fremmednøkkel, i motsetning til alle andre pekere i Antidep: fysisk sletting skal ha særskilt audit (DATABASE_ARCHITECTURE.md §36), og en fremmednøkkel ville enten blokkert slettingen eller fjernet auditraden sammen med objektet. Snapshotet bærer derfor innholdet, slik at raden fortsatt sier hva som forsvant.';
comment on column audit.events.actor_id is
  'Aktøren som utførte operasjonen. Alltid utfylt: en audithendelse uten attribusjon svarer ikke på spørsmålet loggen finnes for (ANTIDEP_CONSTITUTION.md §14). Fremmednøkkelen er RESTRICT, så en aktør ikke kan slettes bort under sin egen historikk.';
comment on column audit.events.old_revision_or_snapshot is
  'Objektets tilstand før operasjonen (DATABASE_ARCHITECTURE.md §35). NULL betyr at objektet ikke fantes før, ikke at tilstanden er ukjent — et snapshot der et felt er null er noe annet. Alltid et json-objekt som bærer objektets egen id.';
comment on column audit.events.new_revision_or_snapshot is
  'Objektets tilstand etter operasjonen (DATABASE_ARCHITECTURE.md §35). NULL betyr at objektet ikke finnes etterpå. Alltid et json-objekt som bærer objektets egen id.';
comment on column audit.events.request_or_run_id is
  'Korrelasjonsnøkkel til forespørselen eller agentkjøringen operasjonen hørte til (DATABASE_ARCHITECTURE.md §35). Bevisst uten fremmednøkkel, fordi verdien oppstår utenfor databasen. Ingen produsent setter den ennå: admin-RPC-laget og provenance.agent_runs finnes ikke.';
comment on column audit.events.reason is
  'Begrunnelsen operatøren oppga, når operasjonen krever en. Kopiert fra kildeoperasjonen framfor formulert på nytt, slik at loggen og objektet sier det samme.';
comment on column audit.events.occurred_at is
  'Når operasjonen fant sted (DATABASE_ARCHITECTURE.md §7.3). Et hendelsestidspunkt, ikke registreringstidspunktet for raden; det siste er created_at. Kan ligge før created_at, men aldri etter.';
comment on column audit.events.created_at is
  'Når Antidep registrerte auditraden. Eies av databasen (catalog.set_created_at()) og er referansepunktet occurred_at måles mot.';

-- «Hva gjorde denne aktøren?» er hovedspørsmålet loggen finnes for.
create index events_actor_id_occurred_at_idx
  on audit.events (actor_id, occurred_at desc);
-- «Hva har skjedd med dette objektet?»
create index events_object_occurred_at_idx
  on audit.events (object_schema, object_table, object_id, occurred_at desc);
-- «Hva skjedde i går?»
create index events_occurred_at_idx
  on audit.events (occurred_at desc);

create trigger events_set_created_at
  before insert on audit.events
  for each row execute function catalog.set_created_at();

-- Append-only, med samme vern som publiseringshistorikken. En auditlogg som kan
-- redigeres av den som blir auditert, er ikke en auditlogg
-- (DATABASE_ARCHITECTURE.md §35, §36).
create trigger events_reject_mutation
  before update or delete on audit.events
  for each row execute function knowledge.reject_append_only_mutation(
    'Auditloggen er et vitnesbyrd om hva som faktisk ble utført, og korrigeres aldri. Var operasjonen feil, rettes den med en ny operasjon, som selv blir auditert.'
  );

alter table audit.events enable row level security;

-- Default deny, som i de andre kanoniske schemaene. Ingen policy skrives:
-- auditloggen har ingen lesevei for klientroller i det hele tatt
-- (MVP_IMPLEMENTATION_PLAN.md §47).
revoke all privileges on all tables in schema audit from public;
revoke all privileges on all tables in schema audit
  from anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Produsentene
--    (DATABASE_ARCHITECTURE.md §48, §60, MVP_IMPLEMENTATION_PLAN.md §25)
--
-- En audittabell uten skrivevei er en påstand om framtidig sporbarhet, ikke
-- sporbarhet. §25 sitt argument for å ta audit tidlig er nettopp at resten av
-- admin-MVP-en skal bygges med sporbarhet fra starten, og da må mønsteret finnes
-- og være testet før admin-flyten skrives.
--
-- De to skriveveiene som finnes i dag er publisering og rolleforvaltning. Begge
-- auditeres med trigger framfor med et kall inne i den skrivende funksjonen.
-- §60 navngir «append-only audit» som en av de få legitime triggerbrukene, og
-- grunnen er akkurat denne: en trigger kan ikke glemmes av neste skrivevei.
-- Rolletildelinger har i dag ingen kontrollert funksjon over seg i det hele
-- tatt — de skrives direkte — så et kall inne i en funksjon ville ikke dekket
-- dem.
--
-- Ingen av triggerfunksjonene er SECURITY DEFINER, og det er en
-- sikkerhetsbeslutning, ikke en forglemmelse. En auditskriver som er mer
-- privilegert enn operasjonen den registrerer, er en vei til å skrive falske
-- auditrader. Konsekvensen er at den som skriver operasjonen også må kunne
-- skrive auditraden — i dag bare eieren. Det er riktig vei å feile: en
-- rolletildeling som ikke kan auditeres, skal ikke kunne registreres.
-- ----------------------------------------------------------------------------

-- Publisering. Auditraden avledes av publiseringshendelsen framfor av
-- oppdateringen på knowledge.claims, av én grunn: hendelsen bærer aktøren og
-- begrunnelsen, og en oppdatering av pekeren gjør ikke det. Uten aktør ville
-- auditraden vært anonym, og en anonym auditrad besvarer ikke §14.
--
-- Objektet er påstanden, ikke hendelsen: det er publiseringspekeren på
-- knowledge.claims som endret seg, og snapshotene viser nettopp den før og etter.
-- Den fullstendige kliniske historikken ligger fortsatt i
-- knowledge.publication_events, som §35 krever.
create function audit.record_publication_event()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
declare
  v_operation audit.event_operation;
begin
  v_operation := case new.action
    when 'publish' then 'claim_published'::audit.event_operation
    when 'replace' then 'claim_publication_replaced'::audit.event_operation
    when 'withdraw' then 'claim_publication_withdrawn'::audit.event_operation
    when 'rollback' then 'claim_publication_rolled_back'::audit.event_operation
  end;

  -- Uttømmende over knowledge.publication_action. En femte handling skal stoppe
  -- publiseringen framfor å gli gjennom uauditert; det er den samme regelen som
  -- else-grenene i CHECK-ene over.
  if v_operation is null then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Publiseringshandlingen %L har ingen tilsvarende auditoperasjon.', new.action
      ),
      hint = 'Legg til verdien i audit.event_operation og i audit.record_publication_event() før handlingen tas i bruk. En publisering som ikke kan auditeres, skal ikke kunne utføres (DATABASE_ARCHITECTURE.md §35).';
  end if;

  insert into audit.events (
    operation, object_id, actor_id,
    old_revision_or_snapshot, new_revision_or_snapshot,
    reason, occurred_at
  )
  values (
    v_operation,
    new.claim_id,
    new.published_by_actor_id,
    jsonb_build_object(
      'id', new.claim_id,
      'current_published_revision_id', new.previous_revision_id
    ),
    jsonb_build_object(
      'id', new.claim_id,
      'current_published_revision_id', new.revision_id
    ),
    new.reason,
    new.published_at
  );

  return null;
end;
$$;

comment on function audit.record_publication_event() is
  'Auditskriver for publiseringslaget: oversetter en rad i knowledge.publication_events til en auditrad om påstanden hvis publiseringspeker flyttet seg. Kjører med kallerens rettigheter, ikke som SECURITY DEFINER, slik at en auditrad aldri kan skrives av noen som ikke kunne utført operasjonen selv.';

revoke execute on function audit.record_publication_event() from public;

create trigger publication_events_record_audit_event
  after insert on knowledge.publication_events
  for each row execute function audit.record_publication_event();

-- Rolleforvaltning. Medlemskapsmodellen er den autoritative
-- autorisasjonskilden (DATABASE_ARCHITECTURE.md §46), og både tildeling og
-- avslutning er sikkerhetskritiske hendelser.
--
-- Her er hele raden snapshotet, ikke bare det endrede feltet. Til forskjell fra
-- publisering finnes det ingen separat hendelsestabell under
-- workflow.user_roles: raden er både tilstand og historikk, og bare et
-- fullstendig snapshot bevarer hva rettigheten faktisk gjaldt.
create function audit.record_user_role_event()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into audit.events (
      operation, object_id, actor_id,
      old_revision_or_snapshot, new_revision_or_snapshot,
      reason, occurred_at
    )
    values (
      'role_granted'::audit.event_operation,
      new.id,
      new.granted_by_actor_id,
      null,
      to_jsonb(new),
      new.grant_reason,
      now()
    );
  else
    insert into audit.events (
      operation, object_id, actor_id,
      old_revision_or_snapshot, new_revision_or_snapshot,
      reason, occurred_at
    )
    values (
      'role_ended'::audit.event_operation,
      new.id,
      new.ended_by_actor_id,
      to_jsonb(old),
      to_jsonb(new),
      new.end_reason,
      now()
    );
  end if;

  return null;
end;
$$;

comment on function audit.record_user_role_event() is
  'Auditskriver for medlemskapsmodellen: registrerer tildeling og avslutning av en rolletildeling med fullstendig snapshot av raden. Kjører med kallerens rettigheter, med samme begrunnelse som audit.record_publication_event().';

revoke execute on function audit.record_user_role_event() from public;

-- To triggere framfor én, fordi en WHEN-betingelse verken kan lese tg_op eller
-- OLD på en INSERT. Betingelsen på UPDATE er nødvendig: workflow.user_roles har
-- updated_at, så en oppdatering som ikke endrer noe ville ellers lagt igjen en
-- auditrad om en hendelse som ikke fant sted.
--
-- Betingelsen er formulert på valid_to framfor på «er avsluttet», fordi
-- workflow.freeze_role_grant() allerede sørger for at det er den eneste
-- endringen som kan skje: alt annet enn avslutningen er frosset, og en avsluttet
-- tildeling kan ikke gjenåpnes.
create trigger user_roles_record_grant_audit_event
  after insert on workflow.user_roles
  for each row execute function audit.record_user_role_event();

create trigger user_roles_record_end_audit_event
  after update on workflow.user_roles
  for each row
  when (old.valid_to is distinct from new.valid_to)
  execute function audit.record_user_role_event();
