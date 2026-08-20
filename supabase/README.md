# Supabase — lokalt utviklingsmiljø

Denne katalogen inneholder Antideps Supabase-utviklingsfundament, i tråd med
[`docs/DATABASE_ARCHITECTURE.md`](../docs/DATABASE_ARCHITECTURE.md) og repo-strukturen i
[`docs/MVP_IMPLEMENTATION_PLAN.md`](../docs/MVP_IMPLEMENTATION_PLAN.md) §6.

- `config.toml` — prosjektkonfigurasjon for Supabase CLI (generert av `supabase init`,
  CLI-versjonen er pinnet i `package.json`). `[api].schemas` styrer hvilke schemaer som
  eksponeres i Data API.
- `migrations/` — versjonerte migrasjoner:
  - 001 schema- og sikkerhetsfundamentet
  - 002 katalogfundamentet
  - 003 `knowledge.sources`, kildeversjoner og `knowledge.evidence_items`
  - 004 `knowledge.claims`, revisjoner, evidenslenker og evidensvurderinger
  - 005 `provenance.actors`, medlemskapsmodellen, verifikasjon og review
  - 006 `knowledge.publication_events` og den kontrollerte publiseringsoperasjonen
  - 006a korreksjon: entydig serialisering av `content_hash` på evidensfunn
  - 007 api-lesemodellen: `api.published_drugs`, `api.published_claims`,
    `api.published_claim_evidence`, med RLS-policyene og grantene under dem

  Nummereringen følger planlagt innhold i `docs/MVP_IMPLEMENTATION_PLAN.md` §18-§27, ikke
  filrekkefølge. Korreksjonsmigrasjoner står utenfor den rekken og får en bokstav, slik at
  «migrasjon 007 — API-lesemodell» (§24) fortsatt betyr det samme i plan, migrasjoner og
  tester.

- `tests/` — pgTAP-tester som kjøres med `npm run db:test`.
- `seed.sql` — kun lokal demodata. Kontrollert vokabular og pilotdata som produksjonen
  er avhengig av, ligger i migrasjonene (se «Hvor seed-data hører hjemme» under).

## Kjøre lokal Supabase

