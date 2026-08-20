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

`ingest` opprettes først når importfundamentet kommer (migrasjon 009).

Tilgang er default deny. `anon` og `authenticated` har kun `usage` på `api`, og hvert
objekt i `api` må få egen `GRANT` i migrasjonen som oppretter det. `service_role` har
ingen tilgang til Antidep-schemaene og er ikke applikasjonens universalnøkkel
(`docs/DATABASE_ARCHITECTURE.md` §49).

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

**Ingen RLS-policies ennå.** En policy har bare virkning for en rolle som allerede har et
tabellprivilegium, og ingen klientrolle har `usage` på `knowledge`, `workflow` eller
`provenance`. Policyene hører sammen med den første kontrollerte skriveveien og grantene som
gjør dem virksomme (`docs/MVP_IMPLEMENTATION_PLAN.md` §48), altså migrasjon 006 og senere.
Klientflaten skal uansett lese publiserte projeksjoner i `api` (migrasjon 007).

**Seedomfang.** Migrasjon 005 seeder bare de to KI-aktørene som faktisk produserte radene i
migrasjon 003 og 004. Ingen verifikasjon og ingen reviewbeslutning er seedet: begge deler er
utførte handlinger, og en seedet godkjenning ville vært nøyaktig den fiktive godkjenningen
`docs/ANTIDEP_CONSTITUTION.md` §12 forbyr. `provenance.agent_runs` opprettes først når en
faktisk automatisk pipeline skriver kjøringer.

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
