-- ============================================================================
-- Migrasjon 007b — kallerens egen autorisasjon blir lesbar
--
-- Utvider api-lesemodellen fra migrasjon 007 (§24) på samme måte som 007a, står
-- utenfor den planlagte rekken i MVP_IMPLEMENTATION_PLAN.md §18-§27 og får
-- derfor en bokstav. Nummeret 009 er fortsatt reservert for DrugProduct- og
-- importfundamentet (§26).
--
-- ----------------------------------------------------------------------------
-- Hvorfor denne migrasjonen finnes
--
-- Adminflyten (§29) er den ene leveransen Slice 1 mangler, og den kan ikke
-- begynne noe sted: hver eneste skjerm i den må først kunne svare på «hvem er
-- jeg, og hva har jeg lov til?». I dag kan ingen klient svare på noen av
-- delene. `workflow.user_roles` og `provenance.actors` er begge helt stengt for
-- klientrollene — ingen grant, ingen policy, default deny — og det er riktig
-- for alt annet enn kallerens egne rader.
--
-- Migrasjonen åpner nøyaktig de radene, og ingenting mer. Den er bevisst det
-- minste defensive førstesteget i adminflyten: en ren lesevei, ingen skrivevei,
-- ingen ny rettighet. Skriveveien er og blir en kontrollert SECURITY
-- DEFINER-funksjon (DATABASE_ARCHITECTURE.md §43), og
-- `030_conventions_test.sql` håndhever at ingen policy i de kanoniske
-- schemaene åpner for annet enn lesing.
--
-- Styrende dokumenter:
--   docs/DATABASE_ARCHITECTURE.md
--     §41  offentlig klient leser avledede views
--     §42  views skal ikke utilsiktet omgå RLS
--     §43  klienten skal ikke skrive direkte til kanoniske tabeller
--     §44  Data API-kontrakten skal være eksplisitt
--     §45  roller på applikasjonsnivå
--     §46  autorisasjonsdata leses fra medlemskapstabellen, ikke fra en claim
--     §48  RLS er default deny
--   docs/MVP_IMPLEMENTATION_PLAN.md
--     §29  Slice 1, «manuell adminflyt»
--     §47, §48 test med faktisk klientrolle, og ingen generell tabellskriving
--     §74.6 tid som avgjør måles på setningen
--   docs/ANTIDEP_CONSTITUTION.md
--     §12  navngitt kvalifisert redaktør
--     §14  attribusjon og etterprøvbarhet
--
-- ----------------------------------------------------------------------------
-- To spørsmål, to views, og hvorfor de ikke er slått sammen
--
-- «Hvem er jeg» og «hva har jeg lov til» har forskjellig kardinalitet: en
-- kaller har null eller én aktør, og null til mange rolletildelinger. Slått
-- sammen til ett view måtte identiteten enten forsvinne når det ikke finnes
-- noen rolletildeling — og et tomt svar sier da ingenting om aktøren — eller
-- bæres som en array. Begge deler er dårligere enn to views som hver svarer på
-- ett spørsmål og har sitt eget tomme tilfelle med en entydig betydning:
--
--   api.my_actor  tom  ingen aktørrad er knyttet til denne brukerkontoen
--   api.my_roles  tom  kalleren har ingen rolletildeling som gjelder nå
--
-- Viewene svarer hver for seg, og de svarer ikke på det sammensatte spørsmålet
-- «kan jeg utføre handling X». Det er adminflytens jobb, og den bygges over
-- disse to. Databasen leverer fakta; en avledet «du har lov»-boolean her ville
-- flyttet en autorisasjonsbeslutning inn i en projeksjon, og ville uansett ikke
-- vært den som gjelder: skriveoperasjonene kontrollerer rettigheten selv, på
-- sin egen setnings tidspunkt (`knowledge.assert_publisher_authorized(uuid, uuid)`).
--
-- ----------------------------------------------------------------------------
-- Tre lås, som i migrasjon 007, og en fjerde fra 007a
--
--   1. Schema-USAGE mangler. anon og authenticated har usage bare på api
--      (migrasjon 001), så de kan ikke navngi workflow.user_roles eller
--      provenance.actors i det hele tatt. Navneoppslaget for et view skjer ved
--      opprettelsen, så viewene leser videre.
--   2. RLS slipper bare gjennom kallerens egne rader. Policyene under er den
--      egentlige radgrensen, og de virker også om lås 1 skulle falle bort.
--   3. Bare SELECT er gitt, og bare til authenticated. anon får ingenting — en
--      uinnlogget kaller har verken aktør eller roller, og skal få avslag
--      framfor et tomt svar som kan forveksles med «ingen roller».
--   4. Granten er på kolonnenivå, ikke tabellnivå. Radene policyene slipper
--      gjennom bærer også `grant_reason`, `granted_by_actor_id`, `end_reason`
--      og aktørens `description` og `retirement_note`. Ingen av dem er
--      kallerens svar på «hva har jeg lov til»; de er governance-tekst om
--      beslutningen, og de hører ikke i klientflaten.
--
-- Merk for vaktposter, som i 007a: et kolonnegrant er *ikke* synlig i
-- has_table_privilege() eller information_schema.role_table_grants, og heller
-- ikke i pg_class.relacl. En vaktpost som bare leser tabellprivilegiet vil
-- svare «ingen tilgang» også når kolonner er åpnet, og være stille sann.
-- 030_conventions_test.sql leser nå pg_attribute.attacl i tillegg, og
-- 210_workflow_access_test.sql fører kolonnene uttømmende.
--
-- ----------------------------------------------------------------------------
-- Hvorfor gyldighetsvinduet ligger i viewet og eierskapet i policyen
--
-- De to predikatene beskytter forskjellige ting, og det er derfor de ligger
-- forskjellige steder:
--
--   eierskap        en sikkerhetsgrense. En kaller skal aldri kunne se en
--                   annens rolletildeling. Hører i RLS, som er radgrensen, og
--                   gjentas i viewet slik migrasjon 007 gjentar
--                   publiseringspredikatet: hvert lag skal være korrekt alene.
--   gyldighet nå    en projeksjonsbeslutning. En avsluttet tildeling er
--                   kallerens egen historikk, ikke en annens data, og å stenge
--                   den ute i RLS ville låst en senere `api`-projeksjon av
--                   kallerens rollehistorikk ute av sin egen tabell.
--
-- **workflow.user_roles er en gyldighetsmodell, ikke et flagg.** Det var
-- reviewfunnet i migrasjon 005b, og det gjelder her med full tyngde: intervallet
-- er halvåpent [valid_from, valid_to), og valid_to kan være satt allerede ved
-- tildeling som en planlagt utløpsdato. «Løpende» og «gyldig nå» er to
-- forskjellige spørsmål, og `valid_to is null` svarer på det første. Viewet
-- stiller det andre, med begge grenser:
--
--   valid_from <= statement_timestamp()      tildelingen har begynt å gjelde
--   valid_to is null or > statement_timestamp()   den er ikke avsluttet
--
-- Uten den nedre grensen ville en tildeling som først begynner å gjelde senere
-- blitt lest som gjeldende nå — en rettighet før den er gitt.
--
-- Tiden måles med statement_timestamp() og ikke now(), etter regelen i
-- MVP_IMPLEMENTATION_PLAN.md §74.6: dette er et predikat som *avgjør* noe.
-- now() er transaksjonens starttidspunkt, og en tilbakekalling ville da ikke
-- virket for en transaksjon som allerede var i gang. Samme valg, og samme
-- begrunnelse, som `knowledge.assert_publisher_authorized(uuid, uuid)`.
--
-- Prisen for at viewet bare viser det som gjelder nå, er ført som gjeld i
-- §74.7: en kaller kan ikke skille «rollen min utløp i går» fra «jeg har aldri
-- hatt en rolle». Begge svarene er like sanne som autorisasjonssvar — kalleren
-- har ingen rettighet nå — men de er forskjellige som forklaring.
--
-- ----------------------------------------------------------------------------
-- Hva viewene bevisst IKKE gjør
--
-- De tildeler ingenting, endrer ingenting og oppretter ingen aktør. En kaller
-- uten aktørrad får et tomt api.my_actor, ikke en rad opprettet på forespørsel:
-- aktørregisteret er festepunktet for all attribusjon (ANTIDEP_CONSTITUTION.md
-- §14), og en aktør som oppstår fordi noen logget inn ville vært en identitet
-- systemet selv fant på.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. RLS: kallerens egen aktørrad
--
-- provenance.actors har vært helt stengt siden migrasjon 005: RLS aktivert uten
-- policies, altså default deny for alle andre enn eieren. Dette er den første
-- policyen på tabellen.
--
-- `auth.uid()` brukes bare til identitet, aldri til autorisasjon
-- (DATABASE_ARCHITECTURE.md §46). Rollen leses fra medlemskapstabellen i punkt
-- 2, ikke fra en claim brukeren kan påvirke.
--
-- Formen `(select auth.uid())` framfor et bart kall er Supabases dokumenterte
-- idiom: uttrykket blir en InitPlan som evalueres én gang per setning framfor
-- én gang per rad. Semantisk er de like, siden auth.uid() er STABLE.
--
-- De seedede KI-aktørene — agent:evidence-extraction og agent:claim-synthesis —
-- har `auth_user_id is null`, og NULL = NULL er ukjent, ikke sant. En kaller
-- uten JWT-subjekt får derfor null rader og ikke hele aktørregisteret. Det
-- hviler på tre-verdi-logikken alene, så det er festet som en assertion i
-- 360_caller_authorization_test.sql framfor å stå som en kommentar.
-- ----------------------------------------------------------------------------
create policy actors_own_actor_read on provenance.actors
  for select to authenticated
  using (auth_user_id = (select auth.uid()));

