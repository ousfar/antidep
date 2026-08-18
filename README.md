# Antidep

Antidep er et klinisk arbeidsverktøy under utvikling: rask, presis og etterprøvbar informasjon
om antidepressiver for helsepersonell i Norge.

Prosjektet er i bootstrap-fasen. Ingen klinisk funksjonalitet er implementert ennå, og ingen
klinisk informasjon er publisert.

## Styringsdokumenter

All utvikling styres av dokumentene i [`docs/`](./docs):

- [`ANTIDEP_CONSTITUTION.md`](./docs/ANTIDEP_CONSTITUTION.md) — ikke-forhandlingsbare prinsipper
- [`MVP_IMPLEMENTATION_PLAN.md`](./docs/MVP_IMPLEMENTATION_PLAN.md) — implementeringsrekkefølge og status
- [`KNOWLEDGE_MODEL.md`](./docs/KNOWLEDGE_MODEL.md), [`EVIDENCE_PIPELINE.md`](./docs/EVIDENCE_PIPELINE.md),
  [`DATABASE_ARCHITECTURE.md`](./docs/DATABASE_ARCHITECTURE.md),
  [`CONTENT_GOVERNANCE.md`](./docs/CONTENT_GOVERNANCE.md),
  [`PRODUCT_INFORMATION_ARCHITECTURE.md`](./docs/PRODUCT_INFORMATION_ARCHITECTURE.md)

## Teknisk stack

React, TypeScript og Vite i klientlaget; Vitest og React Testing Library for tester;
ESLint og Prettier for kodekvalitet. Supabase/PostgreSQL er valgt som kanonisk dataplattform
og innføres fra og med de første databaseslicene (se `supabase/README.md`). Hosting er
planlagt på Vercel.

## Kom i gang

Krav: Node.js 22 (se `.nvmrc`) og npm.

```bash
npm ci        # installer avhengigheter fra package-lock.json
npm run dev   # start utviklingsserver
```

## Kommandoer

```bash
npm run dev          # utviklingsserver med hot reload
npm run build        # typecheck + produksjonsbygg til dist/
npm run preview      # serverer produksjonsbygget lokalt
npm run lint         # ESLint
npm run format       # Prettier (skriver endringer)
npm run format:check # Prettier (kun kontroll, brukes i CI)
npm run typecheck    # TypeScript uten emit
npm run test         # Vitest, én kjøring (brukes i CI)
npm run test:watch   # Vitest i watch-modus
```

CI (GitHub Actions, `.github/workflows/ci.yml`) kjører lint, formatkontroll, typecheck,
tester og produksjonsbygg på alle pull requests og på `main`.

## Miljøvariabler

Kopier `.env.example` til `.env.local` og fyll inn verdier ved behov. Kun variabler med
`VITE_`-prefiks eksponeres til nettleseren. Reelle nøkler skal aldri committes, og Supabase
`service_role`-/secret-nøkler skal aldri finnes i klientkode eller i repoet.

## Prosjektstruktur

```text
docs/        styringsdokumenter (arkitektur, governance, plan)
src/
  app/       app-skall og applikasjonsoppsett
supabase/    databasegrunnlag; migrasjoner kommer fra og med PR B
tests/       testoppsett og tverrgående tester (e2e kommer i senere slices)
```

`src/` vokser mot strukturen i MVP-planen §6 (`components/`, `features/`, `lib/`, `routes/`,
`types/`); katalogene opprettes først når de tas i bruk.

## Deploy

Repoet er forberedt for Vercel med framework-preset **Vite** (auto-detektert; ingen egen
konfigurasjonsfil er nødvendig ennå). Preview deployments for PR-er aktiveres ved å koble
repoet til et Vercel-prosjekt, jf. MVP-planen §53.

## Arbeidsform

Små, énformåls-PR-er med eksplisitt validering (MVP-planen §51–52). Endringer vurderes mot
styringsdokumentene, ikke bare mot om koden «virker».
