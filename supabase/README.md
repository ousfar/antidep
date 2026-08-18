# Supabase-katalog

Denne katalogen er reservert for Antideps databasegrunnlag, i tråd med
[`docs/DATABASE_ARCHITECTURE.md`](../docs/DATABASE_ARCHITECTURE.md) og repo-strukturen i
[`docs/MVP_IMPLEMENTATION_PLAN.md`](../docs/MVP_IMPLEMENTATION_PLAN.md) §6.

## Status

PR A (prosjektbootstrap) etablerer bevisst **ingen** schema, migrasjoner eller seed-data.

- `migrations/` — versjonerte migrasjoner kommer fra og med PR B
  (migrasjon 001, schema- og sikkerhetsfundament).
- `seed.sql` og `tests/` opprettes når de første migrasjonene og databasetestene innføres.

## Før første migrasjon

Før schemaimplementasjon starter skal Supabase-forutsetningene verifiseres mot gjeldende
plattformdokumentasjon (CLI-versjon, Data API-eksponering, RLS-veiledning, custom schemas,
view-sikkerhet), jf. `docs/MVP_IMPLEMENTATION_PLAN.md` §8.

Schemaendringer skal alltid ligge som versjonerte migrasjoner her i repoet; manuelle
endringer i Supabase Dashboard skal ikke være kilden til produksjonsschema
(`docs/MVP_IMPLEMENTATION_PLAN.md` §54).
