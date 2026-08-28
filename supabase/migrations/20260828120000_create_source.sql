-- ============================================================================
-- Migrasjon 007c — den kontrollerte skriveveien for å opprette en Source
--
-- Steg 2 av «manuell adminflyt» (MVP_IMPLEMENTATION_PLAN.md §29): «Editor
-- oppretter Source», det første leddet i §15 sin admin-workflow. Steg 1
-- (migrasjon 007b + innlogging/«Min tilgang», §74.21-§74.22) åpnet leseveien
-- «hvem er jeg, og hva har jeg lov til?». Denne migrasjonen åpner den første
-- skriveveien: én kilde, ingenting mer av kjeden. EvidenceItem, ClaimRevision,
-- review og publisering hører til senere PR-er, én om gangen (§51).
--
-- Utvider api-lesemodellen fra migrasjon 007 (§24) med det første skrivbare
-- medlemmet, på samme måte 007a og 007b utvidet den med lesbare views, og
-- følger derfor samme bokstavkonvensjon videre: 007 → 007a → 007b → 007c.
-- Står utenfor den planlagte rekken i §18-§27. Nummeret 009 er fortsatt
-- reservert for DrugProduct-/importfundamentet (§26), urørt av denne
-- migrasjonen.
--
-- Styrende dokumenter:
--   docs/ANTIDEP_CONSTITUTION.md
--     §14  attribusjon: en handling skal spores til hvem eller hva som utførte den
--   docs/DATABASE_ARCHITECTURE.md
--     §35-§36  audit.events, og at fysisk sletting krever særskilt audit
--     §38  publisering (og enhver kontrollert operasjon) er én transaksjon
--     §43  klienten skal ikke skrive direkte til kanoniske tabeller
--     §44  Data API-kontrakten skal være eksplisitt: eksponering, GRANT, RLS,
--          test med faktisk klientrolle
--     §45-§50  roller, RLS default deny, privilegerte databasefunksjoner
--   docs/MVP_IMPLEMENTATION_PLAN.md
--     §14-§16  admin er en del av MVP, og rollene §16 lister
--     §29  Slice 1, «manuell adminflyt»
--     §74.4, §74.7, §74.21, §74.22  status og gjeld adminflyten arver
--
-- ----------------------------------------------------------------------------
-- Ett inngangspunkt, én SECURITY DEFINER-funksjon, eksponert i api
--
-- api.create_source(...) er hele skriveveien. Klienten kaller den ene
-- funksjonen; den validerer kalleren, setter inn raden og lar
-- audit.record_source_event() (avsnitt 3) registrere hendelsen i samme
-- transaksjon, som en trigger — ikke fordi funksjonen glemmer å skrive
-- auditraden selv, men fordi migrasjon 008 alt har lagt den plikten på
-- INSERT på knowledge.sources, uansett hvilken skrivevei som til slutt fører
-- dit (§35, §60: «en trigger kan ikke glemmes av neste skrivevei»).
--
-- Funksjonen er SECURITY DEFINER fordi knowledge.sources, workflow.user_roles
-- og provenance.actors alle har RLS med default deny for authenticated (§48);
-- uten det ville verken rolleoppslaget eller selve INSERT-en vært mulig for
-- klientrollen. Den har tomt search_path, schemakvalifiserte navn, EXECUTE
-- revokert fra PUBLIC og gitt bare til authenticated, og den validerer kalleren
-- selv, på sitt eget kall — den stoler ikke på hva klienten leste fra
-- api.my_actor/api.my_roles i et tidligere kall (§74.21: de viewene svarer på
-- hva kalleren HAR, ikke hva kalleren FÅR LOV TIL; den avgjørelsen tas her).
--
-- ----------------------------------------------------------------------------
-- Hvorfor aktøren utledes av auth.uid(), ikke oppgis som parameter
--
-- knowledge.assert_publisher_authorized(p_publisher_actor_id, p_topic_concept_id)
-- (migrasjon 006) tar aktøren som parameter og kontrollerer at den stemmer med
-- auth.uid(). Det gir mening der: verdien skal uansett skrives inn i
-- knowledge.publication_events.published_by_actor_id, og tre forskjellige
-- operasjoner (publish/replace, withdraw, rollback) deler samme kontroll
-- funksjon med samme signatur.
--
-- Her finnes ingen klientoppgitt verdi å kontrollere mot: attribusjonen for en
-- ny kilde KAN aldri være noe annet enn kallerens egen aktør, så funksjonen
-- slår den opp selv i stedet for å be klienten sende inn en verdi den likevel
-- bare ville fått bekreftet eller avvist. Det fjerner en hel feilklasse — en
-- klient som (ved en feil, ikke ved ondsinnethet) sender en annen aktørs id —
-- uten å tape noe: knowledge.assert_editor_authorized() (avsnitt 2) returnerer
-- den samme verdien knowledge.assert_publisher_authorized() ville validert.
-- En senere skrivevei som deler mønster med publiseringens tre operasjoner
-- (flere funksjoner, samme aktør oppgitt av klienten) kan fortsatt velge
-- parameterformen; det er en avgjørelse for den PR-en, ikke en føring herfra.
--
-- ----------------------------------------------------------------------------
-- Hvorfor editor-sjekken ikke er avgrenset til et klinisk begrep
--
-- workflow.user_roles.scope_id peker på catalog.clinical_concepts (§47): en
-- rolletildeling KAN avgrenses til ett innholdsområde. knowledge.sources har
-- ingen slik avgrensning — en kilde er ikke selv om ett tema, den blir referert
-- av evidensfunn som senere kan gjelde ulike kliniske begreper (§16, §17: en
-- artikkel kan rapportere flere endepunkter). Det finnes derfor ingen
-- p_topic_concept_id å kontrollere en avgrenset tildeling mot, og
-- knowledge.assert_editor_authorized() godtar enhver gyldig editor-tildeling,
-- avgrenset eller ikke: en editor med en avgrenset tildeling kan opprette
-- kilder, fordi kilden i seg selv ikke er avgrenset til noe reviewer/publisher
-- senere skal kontrollere mot. Det er en bevisst, dokumentert avveining og ikke
-- en forglemmelse — se PR-beskrivelsen for alternativet som ble vurdert og
-- valgt bort. En senere skrivevei som OPPRETTER et avgrenset objekt (EvidenceItem
-- knyttet til et endepunkt, ClaimRevision under et klinisk begrep) skal ta
-- stilling til scope på nytt; det er ikke gitt av denne funksjonen.
--
-- ----------------------------------------------------------------------------
-- Hvorfor generert-kolonnene og CHECK-en på audit.events må bygges om
--
-- object_schema og object_table (migrasjon 008) er GENERATED ALWAYS ... STORED
-- over et CASE-uttrykk på operation. PostgreSQL har ingen ALTER COLUMN som
-- endrer uttrykket til en generert kolonne; den eneste veien er å fjerne og
-- opprette den på nytt — her gjort i avsnitt 1, med indeksen som bruker begge
-- kolonnene tatt ned og opp igjen rundt det. events_snapshot_shape_check
-- bygges om av samme grunn: en CHECK kan endres bare ved DROP/ADD CONSTRAINT.
-- Tabellen er tom i alle miljøer bortsett fra det hostede (der migrasjon 007a
-- sin rolletildeling kan ha skrevet én rad); begge operasjonene er trygge på en
-- levende rad, siden CASE-uttrykket dekker den eksisterende verdien uendret.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. audit.events utvides til å kunne peke på knowledge.sources
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
      -- En opprettelse, som role_granted: raden fantes ikke før, så det er
      -- ikke noe old-snapshot å vise.
      when 'source_created' then
        old_revision_or_snapshot is null and new_revision_or_snapshot is not null
      else false
    end
  );

