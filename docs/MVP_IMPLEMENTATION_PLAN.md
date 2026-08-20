# Antidep MVP Implementation Plan

**Versjon:** 0.1  
**Dato:** 18. august 2026  
**Status:** Første implementeringsplan  
**Styrende dokumenter:** [`ANTIDEP_CONSTITUTION.md`](./ANTIDEP_CONSTITUTION.md), [`KNOWLEDGE_MODEL.md`](./KNOWLEDGE_MODEL.md), [`EVIDENCE_PIPELINE.md`](./EVIDENCE_PIPELINE.md), [`DATABASE_ARCHITECTURE.md`](./DATABASE_ARCHITECTURE.md), [`CONTENT_GOVERNANCE.md`](./CONTENT_GOVERNANCE.md) og [`PRODUCT_INFORMATION_ARCHITECTURE.md`](./PRODUCT_INFORMATION_ARCHITECTURE.md)

## 1. Formål

Dette dokumentet markerer overgangen fra arkitektur til faktisk bygging av Antidep.

Målet er å få frem en liten, produksjonslignende MVP som demonstrerer at hele kjeden fungerer:

```text
kilde
→ strukturert evidens
→ verifisering
→ claim
→ evidensvurdering
→ human review
→ publisering
→ kliniker-UI
→ kildedrilldown
```

Planen skal styre rekkefølgen på implementasjonen og hindre to vanlige feil:

1. at prosjektet bygger stor teknisk infrastruktur før noen komplett klinisk arbeidsflyt fungerer
2. at prosjektet fyller databasen med store mengder innhold før evidens-, review- og publiseringsmekanismene er validert

Implementasjonen skal derfor skje i små, reviewbare **vertikale slices**.

---

## 2. Normative begreper

- **SKAL**: krav som må oppfylles før MVP kan anses arkitekturmessig korrekt.
- **BØR**: sterk standard som kan fravikes med dokumentert grunn.
- **KAN**: tillatt, men ikke påkrevd.

---

# Del I — Hva MVP-en skal bevise

## 3. MVP er en arkitekturvalidering, ikke et komplett antidepressivleksikon

MVP-en skal bevise at Antidep kan:

- representere antidepressiver og norske produkter strukturert
- lagre en kilde og konkrete evidensfunn separat
- formulere atomiske, versjonerte claims
- koble evidens til claims med eksplisitt relasjonstype
- representere usikkerhet og evidenssikkerhet
- verifisere ekstraksjon og claim-støtte uavhengig
- håndtere human review
- publisere og erstatte revisjoner uten å miste historikk
- vise den samme kunnskapen i legemiddel-, sammenlignings- og temavisning
- vise «Hvorfor sier Antidep dette?» ned til konkret evidens og kilde
- håndtere `ingen vurderbar evidens` uten at dette ser ut som null risiko eller null effekt
- gjennomføre en kontrollert, deterministisk klinisk regel for et begrenset bytte-/nedtrappingsscenario
- fungere på desktop og mobil
- kunne administreres uten direkte databasearbeid i normal redaksjonell drift

MVP-en skal **ikke** bevise at Antidep allerede dekker hele antidepressivfeltet.

## 4. Primært suksesskriterium

Den viktigste testen er ikke antall virkestoffer eller antall sider.

MVP-en er vellykket når en kliniker kan gå fra et konkret spørsmål til et korrekt, kort svar og derfra ned til den strukturerte evidensen, samtidig som en redaktør kan oppdatere samme kunnskapsobjekt gjennom en kontrollert review- og publiseringsflyt.

---

# Del II — Teknisk baseline

## 5. Anbefalt applikasjonsstack

Første implementasjon BØR bruke en enkel TypeScript-basert webstack:

```text
Frontend
  React
  TypeScript
  Vite

Backend / data
  Supabase
  PostgreSQL
  Supabase Auth
  kontrollerte server-/RPC-operasjoner

Hosting
  Vercel

Testing
  Vitest
  React Testing Library
  Playwright
  database-/RLS-tester
```

Begrunnelse:

- produktet er primært en interaktiv klinikerapp, ikke et innholdstungt SEO-nettsted
- Vite holder klientlaget enkelt
- React/TypeScript passer godt til strukturerte komponenter, admin-UI og sammenligningstabeller
- PostgreSQL/Supabase er allerede valgt som kanonisk dataplattform i arkitekturen
- Vercel gir enkel distribusjon og preview deployments

Hvis implementasjonen avdekker et konkret behov som klart favoriserer en annen frontendarkitektur, kan dette valget revurderes. Det skal ikke byttes rammeverk av smakshensyn.

## 6. Anbefalt repo-struktur

Start enkelt:

```text
/
├─ docs/
├─ src/
│  ├─ app/
│  ├─ components/
│  ├─ features/
│  ├─ lib/
│  ├─ routes/
│  └─ types/
├─ supabase/
│  ├─ migrations/
│  ├─ seed.sql
│  └─ tests/
├─ tests/
│  └─ e2e/
├─ package.json
└─ ...
```

Ikke innfør monorepo, mange packages eller egen mikroservicearkitektur før et konkret behov eksisterer.

## 7. Avhengigheter skal holdes nøkterne

MVP-en bør bruke få, velbegrunnede biblioteker.

Aktuelle kategorier:

- routing
- server-state/data fetching
- skjema-/inputvalidering
- tilgjengelige UI-primitiver
- testing

Ikke innfør en tung design system-stack, generisk workflow-motor eller egen abstraksjonsramme for KI før behovet er demonstrert.

## 8. Supabase-forutsetninger skal verifiseres før første migrasjon

Før schemaimplementasjon starter skal teamet kontrollere gjeldende:

