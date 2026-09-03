-- ============================================================================
-- Migrasjon 005c — redaktørkontoen får `editor`-rollen, altså retten til å
--                  registrere kilder og evidens som forslag
--
-- Utvider medlemskapsmodellen fra migrasjon 005 (§20) på samme måte som 005a og
-- 005b, står utenfor den planlagte rekken i MVP_IMPLEMENTATION_PLAN.md §18-§27
-- og får derfor en bokstav. Nummeret 009 er fortsatt reservert for DrugProduct-
-- og importfundamentet (§26).
--
-- ----------------------------------------------------------------------------
-- Hvorfor denne migrasjonen finnes
--
-- Migrasjon 007c åpnet den kontrollerte skriveveien `api.create_source(...)`,
-- og den krever gjennom `knowledge.assert_editor_authorized()` en gyldig
-- tildeling med `role_code = 'editor'`. Ingen migrasjon tildelte den rollen til
-- noen: migrasjon 005b tildeler `reviewer`, og bare den. Skriveveien var derfor
-- stengt for enhver innlogget bruker i ethvert miljø, også i produksjon —
-- «Brukeren har ikke gyldig editor-rolle» på `/sources/new` (§74.24, GitHub-issue
-- 36).
--
-- Det var aldri en feil i 007c. Kontrollen skal være der, og den skal avvise;
-- det som manglet var tildelingen på den andre siden. Denne migrasjonen skriver
-- den, og gjør ingenting annet.
--
-- ----------------------------------------------------------------------------
-- Hvorfor `editor` kan selvtildeles, og hvorfor begrunnelsen ikke arves fra 005b
--
-- Migrasjon 005b begrunnet selvtildelingen av `reviewer` med
-- ANTIDEP_CONSTITUTION.md §12: prosjekteieren *er* den navngitte kvalifiserte
-- redaktøren, og det finnes ingen høyere menneskelig instans i basen som kunne
-- tildelt faglig godkjenningsrett. Den begrunnelsen gjelder en rett til å
-- godkjenne. Den skal ikke gjenbrukes her, fordi `editor` er en annen rett med
-- en annen terskel — og en tildeling som arver en begrunnelse, er en tildeling
-- ingen har tatt stilling til.
--
-- `editor` er retten til å registrere kilder og evidens som *forslag*
-- (CONTENT_GOVERNANCE.md §8: opprette og redigere utkast, håndtere kilde- og
-- metadataarbeid, sende innhold til review). Den gir ikke:
--
--   faglig godkjenningsrett   `workflow.enforce_reviewer_qualification()` krever
--                             `reviewer` på beslutningstidspunktet, og leser
--                             ikke `editor` i det hele tatt
--   publiseringsrett          `knowledge.assert_publisher_authorized(uuid, uuid)`
--                             krever `publisher`, og sier selv at «å godkjenne og
--                             å publisere er to forskjellige handlinger»
--   en vei utenom gaten       publiseringsgaten i migrasjon 006 stiller sju krav
--                             som ingen rolletildeling kan innfri
--
-- Terskelen for selvtildeling er derfor lavere enn for `reviewer`, og det er en
-- konsekvens av hva rollen kan utrette alene: ingenting en editor registrerer,
-- kan nå en kliniker uten at en verifikasjon, en menneskelig godkjenning og en
-- publisering har funnet sted etterpå (ANTIDEP_CONSTITUTION.md §12, §13). En
-- selvtildelt `editor` utvider altså ikke den faglige autoriteten prosjekteieren
-- allerede har; den gjør et arbeidsverktøy tilgjengelig for den som uansett er
-- eneste redaktør.
--
-- Det som *ikke* følger av dette, og som ikke skal leses inn i tildelingen: at
-- samme person har både `editor` og `reviewer`, betyr at forfatter og godkjenner
-- er samme menneske for alt denne redaktøren selv registrerer.
-- CONTENT_GOVERNANCE.md §5 krever at høyrisikoinnhold godkjennes av noen som
-- ikke var hovedforfatter. Fram til nå har §5 vært innfridd nærmest ved et uhell,
-- fordi det eneste innholdet i basen er skrevet av en KI-aktør. Denne
-- tildelingen gjør bindingen konkret, og den er ført som gjeld i
-- MVP_IMPLEMENTATION_PLAN.md §74.7 med utløsende hendelse «før første
-- publisering av klinisk innhold». Migrasjonen løser den ikke og later ikke som
-- om den gjør det; den skriver den inn i `grant_reason`, der en revisor finner
-- den ved siden av rettigheten den gjelder.
--
-- ----------------------------------------------------------------------------
-- Hvorfor dette er en ny funksjon, og ikke en parameter på 005b sin
--
-- `workflow.ensure_named_editor_authorization()` gjør nesten det samme, og
-- fristelsen er å gi den en `p_role`-parameter framfor å skrive en funksjon til.
-- Migrasjon 005b avviste nettopp den formen med en begrunnelse som gjelder like
-- fullt her: en parameterisert utgave ville vært en generell «gi denne kontoen
-- hvilken som helst rolle»-funksjon, altså en rettighetseskalering med et
-- vennlig navn. `publisher` og `admin` ville vært like tilgjengelige som
-- `editor`, og forskjellen mellom de fire rollene ville flyttet seg fra koden til
-- den som skriver kallet.
--
-- Prisen er at de fire tilstandene under (gyldig nå, framtidig, avsluttet, ingen)
-- er skrevet ned to steder. Den er betalt bevisst, og den er lavere enn den ser
-- ut: 005b sin funksjon eier i tillegg koblingen mellom aktørraden og
-- brukerkontoen, og den er *ikke* gjentatt her — denne funksjonen krever at
-- koblingen finnes, og skriver den ikke selv. Å endre 005b sin funksjon i stedet
-- ville dessuten vært å skrive om sikkerhetskritisk kode som allerede har kjørt i
-- produksjon (§74.23), for å få den til å tjene et annet formål enn den ble
-- reviewet for.
--
-- ----------------------------------------------------------------------------
-- Miljøavhengig, etter samme «vei a» som 005b
--
-- `workflow.user_roles.user_id` er NOT NULL med fremmednøkkel til `auth.users`.
-- Kontoen finnes bare i det hostede prosjektet; CI og lokal utvikling starter en
-- fersk stack uten den. MVP_IMPLEMENTATION_PLAN.md §74.18 valgte «vei a»:
-- tildelingen gjøres betinget av at kontoen faktisk finnes. Vei b (seedfilen)
-- kjører etter migrasjonene og hjelper ikke; vei c (en operasjonell
-- engangshandling utenfor repoet) bryter §54 og gjør tildelingen usporbar.
--
-- Prisen er den samme som i 005b, og betales på samme måte:
--
--   1. Raden uteblir ikke i stillhet. Mangler kontoen, gir funksjonen en synlig
--      `notice` og returnerer statusen `account_missing`.
--   2. Logikken ligger i én navngitt funksjon, slik at testene kjører nøyaktig
--      den koden som kjører i produksjon framfor en kopi av den.
--   3. Begge grenene kjøres i CI. `380_source_registration_role_test.sql` dekker
--      den negative — kontoen mangler, ingenting skrives — og den positive ved å
--      opprette kontoen inne i en transaksjon som rulles tilbake.
--
-- Funksjonen blir stående etter migrasjonen, med hensikt: i et miljø der kontoen
-- kommer senere, skal tildelingen kunne fullføres med ett kall til framfor med en
-- ny migrasjon som bærer en andre kopi av logikken.
--
-- ----------------------------------------------------------------------------
-- Koblingen mellom aktør og konto er en forutsetning, ikke noe funksjonen ordner
--
-- `knowledge.assert_editor_authorized()` slår opp aktøren på
-- `auth_user_id = auth.uid()` og krever *begge* deler: en aktørrad knyttet til
-- kontoen, og en gyldig `editor`-tildeling. En tildeling til en konto uten
-- aktørrad ville derfor vært en rettighet uten den attribusjonen den hviler på —
-- skriveveien ville fortsatt avvist kalleren, bare med en annen feilmelding.
--
-- Koblingen er migrasjon 005b sin, og settes der. Finner denne funksjonen kontoen
-- i `auth.users` uten at aktøren peker på den, er migrasjonskjeden brutt eller
-- 005b sin funksjon ikke kalt i dette miljøet, og det skal feile høyt framfor å
-- skrive en rettighet ingen kan bruke.
--
-- ----------------------------------------------------------------------------
-- Hva «allerede tildelt» betyr, og hvorfor det ikke er «valid_to is null»
--
-- Uendret fra 005b, og av samme grunn: `workflow.user_roles` er en
-- gyldighetsmodell og ikke et flagg. Tildelingen har et halvåpent intervall
-- [valid_from, valid_to), og `valid_to` kan være satt allerede ved tildeling som
-- en planlagt utløpsdato. «Løpende» og «gyldig nå» er derfor to forskjellige
-- spørsmål, og bare det andre er det funksjonen skal svare på.
--
--   gyldig nå               already_authorized   ingenting skrives
--   starter i framtiden     role_not_yet_valid   ingenting skrives
--   avsluttet               role_ended           ingenting skrives
--   ingen tildeling         authorized           tildelingen skrives
--
-- Gyldighet måles med `statement_timestamp()` og ikke med `now()`: dette er et
-- predikat som *avgjør* noe (MVP_IMPLEMENTATION_PLAN.md §74.6).
--
-- **En avsluttet tildeling gjeninnføres ikke.** DATABASE_ARCHITECTURE.md §46
-- krever at en rettighet skal kunne tilbakekalles umiddelbart, og en
-- tilbakekalling som en rutinemessig `supabase db push` stilltiende omgjør, er
-- ingen tilbakekalling. `workflow.freeze_role_grant()` sier det samme om
-- modellen: en gjeninnføring er en ny tildeling med sin egen begrunnelse og sitt
-- eget tidsrom, og en slik begrunnelse kan ikke dikte seg selv opp i en
-- bootstrap. Funksjonen rapporterer `role_ended` og lar et menneske avgjøre.
--
-- Predikatet er avgrenset til `scope_id is null`, samme nøkkel som
-- `user_roles_no_overlapping_grant_excl` bruker. En *avgrenset* editor-tildeling
-- er en annen og smalere rettighet: den kolliderer ikke med denne, og den skal
-- verken blokkere tildelingen eller telle som den. Merk at
-- `knowledge.assert_editor_authorized()` godtar begge — en Source er ikke selv
-- avgrenset til noe klinisk begrep (§74.24) — men det gjør dem ikke til samme
-- tildeling i medlemskapsmodellen.
--
-- ----------------------------------------------------------------------------
-- Hva migrasjonen bevisst IKKE gjør
--
-- Den svekker ingen kontroll. `api.create_source(...)` og
-- `knowledge.assert_editor_authorized()` er urørt: migrasjonen legger til en rad
-- som består den kontrollen som allerede finnes, og endrer ikke kontrollen selv.
--
-- Den registrerer ingen verifikasjon, ingen reviewbeslutning og ingen
-- publisering, og den åpner ikke publiseringsgaten. Milepæl B mangler fortsatt
-- ekstraksjonsverifikasjonene, claim-verifikasjonene og selve godkjenningen
-- (§74.4). Den rører heller ikke `reviewer`-tildelingen fra 005b: de to rollene
-- er forskjellige rettigheter, de lever som hver sin rad, og ingen av dem er
-- utledet av den andre.
-- ============================================================================