comment on constraint events_snapshot_shape_check on audit.events is
  'Hvilke av de to snapshotene som skal være satt, følger av operasjonen. Uttømmende over audit.event_operation: en ny verdi uten egen gren gir ELSE false, altså en avvist innsetting framfor en stille tom kolonne.';

-- ----------------------------------------------------------------------------
-- 2. knowledge.assert_editor_authorized() — den gjenbrukbare kontrollen
--
-- SECURITY INVOKER (standard), som knowledge.assert_publisher_authorized(uuid,
-- uuid): den kalles alltid fra innsiden av en SECURITY DEFINER-funksjon, og
-- arver dermed den elevated konteksten derfra. Tomt search_path og
-- schemakvalifiserte navn likevel, av samme grunn som resten av
-- sikkerhetskritisk kode i denne basen (§50).
-- ----------------------------------------------------------------------------
create function knowledge.assert_editor_authorized()
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
      hint = 'En kilde skal attribueres til en registrert aktør (ANTIDEP_CONSTITUTION.md §14). En kaller uten aktørrad kan ikke opprette noe i sitt eget navn. Ta kontakt med en administrator for å få kontoen din knyttet til en aktør.';
  end if;

  if v_retired_at is not null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Aktøren er trukket tilbake og kan ikke opprette kilder.',
      hint = 'En tilbaketrukket aktør beholder sin historikk, men kan ikke utføre nye handlinger.';
  end if;

  if not exists (
    select 1
    from workflow.user_roles ur
    where ur.user_id = auth.uid()
      and ur.role_code = 'editor'
      and ur.valid_from <= statement_timestamp()
      and (ur.valid_to is null or ur.valid_to > statement_timestamp())
  ) then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Brukeren har ikke gyldig editor-rolle.',
      hint = 'Rollen leses fra workflow.user_roles, ikke fra en JWT-claim (DATABASE_ARCHITECTURE.md §46). En avgrenset editor-tildeling er tilstrekkelig: en Source er ikke selv avgrenset til noe klinisk begrep.';
  end if;

  return v_actor_id;
