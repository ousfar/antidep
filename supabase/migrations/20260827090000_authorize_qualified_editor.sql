-- ============================================================================
-- Migrasjon 005b — redaktørens brukerkonto knyttes til aktørraden, og
--                  reviewer-rollen tildeles
--
-- Utvider aktørregisteret og medlemskapsmodellen fra migrasjon 005 (§20) på
-- samme måte som 005a, står utenfor den planlagte rekken i
-- MVP_IMPLEMENTATION_PLAN.md §18-§27 og får derfor en bokstav. Nummeret 009 er
-- fortsatt reservert for DrugProduct- og importfundamentet (§26).
--
-- ----------------------------------------------------------------------------
-- Hvorfor denne migrasjonen finnes
--
-- Migrasjon 005a registrerte den navngitte kvalifiserte redaktøren
-- ANTIDEP_CONSTITUTION.md §12 krever, men bevisst uten brukerkonto og uten
-- rolletildeling: kontoen er en reell Supabase-konto som må opprettes i
-- autentiseringslaget, ikke i en migrasjon. Kontoen er nå opprettet av
-- prosjekteieren i det hostede prosjektet (MVP_IMPLEMENTATION_PLAN.md §74.18).
--
-- Denne migrasjonen betaler ut den koblingen: den knytter aktørraden til
-- kontoen og tildeler `reviewer`-rollen. Det er den første av de fire tingene
-- som gjenstår for Milepæl B (§74.4). Den åpner fortsatt ikke
-- publiseringsgaten: G4/G5, G8/G9 og G13 er urørt, og en godkjenning er en
-- utført menneskelig handling som ingen migrasjon kan registrere på forskudd.
--
-- ----------------------------------------------------------------------------
-- Migrasjonen er miljøavhengig, og det er et valg med en pris
--
-- `workflow.user_roles.user_id` er NOT NULL med fremmednøkkel til `auth.users`.
-- Kontoen finnes bare i det hostede prosjektet; CI og lokal utvikling starter
-- en fersk stack uten den. MVP_IMPLEMENTATION_PLAN.md §74.18 veide tre veier
-- og valgte «vei a»: koblingen gjøres betinget av at kontoen finnes.
--
--   Vei b — å seede en tilsvarende konto i supabase/seed.sql — er ikke en vei.
--   `supabase/config.toml` sier det selv om [db.seed]: «If enabled, seeds the
--   database after migrations during a db reset.» Seedfilen kjøres etter
--   migrasjonene, så denne migrasjonen ville uansett kjørt før kontoen fantes.
--
--   Vei c — å holde koblingen utenfor migrasjonene som en operasjonell
--   engangshandling — bryter §54 og gjør rolletildelingen usporbar i repoet.
--
-- Prisen for vei a står i §74.18: migrasjonen gjør forskjellige ting i
-- forskjellige miljøer, og CI kunne endt opp med aldri å kjøre den grenen som
-- faktisk kjører i produksjon. Prisen betales her, ikke ties i hjel:
--
--   1. Raden uteblir ikke i stillhet. Mangler kontoen, gir funksjonen under en
--      synlig `notice` og returnerer statusen `account_missing`.
--   2. Logikken ligger i én navngitt funksjon, ikke som løse setninger i denne
--      filen, slik at testene kan kjøre nøyaktig den koden som kjører i
--      produksjon framfor en kopi av den. En kopi ville vært to påstander som
--      kan drive fra hverandre, ikke én kontrollert.
--   3. Begge grenene kjøres i CI. `220_provenance_seed_test.sql` dekker den
--      negative — kontoen mangler, ingenting skrives —, og
--      `350_editor_authorization_test.sql` dekker den positive ved å opprette
--      kontoen inne i en transaksjon som rulles tilbake, slik testene allerede
--      gjør for alt annet.
--
-- Funksjonen blir stående etter migrasjonen, og det er med hensikt. Vei a betyr
-- at koblingen kan bli stående ugjort i et miljø der kontoen kommer senere. Da
-- skal den kunne fullføres ved å kalle den samme funksjonen én gang til, ikke
-- ved at noen skriver en ny migrasjon med en andre kopi av logikken.
--
-- Funksjonen tar ingen parametere. Både kontoens `uuid` og aktørens `actor_key`
-- er konstanter i kroppen, slik at den bare kan gjøre denne ene tildelingen.
-- En parameterisert utgave ville vært en generell «gi hvem som helst
-- reviewer»-funksjon, altså en rettighetseskalering med et vennlig navn.
--
-- ----------------------------------------------------------------------------
-- Selvtildeling, og hvorfor begrunnelsen må stå i raden
--
-- `granted_by_actor_id` er NOT NULL og peker på en aktør. Beslutningen ble tatt
-- og skrevet ned i migrasjon 005a: rollen tildeles av redaktørens egen aktør.
-- Autoriteten kommer utenfra systemet, prosjekteieren *er* den kvalifiserte
-- redaktøren, og det finnes ingen høyere menneskelig instans i basen.
-- Alternativet ville gjort en KI-prosess til opphavet til et menneskes faglige
-- godkjenningsrett, stikk i strid med ANTIDEP_CONSTITUTION.md §10 og §12.
--
-- Ingen CHECK forbyr selvtildeling. Begrunnelsen står derfor eksplisitt i
-- `grant_reason`, som er NOT NULL nettopp fordi «en rettighet uten begrunnelse
-- ikke er etterprøvbar». Det er hele sikringen, og den er tekstlig — derfor
-- kontrollerer 350 at ordlyden faktisk navngir selvtildelingen.
--
-- ----------------------------------------------------------------------------
-- Hva migrasjonen bevisst IKKE gjør
--
-- Den registrerer ingen verifikasjon, ingen reviewbeslutning og ingen
-- publisering. Alle tre er utførte handlinger (ANTIDEP_CONSTITUTION.md §11,
-- §12), og ingen slik handling har funnet sted.
--
-- Den lukker heller ikke governance-hullet 005a gjorde synlig: kompetansekravet
-- for reviewer-scope er fortsatt ikke definert (CONTENT_GOVERNANCE.md §11), og
-- redaktøren er utpekt av seg selv. Tildelingen hviler på prosjekteierrollen,
-- og det står i `grant_reason` framfor å bli borte i en kommentar.
-- ============================================================================