comment on policy actors_own_actor_read on provenance.actors is
  'Kallerens egen aktørrad, og bare den. auth.uid() brukes til identitet, ikke til autorisasjon (DATABASE_ARCHITECTURE.md §46). anon er ikke med i policyen: en uinnlogget kaller har ingen aktør. Aktører uten brukerkonto — KI-aktørene og mennesker registrert før kontoen fantes — har auth_user_id NULL og slipper aldri gjennom, fordi NULL = NULL er ukjent. Policyen er radgrensen; kolonnegranten under avgjør hva av raden som kan leses.';

-- ----------------------------------------------------------------------------
-- 2. RLS: kallerens egne rolletildelinger
--
-- workflow.user_roles er autorisasjonskilden (DATABASE_ARCHITECTURE.md §46), og
-- den viktigste tabellen i hele modellen å ikke åpne for mye: en klientrolle som
-- kunne lese andres rader ville kunne kartlegge hvem som har faglige
-- rettigheter, og en som kunne skrive ville kunne gi seg selv dem. Policyen
-- gjelder derfor bare SELECT, bare for authenticated, og bare på rader der
-- user_id er kalleren selv.
--
-- Gyldighetsvinduet er bevisst ikke med her — se hovedkommentaren over.
-- ----------------------------------------------------------------------------
create policy user_roles_own_grants_read on workflow.user_roles
  for select to authenticated
  using (user_id = (select auth.uid()));

