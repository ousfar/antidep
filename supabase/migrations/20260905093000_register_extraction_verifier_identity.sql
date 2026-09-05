-- ============================================================================
-- Migrasjon 005f — den første agentidentiteten: ekstraksjonsverifikatoren
--
-- Utvider aktørregisteret fra migrasjon 005 (§22) og identitetsmodellen fra
-- 005e, og står utenfor den planlagte rekken i MVP_IMPLEMENTATION_PLAN.md
-- §18-§27. Nummeret 009 er fortsatt reservert for DrugProduct-/importfundamentet
-- (§26).
--
-- ----------------------------------------------------------------------------
-- Hva raden er, og hva den ikke er
--
-- To rader: en agentaktør i rollen extraction_verification, og den tekniske
-- identiteten den handler med. Aktøren er den som står oppført på
-- verifikasjonene i ettertid; identiteten er legitimasjonen kjøreren
-- autentiserer seg med, og de to er skilt fordi legitimasjonen kan roteres uten
-- at historikken skifter opphav.
--
-- Identiteten er **inert etter denne migrasjonen**. secret_hash er NULL, og
-- provenance.authenticate_agent_identity() avviser en identitet uten utstedt
-- legitimasjon. Å registrere en identitet og å gi den evnen til å handle er to
-- forskjellige handlinger, og denne migrasjonen gjør bare den første.
--
-- ----------------------------------------------------------------------------
-- Hvorfor legitimasjonen ikke utstedes her
--
-- En hemmelighet som ble generert av en migrasjon, måtte enten stå i repoet
-- eller returneres til den som kjørte migrasjonen. Det første er utelukket
-- (DATABASE_ARCHITECTURE.md §49: ingen hemmeligheter i repoet). Det andre ville
-- ført klartekstverdien gjennom en agentsesjons logg og videre inn i en
-- transkripsjon — altså spredt den til nøyaktig de stedene en legitimasjon ikke
-- skal ligge.
--
-- Utstedelsen hører derfor til den PR-en som faktisk bygger kjøreren, og gjøres
-- med ett kall til provenance.issue_agent_identity_credential(text, text) i det miljøet
-- kjøreren skal lese hemmeligheten fra. Fram til da er identiteten registrert,
-- reviewbar og ute av stand til å gjøre noe.
--
-- ----------------------------------------------------------------------------
-- Hvorfor nøkkelen har et løpenummer
--
-- `-01` er ikke pynt. Målet er flere uavhengige kontrollag framfor manuell
-- menneskelig kontroll, og et andre kontrollag er en andre aktør med samme
-- rolle, sin egen identitet og sin egen kjøring — ikke en ny rolle og ikke en ny
-- legitimasjon på den samme identiteten. Nummeret gjør at den andre kan hete det
-- den skal hete, framfor å arve et navn som allerede var tatt av det som skulle
-- vært det første av flere.
--
-- Rollen er den samme for begge: rollen er rettighetsgrensen, ikke identiteten
-- (migrasjon 005e).
--
-- ----------------------------------------------------------------------------
-- Hva denne identiteten kan verifisere, og hva den ikke kan
--
-- workflow.evidence_verifications krever at verifikatoren er en annen aktør enn
-- den som laget funnet. Avlest mot de tre evidensfunnene som finnes i
-- produksjon i dag (§74.29):
--
--   to funn opprettet av `agent:evidence-extraction`  kan verifiseres av denne
--   ett funn opprettet av den menneskelige redaktøren  kan verifiseres av denne
--
-- Den kan ikke verifisere noe den selv har laget, og den kan ikke lage noe: den
-- har rollen extraction_verification og ingen annen, så
-- provenance.authenticate_agent_identity() avviser den for enhver
-- ekstraksjonsoperasjon. Den kan heller ikke registrere en reviewbeslutning:
-- workflow.review_decisions krever en menneskelig aktør, deklarativt håndhevet,
-- og ANTIDEP_CONSTITUTION.md §12 er uendret.
--
-- ----------------------------------------------------------------------------
-- Registreringen er attribuert til et menneske, og det er en regel
--
-- registered_by_actor_id peker på den navngitte kvalifiserte redaktøren
-- (migrasjon 005a), og agent_identities_registered_by_human_check håndhever at
-- den *må* peke på et menneske. En agent som kunne registrere agenter, ville
-- vært en rettighetseskalering med ett ekstra ledd (CONTENT_GOVERNANCE.md §14).
-- ============================================================================

insert into provenance.actors (actor_type, actor_key, display_name, description, agent_role)
values (
  'agent',
  'agent:extraction-verification',
  'Antidep ekstraksjonsverifikator',
  'KI-prosess i rollen som kontrollerer at et evidensfunn faktisk gjengir det kilden rapporterer (EVIDENCE_PIPELINE.md §25, ANTIDEP_CONSTITUTION.md §11). Kontrollerer ekstraksjoner andre aktører har laget, mot kildematerialet, og kan aldri kontrollere en ekstraksjon den selv står bak: workflow.evidence_verifications avviser en verifikasjon der verifikator og ekstraktør er samme aktør. Rollen er samtidig rettighetsgrensen — aktøren har ingen ekstraksjonsrolle, og kan derfor ikke registrere evidensfunn i det hele tatt. Kjører med sin egen tekniske identitet (provenance.agent_identities), ikke med en brukerkonto og ikke med service_role.',
  'extraction_verification'
);

insert into provenance.agent_identities (
  actor_id,
  agent_role,
  identity_key,
  registered_by_actor_id,
  registered_by_actor_type,
  registration_reason
)
select
  verifier.id,
  'extraction_verification'::provenance.agent_role,
  'agent-identity:extraction-verification-01',
  editor.id,
  'human'::provenance.actor_type,
  'Første tekniske agentidentitet i Antidep, registrert for at ekstraksjonsverifikasjonen (MVP_IMPLEMENTATION_PLAN.md §15, ledd 3) skal kunne utføres av en separat KI-verifikator framfor av en andre navngitt person. Valget mellom de to er tatt som en prosjektbeslutning: kontrollen skal ligge i flere uavhengige agentledd, og menneskelig kontroll skal brukes der den trengs framfor som normalvei (§74.31). Identiteten har rollen extraction_verification og ingen annen, og kan derfor verken registrere evidensfunn, formulere påstander eller registrere en faglig godkjenning — den siste er dessuten forbeholdt mennesker av ANTIDEP_CONSTITUTION.md §12, uendret. Legitimasjon er ikke utstedt: identiteten er inert til provenance.issue_agent_identity_credential(text, text) kalles i det miljøet kjøreren skal lese hemmeligheten fra.'
from
  (select id from provenance.actors where actor_key = 'agent:extraction-verification') as verifier,
  (select id from provenance.actors where actor_key = 'human:peder-holman') as editor;

-- Registreringen skal ikke kunne bli en stille no-op om en av de to
-- aktøroppslagene svikter: en tom krysskobling ville satt inn null rader uten å
-- feile, og identiteten ville manglet uten at noe sa fra. Samme resonnement som
-- migrasjon 005c gjør for en manglende aktørrad.
do $$
begin
  if not exists (
    select 1 from provenance.agent_identities
    where identity_key = 'agent-identity:extraction-verification-01'
  ) then
    raise exception using
      errcode = 'no_data_found',
      message = 'Agentidentiteten agent-identity:extraction-verification-01 ble ikke registrert.',
      hint = 'Registreringen forutsetter at både agent:extraction-verification og human:peder-holman finnes som aktører. Kontroller at migrasjon 005a har kjørt.';
  end if;
end;
$$;