- Supabase changelog
- Data API-eksponering og grants
- RLS-veiledning
- custom schemas
- view-sikkerhet
- databasefunksjoner
- CLI-versjon og migrasjonsworkflow

`DATABASE_ARCHITECTURE.md` er styrende, men plattformdetaljer kan ha endret seg siden dokumentet ble skrevet.

---

# Del III — MVP-scope

## 9. Pilotsett av antidepressiver

MVP-en skal ikke starte med alle antidepressiver.

Følgende seks virkestoffer anbefales som pilotsett:

| Virkestoff | Hvorfor det inngår i pilotsettet |
|---|---|
| **sertralin** | vanlig SSRI og egnet baseline for mange sammenligninger |
| **escitalopram** | vanlig SSRI med relevant dose-/QT- og interaksjonskontekst |
| **fluoksetin** | svært lang halveringstid; viktig test av bytte-/nedtrappingslogikk |
| **venlafaksin** | SNRI og nyttig test av seponeringsproblemer og formuleringer |
| **mirtazapin** | annen farmakologisk profil; tydelig relevant for vekt og sedasjon |
| **vortioksetin** | multimodal profil og nyttig kontrast for blant annet seksuell funksjon |

Dette er et **arkitekturpilotsett**, ikke en påstand om at disse seks alltid er de viktigste antidepressivene klinisk.

## 10. Første utvidelsessett

Følgende kan vurderes etter at pilotsettet fungerer:

- duloksetin
- paroksetin
- citalopram
- amitriptylin
- klomipramin
- bupropion der norsk indikasjon/off-label-kontekst er tydelig modellert

Utvidelse skal ikke skje før pipeline- og reviewkvalitet er demonstrert.

## 11. Pilottemaer / ClinicalConcepts

MVP-en skal prioritere følgende innholdsområder:

1. **effekt ved depressiv lidelse**
2. **vektendring**
3. **seksuell dysfunksjon**
4. **sedasjon / søvn**
5. **seponeringssymptomer / seponeringsproblemer**
6. **sentral farmakokinetikk**, inkludert halveringstid og aktive metabolitter når relevant
7. **viktige farmakokinetiske interaksjoner**
8. **utvalgte sikkerhetsområder**, først og fremst områder som er egnet til reell sammenligning mellom pilotlegemidlene
9. **norske preparater, formuleringer og styrker**

MVP-en trenger ikke komplett dekning av alle underområder for alle seks legemidler før første interne pilot.

## 12. Første «golden slice»

Den aller første komplette vertikale slicen skal være:

```text
sertralin + mirtazapin
×
vektendring
```

Denne slicen skal inneholde:

- to `Drug`-objekter
- relevante `ClinicalConcept`/Population-objekter
- minst én reell Source
- minst ett verifisert EvidenceItem per relevant kilde
- atomiske Claims
- ClaimEvidenceLinks
- EvidenceAssessment
- human ReviewDecision
- PublicationEvent
- offentlig API-projeksjon
- legemiddelvisning
- enkel sammenligning
- «Hvorfor sier Antidep dette?»

Før denne kjeden fungerer skal prosjektet ikke masseimplementere andre temaer.

---

# Del IV — Funksjonelt MVP-omfang

## 13. Klinikerflate

Før første offentlige MVP skal følgende hovedflyter fungere.

### 13.1 Søk og legemiddeloppslag

Brukeren skal kunne:

```text
åpne Antidep
→ søke på virkestoff eller norsk handelsnavn
→ åpne legemiddelside
→ se kort standardinformasjon
→ åpne et faglig tema
→ åpne claim/evidens
```

### 13.2 Sammenligning

Brukeren skal kunne:

```text
velge 2–4 pilotlegemidler
→ velge relevante dimensjoner
→ se sammenligning
→ velge «vis bare forskjeller»
→ åpne evidensgrunnlaget for et datapunkt
```

### 13.3 Klinisk situasjon

Minst følgende temainnganger bør fungere:

- vektøkning
- seksuell dysfunksjon
- sedasjon/søvn
- seponeringsproblemer

Temavisningen skal være en projeksjon av de samme Claims som brukes på legemiddelsiden.

### 13.4 Evidensdrilldown

For ethvert publisert klinisk relevant claim skal brukeren kunne åpne:

```text
Hva sier Antidep?
→ hvor sikker er kunnskapen?
→ hvilke studier/kilder ligger bak?
→ hvordan støtter eller motsier kilden claimet?
→ hvor i kilden finnes evidensfunnet?
```

### 13.5 Bytte/nedtrapping

MVP-en skal inneholde en **begrenset, eksplisitt støttet** bytte-/nedtrappingsmotor.

Den skal ikke late som alle legemiddelpar er støttet.

Første versjon bør:

- bare aktivere planer for eksplisitt faglig godkjente overganger
- bruke faktiske norske formuleringer/styrker
- vise hvilken regelversjon som ble brukt
- vise sentrale forutsetninger
- tillate at klinikeren velger blant definerte tempoalternativer der dette er faglig forsvarlig
- vise tydelig når en overgang ikke er støttet i Antidep ennå

Første implementerte regel bør velges fordi den tester arkitekturen godt, ikke fordi flest mulige scenarioer skal dekkes.

---

# Del V — Admin- og review-MVP

## 14. Admin er en del av MVP, ikke et senere internt verktøy

MVP-en er ikke ferdig hvis innhold bare kan opprettes ved SQL, seed-filer eller Claude Code.

Følgende redaksjonelle handlinger skal kunne utføres i UI før offentlig lansering:

- opprette Source
- opprette eller korrigere EvidenceItem
- opprette Claim / ny ClaimRevision
- koble EvidenceItem til ClaimRevision
- angi relasjonstype
- registrere EvidenceAssessment
- sende til review
- godkjenne eller avvise
- forhåndsvise publisert utseende
- publisere
- erstatte en publisert revisjon
- trekke tilbake publisert revisjon
- se historikk