comment on policy user_roles_own_grants_read on workflow.user_roles is
  'Kallerens egne rolletildelinger, og bare dem. Radgrensen er eierskap og ikke gyldighet: en avsluttet tildeling er kallerens egen historikk, og avgrensningen til det som gjelder nå hører til projeksjonen i api.my_roles. Rollen leses her fra medlemskapstabellen og aldri fra en JWT-claim (DATABASE_ARCHITECTURE.md §46). Bare SELECT: skriveveien er en kontrollert SECURITY DEFINER-funksjon (§43).';

-- ----------------------------------------------------------------------------
-- 3. Grant på kolonnenivå
--
-- Et security_invoker-view kan ikke projisere eller filtrere på en kolonne
-- kalleren mangler grant på, uansett hva viewet inneholder. Et policyuttrykk kan
-- derimot fritt referere kolonner kalleren ikke har — privilegiene gjelder
-- spørringen, ikke policyen — så radgrensen svekkes ikke av at granten er smal.
--
-- Kolonnene som er utelatt, er utelatt med hensikt:
--
--   provenance.actors.description        hvorfor aktøren finnes; governance-tekst
--   provenance.actors.retirement_note    hvorfor aktøren ble tatt ut av bruk
--   provenance.actors.auth_user_id       kalleren kjenner sin egen kontoidentitet
--                                        fra sesjonen; å projisere den tilbake
--                                        ville vært en kolonne uten informasjon
--   provenance.actors.agent_role         alltid NULL for en aktør med konto
--   workflow.user_roles.grant_reason     begrunnelsen for tildelingen. Den er
--                                        etterprøvbarheten i §14 og skrevet for
--                                        en revisor, ikke for innehaveren
--   workflow.user_roles.granted_by_actor_id  hvem som tildelte
--   workflow.user_roles.ended_by_actor_id, end_reason  hvem som avsluttet, og hvorfor
--   workflow.user_roles.id               tildelingens identitet; se punkt 5
--
-- `auth_user_id` og `user_id` er med i granten fordi viewene filtrerer på dem.
-- Begge er kallerens egen kontoidentitet, som kalleren allerede kjenner.
-- ----------------------------------------------------------------------------
grant select (id, actor_key, display_name, auth_user_id, retired_at)
  on provenance.actors to authenticated;