end;
$$;

comment on function knowledge.assert_editor_authorized() is
  'Kontrollerer at den innloggede brukeren har en registrert, ikke-tilbaketrukket aktør og en gyldig editor-rolle på kallets eget tidspunkt (statement_timestamp(), ikke transaksjonens starttidspunkt, slik at en tilbakekalling virker umiddelbart — MVP_IMPLEMENTATION_PLAN.md §74.6), og returnerer aktørens id. Avviser aldri stille: hvert av de tre kravene har sin egen feilmelding. Enhver gyldig editor-tildeling godtas, avgrenset eller ikke — se migrasjonens hodekommentar for hvorfor. Kalles fra innsiden av en SECURITY DEFINER-funksjon og trenger derfor ikke være det selv.';

revoke execute on function knowledge.assert_editor_authorized() from public;

-- ----------------------------------------------------------------------------
-- 3. audit.record_source_event() — produsenten for INSERT på knowledge.sources
--
-- Samme mønster som audit.record_user_role_event() (migrasjon 008): ikke
-- SECURITY DEFINER, slik at auditskriveren aldri er mer privilegert enn
-- operasjonen den registrerer (§35, §60). Hele raden er snapshotet, som for
-- role_granted: knowledge.sources har ingen egen hendelsestabell under seg slik
-- publisering har, så snapshotet er det eneste som bevarer hva som ble
-- registrert.
-- ----------------------------------------------------------------------------
create function audit.record_source_event()
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
    'source_created'::audit.event_operation,
    new.id,
    new.created_by_actor_id,
    null,
    to_jsonb(new),
    now()
  );

  return null;
end;
$$;

comment on function audit.record_source_event() is
  'Auditskriver for kildelaget: registrerer at en kilde ble opprettet, med hele raden som snapshot. Kjører med kallerens rettigheter, ikke som SECURITY DEFINER, slik at en auditrad aldri kan skrives av noen som ikke kunne utført operasjonen selv (samme begrunnelse som audit.record_publication_event() og audit.record_user_role_event()).';

revoke execute on function audit.record_source_event() from public;

create trigger sources_record_creation_audit_event
  after insert on knowledge.sources
  for each row execute function audit.record_source_event();