create function workflow.ensure_named_editor_authorization()
  returns text
  language plpgsql
  -- SECURITY INVOKER (standard): funksjonen skal ikke kunne gi mer enn kalleren
  -- allerede har. Tomt search_path og schemakvalifiserte navn likevel, etter
  -- samme mønster som resten av funksjonene i migrasjon 005
  -- (DATABASE_ARCHITECTURE.md §50).
  set search_path = ''
as $$
declare
  -- Kontoen prosjekteieren opprettet i autentiseringslaget i det hostede
  -- prosjektet (MVP_IMPLEMENTATION_PLAN.md §74.18). Formen er kontrollert som
  -- gyldig uuid v4; at raden finnes, er det `auth.users`-oppslaget under som
  -- avgjør — ikke denne konstanten.
  c_account_id constant uuid := 'a703ede9-3f58-4de9-8c85-73936d58df1f';
  c_actor_key constant text := 'human:peder-holman';
  v_actor_id uuid;
  v_linked_account_id uuid;
  v_granted integer;
begin
  select a.id, a.auth_user_id into v_actor_id, v_linked_account_id
  from provenance.actors a
  where a.actor_key = c_actor_key;

  -- Aktørraden kommer fra migrasjon 005a og skal alltid finnes. Mangler den, er
  -- migrasjonskjeden brutt, og det skal feile høyt framfor å bli en stille
  -- no-op som ser ut som «kontoen manglet».
  if v_actor_id is null then
    raise exception using
      errcode = 'no_data_found',
      message = format('Aktøren %L finnes ikke; migrasjon 005a har ikke kjørt.', c_actor_key),
      hint = 'Rolletildelingen forutsetter at den navngitte kvalifiserte redaktøren er registrert som aktør.';
  end if;

  -- En aktør som allerede peker på en annen konto skal ikke få rollen tildelt
  -- til denne. provenance.freeze_actor_identity() ville nektet å flytte
  -- koblingen, og tildelingen ville da autorisert en konto som ikke er bundet
  -- til redaktøraktøren — altså en rettighet uten den attribusjonen den hviler
  -- på.
  if v_linked_account_id is not null and v_linked_account_id <> c_account_id then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Aktøren %L er allerede knyttet til brukerkontoen %L og kan ikke autoriseres for en annen.',
        c_actor_key, v_linked_account_id
      ),
      hint = 'Aktøridentiteten er frosset (provenance.freeze_actor_identity()). En annen person er en annen aktør, med sin egen rad.';
  end if;

  if not exists (select 1 from auth.users u where u.id = c_account_id) then
    raise notice
      'Brukerkontoen % finnes ikke i auth.users. Aktøren % er ikke knyttet til en konto, og reviewer-rollen er ikke tildelt. Dette er forventet i en lokal stack og i CI; kall workflow.ensure_named_editor_authorization() på nytt i miljøet der kontoen finnes.',
      c_account_id, c_actor_key;
    return 'account_missing';
  end if;

  -- Koblingen kan settes nøyaktig én gang fra NULL. Predikatet gjør kallet
  -- idempotent uten å be freeze_actor_identity() om unntak den ikke gir.
  update provenance.actors
  set auth_user_id = c_account_id
  where id = v_actor_id
    and auth_user_id is null;

  insert into workflow.user_roles
    (user_id, role_code, scope_id, granted_by_actor_id, grant_reason)
  select
    c_account_id,
    'reviewer',
    -- NULL betyr «uten avgrensning», ikke «ukjent avgrensning». Antidep har ett
    -- innholdsområde og én redaktør; en avgrensning til ett klinisk begrep ville
    -- vært en presisjon vi ikke har dekning for.
    null,
    v_actor_id,
    'Selvtildeling, og det er et bevisst valg. Prosjekteieren er den navngitte kvalifiserte redaktøren ANTIDEP_CONSTITUTION.md §12 krever, og det finnes ingen høyere menneskelig instans i Antidep som kunne tildelt rollen. Alternativet — at en KI-aktør tildeler et menneske faglig godkjenningsrett — ville gjort en KI-prosess til opphavet til den retten, stikk i strid med §10 og §12. Ingen CHECK forbyr selvtildeling, så begrunnelsen står her. Tildelingen hviler på prosjekteierrollen og ikke på et fastsatt kompetansekrav: Antidep har ennå ingen Clinical Lead til å definere kompetansekravene for reviewer-scope (CONTENT_GOVERNANCE.md §11). Den skal revurderes når kravene finnes.'
  where not exists (
    select 1
    from workflow.user_roles ur
    where ur.user_id = c_account_id
      and ur.role_code = 'reviewer'
      and ur.scope_id is null
      and ur.valid_to is null
  );

  get diagnostics v_granted = row_count;

  return case when v_granted > 0 then 'authorized' else 'already_authorized' end;
end;
$$;

comment on function workflow.ensure_named_editor_authorization() is
  'Idempotent autorisasjon av den navngitte kvalifiserte redaktøren (ANTIDEP_CONSTITUTION.md §12): knytter aktørraden fra migrasjon 005a til brukerkontoen og tildeler en løpende reviewer-rolle uten scope. Returnerer account_missing, authorized eller already_authorized. Kontoen finnes bare i miljøet den ble opprettet i, så funksjonen skriver ingenting og gir en notice der den mangler (MVP_IMPLEMENTATION_PLAN.md §74.18). Konto og aktørnøkkel er konstanter i kroppen: funksjonen kan bare gjøre denne ene tildelingen, aldri en vilkårlig.';

revoke execute on function workflow.ensure_named_editor_authorization() from public;

-- Selve utførelsen. `select` framfor `do`, slik at statusen står i utdataene fra
-- `supabase db push` og `supabase db reset` ved siden av en eventuell notice.
select workflow.ensure_named_editor_authorization();