## 15. Første admin-workflow

Første komplette admin-workflow skal være:

```text
Editor oppretter Source
→ Editor registrerer EvidenceItem
→ separat verifier verifiserer ekstraksjonen
→ Editor oppretter ClaimRevision
→ Claim–Evidence-relasjon registreres
→ claim-støtte verifiseres
→ EvidenceAssessment registreres
→ Clinical Reviewer godkjenner
→ Publisher publiserer
→ kliniker-UI oppdateres
```

Systemet skal vise hvorfor et steg er blokkert dersom en gate mangler.

## 16. Roller i første tekniske implementasjon

Følgende applikasjonsroller implementeres først:

- `editor`
- `reviewer`
- `publisher`
- `admin`

`clinical_lead` og `evidence_lead` kan initialt være governance-attributter/ansvarsroller uten egne tekniske tillatelser dersom ingen særskilt handling krever det ennå.

Agentbrukere skal ikke representeres som vanlige menneskelige editor-brukere.

---

# Del VI — Databaseimplementasjon i rekkefølge

## 17. Migrasjonsstrategi

Databasen skal bygges i små migrasjoner som følger de vertikale slicene.

Ikke opprett alle tabeller fra `DATABASE_ARCHITECTURE.md` i én gigantisk initial migration.

## 18. Migrasjon 001 — schema- og sikkerhetsfundament

Opprett:

```text
catalog
knowledge
workflow
provenance
audit
api
```

Etabler:

- nødvendige extensions
- eksplisitte grants/revokes
- grunnleggende rolle-/sikkerhetsmodell
- conventions for UUID/timestamps
- migrasjonstest som bekrefter at kanoniske schema ikke er offentlig lesbare

Ingen klinisk data ennå.

## 19. Migrasjon 002 — katalogfundament

Opprett minimum:

```text
catalog.drugs
catalog.drug_names
catalog.clinical_concepts
catalog.populations
```

Seed kun data som trengs for første golden slice.

## 20. Migrasjon 003 — Source og EvidenceItem

Opprett minimum:

```text
knowledge.sources
knowledge.source_identifiers
knowledge.source_versions
knowledge.evidence_items
```

Implementer:

- identitetsconstraints
- kildestatus
- source locator
- eksplisitte null/ukjent-tilstander der nødvendig
- immutabilitetsstrategi for EvidenceItem

## 21. Migrasjon 004 — Claims

Opprett:

```text
knowledge.claims
knowledge.claim_revisions
knowledge.claim_evidence_links
knowledge.evidence_assessments
```

Implementer:

- immutable revisjoner
- unik revisjonsnummerering per claim
- relationship-type constraints
- knowledge type
- certainty/no-evidence-semantikk

## 22. Migrasjon 005 — review og proveniens

Opprett minimum:

```text
provenance.actors
workflow.evidence_verifications
workflow.claim_verifications
workflow.review_decisions
workflow.user_roles
```

Agent-run-tabeller kan implementeres samtidig dersom første evidenspipeline bruker agentkjøringer allerede i denne slicen.

## 23. Migrasjon 006 — publisering

Opprett:

```text
knowledge.publication_events
```

Implementer kontrollert publiseringsoperasjon.

Publisering skal:

- være transaksjonell
- kontrollere nødvendige gates
- oppdatere current published revision atomisk
- opprette PublicationEvent
- avvise ugyldig publisering med forståelig feil

## 24. Migrasjon 007 — API-lesemodell

Opprett første views:

```text
api.published_drugs
api.published_claims
api.published_claim_evidence
```

Kun publiserte revisjoner skal vises.

Test eksplisitt med faktisk klientrolle.

## 25. Migrasjon 008 — audit

Opprett:

```text
audit.events
```

Audit bør komme tidlig nok til at resten av admin-MVP-en bygges med sporbarhet fra starten.

## 26. Migrasjon 009 — DrugProduct/importfundament

Når golden slice er stabil, opprett:

```text
catalog.drug_products
```

og nødvendig ingest/staging for første autoritative norske produktdatasett.

Ikke start automatisert produktimport før:

- ekstern identitet er bestemt
- idempotens er testet
- endringsdeteksjon er definert
- tidsvaliditet er modellert

## 27. Migrasjon 010+ — kun når neste slice trenger det

Eksempler:

- studies/study_sources
- evidence work units
- search history
- screening decisions
- clinical rules
- interactions

Ikke opprett dem kun fordi de finnes i fremtidsarkitekturen.

---

# Del VII — Vertikale implementasjonsslices

## 28. Slice 0 — prosjektbootstrap

### Leveranser

- React/TypeScript/Vite-app
- lint/format/typecheck
- testgrunnlag
- miljøvariabelstruktur
- Supabase lokal/dev-oppsett
- Vercel preview deployment
- enkel CI
- grunnleggende app shell

### Definition of done

- clean checkout kan installeres og kjøres etter dokumenterte kommandoer
- typecheck og tester kjører i CI
- preview deployment fungerer
- ingen secrets i klient/repo

## 29. Slice 1 — golden evidence slice

### Klinisk scope

```text
sertralin vs mirtazapin
vektendring
```

### Leveranser

- migrasjon 001–006
- Source
- EvidenceItem
- Claim/ClaimRevision
- EvidenceAssessment
- verifikasjon
- review
- publisering
- manuell adminflyt

### Definition of done

En kvalifisert reviewer kan gjennom admin-UI publisere ett reelt claim, og systemet kan rekonstruere hele provenienskjeden.

## 30. Slice 2 — første kliniker-UI

### Leveranser