create function workflow.ensure_editor_role_grant()
  returns text
  language plpgsql
  -- SECURITY INVOKER (standard): funksjonen skal ikke kunne gi mer enn kalleren
  -- allerede har. Tomt search_path og schemakvalifiserte navn likevel, etter
  -- samme mønster som resten av funksjonene i migrasjon 005 og 005b
  -- (DATABASE_ARCHITECTURE.md §50).
  set search_path = ''
as $$
declare
  -- Samme konto og samme aktørnøkkel som migrasjon 005b. Konstanter i kroppen,
  -- ikke parametere: funksjonen kan bare gjøre denne ene tildelingen, aldri en
  -- vilkårlig. At raden finnes, er `auth.users`-oppslaget under som avgjør —
  -- ikke denne konstanten.
  c_account_id constant uuid := 'a703ede9-3f58-4de9-8c85-73936d58df1f';
  c_actor_key constant text := 'human:peder-holman';
  v_actor_id uuid;
  v_linked_account_id uuid;
  -- Ett oppslag, tre svar. Å stille de tre spørsmålene hver for seg ville gjort
  -- rekkefølgen mellom dem til et implisitt valg; her er presedensen skrevet ut.
  v_valid_now boolean;
  v_starts_later boolean;
  v_any_grant boolean;
