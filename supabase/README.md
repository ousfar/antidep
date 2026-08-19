# Supabase — lokalt utviklingsmiljø

Denne katalogen inneholder Antideps Supabase-utviklingsfundament, i tråd med
[`docs/DATABASE_ARCHITECTURE.md`](../docs/DATABASE_ARCHITECTURE.md) og repo-strukturen i
[`docs/MVP_IMPLEMENTATION_PLAN.md`](../docs/MVP_IMPLEMENTATION_PLAN.md) §6.

- `config.toml` — prosjektkonfigurasjon for Supabase CLI (generert av `supabase init`,
  CLI-versjonen er pinnet i `package.json`). `[api].schemas` styrer hvilke schemaer som
  eksponeres i Data API.
- `migrations/` — versjonerte migrasjoner. Migrasjon 001 etablerer schema- og
  sikkerhetsfundamentet, migrasjon 002 katalogfundamentet.
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

Tabellene har RLS aktivert og ingen policies. De er derfor default deny for alle andre enn
eieren. Redaksjonell lesetilgang forutsetter medlemskapsmodellen i migrasjon 005, og
klientflaten skal uansett lese publiserte projeksjoner i `api` (migrasjon 007).

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