-- ----------------------------------------------------------------------------
-- 4. api.create_source(...) — den eneste skriveveien
--
-- Parametrene speiler nøyaktig de skrivbare feltene på knowledge.sources ved
-- opprettelse: source_status, status_note og superseded_by_source_id er
-- livssyklusfelter en senere korreksjons-RPC skal eie (§74.7 sin gjeldspost om
-- fysisk sletting og §36 gjelder tilsvarende for statusendring), ikke noe en
-- ny kilde kan starte i annen tilstand enn 'active' uten begrunnelse.
--
-- Ingen feltvalidering er duplisert her utover det parameterlisten selv
-- uttrykker (hvilke felter som finnes, og hvilke som er valgfrie). Databasens
-- CHECK-constraints på knowledge.sources — tittel trimmet og 1-600 tegn, dato
-- og presisjon parkoblet og så videre — er fasiten (migrasjon 003); en
-- avvisning derfra propageres til klienten som den er, ikke gjettes på her.
--
-- p_source_type og p_publication_date_precision er `text`, ikke de kanoniske
-- enum-typene, og castes til dem *inne* i funksjonskroppen. Prøvd direkte mot
-- denne stacken: PostgREST bygger selv et uttrykk som caster JSON-verdien til
-- parameterens deklarerte type, skrevet schemakvalifisert
-- (`$1::knowledge.source_type`), og den casten evalueres i kallerens egen
-- sesjon — før funksjonen i det hele tatt starter. authenticated har ingen
-- USAGE på knowledge (§47: klientroller skal ikke kunne navngi et kanonisk
-- schema i det hele tatt), så et RPC-kall med enum-typede parametre feiler med
-- «permission denied for schema knowledge», uansett at selve funksjonen er
-- SECURITY DEFINER — feilen oppstår før EXECUTE-sjekken på funksjonen engang
-- er nådd. Med `text` som parametertype gjør ikke PostgREST noen slik cast,
-- og castingen skjer i stedet i INSERT-setningen under, som kjører i
-- funksjonens SECURITY DEFINER-kontekst — altså som funksjonens eier, som har
-- USAGE på knowledge. En ugyldig verdi gir fortsatt en avvisning fra databasen
-- (22P02, invalid_text_representation), bare ett steg lenger inn enn om
-- PostgREST hadde castet den; ingen validering er lagt til for å kompensere.
-- ----------------------------------------------------------------------------
create function api.create_source(
  p_source_type text,
  p_title text,
  p_authors_or_issuer text,
  p_publisher_or_journal text default null,
  p_volume text default null,
  p_issue text default null,
  p_pages text default null,
  p_publication_date date default null,
  p_publication_date_precision text default null
)
  returns uuid
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_source_id uuid;
begin
  v_actor_id := knowledge.assert_editor_authorized();

  insert into knowledge.sources (
    source_type, title, authors_or_issuer, publisher_or_journal,
    volume, issue, pages, publication_date, publication_date_precision,
    created_by_actor_id
  )
  values (
    p_source_type::knowledge.source_type, p_title, p_authors_or_issuer, p_publisher_or_journal,
    p_volume, p_issue, p_pages, p_publication_date,
    p_publication_date_precision::knowledge.date_precision,
    v_actor_id
  )
  returning id into v_source_id;

  return v_source_id;
end;
$$;

comment on function api.create_source(
  text, text, text, text, text, text, text, date, text
) is
  'Den kontrollerte skriveveien for å opprette en Source (DATABASE_ARCHITECTURE.md §43, MVP_IMPLEMENTATION_PLAN.md §15, §29). Kontrollerer at kalleren har en registrert, aktiv aktør og en gyldig editor-rolle (knowledge.assert_editor_authorized()), setter inn raden attribuert til kallerens egen aktør, og returnerer den nye kildens id. SECURITY DEFINER fordi knowledge.sources, workflow.user_roles og provenance.actors har RLS med default deny for authenticated; funksjonen har tomt search_path og validerer kalleren selv, på sitt eget kall (§50). p_source_type og p_publication_date_precision er text og castes til de kanoniske enum-typene inne i funksjonskroppen, ikke i parameterlisten — se migrasjonens hodekommentar for hvorfor. source_status, status_note og superseded_by_source_id er ikke parametre: en ny kilde er alltid active, og livssyklusendringer hører til en egen, senere skrivevei.';

revoke execute on function api.create_source(
  text, text, text, text, text, text, text, date, text
) from public;
grant execute on function api.create_source(
  text, text, text, text, text, text, text, date, text
) to authenticated;