- `/drugs/sertralin`
- `/drugs/mirtazapin`
- enkel temaside for vekt
- claim-komponent
- uncertainty/certainty-visning
- `Hvorfor sier Antidep dette?`
- kildedetalj

### Definition of done

En kliniker kan finne claimet og forstå:

- hva Antidep hevder
- hva det gjelder
- hvor sikker kunnskapen er
- hva evidensen er
- hvilken kilde som støtter eller motsier det

uten admin-tilgang.

## 31. Slice 3 — sammenligning

### Leveranser

- valg av legemidler
- valg av dimensjoner
- sammenligningsvisning
- responsiv mobilrepresentasjon
- `vis bare forskjeller`
- drilldown fra hvert datapunkt

### Definition of done

Sertralin og mirtazapin kan sammenlignes uten duplisert innhold eller separat sammenligningstekst i databasen.

## 32. Slice 4 — norsk produktdata

### Leveranser

- DrugProduct-modell
- staging/importmekanisme
- pilotimport for de seks virkestoffene
- handelsnavn
- formuleringer
- styrker
- tidsvaliditet
- idempotent rerun

### Definition of done

Brukeren kan svare korrekt på «hvilke styrker finnes i Norge?» og importen kan kjøres på nytt uten semantiske duplikater.

## 33. Slice 5 — utvid evidenspipelinen

### Leveranser

Utvid golden slice til:

```text
6 pilotlegemidler
×
vekt
seksuell dysfunksjon
sedasjon/søvn
seponering
```

Ikke nødvendigvis alle 24 kombinasjoner umiddelbart; arbeid i batches som kan reviewes.

### Pipelinekrav

- source discovery
- source assessment
- extraction
- separat verification
- claim drafting
- contradictory-evidence check
- evidence assessment
- claim support verification
- human review

### Definition of done

Det finnes målt feilrate for agentassistert ekstraksjon og claim-verifikasjon på pilotsettet.

## 34. Slice 6 — kliniske temasider og globalt søk

### Leveranser

- temavisninger
- søk på virkestoff
- handelsnavn
- klinisk konsept
- relevante claims
- dypelenker

### Definition of done

Den samme ClaimRevision vises konsistent på legemiddelside, temaside, søk og sammenligning.

## 35. Slice 7 — bytte/nedtrapping, første regel

### Scope

Velg én eller noen få klinisk veldefinerte overganger som tester:

- lang vs kort halveringstid
- tilgjengelige norske styrker
- doseendringer
- eksplisitte forutsetninger

### Leveranser

- `ClinicalRule`-objekt eller tilsvarende versjonert regelartefakt
- deterministisk beregningsmotor
- rule version
- klinisk rationale/evidenskobling
- enhetstester
- edge-case-tester
- human clinical approval
- UI med tydelig supported/unsupported-status

### Definition of done

Samme input + samme regelversjon gir deterministisk samme plan, og brukeren kan se hvilken regel og hvilke forutsetninger som ligger bak.

## 36. Slice 8 — full pilot og hardening

### Leveranser

- alle seks pilotlegemidler
- de avtalte MVP-temaene med akseptabel dekning
- mobilgjennomgang
- keyboard/accessibility-gjennomgang
- feilrapportering
- re-review-flagg
- source correction/retraction-propagation
- observability/logging
- sikkerhetstesting
- usability-test med klinikere

### Definition of done

MVP-en oppfyller lanseringskriteriene i dette dokumentet.

---

# Del VIII — Evidenspipeline i første implementasjon

## 37. Automatiser sent, men ikke for sent

Første golden slice kan opprettes delvis manuelt for å validere datamodellen.

Agentpipeline skal deretter implementeres på samme objekter.

Unngå to ekstremer:

- full agentautomatisering før objektmodellen er testet
- langvarig manuell innholdsproduksjon som om agentpipeline ikke er et kjernekrav

## 38. Første agentroller

Implementer i denne rekkefølgen:

1. **Extraction agent**
2. **Extraction verifier**
3. **Claim drafter**
4. **Claim support verifier**
5. **Contradiction/adversarial checker**
6. **Source discovery/assessment**

Grunnen til at discovery ikke nødvendigvis kommer først teknisk, er at ekstraksjon/verifikasjon kan testes på et lite manuelt kuratert kildesett før man bygger robust søkeorkestrering.

## 39. Agent-output skal være strukturert

Agentene skal produsere validerbare objekter, ikke fritekst som direkte lagres som publisert kunnskap.

Eksempel:

```text
Extraction agent
→ EvidenceItem candidate
→ schema validation
→ verification queue
```

## 40. Mål kvalitet før skalering

På pilotsettet skal minst følgende måles:

- numerisk ekstraksjonsfeil
- feil populasjon
- feil komparator
- feil tidsramme
- locator-feil
- claim som overdriver evidensen
- manglende sentrale forbehold
- feil support/contradict-relasjon
- oversett motstridende evidens

Ingen bestemt prosentgrense fastsettes i plan v0.1; terskler skal bestemmes etter at en representativ evalueringssample finnes.

---

# Del IX — Teststrategi

## 41. Testpyramide

MVP-en skal ha flere testnivåer.

### Database

Test:

- constraints
- foreign keys
- immutabilitet
- grants
- RLS
- publiseringsgates
- rollback
- audit
- idempotent import

### Domene-/regeltester

Test:

- mapping av knowledge types
- certainty/no-evidence states
- sammenligningslogikk
- ClinicalRule
- dose-/styrkeberegning

### Komponenttester

Test:

- claim card
- uncertainty-visning
- evidence drilldown
- sammenligningsceller
- forms/admin validation

### End-to-end

Test representative kliniske oppgaver.

## 42. Kritiske negative tester

MVP-en skal eksplisitt teste at systemet **nekter**:

- publisering uten evidens når evidens kreves
- publisering uten human review når dette kreves
- review av en revisjon som senere er endret uten nytt review
- redigering av publisert immutable revisjon
- vanlig brukerlesing av private knowledge/workflow-tabeller
- adminhandling uten riktig rolle
- klinisk plan for unsupported transition
- visning av `no evidence` som null

## 43. Accessibility-test

Automatisert testing er ikke tilstrekkelig.

Før lansering skal sentrale flyter testes manuelt med:

- keyboard
- synlig fokus
- zoom
- smal mobilviewport
- screen-reader-semantikk på sentrale komponenter
- informasjon uten farge

---

# Del X — UX- og klinisk validering

## 44. Første usability-runde

Bruk 3–5 klinikere tidlig, før full pilotdekning.

Oppgaver:

- finn tilgjengelige norske styrker
- finn et konkret claim
- identifiser evidenssikkerheten
- finn kilden
- sammenlign sertralin og mirtazapin på vekt
- identifiser at manglende evidens ikke betyr lav risiko

## 45. Andre usability-runde

Etter Slice 7:

- sammenlign 3–4 antidepressiver
- bruk temaside
- gjennomfør støttet bytte-/nedtrappingsscenario
- identifiser unsupported scenario
- finn rationale og regelversjon

## 46. Mål

Følg minst:

- tid til korrekt svar
- feilrate
- misforstått usikkerhet
- kildefunnrate
- navigasjonsfriksjon
- mobilgjennomførbarhet
- feilaktig inferert behandlingsrangering

---

# Del XI — Sikkerhet og tilgang

## 47. Offentlig lesing

Offentlig klinikerflate skal kun lese eksplisitt publiserte API-projeksjoner.

Den skal ikke få direkte `SELECT` mot:

- `knowledge`
- `workflow`
- `provenance`
- `audit`
- `ingest`

## 48. Admin-skriving

Admin-klienten skal ikke få generell tabellskriveadgang til kanoniske data.

Sentrale operasjoner skal gå gjennom kontrollerte server-/RPC-grenser som kan:

- validere rolle
- validere objektstatus
- håndheve preconditions
- opprette audit
- utføre transaksjoner

## 49. Least privilege for agenter

En ekstraksjonsagent skal ikke kunne publisere.

En source discovery-agent skal ikke kunne endre Claims.

En verifier skal kunne skrive verifikasjonsresultat, ikke overskrive inputobjektet som verifiseres.

## 50. Ingen pasientdata i MVP

MVP-en skal ikke lagre:

- navn
- fødselsnummer
- journaltekst
- pasientprofiler
- fritekstkasus med identifiserbare opplysninger

Bytte-/nedtrappingsverktøy skal operere på de nødvendige legemiddel- og doseparameterne uten permanent pasientprofil.

---

# Del XII — CI/CD og arbeidsform

## 51. Små PR-er

Etter implementeringsplanen skal arbeidet deles i små PR-er.

Et typisk godt implementerings-PR skal gjøre én ting, for eksempel:

- bootstrap frontend
- opprett schema skeleton
- implementer Source/EvidenceItem
- implementer ClaimRevision
- implementer publication RPC
- bygg ClaimCard
- bygg evidence drawer

Unngå PR-er som samtidig endrer schema, evidenspipeline, admin-UI og kliniker-UI i stor skala.

## 52. Hver PR skal ha eksplisitt validation

Relevant kombinasjon av:

```text
lint
typecheck
unit tests
database tests
RLS tests
e2e tests
build
```

Dokumentasjons-PR-er trenger ikke kjøre unødvendige app-tester dersom ingen appkode påvirkes.

## 53. Preview deployments

UI-PR-er bør få Vercel preview deployment slik at klinisk og visuell review kan gjøres uten lokal utviklingsmiljø.

## 54. Databaseendringer

Schemaendringer skal alltid ligge som versjonerte migrasjoner i repoet.

Produksjonsschema skal ikke utvikles ved manuelle Dashboard-endringer som ikke finnes i Git-historikken.

---

# Del XIII — Hva som eksplisitt ikke skal bygges nå

## 55. Ikke-MVP

Følgende utsettes:

- komplett dekning av alle antidepressiver
- full individuell behandlingsanbefalingsmotor
- automatisk «beste antidepressiv for denne pasienten»
- pasientprofiler
- journalintegrasjon
- TDM-modul
- full farmakogenetikkmodul
- avansert interaksjonsontologi
- institusjonelle overlays
- embeddings/semantisk søk med mindre vanlig søk viser seg utilstrekkelig
- native mobilapp
- offline-first-synkronisering
- flerspråklig UI
- generisk workflow builder
- generisk regel-DSL
- automatisert masspublisering uten human review

## 56. Beslutningsstøtte avgrenses bevisst

Temasider og sammenligning skal ikke automatisk rangere legemidler som «best».

Individuell, algoritmisk behandlingsanbefaling er en senere produktfase med separat regulatorisk og klinisk validering.

---

# Del XIV — Milepæler

## 57. Milepæl A — teknisk fundament

Oppnådd når:

- app kjører
- CI kjører
- Supabase-devmiljø fungerer
- sikkerhetsgrensene er etablert
- første migrasjoner er i repoet

## 58. Milepæl B — første publiserte Claim

Oppnådd når:

- Source → EvidenceItem → Claim → review → publish fungerer
- publisering skjer gjennom kontrollert operasjon
- historikk/proveniens er intakt

Dette er den første store arkitekturmilepælen.

## 59. Milepæl C — første kliniske end-to-end-opplevelse

Oppnådd når klinikeren kan:

```text
søke
→ åpne legemiddel
→ lese claim
→ sammenligne
→ åpne evidens
```

for golden slice.

## 60. Milepæl D — redaksjonell selvbetjening

