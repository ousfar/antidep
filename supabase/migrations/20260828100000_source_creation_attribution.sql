-- ============================================================================
-- Migrasjon 003a — knowledge.sources får created_by_actor_id
--
-- Utvider kildetabellen fra migrasjon 003 (§20), står utenfor den planlagte
-- rekken i MVP_IMPLEMENTATION_PLAN.md §18-§27 og får derfor en bokstav, etter
-- samme konvensjon som 005a, 006a og 007a. Nummeret 009 er fortsatt reservert
-- for DrugProduct- og importfundamentet (§26).
--
-- ----------------------------------------------------------------------------
-- Et hull migrasjon 005 etterlot
--
-- Migrasjon 005 (§22) la created_by_actor_id til evidence_items, claims,
-- claim_revisions, claim_evidence_links og evidence_assessments — «attribusjonen
-- legges på plass», sa migrasjonens egen kommentar. knowledge.sources sto
-- utenfor lista, uten begrunnelse. Aktørraden agent:evidence-extraction som
-- samme migrasjon registrerte, sier selv at den «Produserte kildene,
-- kildeversjonene og evidensfunnene i migrasjon 003» — kildene var alltid
-- omfattet av den setningen, bare ikke av kolonnetillegget.
--
-- Konsekvensen har stått urørt siden: en kilde er det eneste kunnskapsobjektet i
-- Antidep uten et festepunkt for hvem som skrev den inn. Det er ikke en reell
-- risiko for de to seedede radene — proveniensen står i migrasjonsteksten — men
-- det blir en reell risiko i det øyeblikket en kilde kan opprettes av en
-- innlogget bruker (MVP_IMPLEMENTATION_PLAN.md §15, §29): en admin-RPC uten en
-- kolonne å skrive attribusjon til, ville enten manglet attribusjon eller måttet
-- late som om en KI-aktør skrev raden. Denne migrasjonen lukker hullet før
-- skriveveien i migrasjon 007c åpnes, av samme grunn som 005 la kolonnen til
-- før publiseringslaget i 006: attribusjon er en forutsetning for skrivevegien,
-- ikke noe som følger etter den.
--
-- Styrende dokumenter:
--   docs/ANTIDEP_CONSTITUTION.md §14  endringer skal være attribuerte
--   docs/DATABASE_ARCHITECTURE.md
--     §13, §16  knowledge.claims og knowledge.sources
--     §37  RESTRICT på fremmednøkler
--   docs/MVP_IMPLEMENTATION_PLAN.md §15, §29  «Editor oppretter Source»
--
-- ----------------------------------------------------------------------------
-- Backfill, som i migrasjon 005
--
-- De to seedede radene fra migrasjon 003 attribueres til agent:evidence-extraction,
-- av nøyaktig den grunnen aktørens egen beskrivelse allerede oppgir. Vinduet
-- mellom ADD COLUMN og SET NOT NULL er så smalt som praktisk mulig, og
-- knowledge.sources har ingen mutation-guard å slå av: tabellen er ikke
-- append-only (en kilde kan oppdateres, jf. migrasjon 003), så en vanlig UPDATE
-- er nok, og updated_at bumpes riktig — raden ble faktisk endret av denne
-- migrasjonen.
--
-- ----------------------------------------------------------------------------
-- Opphavet fryses, resten av kilden forblir redigerbar
--
-- Migrasjon 005 slo fast prinsippet i én setning: «Opphavet er en del av
-- identiteten og skal ikke kunne omskrives i ettertid.» På de append-only
-- tabellene fulgte det av at raden ikke kan endres i det hele tatt; på
-- knowledge.claims, som er muterbar, ble vernet uttrykt eksplisitt ved at
-- created_by_actor_id ble tatt inn i knowledge.freeze_claim_identity().
--
-- knowledge.sources er muterbar av samme grunn som claims — en kilde er en
-- beskrivelse som kan korrigeres, og statusen må kunne endres når kilden trekkes
-- tilbake — men hadde fram til nå ingen frysetrigger overhodet, fordi den ikke
-- hadde noe felt som var en del av identiteten. Den nye kolonnen er det første,
-- og den arver derfor prinsippet framfor å hvile på at framtidige RPC-er lar
-- feltet være i fred. En attribusjon som kan skrives om av den som blir
-- attribuert, er ingen attribusjon (ANTIDEP_CONSTITUTION.md §14).
--
-- Vernet er bevisst smalt: nøyaktig identiteten og opphavet, ingenting annet.
-- Tittel, forfattere, bibliografiske felter, status, status_note og
-- superseded_by_source_id er livssyklus og korreksjon, ikke identitet, og skal
-- fortsatt kunne endres — 100_knowledge_immutability_test.sql krever begge deler.
--
-- Raden selv er med, og det er ikke overforsiktighet: migrasjon 007c lar
-- audit.events peke på en kilde med object_id og uten fremmednøkkel, av den
-- grunnen DATABASE_ARCHITECTURE.md §36 gir. Migrasjon 008 måtte ta identiteten
-- inn i workflow.freeze_role_grant() da nøyaktig den avhengigheten oppstod der,
-- og argumentet er identisk her: en nyopprettet kilde har ennå ingen inngående
-- fremmednøkler — verken evidensfunn, kildeversjoner eller identifikatorer —
-- så ingenting utenfra holder primærnøkkelen på plass i det vinduet auditraden
-- allerede finnes. En omnummerering ville etterlatt auditsporet på en rad som
-- ikke finnes.
-- ============================================================================

