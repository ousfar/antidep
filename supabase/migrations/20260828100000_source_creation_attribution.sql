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