Krav: [Docker](https://docs.docker.com/get-docker/) må være installert og kjøre.
Supabase CLI følger med som pinnet devDependency (`npm ci` er nok; ingen global installasjon).

```bash
npm run db:start   # starter lokal stack (Postgres, API m.m.) og skriver ut URL-er og nøkler
npm run db:status  # viser status og lokale nøkler for kjørende stack
npm run db:reset   # gjenskaper lokal database og kjører alle migrasjoner fra bunnen av
npm run db:test    # kjører pgTAP-testene i tests/ mot den lokale databasen
npm run db:stop    # stopper stacken
```

`db:start` skriver ut lokal `API URL` og publishable-nøkkel. Kopier dem inn i `.env.local`
(se `.env.example`) når app-koden begynner å lese fra Supabase.

Verdiene fra den lokale stacken er kun lokale utviklingsnøkler, men reelle prosjektnøkler
skal aldri committes, og secret-/`service_role`-nøkler skal aldri finnes i klientkode
(`docs/DATABASE_ARCHITECTURE.md` §49).

## Schema- og sikkerhetsgrensen

Migrasjon 001 oppretter de logiske schemaene fra `docs/DATABASE_ARCHITECTURE.md` §6:

| Schema       | Innhold                                            | Data API  |
| ------------ | -------------------------------------------------- | --------- |
| `catalog`    | virkestoffer, produkter, kliniske begreper         | privat    |
| `knowledge`  | claims, revisjoner, kilder, evidens, vurderinger   | privat    |
| `workflow`   | arbeidsflyt, verifikasjon, review, rollemedlemskap | privat    |
| `provenance` | aktører, pipeline-/modellversjoner, sporbarhet     | privat    |
| `audit`      | append-only hendelseslogg                          | privat    |
| `api`        | publiserte views og kontrollerte RPC-er            | eksponert |

Fra migrasjon 007 er `[api].schemas` i `config.toml` satt til `["api", "graphql_public"]`.
`public` ble tatt ut fordi det ikke inneholder Antidep-objekter, og en tom eksponering er
fortsatt en eksponering. `api` står først og er dermed standardprofilen i PostgREST.

`ingest` opprettes først når importfundamentet kommer (migrasjon 009).

Tilgang er default deny. `anon` og `authenticated` har `usage` bare på `api`, og hvert
objekt i `api` må få egen `GRANT` i migrasjonen som oppretter det. `service_role` har
ingen tilgang til Antidep-schemaene og er ikke applikasjonens universalnøkkel
(`docs/DATABASE_ARCHITECTURE.md` §49).

Fra migrasjon 007 har klientrollene i tillegg `SELECT` på de elleve kanoniske tabellene
api-viewene leser. Det følger av at views i `api` er `security_invoker` og altså leser med
kallerens rettigheter (§42). Granten åpner ikke tabellene: uten `usage` på schemaet kan
klientrollene ikke navngi dem — forsøket gir «permission denied for schema» — og RLS
slipper uansett bare gjennom rader som er nådd fra en publisert påstand. Se
«API-lesemodellen» under.

Konvensjoner som gjelder for alle senere migrasjoner, håndhevet av
`tests/030_conventions_test.sql`:

- primærnøkkelen er én databasegenerert `uuid`-kolonne med `default gen_random_uuid()`
- alle tidspunkter som `timestamptz`, med `created_at timestamptz not null default now()`
- RLS aktivert på alle tabeller i de kanoniske schemaene, uten grants til klientrollene
- `security_invoker` på views i `api`
- `SECURITY DEFINER`-funksjoner kun med `search_path = ''` og schemakvalifiserte navn, og
  uten `EXECUTE` til `PUBLIC`

Schemaendringer skal alltid ligge som versjonerte migrasjoner her i repoet; manuelle
endringer i Supabase Dashboard skal ikke være kilden til produksjonsschema
(`docs/MVP_IMPLEMENTATION_PLAN.md` §54). Eksponerte schemaer i det hostede prosjektet må
holdes i synk med `[api].schemas` her.

Supabase-forutsetningene i `docs/MVP_IMPLEMENTATION_PLAN.md` §8 ble kontrollert mot
plattformdokumentasjonen 18. august 2026, før migrasjon 001 ble skrevet.

## Katalogfundamentet

Migrasjon 002 oppretter virkestoffidentiteten, det kontrollerte begrepsvokabularet og
populasjonsmodellen som Claims, evidens og publiserte projeksjoner senere peker på:

| Tabell                      | Innhold                                                                        |
| --------------------------- | ------------------------------------------------------------------------------ |
| `catalog.drugs`             | stabil identitet for virkestoff, med kanonisk navn og status                   |
| `catalog.drug_names`        | aliaser, handelsnavn og historiske navn med eksplisitt navnetype               |
| `catalog.drug_identifiers`  | eksterne identifikatorer, foreløpig WHO ATC                                    |
| `catalog.clinical_concepts` | kontrollert begrepsvokabular med begrepstype og valgfritt hierarki             |
| `catalog.populations`       | strukturerte gyldighetsgrenser for alder, indikasjon, graviditet, komorbiditet |

Kanoniske navn og eksterne identifikatorer er unike, men aldri primærnøkkel: primærnøkkelen
er alltid en databasegenerert `uuid` (`docs/DATABASE_ARCHITECTURE.md` §8). Alle fremmednøkler
i `catalog` bruker `RESTRICT` (§37), så klinisk relevant historikk kan ikke forsvinne som
bivirkning av en sletting.

I `catalog.populations` betyr `NULL` i en dimensjon at populasjonen **ikke er avgrenset** på
den dimensjonen. `NULL` betyr ikke «ukjent» og ikke «vurdert og funnet irrelevant»
(`docs/ANTIDEP_CONSTITUTION.md` §6).

`created_at` og `updated_at` eies av databasen på alle katalogtabellene. En trigger setter
dem ved både `INSERT` og `UPDATE`, så en kaller kan verken glemme eller forfalske dem; en
`default` alene ville bare gjelde når kolonnen utelates. Tidspunkter fra den eksterne
virkeligheten hører til `recorded_at` eller `valid_from`/`valid_to`, ikke hit
(`docs/DATABASE_ARCHITECTURE.md` §7.3).

**Populasjonsdefinisjonen er uforanderlig.** En populasjon er en gyldighetsgrense, ikke bare
en etikett, og `ClaimRevision`/`EvidenceItem` peker på `population_id`. Kunne de definerende
feltene endres etterpå, ville en redigering stille endret omfanget av all historikk som
allerede peker dit, uten ny revisjon (`docs/DATABASE_ARCHITECTURE.md` §7, §7.1). En trigger
avviser derfor endring av etikett, aldersgrenser, indikasjon, graviditetskontekst og
komorbiditet. **Et endret omfang er en ny populasjon:** opprett en ny rad og sett den gamle
til `status = 'deprecated'`. Status og tidsstempler er utenfor vernet, så utfasing er mulig
uten å røre betydningen. Vernet gjelder også eieren; en reell datakorreksjon i en senere
migrasjon må slå av triggeren eksplisitt, som en synlig og reviewbar handling.

Begrepshierarkiet er bevisst ikke vernet på samme måte: en `ClinicalConcept` organiserer og
gjenfinner innhold og er ikke en gyldighetsgrense for en påstand, så en etikettkorreksjon
der endrer ikke omfanget av historikk.

Tabellene har RLS aktivert og ingen policies. De er derfor default deny for alle andre enn
eieren, og det samme gjelder tabellene i `knowledge`, `workflow` og `provenance`. Se
«Review og proveniens» under for hvorfor policyene fortsatt ikke er skrevet.

## Review og proveniens

Migrasjon 005 innfører attribusjonen og kontrollene som `docs/ANTIDEP_CONSTITUTION.md` §10,
§11, §12 og §14 krever:

| Tabell                            | Innhold                                                                       |
| --------------------------------- | ----------------------------------------------------------------------------- |
| `provenance.actors`               | normalisert aktør: menneske, KI-agent, deterministisk prosess, import, system |
| `workflow.user_roles`             | medlemskapsmodellen med scope og gyldighetsperiode                            |
| `workflow.evidence_verifications` | kontroll av at et evidensfunn gjengir kilden riktig                           |
| `workflow.claim_verifications`    | kontroll av at en påstandsrevisjon holder mot grunnlaget                      |
| `workflow.review_decisions`       | menneskelig faglig beslutning som eget beslutningsobjekt                      |

Samtidig får `knowledge.evidence_items`, `claims`, `claim_revisions`,
`claim_evidence_links` og `evidence_assessments` en påkrevd `created_by_actor_id`.

**Generering og verifikasjon er atskilte operasjoner.** Verifikasjonsraden ligger ved siden
av objektet og endrer det aldri, og en speilkolonne låst til foreldreraden gjør at en
radlokal `CHECK` kan avvise at verifikatoren er den samme aktøren som laget objektet. En
bekreftelse kan heller ikke hvile på et avledet sammendrag alene, og en claim-verifikasjon
kan bare konkluderes som `verified` når alle sju kontrollpunktene i
`docs/DATABASE_ARCHITECTURE.md` §30 er bedømt og holder.

**Tidsmodellen kan ikke konstrueres i etterkant.** `verified_at` og `decided_at` er
kallerstyrte hendelsestidspunkter, og `decided_at` bestemmer hvilken rolletildeling som
teller som gyldig. `created_at` på de tre append-only workflow-tabellene eies derfor av
databasen, hendelsestidspunktet kan ikke ligge etter det, og kvalifikasjonskontrollen
krever at selve rolletildelingsraden fantes senest på beslutningstidspunktet. En rolle
opprettet i dag kan dermed ikke legitimere en «godkjenning» datert i fjor ved å
tilbakedatere `valid_from`. En kontroll eller beslutning som faktisk fant sted tidligere
kan fortsatt registreres i etterkant.

**Bare mennesker kan godkjenne.** `workflow.review_decisions` krever en aktør av typen
`human` — håndhevet av en sammensatt fremmednøkkel og en `CHECK` — og en trigger krever i
tillegg at aktøren hadde gyldig `reviewer`-rolle for objektets innholdsområde på
beslutningstidspunktet. Rollen leses fra `workflow.user_roles`, aldri fra en JWT-claim
(`docs/DATABASE_ARCHITECTURE.md` §46). `admin` er brukerforvaltning og gir ikke faglig
godkjenningsrett.

**En tilbaketrukket ekstraksjon er en beslutning, ikke en statuskolonne.** Spørsmålet stod
åpent fra migrasjon 003 og er avgjort her: `review_type = 'extraction_withdrawal'` i
`workflow.review_decisions`. Publiseringsgaten i migrasjon 006 må lese den avledede
tilstanden og nekte å publisere en revisjon som hviler på et tilbaketrukket evidensfunn.

**Ingen skrivepolicies.** Migrasjon 007 skrev de første RLS-policyene, men bare for `SELECT`
og bare på leseveien til publiserte påstander. Skriveveien er fortsatt en kontrollert
`SECURITY DEFINER`-funksjon, ikke tabelltilgang (`docs/DATABASE_ARCHITECTURE.md` §43), og
`030_conventions_test.sql` håndhever at ingen policy i de kanoniske schemaene åpner for annet
enn lesing. `workflow` og `provenance` har fortsatt verken grants eller policies.

**Seedomfang.** Migrasjon 005 seeder bare de to KI-aktørene som faktisk produserte radene i
migrasjon 003 og 004. Ingen verifikasjon og ingen reviewbeslutning er seedet: begge deler er
utførte handlinger, og en seedet godkjenning ville vært nøyaktig den fiktive godkjenningen
`docs/ANTIDEP_CONSTITUTION.md` §12 forbyr. `provenance.agent_runs` opprettes først når en
faktisk automatisk pipeline skriver kjøringer.

## API-lesemodellen

Migrasjon 007 åpner den første leseveien fra klientflaten inn i kunnskapsbasen
(`docs/MVP_IMPLEMENTATION_PLAN.md` §24):

| View                           | Innhold                                                                   |
| ------------------------------ | ------------------------------------------------------------------------- |
| `api.published_drugs`          | virkestoff Antidep har minst én publisert påstand om, med ATC-kode        |
| `api.published_claims`         | én rad per publisert påstand, med strukturert betydning og sikkerhetsgrad |
| `api.published_claim_evidence` | evidensgrunnlaget bak hver påstand, med funn, kilde, DOI og PMID          |

**Tre lås står mellom en klientrolle og en upublisert påstand.** Klientrollene mangler `usage`
på de kanoniske schemaene og kan ikke navngi tabellene. RLS slipper bare gjennom rader nådd fra
en publisert, ikke tilbaketrukket påstand. Og bare `SELECT` er gitt, bare til `anon` og
`authenticated`. Hvert lag testes for seg i `tests/290_api_read_model_access_test.sql`, med
faktisk klientrolle, slik §24 og `docs/DATABASE_ARCHITECTURE.md` §44 punkt 4 krever.

**Viewene bærer publiseringspredikatet i tillegg til RLS.** Det er bevisst dobbeltarbeid: hvert
lag skal være korrekt alene, slik at verken en tapt policy eller en feilskrevet join er nok til
å vise upublisert eller tilbaketrukket innhold. Nettopp derfor testes de hver for seg — leses
et view som eier, er RLS av, og viewets eget filter er det eneste som svarer.

**Projeksjonen er tom inntil noe faktisk er publisert.** Det er korrekt oppførsel, ikke en
mangel: publisering krever en menneskelig faglig godkjenning som ikke kan seedes
(`docs/ANTIDEP_CONSTITUTION.md` §12, `docs/MVP_IMPLEMENTATION_PLAN.md` §74.4). Testene
publiserer derfor sitt eget innhold inne i en transaksjon som rulles tilbake.

**Kontrakten er tekst, ikke enum.** Viewene caster enum-kolonner til `text`. Verdiene er de
samme, men den offentlige kontrakten bindes ikke til PostgreSQL-typen, og klientrollene trenger
ikke `usage` på typene. Om enumene på sikt byttes mot oppslagstabeller
(`docs/MVP_IMPLEMENTATION_PLAN.md` §74.5 punkt 1), er det da ikke en brytende API-endring.

**Identiteten er uuid, med ATC som ekstern nøkkel.** Katalogobjekter eksponeres med sin
databasegenererte `uuid` (`docs/DATABASE_ARCHITECTURE.md` §8). For virkestoff følger ATC-kodene
med som språkuavhengig ekstern nøkkel, som sortert array. `NULL` der betyr at ingen ATC-kode er
registrert i Antidep, ikke at virkestoffet mangler en.

**Identifikatorer aggregeres, de joines ikke.** `catalog.drug_identifiers` og
`knowledge.source_identifiers` er unike på `(identifier_system, identifier_value)`, ikke på
`(forelder, identifier_system)`: ett virkestoff kan ha flere ATC-koder, og ingenting hindrer to
DOI-er på samme kilde. Joinet inn ville de multiplisert raden — ett evidensfunn ville blitt til
to og sett ut som to uavhengige funn. ATC-kodene aggregeres derfor til en array, og DOI og PMID
hentes med skalare underspørringer.

## Hvor seed-data hører hjemme

Kontrollert vokabular og pilotdata som produksjonen er avhengig av, ligger i den versjonerte
migrasjonen som oppretter tabellene. Kliniske objekter i senere migrasjoner får fremmednøkler
til disse radene, og `seed.sql` kjøres bare ved lokal `supabase db reset` — data som bare
finnes der, ville ikke finnes i det hostede prosjektet.

`seed.sql` er derfor reservert for rent lokal demodata og er foreløpig tom.

Katalogdataene for den første golden slicen — sertralin, mirtazapin, `vektendring`,
`depressiv lidelse` og populasjonen «voksne med depressiv lidelse» — seedes av migrasjon 002.
Norske produktdata seedes ikke for hånd; de kommer gjennom `catalog.drug_products` og
FEST-importen i migrasjon 009.