alter table knowledge.sources
  add column created_by_actor_id uuid
    references provenance.actors (id) on update restrict on delete restrict;

update knowledge.sources
set created_by_actor_id = (
  select a.id from provenance.actors a where a.actor_key = 'agent:evidence-extraction'
);

alter table knowledge.sources
  alter column created_by_actor_id set not null;

comment on column knowledge.sources.created_by_actor_id is
  'Aktøren som registrerte kilden (DATABASE_ARCHITECTURE.md §13, ANTIDEP_CONSTITUTION.md §14). De to seedede radene fra migrasjon 003 er attribuert til agent:evidence-extraction, som produserte dem; senere rader skrives av den kontrollerte skriveveien i migrasjon 007c og attribueres til den innloggede kallerens egen aktør.';

create index sources_created_by_actor_id_idx
  on knowledge.sources (created_by_actor_id);

-- Triggeren opprettes etter backfillen med hensikt: backfillen setter kolonnen
-- fra NULL til aktøren, altså nøyaktig den endringen vernet skal nekte. Samme
-- rekkefølge som i migrasjon 005, der freeze_claim_identity() ble erstattet
-- etter at UPDATE-ene var kjørt.
create function knowledge.freeze_source_attribution()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  if new.id is distinct from old.id then
    raise exception using
      errcode = 'restrict_violation',
      message = format('Kilde %L kan ikke skifte identitet.', old.id),
      hint = 'Auditloggen peker på kilden med object_id og uten fremmednøkkel (DATABASE_ARCHITECTURE.md §35, §36). En omnummerering ville etterlatt auditsporet på en rad som ikke finnes.';
  end if;

  if new.created_by_actor_id is distinct from old.created_by_actor_id then
    raise exception using
      errcode = 'restrict_violation',
      message = format('Opphavet til kilde %L er uforanderlig og kan ikke endres.', old.id),
      hint = 'Hvem som registrerte kilden er en observasjon, ikke et redigerbart felt (ANTIDEP_CONSTITUTION.md §14). Tittel, forfattere, bibliografiske felter og status kan korrigeres; opphavet kan ikke skrives om i ettertid.';
  end if;

  return new;
end;
$$;

comment on function knowledge.freeze_source_attribution() is
  'Immutable-row guard: hindrer at identiteten og opphavet til en kilde endres etter innsetting. Alt annet på raden — tittel, forfattere, bibliografiske felter, status, status_note og superseded_by_source_id — er korreksjon og livssyklus, og forblir redigerbart. Samme prinsipp som knowledge.freeze_claim_identity() håndhever for den andre muterbare kunnskapstabellen.';

revoke execute on function knowledge.freeze_source_attribution() from public;

create trigger sources_freeze_attribution
  before update on knowledge.sources
  for each row execute function knowledge.freeze_source_attribution();