begin
  select a.id, a.auth_user_id into v_actor_id, v_linked_account_id
  from provenance.actors a
  where a.actor_key = c_actor_key;

  -- Aktørraden kommer fra migrasjon 005a og skal alltid finnes. Mangler den, er
  -- migrasjonskjeden brutt, og det skal feile høyt framfor å bli en stille no-op
  -- som ser ut som «kontoen manglet».
  if v_actor_id is null then
    raise exception using
      errcode = 'no_data_found',
      message = format('Aktøren %L finnes ikke; migrasjon 005a har ikke kjørt.', c_actor_key),
      hint = 'Rolletildelingen forutsetter at den navngitte kvalifiserte redaktøren er registrert som aktør.';
  end if;

  if not exists (select 1 from auth.users u where u.id = c_account_id) then
    raise notice
      'Brukerkontoen % finnes ikke i auth.users. Editor-rollen er ikke tildelt, og skriveveien api.create_source() er derfor fortsatt stengt i dette miljøet. Dette er forventet i en lokal stack og i CI; kall workflow.ensure_editor_role_grant() på nytt i miljøet der kontoen finnes.',
      c_account_id;
    return 'account_missing';
  end if;

  -- Kontoen finnes, men aktøren peker ikke på den. Da ville tildelingen vært en
  -- rettighet uten den attribusjonen den hviler på: skriveveien slår opp aktøren
  -- på auth_user_id og ville avvist kalleren uansett. Koblingen er 005b sin, og
  -- settes der — ikke her, hvor en andre kopi av den logikken ville kunnet drive
  -- fra originalen.
  if v_linked_account_id is distinct from c_account_id then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Aktøren %L er ikke knyttet til brukerkontoen %L, og kan ikke tildeles editor-rollen for den.',
        c_actor_key, c_account_id
      ),
      hint = 'Koblingen settes av workflow.ensure_named_editor_authorization() (migrasjon 005b). Kall den først i dette miljøet. Peker aktøren på en annen konto, er den frosset av provenance.freeze_actor_identity(), og en annen person er en annen aktør med sin egen rad.';
  end if;

  select
    count(*) filter (
      where ur.valid_from <= statement_timestamp()
        and (ur.valid_to is null or ur.valid_to > statement_timestamp())
    ) > 0,
    count(*) filter (where ur.valid_from > statement_timestamp()) > 0,
    count(*) > 0
  into v_valid_now, v_starts_later, v_any_grant
  from workflow.user_roles ur
  where ur.user_id = c_account_id
    and ur.role_code = 'editor'
    and ur.scope_id is null;

  -- Presedensen er skrevet ut framfor å falle ut av rekkefølgen på tre
  -- uavhengige if-er. En avsluttet tildeling ved siden av en løpende betyr at
  -- rettigheten gjelder; det motsatte svaret ville vært feil på den farligste
  -- måten en autorisasjonskontroll kan ta feil.
  if v_valid_now then
    return 'already_authorized';
  end if;

  if v_starts_later then
    raise notice
      'Kontoen % har en editor-tildeling som først begynner å gjelde senere. Ingen ny tildeling er skrevet: en tildeling nå ville overlappet den, og databasen ville avvist den (user_roles_no_overlapping_grant_excl).',
      c_account_id;
    return 'role_not_yet_valid';
  end if;

  if v_any_grant then
    raise notice
      'Kontoen % har hatt en editor-tildeling som er avsluttet. Ingen ny er skrevet: en tilbakekalling som en migrasjonskjøring omgjør, er ingen tilbakekalling (DATABASE_ARCHITECTURE.md §46). En gjeninnføring er en ny tildeling med sin egen begrunnelse, og den avgjørelsen hører til et menneske.',
      c_account_id;
    return 'role_ended';
  end if;

  insert into workflow.user_roles
    (user_id, role_code, scope_id, granted_by_actor_id, grant_reason)
  values (
    c_account_id,
    'editor',
    -- NULL betyr «uten avgrensning», ikke «ukjent avgrensning». En Source er ikke
    -- selv avgrenset til ett klinisk begrep, så en avgrenset tildeling ville vært
    -- en presisjon uten dekning i det objektet rollen først skal brukes på.
    null,
    v_actor_id,
    'Selvtildeling, og terskelen er en annen enn for reviewer-rollen. editor gir rett til å registrere kilder og evidens som forslag, og ingenting mer: verken faglig godkjenningsrett eller publiseringsrett følger av den, og alt som registreres må gjennom verifikasjon, menneskelig godkjenning og publiseringsgaten før det kan nå en kliniker (ANTIDEP_CONSTITUTION.md §12, §13). Rollen kan derfor ikke alene føre noe ut i produktet, og den utvider ikke den faglige autoriteten prosjekteieren allerede har. Antidep har én redaktør og ingen høyere menneskelig instans i basen; alternativet ville gjort en KI-aktør til opphavet til et menneskes redaksjonelle rett (§10). Ingen CHECK forbyr selvtildeling, så begrunnelsen står her. At samme person nå både registrerer innhold og godkjenner det, er registrert gjeld (CONTENT_GOVERNANCE.md §5, MVP_IMPLEMENTATION_PLAN.md §74.7) og skal avklares før første publisering av klinisk innhold.'
  );

  return 'authorized';