grant select (user_id, role_code, scope_id, scope_type, valid_from, valid_to)
  on workflow.user_roles to authenticated;

-- ----------------------------------------------------------------------------
-- 4. api.my_actor — hvem er jeg
--
-- Null eller én rad. `actors_auth_user_key` gjør auth_user_id unik, så to
-- aktørrader kan ikke peke på samme konto; regelen finnes nettopp for at kravet
-- om at godkjenner og forfatter er forskjellige ikke skal kunne omgås ved å
-- opprette en aktør til.
--
-- `actor_type` er bevisst ikke projisert. `actors_auth_user_is_human_check`
-- håndhever at bare en `human` kan ha en brukerkonto, så kolonnen ville hatt
-- nøyaktig én mulig verdi for hver rad viewet kan vise. Antakelsen er festet som
-- en assertion i 360_caller_authorization_test.sql, ikke etterlatt som en
-- kommentar — og den prøves ved å forsøke å opprette en KI-aktør med konto,
-- framfor ved å telle at det ikke finnes noen.
-- ----------------------------------------------------------------------------
create view api.my_actor
  with (security_invoker = true) as
select
  a.id           as actor_id,
  a.actor_key    as actor_key,
  a.display_name as display_name,
  a.retired_at   as retired_at
from provenance.actors a
where a.auth_user_id = (select auth.uid());

comment on view api.my_actor is
  'Aktørraden som er knyttet til den innloggede brukerkontoen, eller ingen rad. Et tomt svar betyr at ingen aktør er knyttet til kontoen — ikke at kalleren er ukjent for systemet — og en klient som viser noe annet enn nettopp det, hevder mer enn viewet sier. Radene filtreres av RLS på provenance.actors, ikke av dette viewet alene. Aktørtypen er ikke projisert: bare et menneske kan ha en brukerkonto (actors_auth_user_is_human_check), så kolonnen ville hatt én mulig verdi.';
comment on column api.my_actor.actor_id is
  'Aktørens stabile identitet, og den verdien senere skriveoperasjoner attribueres til (ANTIDEP_CONSTITUTION.md §14). Databasegenerert uuid.';
comment on column api.my_actor.actor_key is
  'Maskinlesbar, språkuavhengig og stabil nøkkel på formen «type:navn», for eksempel human:peder-holman. Endres ikke når visningsnavnet endres, og er frosset av provenance.freeze_actor_identity().';
comment on column api.my_actor.display_name is
  'Aktørens visningsnavn. Presentasjon, ikke identitet: navnet kan endres uten at aktøren blir en annen.';
comment on column api.my_actor.retired_at is
  'Tidspunktet aktøren ble tatt ut av bruk, eller NULL. En tilbaketrukket aktør beholder hele sin historikk, men kan ikke utføre nye handlinger — publiseringsoperasjonen avviser den (knowledge.assert_publisher_authorized(uuid, uuid)). En klient som ignorerer verdien vil vise rettigheter kalleren ikke får brukt. Begrunnelsen for tilbaketrekkingen er ikke eksponert.';

grant select on api.my_actor to authenticated;