Oppnådd når vanlig innholdsarbeid for pilotobjektene ikke krever SQL eller vibekoding.

## 61. Milepæl E — pilotkunnskapsbase

Oppnådd når seks pilotlegemidler har reviewet dekning av de prioriterte temaene i den graden som er definert for intern pilot.

## 62. Milepæl F — begrenset klinisk verktøy

Oppnådd når minst én bytte-/nedtrappingsregel er versjonert, testet, faglig godkjent og brukt gjennom UI.

## 63. Milepæl G — offentlig MVP-kandidat

Oppnådd når lanseringskriteriene under er oppfylt.

---

# Del XV — Lanseringskriterier

## 64. Faglig

Før offentlig MVP:

- alle publiserte evidenssynteser har nødvendig human review
- alle publiserte claims har sporbar evidens eller eksplisitt relevant deterministisk kilde
- relevante motstridende funn er representert
- `no evidence` brukes korrekt
- alle aktive ClinicalRules er eksplisitt godkjent
- review-overdue høyrisikoinnhold er ikke publisert som om det var aktuelt

## 65. Teknisk

- ingen kjente kritiske RLS-/grant-feil
- ingen secrets i klienten
- publisering og rollback er testet
- migrasjoner kan kjøres reproduserbart
- backup/recovery-forutsetninger er dokumentert
- logging er tilstrekkelig for feilsporing uten pasientdata
- kritiske E2E-tester er grønne

## 66. UX

- sentrale kliniske oppgaver er gjennomført med klinikere
- brukerne kan finne evidensgrunnlag
- ukjent/usikkert misforstås ikke systematisk som trygt
- mobilflytene er brukbare
- keyboard-flyt fungerer
- farge er ikke eneste informasjonsbærer

## 67. Governance

- aktive roller er definert
- Publisher-funksjon finnes
- Clinical Reviewer finnes
- ansvar for evidensmetodikk er definert
- feilrapportering har eier
- sikkerhetskritisk avpublisering kan gjennomføres raskt

---

# Del XVI — Første konkrete PR-rekke etter denne planen

## 68. Anbefalt PR-sekvens

Etter at denne planen er merget, anbefales følgende implementeringsrekkefølge:

```text
PR A  chore: bootstrap Antidep web app
PR B  db: add schema and security foundation
PR C  db: add drug and clinical concept catalog
PR D  db: add sources and evidence items
PR E  db: add claims and evidence assessments
PR F  db: add review and publication workflow
PR G  feat: add admin golden-slice workflow
PR H  feat: add published claim API views
PR I  feat: add first drug and evidence UI
PR J  feat: add comparison golden slice
PR K  db: add Norwegian product model and ingest
PR L+ expand pilot evidence pipeline and content
```

Hver PR skal vurderes mot de styrende dokumentene, ikke bare mot om koden «virker».

Rekkefølgen over er den opprinnelig planlagte. Den faktiske rekkefølgen har avveket
fra og med PR F: databasearbeidet er gjennomført med **én migrasjon per PR**, slik at
hver migrasjon kan reviewes for seg. Etikettene PR F og PR G over svarer derfor ikke
til det som faktisk ble bygget. Se §74 for den faktiske rekkefølgen.

## 69. Første implementeringsoppgave

Den aller neste arbeidsoppgaven etter at denne planen er godkjent skal være:

> **Bootstrap en minimal React + TypeScript + Vite-applikasjon med test-, CI- og Supabase-utviklingsfundament, uten å implementere klinisk funksjonalitet ennå.**

Denne oppgaven skal samtidig etablere en kort `CLAUDE.md` eller tilsvarende agentinstruks som peker til de styrende dokumentene i `docs/`, uten å kopiere dem inn og dermed blåse opp konteksten.

---

# Del XVII — Hvordan planen skal vedlikeholdes

## 70. Planen er operativ

`MVP_IMPLEMENTATION_PLAN.md` skal brukes som prosjektets fremdriftskart frem til MVP.

Når en slice er ferdig, skal status oppdateres eksplisitt.

Anbefalt statusmarkering:

```text
[ ] not started
[~] in progress
[x] done
[!] blocked / needs decision
```

## 71. Ikke skriv historien om igjen

Hvis implementasjonen krever avvik fra planen:

- dokumenter beslutningen
- oppdater relevant del
- behold Git-historikken
- endre overordnet arkitektur bare dersom erfaring faktisk viser at den bør endres

Små tekniske avvik krever ikke at konstitusjonen eller kunnskapsmodellen omskrives.

## 72. Arkitekturgjeld skal være eksplisitt

Hvis en MVP-forenkling bryter en ønsket langsiktig egenskap uten å bryte en invariant, skal den registreres som eksplisitt arkitekturgjeld med:

- hva som er forenklet
- hvorfor
- risiko
- trigger for når det må ryddes opp

---

# Del XVIII — MVP-statusoversikt

## 73. Initial status ved versjon 0.1

Listen under er statusen slik den var da planen ble skrevet, og beholdes som
historikk (§71). **Gjeldende status står i §74.**

```text
[x] Product/evidence constitution
[x] Knowledge model
[x] Evidence pipeline specification
[x] Database architecture
[x] Content governance
[x] Product information architecture
[x] MVP implementation plan drafted

[~] Web application bootstrap
[x] Supabase schema/security foundation
[~] Golden evidence slice
[ ] First admin workflow
[ ] First published Claim
[ ] First clinician UI
[ ] Comparison golden slice
[ ] Norwegian product ingest
[ ] Pilot evidence pipeline
[ ] Clinical situation views
[ ] First ClinicalRule
[ ] Usability validation
[ ] Security/accessibility hardening
[ ] Public MVP candidate
```

---

## 74. Status etter migrasjon 006