end;
$$;

comment on function workflow.ensure_editor_role_grant() is
  'Idempotent tildeling av `editor`-rollen til den navngitte kvalifiserte redaktørens brukerkonto, altså retten til å registrere kilder og evidens som forslag (CONTENT_GOVERNANCE.md §8). Åpner den kontrollerte skriveveien api.create_source(text, text, text, text, text, text, text, date, text) fra migrasjon 007c, som krever en gyldig editor-tildeling gjennom knowledge.assert_editor_authorized(). Gir verken faglig godkjenningsrett (reviewer) eller publiseringsrett (publisher): de tre er forskjellige rettigheter med hver sin rad. Forutsetter at aktørraden er knyttet til kontoen av workflow.ensure_named_editor_authorization() (migrasjon 005b) og setter ikke koblingen selv. Returnerer account_missing (ingen rad i auth.users), authorized (tildelingen ble skrevet), already_authorized (en tildeling er gyldig nå), role_not_yet_valid (en tildeling begynner å gjelde senere) eller role_ended (en tildeling er avsluttet). Bare authorized skriver noe. Gyldighet måles med statement_timestamp() fordi predikatet avgjør noe (MVP_IMPLEMENTATION_PLAN.md §74.6). En avsluttet tildeling gjeninnføres aldri: en tilbakekalling som en migrasjonskjøring omgjør, er ingen tilbakekalling (DATABASE_ARCHITECTURE.md §46). Konto og aktørnøkkel er konstanter i kroppen, og rollen er det også: funksjonen kan bare gjøre denne ene tildelingen, aldri en vilkårlig.';

revoke execute on function workflow.ensure_editor_role_grant() from public;

-- Selve utførelsen. `select` framfor `do`, slik at statusen står i utdataene fra
-- `supabase db push` og `supabase db reset` ved siden av en eventuell notice.
select workflow.ensure_editor_role_grant();