-- ----------------------------------------------------------------------------
-- 5. api.my_roles — hva har jeg lov til nå
--
-- Én rad per rolletildeling som gjelder på spørringens tidspunkt. Ingen rad for
-- en tildeling som er avsluttet eller som først begynner å gjelde senere.
--
-- Tildelingens `id` er ikke projisert. Innenfor det settet viewet viser, er
-- (role_code, scope_id) allerede entydig: `user_roles_no_overlapping_grant_excl`
-- forbyr to overlappende tildelinger av samme rolle til samme bruker og samme
-- scope, og to rader som begge gjelder nå ville nettopp overlappet. En klient
-- trenger derfor ingen egen nøkkel, og tildelingens identitet er et
-- governance-objekt som hører til adminflyten framfor til innehaverens egen
-- visning. Også denne antakelsen prøves i 360_caller_authorization_test.sql ved
-- å forsøke innsettingen, ikke ved å lese constraint-definisjonen.
--
-- `scope_id` uten `scope_type` ville vært tvetydig i feil retning: en
-- *avgrenset* reviewer-tildeling er en smalere rettighet enn en uavgrenset, og
-- en klient som ikke ser avgrensningen ville lest den som full rett. Begge
-- kolonnene er derfor med, og de er NULL sammen — scope_type er en generert
-- kolonne utledet av scope_id nettopp for at de to ikke skal kunne komme i
-- utakt.
--
-- Scopets *etikett* er ikke med. `catalog.clinical_concepts` er bare lesbar for
-- klientrollene gjennom publiseringspredikatet i migrasjon 007, så et begrep som
-- ennå ikke har en publisert påstand under seg ville gitt en tom etikett ved
-- siden av en reell avgrensning — altså en avgrensning som så ut som ingen.
-- Prisen er at klienten foreløpig ikke kan navngi scopet; det er registrert som
-- gjeld i MVP_IMPLEMENTATION_PLAN.md §74.7.
-- ----------------------------------------------------------------------------
create view api.my_roles
  with (security_invoker = true) as
select
  ur.role_code::text  as role_code,
  ur.scope_id         as scope_id,
  ur.scope_type::text as scope_type,
  ur.valid_from       as valid_from,
  ur.valid_to         as valid_to
from workflow.user_roles ur
where ur.user_id = (select auth.uid())
  and ur.valid_from <= statement_timestamp()
  and (ur.valid_to is null or ur.valid_to > statement_timestamp());

comment on view api.my_roles is
  'Den innloggede brukerens egne rolletildelinger som gjelder nå. En avsluttet tildeling og en som først begynner å gjelde senere er begge fraværende: en tildeling er ingen rettighet utenfor sitt eget halvåpne intervall [valid_from, valid_to). Gyldigheten måles med statement_timestamp() og ikke now(), fordi predikatet avgjør noe (MVP_IMPLEMENTATION_PLAN.md §74.6) — en tilbakekalling skal virke umiddelbart (DATABASE_ARCHITECTURE.md §46). Et tomt svar betyr «ingen rettighet nå», og skiller ikke en utløpt tildeling fra en som aldri fantes. Viewet er en projeksjon og ikke autorisasjonen selv: skriveoperasjonene kontrollerer rettigheten på nytt på sin egen setnings tidspunkt.';
comment on column api.my_roles.role_code is
  'Applikasjonsrollen, som tekst (MVP_IMPLEMENTATION_PLAN.md §16). admin er bruker- og systemforvaltning og gir ikke faglig godkjenningsrett; klinisk godkjenning krever reviewer, og publisering krever publisher (DATABASE_ARCHITECTURE.md §45). De tre er forskjellige rettigheter og skal ikke slås sammen i visningen.';
comment on column api.my_roles.scope_id is
  'Det kliniske begrepet tildelingen er avgrenset til, eller NULL for en uavgrenset tildeling. NULL betyr «uten avgrensning», ikke «ukjent avgrensning». Etiketten er ikke eksponert; se viewkommentaren.';
comment on column api.my_roles.scope_type is
  'Hva scope_id peker på, som tekst, eller NULL når tildelingen er uavgrenset. Utledet av scope_id i en generert kolonne, så de to kan ikke komme i utakt. Kolonnen finnes for at en klient skal kunne se at en tildeling *er* avgrenset uten å kunne slå opp begrepet: en avgrenset rettighet som leses som uavgrenset er den farligste retningen å ta feil i.';
comment on column api.my_roles.valid_from is
  'Tidspunktet tildelingen begynte å gjelde. Alltid i fortiden for en rad som vises her.';
comment on column api.my_roles.valid_to is
  'Tidspunktet tildelingen opphører, eller NULL når ingen sluttdato er satt. En verdi her er en planlagt utløpsdato som ennå ikke har inntruffet — raden vises jo — og ikke en tilbakekalling som allerede har virket. Begrunnelsen for avslutningen er ikke eksponert.';

grant select on api.my_roles to authenticated;