**Oppdatert:** 20. august 2026 (etter at PR #15, migrasjon 006, ble merget)

### 74.1 Gjeldende statusmarkering

```text
[x] Product/evidence constitution
[x] Knowledge model
[x] Evidence pipeline specification
[x] Database architecture
[x] Content governance
[x] Product information architecture
[x] MVP implementation plan drafted

[x] Web application bootstrap
[x] Supabase schema/security foundation
[~] Golden evidence slice
[!] First admin workflow
[!] First published Claim
[ ] First clinician UI
[ ] Comparison golden slice
[ ] Norwegian product ingest
[ ] Pilot evidence pipeline
[ ] Clinical situation views
[ ] First ClinicalRule
[ ] Usability validation
[ ] Security/accessibility hardening
[ ] Public MVP candidate
```

**Milepæl A (§57) er nådd.** Appen kjører, CI kjører, Supabase-devmiljøet fungerer,
sikkerhetsgrensene er etablert og de første migrasjonene er i repoet.

**Slice 0 (§28) er ferdig.** Alle fire punktene i definition of done er innfridd, også
preview deployment: Vercel-prosjektet er koblet til repoet gjennom GitHub-integrasjonen
og bygger både preview per pull request og produksjon fra `main`. Koblingen er satt opp
på prosjektsiden hos Vercel, ikke som konfigurasjon i repoet, så fravær av `vercel.json`
sier ingenting om status.

`First admin workflow` og `First published Claim` står som `[!]` — blokkert og avhengig
av en beslutning, ikke av kode. Se §74.4.

### 74.2 Faktisk PR-rekkefølge

```text
PR A  chore: bootstrap Antidep web app                    (#9)   merget
PR B  db: add schema and security foundation              (#10)  merget   migrasjon 001
PR C  db: add drug and clinical concept catalog           (#11)  merget   migrasjon 002
PR D  db: add sources and evidence items                  (#12)  merget   migrasjon 003
PR E  db: add claims and evidence assessments             (#13)  merget   migrasjon 004
PR F  db: add review and provenance                       (#14)  merget   migrasjon 005
PR G  db: add publication events and gate                 (#15)  merget   migrasjon 006
```

Avviket fra §68 er bevisst: én migrasjon per PR gir mindre og mer reviewbare enheter,
i tråd med §51. Den planlagte PR G — `feat: add admin golden-slice workflow` — er
dermed ikke bygget ennå, og glir til etter migrasjon 007.

Databaselaget teller nå 872 pgTAP-assertions over 27 testfiler.

### 74.3 Hva databasen faktisk inneholder

Kunnskapsmodellen er komplett til og med publisering: katalog, kilder og kildeversjoner,
evidensfunn, påstander med immutable revisjoner, evidenslenker, evidensvurderinger,
aktører, rollemodell, ekstraksjons- og claim-verifikasjon, reviewbeslutninger, og
publiseringshistorikk med en kontrollert publiseringsoperasjon.

Innholdet er derimot bevisst minimalt, og det er ikke det samme som at slicen er ferdig:

- to virkestoff, to kliniske begreper, én populasjon
- to kilder og to evidensfunn
- to påstander med én revisjon, én evidenslenke og én evidensvurdering hver
- to aktører, begge KI-roller

**Ingen verifikasjon, ingen reviewbeslutning og ingen publisering er registrert.** Det
finnes ingen menneskelig aktør, ingen brukerkonto og ingen rolletildeling. De to
påstandene er ubekreftede KI-forslag, og `current_published_revision_id` er tom på
begge.

### 74.4 Milepæl B er ikke nådd, og hvorfor

§58 krever at kjeden Source → EvidenceItem → Claim → review → publish *fungerer*.
Maskineriet finnes og er testet, men kjeden er ikke kjørt gjennom med reelle data.

Det er ikke en teknisk mangel. Publisering av en evidenssyntese krever menneskelig
faglig godkjenning fra en navngitt kvalifisert redaktør (ANTIDEP_CONSTITUTION.md §12),
og migrasjon 005 gjorde det til en strukturell umulighet uten en reell person: en
reviewbeslutning krever en aktør av typen `human`, knyttet til en brukerkonto, med
gyldig `reviewer`-rolle for innholdsområdet på beslutningstidspunktet.

**Neste skritt mot Milepæl B er derfor en governance-beslutning, ikke en kodeoppgave:**
hvem er kvalifisert redaktør, og hvordan registreres vedkommende? Å seede en redaktør
ville vært å oppfinne den godkjenningen konstitusjonen krever.

Konsekvens for rekkefølgen: migrasjon 007 (§24) kan bygges nå, men api-projeksjonene
vil vise et tomt publisert sett. Det er korrekt oppførsel, og 007 må testes mot data
opprettet inne i en transaksjon — samme mønster som 006 — framfor mot seedet innhold.

### 74.5 Beslutninger som bør tas før migrasjon 007

Disse er billigst å avgjøre før api-projeksjonene begynner å eksponere verdier utad,
fordi de da blir en offentlig kontrakt:

1. **Enum kontra oppslagstabell.** Det finnes nå 37 enum-typer, fordelt på
   migrasjonene 001-006 med henholdsvis 1, 6, 11, 7, 10 og 2. Et bytte blir dyrere
   etter at verdiene er eksponert.
2. **Stabil, språkuavhengig nøkkel for katalogobjekter.** Skal api-en eksponere uuid-er
   eller stabile nøkler? `provenance.actors.actor_key` (formatet `type:navn`) er et
   mønster som allerede finnes.
3. **Om `public` skal fjernes fra `[api].schemas`.** Hører naturlig sammen med at
   `api`-schemaet faktisk tas i bruk.

### 74.6 Invariant etablert i migrasjon 006

To reviewfunn i PR #15 hadde samme rot: PostgreSQL-tid har flere betydninger, og
`now()` er transaksjonens *starttidspunkt* — verken committidspunkt eller nåtid.
Regelen som ble etablert, gjelder framover:

> **Tid som *avgjør* noe måles på setningen (`statement_timestamp()`).
> Tid som *registrerer* noe måles på transaksjonen (`now()`).**

Spørsmålet «er evidensgrunnlaget endret siden godkjenningen?» besvares dessuten ikke
med tid i det hele tatt, men med et databaseeid avtrykk av settet, fordi
commitrekkefølgen ikke er lesbar fra radene. Den som skriver ny autorisasjons- eller
gyldighetslogikk bør lese dette før `now()` brukes i et predikat.

### 74.7 Registrert arkitekturgjeld (§72)

| Gjeld | Risiko | Trigger for opprydding |
|---|---|---|
| `knowledge.set_evidence_item_content_hash()` skjøter med `concat_ws('\|', …)` mens fritekstfelt kan inneholde `\|`, og hashen er `UNIQUE` | En serialiseringskollisjon ville avvist et legitimt distinkt evidensfunn som dublett | Egen liten migrasjon som bytter funksjonen og rehasher under nytt prefiks. Har ligget siden migrasjon 004 og bør ikke bli liggende lenger |
| Tidsbasert utløp av review er ikke håndhevet i publiseringsgaten | En godkjenning eldes uten at noe fanger det | Migrasjonen som innfører `workflow.review_requirements` / `review_due_at`. Krever først en klinisk policy for hvor lenge en godkjenning er gyldig per kunnskapstype og risiko |
| Godkjenningens evidensavtrykk beregnes ved innsetting, ikke fra det reviewer faktisk så | En lenke som commiter mellom reviewers lesing og lagring av beslutningen havner i avtrykket | Admin-flyten oppgir avtrykket den viste reviewer. Kolonnen er utformet for det |
| `knowledge.publication_object_type` har én verdi, og hendelsen har én ekte fremmednøkkel | En andre publiserbar objekttype kan friste til å gjenbruke `claim_id` som generisk `object_id` | Migrasjonen som innfører objekttype nummer to må legge til egen fremmednøkkelkolonne og eget speil |
| `KNOWLEDGE_MODEL.md` §8 lister fortsatt `status` som minimumsfelt på Claim | Motstrid mot `DATABASE_ARCHITECTURE.md` §15 | Med publiseringshendelsene på plass er den avledede livssyklusen komplett; §8 bør ryddes i favør av §15 |
| Ingen RLS-policies og ingen grants på kanoniske tabeller | Ingen — skriveveien er en `SECURITY DEFINER`-funksjon som ikke trenger dem | Migrasjonen som eksponerer en RPC-flate i `api`, med egen trusselvurdering |
| Felles hjelpefunksjoner (`catalog.set_row_timestamps()`, `catalog.set_created_at()`, `knowledge.reject_append_only_mutation()`) brukes fra flere schemaer | Lav; plasseringen er misvisende | Et `util`-schema endrer `DATABASE_ARCHITECTURE.md` §6 og hver schemauttømmende vaktpost i testpakken. Egen beslutning |

Mindre tekstgjeld, samlet til én oppryddings-PR: kolonnekommentaren på
`catalog.drugs.updated_at` viser til `catalog.set_updated_at()`, som ikke finnes,
testbeskrivelsene i `060_catalog_access_test.sql` og `110_knowledge_access_test.sql`
sier fortsatt at medlemskapsmodellen kommer i migrasjon 005, og kommentarene i
migrasjon 005 og 006 oppgir antallet enum-typer til henholdsvis 28 og 30. Det
riktige tallet er 37; undertellingen oppsto i 005 og ble videreført i 006.

---

# Del XIX — Ikke-forhandlingsbare implementeringsprinsipper

1. **Bygg vertikalt; ikke bygg hele databasen før første kliniske flyt.**
2. **Ingen masseinnholdsproduksjon før evidenspipelinen er kvalitetsmålt.**
3. **Admin-UI bygges tidlig nok til at innhold ikke blir kode.**
4. **Publiserte revisjoner er immutable.**
5. **Kliniker-UI leser publiserte projeksjoner, ikke redaksjonelle tabeller.**
6. **Samme Claim driver alle kliniske visninger.**
7. **Usikkerhet og fravær av evidens er eksplisitte datatilstander.**
8. **ClinicalRules er deterministiske, versjonerte og testede.**
9. **Unsupported kliniske scenarioer skal være tydelig unsupported, ikke improviseres av KI.**
10. **Agentroller følger least privilege og kan ikke selvpublisere høyrisikoinnhold.**
11. **Databaseintegritet håndheves i databasen der det er praktisk og korrekt.**
12. **Ingen pasientdatabase etableres som bivirkning av MVP-utviklingen.**
13. **Mobil, tilgjengelighet og evidensdrilldown testes før offentlig MVP.**
14. **Små, reviewbare PR-er er normal utviklingsenhet.**
15. **Styringsdokumentene er kontrakten; implementasjonen skal ikke gradvis definere et annet produkt.**

---

## 75. Neste steg

> **Merk:** Avsnittet under er skrevet ved planens godkjenning og beskriver oppstarten.
> Det er beholdt som historikk (§71). Planleggingsfasen er avsluttet, og PR A til PR G
> er merget (§74.2). **Gjeldende neste steg står i §74.4 og §74.5.**

Når denne planen er godkjent, avsluttes planleggingsfasen som standard arbeidsmodus.

Neste steg er **faktisk implementasjon**, med PR A:

```text
chore: bootstrap Antidep web app
```

Deretter følges PR-rekken og milepælene i dette dokumentet, med planen oppdatert fortløpende etter hvert som prosjektet går fra arkitektur til fungerende klinisk produkt.
