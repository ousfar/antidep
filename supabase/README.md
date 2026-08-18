# Supabase — lokalt utviklingsmiljø

Denne katalogen inneholder Antideps Supabase-utviklingsfundament, i tråd med
[`docs/DATABASE_ARCHITECTURE.md`](../docs/DATABASE_ARCHITECTURE.md) og repo-strukturen i
[`docs/MVP_IMPLEMENTATION_PLAN.md`](../docs/MVP_IMPLEMENTATION_PLAN.md) §6.

- `config.toml` — prosjektkonfigurasjon for Supabase CLI (generert av `supabase init`,
  CLI-versjonen er pinnet i `package.json`).
- `migrations/` — versjonerte migrasjoner. Bevisst tom i PR A; migrasjon 001
  (schema- og sikkerhetsfundament) kommer i PR B.
- `seed.sql` og `tests/` opprettes når de første migrasjonene og databasetestene innføres.

## Kjøre lokal Supabase

Krav: [Docker](https://docs.docker.com/get-docker/) må være installert og kjøre.
Supabase CLI følger med som pinnet devDependency (`npm ci` er nok; ingen global installasjon).

```bash
npm run db:start   # starter lokal stack (Postgres, API m.m.) og skriver ut URL-er og nøkler
npm run db:status  # viser status og lokale nøkler for kjørende stack
npm run db:reset   # gjenskaper lokal database og kjører migrasjoner (ingen ennå i PR A)
npm run db:stop    # stopper stacken
```

`db:start` skriver ut lokal `API URL` og publishable-nøkkel. Kopier dem inn i `.env.local`
(se `.env.example`) når app-koden begynner å bruke Supabase fra PR B.

Verdiene fra den lokale stacken er kun lokale utviklingsnøkler, men reelle prosjektnøkler
skal aldri committes, og secret-/`service_role`-nøkler skal aldri finnes i klientkode
(`docs/DATABASE_ARCHITECTURE.md` §49).

## Før første migrasjon (PR B)

Før schemaimplementasjon starter skal Supabase-forutsetningene verifiseres mot gjeldende
plattformdokumentasjon (CLI-versjon, Data API-eksponering, RLS-veiledning, custom schemas,
view-sikkerhet), jf. `docs/MVP_IMPLEMENTATION_PLAN.md` §8.

Schemaendringer skal alltid ligge som versjonerte migrasjoner her i repoet; manuelle
endringer i Supabase Dashboard skal ikke være kilden til produksjonsschema
(`docs/MVP_IMPLEMENTATION_PLAN.md` §54).
