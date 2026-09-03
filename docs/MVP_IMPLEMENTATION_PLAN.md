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

## 74. Status etter kildevisningen

**Oppdatert:** 27. august 2026 (etter `db: authorize the named qualified editor`, som
knytter redaktørens brukerkonto til aktørraden og tildeler `reviewer`-rollen — se §74.20;
forrige oppdatering etter `test: verify the api column contract`, som binder radtypene i
`src/types/` til databasens kolonner, §74.19)

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
[x] First clinician UI
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

`First admin workflow` og `First published Claim` står fortsatt som `[!]`, men grunnen har
endret seg. Fram til nå var de blokkert av en governance-beslutning som ikke var tatt: hvem er
den navngitte kvalifiserte redaktøren? Den beslutningen er tatt, og redaktøren er registrert
som aktør (§74.17). Det som gjenstår er ikke lenger et åpent spørsmål, men konkret arbeid som
ikke er gjort: en reell brukerkonto, en rolletildeling, to verifikasjonsfaser og en
godkjenning. Se §74.4.

**Slice 2 (§30) er ferdig.** Alle fem punktene i definition of done er dekket: klinikeren kan
finne påstanden og se hva Antidep hevder, hva det gjelder, hvor sikker kunnskapen er, hva
evidensen er og hvilken kilde som støtter eller motsier den — uten admin-tilgang. Det kom med
evidensvisningen (§74.15), som viser hele kilderaden på hvert funn: dokumenttype, tittel,
forfattere, tidsskrift, publiseringsdato med sin presisjon, kildestatus, DOI, PMID, sted i
kilden og kildeversjon.

Det siste leveransepunktet, «kildedetalj», kom med kildevisningen (§74.16):
`PRODUCT_INFORMATION_ARCHITECTURE.md` §42 er eksplisitt på at en `Source`-visning — én side
per kilde, med alt Antidep bruker den til — er en *annen* visning enn claim-evidensvisningen,
og de to lenker nå til hverandre uten å være blandet. Markeringen er derfor flyttet fra `[~]`
til `[x]`. Innholdet bak den er fortsatt minimalt av samme grunn som resten: ingenting er
publisert (§74.4).

**Produktinvariant 9 er innfridd.** «Hvorfor sier Antidep dette?» går nå fra hvert
påstandskort til en visning som faktisk svarer.

### 74.2 Faktisk PR-rekkefølge

```text
PR A  chore: bootstrap Antidep web app                                     (#9)   merget
PR B  db: add schema and security foundation                               (#10)  merget   migrasjon 001
PR C  db: add drug and clinical concept catalog                            (#11)  merget   migrasjon 002
PR D  db: add sources and evidence items                                   (#12)  merget   migrasjon 003
PR E  db: add claims and evidence assessments                              (#13)  merget   migrasjon 004
PR F  db: add review and provenance                                        (#14)  merget   migrasjon 005
PR G  db: add publication events and gate                                  (#15)  merget   migrasjon 006
      docs: record implementation status after migration 006               (#16)  merget   ingen migrasjon
      db: make evidence item content hash unambiguous                      (#17)  merget   migrasjon 006a
      db: add api published read model                                     (#18)  merget   migrasjon 007
      ci: verify the numeric claims in the plan                            (#19)  merget   ingen migrasjon
      db: add audit events                                                 (#20)  merget   migrasjon 008
      db: expose publication and review timestamps in api                  (#21)  merget   migrasjon 007a
      feat: add published read model client                                (#22)  merget   ingen migrasjon
      feat: add claim card and certainty display                           (#23)  merget   ingen migrasjon
      feat: add routing and first clinician pages                          (#24)  merget   ingen migrasjon
      feat: add the claim evidence view                                    (#25)  merget   ingen migrasjon
      feat: add the source view                                            (#26)  merget   ingen migrasjon
      db: register the named qualified editor                              (#27)  merget   migrasjon 005a
      docs: correct the record of the hosted Supabase project              (#28)  merget   ingen migrasjon
      test: verify the api column contract                                 (#29)  merget   ingen migrasjon
      docs: clarify collaboration and reporting rules                      (#30)  merget   ingen migrasjon
      db: authorize the named qualified editor                             (#31)  merget   migrasjon 005b
      db: expose the caller's own actor and roles                          (#32)  merget   migrasjon 007b
      docs: mark #32 as merged in the PR log                               (#33)  merget   ingen migrasjon
      feat: add sign-in and my access                                      (#34)  merget   ingen migrasjon
      docs: record that the hosted project is migrated and api is exposed  (#37)  merget   ingen migrasjon
```

Avviket fra §68 er bevisst: én migrasjon per PR gir mindre og mer reviewbare enheter,
i tråd med §51. Den planlagte PR G — `feat: add admin golden-slice workflow` — er
dermed ikke bygget ennå, og glir til etter migrasjon 008. Rekkefølgen mellom migrasjon
008 og PR I (`feat: add first drug and evidence UI`) er avgjort til fordel for 008, fordi
§25 er eksplisitt på at audit skal komme tidlig nok til at resten av admin-MVP-en bygges
med sporbarhet fra starten. Se §74.10.

PR I bygges i deler, slik §51 forutsetter: «bygg ClaimCard» og «bygg evidence drawer» står
der som egne PR-er. Første del, `feat: add published read model client`, inneholdt ingen
visning og etablerte den typede leseveien fra `api` inn i appen (§74.12). Andre del,
`feat: add claim card and certainty display`, er den første klinikerflaten: presentasjons-
enheten for én publisert påstand, uten ruting og uten datahenting (§74.13). Tredje del,
`feat: add routing and first clinician pages`, er den første navigerbare flaten: adressene,
forsiden, legemiddelsidene og temasiden, med datahenting (§74.14). Fjerde del,
`feat: add the claim evidence view`, er evidensdrilldownen bak «Hvorfor sier Antidep dette?»
(§74.15). Femte og siste del, `feat: add the source view`, er kildedetaljen: én side per kilde,
med alt Antidep bruker den til (§74.16). **PR I er dermed ferdig, og med den Slice 2.**

Tabellen over er en logg over utført arbeid, og skal føres i den PR-en som gjør arbeidet
ferdig, ikke i en senere. Statuskolonnen beskriver tilstanden da raden ble skrevet, så den
nyeste raden står alltid som `åpen` til neste PR retter den. Hva 006a innfridde, står i §74.8;
hva 007 innfridde, i §74.9.

**Raden for #37 føres her og ikke av #37 selv, og det er femte gangen konvensjonen svikter.**
Den PR-en skrev §74.18, §74.23 og `supabase/README.md` uten å føre sin egen rad, og etterlot
samtidig #34 stående som `åpen` selv om den var merget. Vaktposten fanget det ikke, og kunne
ikke: den krever bare at hver rad *unntatt den nyeste* står som `merget`, og den nyeste raden
var nettopp #34. En rad som aldri blir skrevet, står ikke under noen — den er utenfor
kontrollen på samme måte som et tall som bare finnes i en hand-off (§74.18). Denne PR-en
etterfører raden og retter #34.

**Hoppet fra #34 til #37 er ikke et hull.** #35 er fortsatt åpen og fører sin egen rad når den
merges, etter konvensjonen over; #36 er en issue og ikke en PR. Rekkefølgen i tabellen er
faktisk mergerekkefølge, ikke nummerrekke, så #35 kommer under #37 når den lander.

Titlene er commit-emnene ordrett. Kolonnebredden er derfor utvidet framfor å forkorte #37 sin
tittel: en logg som gjengir noe annet enn historikken, kan ikke sammenlignes med den.

Raden for #30 føres her og ikke av #30 selv. Den PR-en endret bare `CLAUDE.md` og rørte
verken planen eller vaktposten, så loggen fikk et hull mellom #29 og #31. Et hull i en tabell
som heter «faktisk PR-rekkefølge» leses som en feil, ikke som et fravær, og etterføring er
billigere enn å la nummerrekken være usann.

Konvensjonen har sviktet fire ganger på rad, og er derfor ikke lenger bare en konvensjon:
`scripts/verify-counts.sh` krever at hver rad unntatt den nyeste står som `merget`, og at
hver rad ført som `merget` har sin commit i git-historikken. Den nyeste raden er unntatt,
fordi en PR ikke kan kjenne sin egen mergestatus — og nettopp derfor slår kontrollen ut i
det øyeblikket noen legger til raden under en foreldet rad.

**Migrasjonsnumrene i §18-§27 navngir planlagt innhold, ikke filrekkefølge.** Den niende
migrasjonsfilen er migrasjon 008, fordi den sjuende — korreksjonsmigrasjonen 006a — står
utenfor den planlagte rekken og fikk en bokstav. Konvensjonen finnes nettopp for at
«migrasjon 007 — API-lesemodell» (§24) skal bety det samme i plan, migrasjoner og tester.
Den tiende filen er migrasjon 007a av samme grunn: den utvider api-lesemodellen fra §24 og
står utenfor den planlagte rekken, og nummeret 009 er reservert for DrugProduct- og
importfundamentet (§26). Den ellevte filen er migrasjon 005a, som utvider aktørregisteret fra
§20 og står utenfor rekken på nøyaktig samme måte. Det gjør også den tolvte, migrasjon
005b, som fullfører det 005a bevisst lot stå åpent, og den trettende, migrasjon 007b, som
utvider api-lesemodellen fra §24 slik 007a gjorde. Filrekkefølgen er dermed 001, 002, 003,
004, 005, 006, 006a, 007, 008, 007a, 005a, 005b, 007b — sortert på tidsstempel, ikke på
migrasjonsnummer, og de tre siste filene bærer de tre laveste bokstavnumrene.

Databaselaget teller nå 1182 pgTAP-assertions over 36 testfiler.

Tallene i dette avsnittet og i §74.5 kontrolleres maskinelt av
`scripts/verify-counts.sh`, som kjører i CI. Bakgrunnen er §74.8: to ganger har et tall
vært feil fordi det ble arvet fra en gjeldspost eller en hand-off og ført videre i god tro,
ikke fordi noen regnet feil. Slår kontrollen ut, er dokumentet feil — kilden vinner. En
setning som omformuleres slik at vakten ikke finner påstanden lenger, teller også som brudd;
ellers ville vakten blitt stille uten at noen merket det.

### 74.3 Hva databasen faktisk inneholder

Kunnskapsmodellen er komplett til og med publisering: katalog, kilder og kildeversjoner,
evidensfunn, påstander med immutable revisjoner, evidenslenker, evidensvurderinger,
aktører, rollemodell, ekstraksjons- og claim-verifikasjon, reviewbeslutninger, og
publiseringshistorikk med en kontrollert publiseringsoperasjon.

Fra migrasjon 007 finnes også leseveien ut: tre views i `api`, de første RLS-policyene, og
`SELECT` til klientrollene på de tretten tabellene viewene leser. Kjeden er dermed lukket i
begge ender — det som mangler mellom dem, er en publisering.

Fra migrasjon 007a bærer `api.published_claims` i tillegg `published_at` og
`last_reviewed_at`, slik at hver publisert påstand har både en publiseringsdato og en dato
for den menneskelige godkjenningen den hviler på — også et deterministisk faktum, som ikke
har noen evidensvurdering. Se §74.11.

Fra migrasjon 008 finnes auditloggen: `audit.events`, med de to produsentene som dekker de
skriveveiene som faktisk finnes i dag — publisering og rolleforvaltning. Loggen er tom i
migrert tilstand, av samme grunn som api-projeksjonene er det: ingenting er publisert, og
ingen rolle er tildelt. Se §74.10.

Innholdet er derimot bevisst minimalt, og det er ikke det samme som at slicen er ferdig:

- to virkestoff, to kliniske begreper, én populasjon
- to kilder og to evidensfunn
- to påstander med én revisjon, én evidenslenke og én evidensvurdering hver
- tre aktører: to KI-roller og den navngitte kvalifiserte redaktøren (§74.17)

**Ingen verifikasjon, ingen reviewbeslutning og ingen publisering er registrert.** Redaktøren
er navngitt, men har verken brukerkonto eller rolletildeling, og kan derfor ikke registrere en
faglig beslutning — `workflow.enforce_reviewer_qualification()` avviser forsøket, og
`220_provenance_seed_test.sql` prøver det framfor å påstå det. De to påstandene er fortsatt
ubekreftede KI-forslag, og `current_published_revision_id` er tom på begge.

**Migrasjon 005b endrer ikke listen over, og det er ikke en forglemmelse.** Den kobler
redaktørens aktørrad til brukerkontoen og tildeler `reviewer`-rollen — men bare i miljøer der
kontoen finnes i `auth.users`. Den finnes bare i det hostede prosjektet, og der er ingen
migrasjon kjørt (§74.18). I en fersk lokal stack og i CI gjør migrasjonen derfor ingenting,
og sier fra om det. Se §74.20.

### 74.4 Milepæl B er ikke nådd, og hvorfor

§58 krever at kjeden Source → EvidenceItem → Claim → review → publish *fungerer*.
Maskineriet finnes og er testet, men kjeden er ikke kjørt gjennom med reelle data.

Det er ikke en teknisk mangel. Publisering av en evidenssyntese krever menneskelig
faglig godkjenning fra en navngitt kvalifisert redaktør (ANTIDEP_CONSTITUTION.md §12),
og migrasjon 005 gjorde det til en strukturell umulighet uten en reell person: en
reviewbeslutning krever en aktør av typen `human`, knyttet til en brukerkonto, med
gyldig `reviewer`-rolle for innholdsområdet på beslutningstidspunktet.

**Governance-beslutningen er tatt.** Spørsmålet var hvem den kvalifiserte redaktøren er, og
prosjekteieren — Peder Holman — har utpekt seg selv. Migrasjon 005a registrerer vedkommende
som menneskelig aktør, slik at beslutningen står som en kanonisk rad framfor som en setning i
dette dokumentet (§74.17).

Konsekvens for rekkefølgen: migrasjon 007 (§24) er bygget, og api-projeksjonene viser et
tomt publisert sett. Det er korrekt oppførsel. 007 er testet mot data opprettet inne i en
transaksjon som rulles tilbake — samme mønster som 006 — framfor mot seedet innhold, og
`220_provenance_seed_test.sql` bekrefter fortsatt at ingenting er publisert.

**Denne teksten sa tidligere at det gjenstod «nøyaktig én ting» for Milepæl B. Det var
feil.** Påstanden ble ført videre fra en tidligere oppdatering uten å bli kontrollert mot
publiseringsgaten i migrasjon 006, og gaten stiller sju krav som ikke er innfridd:

| Krav | Hva som mangler |
|---|---|
| G4, G5 | Hvert lenket evidensfunn skal ha en registrert ekstraksjonsverifikasjon, og den gjeldende skal bekrefte funnet. `workflow.evidence_verifications` er tom |
| G8, G9 | Revisjonen skal ha en registrert claim-verifikasjon, og den gjeldende skal si `verified`. `workflow.claim_verifications` er tom |
| G11, G12 | Menneskelig godkjenning skal finnes og være den gjeldende beslutningen. `workflow.review_decisions` er tom |
| G13 | Evidensgrunnlaget skal være det samme som godkjenningen ble gitt for. Forutsetter at en godkjenning finnes |

Registreringen av redaktøren berører ingen av dem. Den fjerner et hinder foran G11 — §12 sin
navngitte redaktør finnes nå — men åpner ikke kravet: en reviewbeslutning krever i tillegg en
reell brukerkonto og en gyldig `reviewer`-rolle, og verifikasjonsfasene bak G4/G5 og G8/G9 er
urørt. Verifikasjonene kan være agentproduserte, så lenge §10 sitt skille mellom den som
genererte og den som kontrollerer holdes, og §11 sitt krav om at kontrollen skjer mot
kildematerialet er innfridd. Godkjenningen kan ikke være agentprodusert.

**Det som gjenstod for Milepæl B var derfor fire ting**, ikke én: en reell brukerkonto med
`reviewer`-rolle for redaktøren, ekstraksjonsverifikasjonene, claim-verifikasjonene og selve
godkjenningen. Alt maskineri fra kilde til klientflate står ferdig og testet rundt det
tomrommet. Den første av de fire er siden utført; se avsnittet under.

**Den første av de fire er utført, og det som gjenstår er tre.** Migrasjon 005b knytter
redaktørens aktørrad til brukerkontoen og tildeler `reviewer`-rollen, og begge grenene av den
er kjørt i CI (§74.20). Migrasjonene er siden kjørt mot det hostede prosjektet, og der tok den
den positive grenen: `workflow.user_roles` har én rad, `role_code = 'reviewer'`, uten
scopebegrensning, uten sluttdato, gyldig nå og selvtildelt av `human:peder-holman` — lest fra
produksjonsdatabasen, ikke antatt (§74.23). G11 sin forutsetning om konto og gyldig rolle er
dermed innfridd. **Det som gjenstår for Milepæl B er ekstraksjonsverifikasjonene,
claim-verifikasjonene og selve godkjenningen.**

> **Avsnittet under er overhalt.** Det stod her mens rollen ennå ikke fantes noe sted, og er
> beholdt som historikk (§71): «Men *utført* er den ingen steder: kontoen finnes bare i det
> hostede prosjektet, og der er ingen migrasjon kjørt (§74.18). Redaktøren har derfor fortsatt
> ingen rolle i noen database.» Begge setningene er nå usanne; se §74.23.

G8 er verdt å merke seg særskilt, fordi den er lett å utelate når kravene listes opp: G9 leser
utfallet på den gjeldende claim-verifikasjonen, mens G8 er kravet om at det finnes en i det
hele tatt. Med en tom tabell feiler begge, på hver sin måte. Dette er sjette gang et tall
eller en påstand i planen har vært arvet framfor kontrollert (§74.8), og den ble funnet ved å
lese gaten framfor hand-offen.

**Beslutningen som blokkerte rollegranten, er tatt og gjennomført.** Prosjekteieren opprettet
redaktørens brukerkonto i autentiseringslaget i det hostede Supabase-prosjektet.
`workflow.user_roles.user_id` er `NOT NULL` med fremmednøkkel til `auth.users`, og CI starter
en fersk lokal stack uten den kontoen, så migrasjonen kunne ikke skrives før det var avgjort
hva den skulle gjøre i miljøer der kontoen ikke finnes. Valget, med prisen på hver vei, står i
§74.18; hvordan prisen faktisk ble betalt, står i §74.20.

**Adminflyten er begynt, og den lukker ingen av de fire.** Migrasjon 007b åpner den
autentiserte leseveien for «hvem er jeg, og hva har jeg lov til?» — kallerens egen aktørrad
og egne gjeldende rolletildelinger, og ingenting mer (§74.21). Det er første steg i «manuell
adminflyt», den ene leveransen §29 lister for Slice 1 og som ikke er bygget. Ingen av de sju
gatekravene i tabellen over er berørt: migrasjonen skriver ingen verifikasjon, ingen
reviewbeslutning og ingen publisering, og den tildeler ingen rettighet. Den gjør bare en
rettighet som allerede finnes, lesbar for den som har den.

### 74.5 Beslutninger tatt før migrasjon 007 eksponerte verdier utad

Alle tre er avgjort, og avgjørelsene er nå offentlig kontrakt:

1. **Enum kontra oppslagstabell — utsatt, og gjort billigere å utsette.** Det finnes
   38 enum-typer, fordelt på de tretten migrasjonsfilene 001, 002, 003, 004, 005, 006, 006a,
   007, 008, 007a, 005a, 005b og 007b — i filrekkefølge, ikke i nummerrekkefølge — med
   henholdsvis 1, 6, 11, 7, 10, 2, 0, 0, 1, 0, 0, 0 og 0. Tallet er kontrollert mot
   kilden (`grep -cE '^create type ' supabase/migrations/*.sql`) og mot databasen.
   Alle tretten ledd er nå oppgitt eksplisitt framfor å la de siste hvile på restpåstanden i
   `scripts/verify-counts.sh`; det er den formen vakten kontrollerer strengest. Verken
   005a, 005b eller 007b legger til enum-typer: den første registrerer én rad i et register
   som allerede finnes, den andre knytter og tildeler, og den tredje projiserer to
   eksisterende vokabularer som `text` slik resten av `api` gjør.
   Viewene caster enum-kolonner til `text`, så den offentlige kontrakten er en streng
   fra et dokumentert vokabular, ikke PostgreSQL-typen. Et senere bytte til
   oppslagstabeller er dermed ikke en brytende API-endring. Castingen sparer også
   klientrollene for `usage` på typene.
2. **Katalogobjekter eksponeres med `uuid`, med ATC som ekstern nøkkel.** Radens
   databasegenererte `uuid` er identiteten (`DATABASE_ARCHITECTURE.md` §8), og for
   virkestoff følger ATC-kodene med som språkuavhengig ekstern nøkkel, som sortert
   array — se §74.9 om hvorfor de aggregeres framfor å joines. En egen
   slug-kolonne etter mønster av `provenance.actors.actor_key` ville krevd en
   katalogmigrasjon utenfor §24 og er ikke innført. Spørsmålet kan tas opp igjen når
   en klient faktisk trenger en menneskelesbar nøkkel i URL-er.
3. **`public` er fjernet fra `[api].schemas`.** Verdien er nå
   `["api", "graphql_public"]`. Schemaet inneholdt ingen Antidep-objekter — §5 er opt-in,
   og en tom eksponering er fortsatt en eksponering. Verdien kontrolleres nå mot
   `supabase/config.toml` av `scripts/verify-counts.sh`, av samme grunn som tallene over: en
   påstand om en konfigurasjonsverdi driver, hvis ingenting sammenligner den med verdien.

   **`api` står først i `config.toml` og er dermed standardprofilen i PostgREST — men appen
   hviler ikke på det.** `src/lib/supabase.ts` setter `db: { schema: 'api' }`, så supabase-js
   sender `Accept-Profile: api` på hver forespørsel og er uavhengig av standardprofilen.
   Rekkefølgen gjelder dessuten bare `config.toml`: i dashboardet er eksponerte schemaer en
   avhukingsmeny uten rekkefølge, så setningen beskriver den lokale stacken og ikke det
   hostede prosjektet.

   **«Endringen må synkes manuelt mot det hostede prosjektet» stod her uten forbehold, og
   var utilstrekkelig.** Det finnes ikke noe `api`-schema å eksponere der: migrasjonene er
   aldri kjørt mot det hostede prosjektet, og databasen der er tom. Se §74.18.
   **Dette er ikke lenger tilstanden.** Migrasjonene er siden kjørt, og synkingen er gjort:
   eksponerte schemaer i det hostede prosjektet er `api, graphql_public`. Se §74.23.

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
| Tidsbasert utløp av review er ikke håndhevet i publiseringsgaten | En godkjenning eldes uten at noe fanger det | Migrasjonen som innfører `workflow.review_requirements` / `review_due_at`. Krever først en klinisk policy for hvor lenge en godkjenning er gyldig per kunnskapstype og risiko |
| Godkjenningens evidensavtrykk beregnes ved innsetting, ikke fra det reviewer faktisk så | En lenke som commiter mellom reviewers lesing og lagring av beslutningen havner i avtrykket | Admin-flyten oppgir avtrykket den viste reviewer. Kolonnen er utformet for det |
| `knowledge.publication_object_type` har én verdi, og hendelsen har én ekte fremmednøkkel | En andre publiserbar objekttype kan friste til å gjenbruke `claim_id` som generisk `object_id` | Migrasjonen som innfører objekttype nummer to må legge til egen fremmednøkkelkolonne og eget speil |
| En tilbaketrukket ekstraksjon utløser ingen automatisk avpublisering eller ny review | En publisert påstand kan bli stående mens deler av grunnlaget er underkjent. Lesemodellen merker det nå (§74.9), men livssyklusen er ikke lukket | Admin-flyten (§29). Der hører beslutningen om hva som skal skje med berørte publiseringer hjemme — automatisk avpublisering er en klinisk policy, ikke en implementasjonsdetalj |
| En fornyet godkjenning etter publisering oppdaterer ikke «sist faglig vurdert» | `last_reviewed_at` er frosset på publiseringshendelsen. Blir en publisert revisjon godkjent på nytt i en reviewsyklus, står den gamle datoen. I dag er det ikke en reell risiko, fordi det ikke finnes noen reviewsyklus | Migrasjonen som innfører `workflow.review_requirements` / `review_due_at`. Den må ta stilling til om en fornyet godkjenning skal flytte datoen, og er samme migrasjon som gjeldsposten om tidsbasert utløp over |
| En reviewbeslutning som ikke er `approved`, registrert etter publisering, er usynlig i lesemodellen | Ber reviewer om endringer på en revisjon som allerede står publisert, flyttes verken publiseringspekeren eller `last_reviewed_at`, og klienten får ingen signal. Parallellen er `withdrawn_evidence_count`, som ble innført for det tilsvarende tilfellet på evidenssiden | Admin-flyten (§29), sammen med beslutningen om hva som skal skje med berørte publiseringer. Å eksponere beslutningstypen er en governance-endring: §74.11 avgrenset kontrakten til tidsstempler |
| Ingen regel håndhever at en publisert påstand har en publiseringshendelse | `knowledge.claims.current_published_revision_id` kan i prinsippet flyttes uten at en hendelse skrives, og da blir `published_at` NULL i `api.published_claims`. Invarianten er dokumentert i migrasjon 006, men bare håndhevet ved at publiseringsoperasjonen er den eneste sanksjonerte skriveveien | Admin-RPC-laget, eller den første migrasjonen som trenger å stole på hendelsen som kilde framfor på pekeren. En deklarativ regel må håndtere at pekeren og hendelsen settes i samme transaksjon |
| `api.published_claims` eksponerer populasjonens etikett, ikke dens strukturerte grenser | Aldersgrenser, indikasjon, graviditetskontekst og komorbiditet ligger bare i etiketteksten | Det første viewet som faktisk trenger å filtrere på populasjon. `catalog.populations` er allerede lesbar for klientrollene, så det er en projeksjonsendring, ikke en tilgangsendring |
| Felles hjelpefunksjoner (`catalog.set_row_timestamps()`, `catalog.set_created_at()`, `knowledge.reject_append_only_mutation()`) brukes fra flere schemaer | Lav; plasseringen er misvisende. Migrasjon 008 gjorde den mer misvisende: `audit.events` bruker begge de to siste, så `catalog` og `knowledge` eier nå hjelpefunksjoner for et schema som ikke har noe med noen av dem å gjøre | Et `util`-schema endrer `DATABASE_ARCHITECTURE.md` §6 og hver schemauttømmende vaktpost i testpakken. Egen beslutning |
| Fysisk sletting av en rolletildeling er selv uauditert | En rolletildeling kan fjernes fysisk uten at det står hvem som fjernet den. Auditradene for tildelingen og avslutningen består — det er nettopp derfor `object_id` ikke har fremmednøkkel — men slettingen selv etterlater ingen rad. En trigger kan ikke navngi den som sletter, fordi `DELETE` ikke bærer en aktør, og `audit.events.actor_id` er med hensikt `NOT NULL` | Admin-flyten (§48). Der går slettingen gjennom en kontrollert funksjon som kjenner aktøren, og `DATABASE_ARCHITECTURE.md` §36 sitt krav om «særskilt audit» ved fysisk sletting kan innfris |
| Endringer på `provenance.actors` auditeres ikke | Aktørraden er festepunktet for all attribusjon, og visningsnavn, beskrivelse og tilbaketrekking kan endres uten spor. Identiteten er riktignok frosset av `provenance.freeze_actor_identity()`, så det som kan endres er presentasjon og livssyklus, ikke hvem aktøren er | Samme trigger som over, og av samme grunn: tabellen har ingen kolonne som sier hvem som endret raden, så en trigger har ingen aktør å registrere |
| `audit.events.request_or_run_id` har ingen produsent | Auditrader kan ikke grupperes etter forespørselen eller agentkjøringen de hørte til, så en operasjon som består av flere skrivinger framstår som uavhengige hendelser | `provenance.agent_runs`, eller det første admin-RPC-laget som har en forespørselsidentitet å sende med |
| Den synlige `notice` fra migrasjon 005b er ikke maskinelt kontrollert | §74.18 krevde at raden ikke skal utebli i stillhet når brukerkontoen mangler, og migrasjonen gir derfor en `notice`. pgTAP kan ikke observere en `notice`, så den delen av kravet hviler på at et menneske leser utdataene fra `supabase db push`. Statusen `account_missing` som funksjonen returnerer, er den halvdelen som *er* kontrollert (`350_editor_authorization_test.sql` assertion 1), og en mutasjon som degraderer `raise notice` til `raise debug` overlever derfor hele suiten | Den første vaktposten som uansett må lese utdataene fra en migrasjonskjøring — eller en avvikling av behovet, ved at kontoen finnes i alle miljøer og grenen ikke lenger kan tas |
| En basiskolonne kan miste sin `NOT NULL` uten at kolonnekontrakten fanger det | Kolonnenavn og kolonnetyper i `api` er nå uttømmende kontrollert mot katalogen, og nullbarheten er målt på faktiske rader (§74.19). Målingen fanger en kolonne som blir nullbar fordi joinen, uttrykket eller projeksjonen endres — den minimale probe-raden går da NULL. Den fanger ikke at en basiskolonne under viewet stille mister sin `NOT NULL`: probe-fiksturen navngir kolonnen i sin `insert`, så den fortsetter å sette en verdi, og raden ser lik ut. Klienten ville lest en kolonne som `string` mens databasen kan svare `null` | Enten en avledning som knytter hver ikke-nullbare api-kolonne til den basiskolonnen den kommer fra og krever `attnotnull` der — det krever en kolonnekartlegging gjennom viewdefinisjonen, som PostgreSQL ikke eksponerer ferdig — eller den første migrasjonen som gjør en basiskolonne nullbar. Migrasjonen må da endre kontraktsraden i `supabase/tests/340_api_column_contract_test.sql` og radtypen sammen |
| Ingen regel binder et kontrastivt effektmål til en komparator | `knowledge.claim_revisions` tillater fortsatt `magnitude_measure = 'mean_difference'` sammen med `comparator_kind = 'none'`, og en redaktør kan skrive kombinasjonen. Migrasjon 003 tillater nøyaktig det samme paret på `knowledge.evidence_items`, så gjelden gjelder begge tabellene. Presentasjonslaget nekter nå å tolke den på begge (§74.13, §74.15) gjennom én felles avledning, men det er et forsvar i visningen, ikke en invariant: dataene er like ugyldige, og enhver annen leser av `api` ser dem rå | Migrasjonen som legger til betingelsen, eller admin-flyten (§29), som er første sted en redaktør kan skrive kombinasjonen. Regelen må ta stilling til `mean_change`, som er en endring fra behandlingsstart og korrekt har `none` |
| Ingen regel binder en tallfestet effekt til at evidensen er graderbar | En revisjon kan bære `magnitude_value` samtidig som vurderingen er `no_assessable_evidence` — som ifølge migrasjon 004 betyr at det ikke finnes tilstrekkelig grunnlag til å gjøre en vurdering i det hele tatt. Kolonnekommentaren på `magnitude_value` sier selv at en påstand som er mer presis enn evidensen under den, er et brudd på `ANTIDEP_CONSTITUTION.md` §4 og §6, men ingen `CHECK` håndhever det på tvers av de to tabellene. Presentasjonslaget skjuler tallet (§74.13); databasen tillater det | Samme migrasjon som over, eller admin-flyten. Regelen krysser `knowledge.claim_revisions` og `knowledge.evidence_assessments`, så den må enten være en trigger eller en betingelse i publiseringsgaten |
| Modellen kan ikke avgjøre om en effektstørrelses fortegn stemmer med påstandens retning | `direction = 'increase'` med `magnitude_value = -0,4` ser motstridende ut, men er det ikke nødvendigvis: fortegnet hører til skalaen `magnitude_unit` måler på, og modellen registrerer ikke om den skalaens positive retning peker samme vei som temaet påstanden handler om. «Økning i vekttap» med en negativ vektforskjell er konsistent. Kontrollen er derfor bevisst ikke innført — den ville gitt falske utslag på gyldige data | Det første objektet som registrerer polariteten til et utfall i forhold til sitt `ClinicalConcept`. Uten det kan verken UI eller en databaseregel bedømme fortegnet |
| Adressen til et katalogobjekt er avledet av visningsnavnet, ikke lagret | `/drugs/sertralin` og `/topics/vektendring` bygges ved å slå opp sluggen mot de kanoniske navnene i det publiserte settet (`src/lib/slug.ts`). En slug avledet av et visningsnavn er ikke en stabil identitet: endres navnet i katalogen, endres adressen, og en delt lenke slutter å virke (§55). Avledningen er dessuten tapsgivende, så to navn kan kollidere — oppslaget svarer da `ambiguous` framfor å velge, men adressen er ikke lenger entydig | En slug-kolonne i katalogen etter mønster av `provenance.actors.actor_key`, i den migrasjonen som først trenger en permanent lenke — eller det første katalogobjektet som faktisk kan skifte navn. Spørsmålet ble utsatt i §74.5 punkt 2 «til en klient faktisk trenger en menneskelesbar nøkkel i URL-er»; det behovet har nå meldt seg, og utsettelsen er derfor gjeld og ikke lenger et åpent valg. Gjelden er bevisst ikke utvidet: kildesiden adresseres med `source_id` framfor med en slug av tittelen (§74.16 punkt 3), så avledningen gjelder fortsatt to objekttyper og ikke tre |
| Temasiden og kildesiden laster hele det publiserte settet | `api` har verken en tema- eller en kildeprojeksjon. `/topics/:slug` henter alle publiserte påstander og filtrerer i klienten, fordi en slug ikke kan inverteres til en etikett. `/sources/:sourceId` henter kilden fra `published_claim_evidence`, men evidensradene bærer ikke `statement`, så hele det publiserte settet hentes i tillegg og **joines** i klienten for å kunne navngi hva kilden brukes til (§74.16 punkt 1). Det skalerer ikke: en kunnskapsbase med hundrevis av påstander lastes i sin helhet for å vise ett tema eller én kilde, og klienten gjør et arbeid databasen burde gjort. Kildesiden er den andre forekomsten og den første som joiner framfor bare å filtrere | Et `api.published_topics`-view og en projeksjon som gir påstandsformuleringen sammen med evidensraden — eller en slug-kolonne i katalogen (posten over) — slik at oppslaget skjer på serversiden, som på legemiddelsiden. Utløses i praksis av den første utvidelsen av pilotinnholdet (§33) |
| `knowledge.sources.superseded_by_source_id` er ikke i api-kontrakten | Kildestatusen `superseded` betyr per migrasjon 003 at en *bestemt* nyere kilde er registrert: kolonnen er NOT NULL hvis og bare hvis statusen er den, og de to forutsetter hverandre. Pekeren er verken i `api.published_claim_evidence` eller i `src/types/api.ts`, så klienten kan ikke følge den. Kildesiden sier derfor eksplisitt at etterfølgeren er registrert uten å kunne navngis (§74.16 punkt 5); uten den setningen ville etiketten «Erstattet av en nyere kilde» vært en halv sannhet, og fravær av et navn ville sett ut som fravær av en etterfølger. Prisen er at en kliniker ikke kan gå fra en utdatert kilde til den som erstattet den | Migrasjonen som utvider viewet. Den må projisere etterfølgerens *tittel* og ikke bare dens `uuid` — en identitet klienten ikke kan slå opp, er ikke et svar — og ta stilling til hva som vises når etterfølgeren ikke selv er lesbar for klientrollene, siden RLS bare gir tilgang til kilder som ligger under en publisert påstand |
| Katalogstatusen på et virkestoff vises ikke i klinikerflaten | `api.published_drugs.status` bærer `active`, `historical` eller `withdrawn`, men beskriver Antideps forvaltning av virkestoffet og ikke markedsstatus i Norge — det står eksplisitt i kommentaren på `catalog.drug_status`. «Aktiv» ved siden av et virkestoffnavn ville blitt lest som det siste, og §58 holder workflow-status utenfor klinikerflaten, så verdien er utelatt. Prisen er at en kliniker ikke kan se at Antidep ikke lenger vedlikeholder et virkestoff det står publiserte påstander om | Det første virkestoffet med publiserte påstander og status ulik `active`. Da må vokabularet lukkes og få kjøretidskontroll (§74.12 punkt 3), og ordlyden må navngi Antidep som subjekt framfor å se ut som en markedsstatus |
| `api.my_roles` kan ikke skille en utløpt rolletildeling fra ingen tildeling | Viewet viser bare tildelinger som gjelder nå, og det er riktig som autorisasjonssvar: begge tilfellene betyr «ingen rettighet nå». Som *forklaring* er de forskjellige. En reviewer hvis tildeling utløp i går, får se «du har ingen roller» uten at noe sier hvorfor, og kan ikke skille det fra aldri å ha hatt en. Radgrensen i RLS er allerede eierskap og ikke gyldighet, nettopp for at en historikkprojeksjon skal være mulig senere uten å røre policyen | Den første adminskjermen som skal forklare hvorfor en rettighet mangler. Da hører det til et eget `api`-view over kallerens egen rollehistorikk, ikke til en oppmyking av `api.my_roles`: å blande gjeldende og utløpte rettigheter i ett svar er nettopp den sammenblandingen viewet finnes for å hindre |
| `api.my_roles.scope_id` kan ikke slås opp til en etikett | En avgrenset rolletildeling viser hvilken *type* den er avgrenset til (`scope_type`), men ikke hvilket klinisk begrep. `catalog.clinical_concepts` er bare lesbar for klientrollene gjennom publiseringspredikatet i migrasjon 007, så et begrep uten publiserte påstander under seg ville gitt en tom etikett ved siden av en reell avgrensning — altså en avgrensning som så ut som ingen, og det er den farligste retningen å ta feil i. Derfor er etiketten utelatt framfor å være noen ganger tom. Prisen er at en klient foreløpig ikke kan navngi avgrensningen. Samme form som `superseded_by_source_id` over: en identitet klienten ikke kan slå opp, er ikke et svar | Den første avgrensede rolletildelingen i faktisk bruk — i dag er redaktørens tildeling uavgrenset (§74.20). Migrasjonen må ta stilling til hva som vises når begrepet ikke er lesbar for kalleren, og det er en tilgangsbeslutning og ikke en projeksjonsdetalj |
| Kompetansekravet for redaktørrollen er ikke definert, og redaktøren er utpekt av seg selv | `ANTIDEP_CONSTITUTION.md` §12 krever en «navngitt kvalifisert redaktør», men ingenting definerer hva som gjør noen kvalifisert. `CONTENT_GOVERNANCE.md` §11 legger nettopp det til Clinical Lead — «definere hvilke kompetansekrav som gjelder for reviewer-scope» — og Antidep har ingen Clinical Lead. Migrasjon 005a registrerer derfor en redaktør hvis utpeking hviler på prosjekteierrollen, ikke på et kontrollert kompetansekrav, og som er utpekt av seg selv. Samme person er dessuten prosjekteier og eneste faglige godkjenner; §45 og §46 ber om at en slik profesjonell binding registreres, og modellen har ingen kolonne for det noe sted. `workflow.user_roles.grant_reason` er i dag det eneste feltet en kvalifikasjon kan skrives i, og det er fritekst på tildelingen og ikke på personen. §72 sitt krav om at høyrisikoinnhold reviewes av noen som ikke var hovedforfatter, er innfridd bare fordi forfatteren er en KI-aktør | Beslutningen om hvem som er Clinical Lead, og migrasjonen som tildeler `reviewer`-rollen: den må skrive kvalifikasjonen inn i `grant_reason` uansett, og er dermed første sted hullet blir konkret. Skal lukkes før den første publiseringen av klinisk innhold — en godkjenning gitt under et udefinert kompetansekrav er ikke etterprøvbar (§14) |

### 74.8 Gjeld innfridd i korreksjonsmigrasjon 006a

Migrasjonen `20260820120000_evidence_item_content_hash_v2.sql` og oppryddingen rundt den
lukket:

- **Serialiseringen av `content_hash` på evidensfunn.** `concat_ws('|', …)` er byttet med
  den lengdeprefiksede kanoniseringen som allerede var husstandard i migrasjon 004 og 006,
  under nytt prefiks `sha256-v2`, og de eksisterende radene er rehashet.
  `280_content_hash_serialization_test.sql` gjenskaper den gamle kanoniseringen og påstår at
  de to fikstursradene faktisk kolliderte under den, slik at testen viser feilen den retter
  framfor bare å hevde at den er rettet.
- **`KNOWLEDGE_MODEL.md` §8 og §9.** Statuskolonnen er fjernet fra minimumsfeltene på både
  `Claim` og `ClaimRevision`, i favør av den avledede livssyklusen i
  `DATABASE_ARCHITECTURE.md` §15. Bare §8 var registrert som gjeld, men §9 stod i nøyaktig
  samme motstrid, og §15 navngir nettopp `claim_revisions.status`.
- **Tekstgjelden.** Kolonnekommentaren på `catalog.drugs.updated_at` navngir nå
  `catalog.set_row_timestamps()`, som faktisk finnes; testbeskrivelsene i `060` og `110`
  sier hvorfor det fortsatt ikke finnes RLS-policies, framfor å vise til migrasjon 005 som
  om den var ukommet; og enum-antallet i kommentarene til migrasjon 005 og 006 er rettet.
  Det riktige tallet er 35 etter 005 og 37 etter 006 — den registrerte gjelden oppga 37 for
  begge. Tallene er nå formulert som antallet *etter den migrasjonen*, som er en historisk
  kjensgjerning og ikke kan drive fra hverandre igjen.

Tre vaktposter kom til eller ble strammet, alle fordi fraværet av dem var grunnen til at
gjelden fikk ligge:

- **Hver kanonisk kolonne må påvirke fingeravtrykket.** Kanoniseringen tar hele raden som
  argument, men feltlisten er eksplisitt, så en kolonne som legges til senere blir ikke
  hashet av seg selv. Kontrollen er derfor kolonneuttømmende: den nuller ut én kolonne om
  gangen på en ferdig utfylt rad og krever at hashen endrer seg. Unntakslisten i testen er
  kontrakten for hva som bevisst står utenfor — blant annet `created_by_actor_id`, som kom
  til i migrasjon 005 uten å bli tatt inn i definisjonen.
- **En kommentar i de kanoniske schemaene kan ikke navngi en funksjon som ikke finnes.**
  Vakten er selv mutasjonstestet i `280`. En kommentar som skal peke framover på noe som
  ennå ikke finnes, skriver navnet uten parentes.
- **Vaktposten mot avslåtte triggere** i `200_workflow_immutability_test.sql` dekker nå både
  `D` og `R`, og også `api`. En trigger satt til replica fyrer ikke i vanlig drift, og et
  vern som ikke fyrer, er ikke et vern.

### 74.9 Hva migrasjon 007 innførte

`20260820140000_api_published_read_model.sql` åpner den første leseveien fra klientflaten
inn i kunnskapsbasen (§24): `api.published_drugs`, `api.published_claims` og
`api.published_claim_evidence`, de tretten `SELECT`-grantene viewene trenger, og de første
RLS-policyene i Antidep.

**Grensen flyttet seg, og måtte skrives om framfor å strykes.** Fram til nå hadde ingen
klientrolle noe privilegium i de kanoniske schemaene i det hele tatt, og fire testfiler
påstod nettopp det. Et `security_invoker`-view leser med kallerens rettigheter
(`DATABASE_ARCHITECTURE.md` §42), så granten er uunngåelig. Reglene er derfor gjort
snevrere, ikke fjernet: klientrollene kan ha `SELECT` og ingenting annet, hver `SELECT`
skal ha en policy under seg, og ingen policy i de kanoniske schemaene får åpne for annet
enn lesing. Alle tre håndheves uttømmende i `030_conventions_test.sql`.

**Tre lås, testet hver for seg.** Klientrollene mangler `usage` på de kanoniske schemaene
og kan derfor ikke navngi tabellene — granten virker bare gjennom viewene, som ble
navneoppslått da de ble opprettet. RLS slipper bare gjennom rader nådd fra en publisert,
ikke tilbaketrukket påstand. Og bare `SELECT` er gitt, bare til `anon` og `authenticated`.
`290_api_read_model_access_test.sql` publiserer sitt eget innhold inne i en transaksjon som
rulles tilbake, og leser deretter som faktisk klientrolle.

**Viewene bærer publiseringspredikatet i tillegg til RLS, og begge lagene testes alene.**
Det er bevisst dobbeltarbeid. Muteringstestingen viste hvorfor det ikke er nok å teste dem
sammen: da viewet ble endret til å følge høyeste revisjonsnummer framfor
publiseringspekeren, overlevde feilen alle assertions lest som `anon` — RLS skjulte
utkastrevisjonen, så også den feilaktige joinen landet på riktig rad. Bare en lesing som
eier, altså forbi RLS, fanget den. Den assertionen ble lagt til som følge av mutasjonen.
Tjuefire mutasjoner ble kjørt i alt; alle ble fanget etter dette.

**Policyene danner en asyklisk kjede.** `knowledge.claims` er selvstendig, og hver øvrige
policy spør bare om raden er nådd fra en rad som allerede er synlig — et `EXISTS` mot en
RLS-beskyttet tabell filtreres av den tabellens egen policy, så synligheten forplanter seg
gjennom `claims → claim_revisions → claim_evidence_links → evidence_items → sources` uten
at noen policy gjentar publiseringspredikatet. En syklus ville gitt «infinite recursion
detected in policy for relation» ved første spørring, ikke ved migrering.

**Lesbarhet og utgivelse er bevisst ulike predikater.** `catalog.drugs`-policyen slipper
gjennom virkestoff som er nevnt av en publisert revisjon eller et synlig evidensfunn, som
subjekt, komparator eller intervensjon — komparatorens navn må kunne leses for at påstanden
skal gi mening. `api.published_drugs` er snevrere og viser bare virkestoff Antidep faktisk
har publisert påstander *om*. En oppføring der ville ellers antydet en dekning som ikke
finnes.

**To NULL-tilstander holdes fra hverandre i `certainty_level`.** Verdien
`no_assessable_evidence` betyr at grunnlaget er vurdert og ikke lar seg gradere, med
`evidence_gap` utfylt. `NULL` betyr at ingen GRADE-vurdering gjelder for påstandstypen, og
forekommer hvis og bare hvis `knowledge_type` er `deterministic_fact` — publiseringsgaten
G10 krever vurdering for de to andre typene. Ingen av dem betyr lav risiko eller ingen
effekt (`ANTIDEP_CONSTITUTION.md` §6, §17), og skillet står i kolonnekommentaren.

**En tilbaketrukket ekstraksjon merkes framfor å skjules.** Publiseringsgaten G6 behandler en
tilbaketrukket ekstraksjon som en hard blokk ved publisering, men beslutningen er append-only og
kan registreres etterpå — og da flytter den verken publiseringspekeren eller evidenslenkene.
Lesemodellen avleder derfor den gjeldende tilstanden med nøyaktig samme regel som gaten bruker,
og eksponerer den som `extraction_withdrawn` på evidensraden og `withdrawn_evidence_count` på
påstanden. Funnet skjules ikke: da ville påstanden sett bedre underbygget ut enn den er.

Dette er den ene grunnen `workflow.review_decisions` er åpnet, og policyen slipper bare gjennom
`review_type = 'extraction_withdrawal'`. Begge utfallene må være lesbare, ikke bare
`extraction_withdrawn`: skjulte vi `extraction_upheld`, ville avledningen «siste beslutning
gjelder» svart forskjellig avhengig av hvem som spør. `workflow.user_roles` — autorisasjonskilden
— er fortsatt helt stengt.

**Identifikatorer aggregeres, de joines ikke.** `catalog.drug_identifiers` og
`knowledge.source_identifiers` er unike på `(identifier_system, identifier_value)`, ikke på
`(forelder, identifier_system)`. Ett virkestoff kan derfor ha flere ATC-koder, og ingenting
hindrer to DOI-er på samme kilde. Var identifikatorene joinet inn i viewene, ville ett
virkestoff blitt til to rader og ett evidensfunn til to — det siste ville fått ett funn til å
se ut som to uavhengige, altså nøyaktig den oppblåsingen av evidensmengden
`claim_evidence_links_revision_item_key` finnes for å hindre. ATC-kodene aggregeres derfor til
en array, og DOI og PMID hentes med skalare underspørringer som velger deterministisk.

Tre av punktene over kom fra reviewen på PR #18 og var reelle: at en tilbaketrukket ekstraksjon
forble synlig som ordinær evidens, at `source_doi`/`source_pmid` som skalarer var tapsbringende
— den ekte seedede DOI-en var faktisk den en «velg den laveste»-regel ville forkastet — og at
kildeversjonen manglet i drilldownen.

En vaktpost ble strammet underveis: kommentarvakten i `280` joinet `pg_description` mot tre
systemkataloger på `objoid` alene. OID-er er unike innenfor hver katalog, ikke på tvers, så
oppslaget kunne treffe en urelatert rad. Policykommentarene fra 007 er de første
kommentarene i Antidep-schemaene som verken beskriver en relasjon, en funksjon eller en
type, og gjorde svakheten nåbar. Hver gren binder nå sin egen `classoid`, og policyer er
tatt inn i vakten framfor å falle utenfor den.

### 74.10 Hva migrasjon 008 innførte

`20260821090000_audit_events.sql` oppretter `audit.events` (§25), vokabularet
`audit.event_operation`, og de to produsentene som gjør loggen til noe annet enn en tom
tabell.

**Sporvalget.** To spor var byggbare etter migrasjon 007: audit (§25) og det første
kliniker-UI-et (§30, PR I). Audit ble valgt fordi §25 selv begrunner rekkefølgen — audit
skal komme tidlig nok til at resten av admin-MVP-en bygges med sporbarhet fra starten — og
fordi kliniker-UI-et støter på en governance-beslutning med det samme: gjeldsposten om
publiserings- og reviewtidspunkt i `api` har nettopp det viewet som trigger, og krever
først en avgjørelse om hvor mye av reviewhistorikken som skal være offentlig. Audit har
ingen slik forutsetning.

Den avgjørelsen er nå tatt, og gjeldsposten innfridd i migrasjon 007a. Se §74.11.

**Auditloggen er et supplement, ikke et andre hjem for faglig historikk.**
`DATABASE_ARCHITECTURE.md` §35 er eksplisitt på det. Den kliniske historikken ligger
fortsatt i revisjonsmodellen og i `knowledge.publication_events`. Det loggen tilfører er
det tverrgående spørsmålet ingen av dem kan besvare: «hva gjorde denne aktøren, på tvers av
objekter og schemaer?» Derfor er raden ett smalt spor per operasjon, ikke en kopi av
innholdet.

**`object_id` har bevisst ingen fremmednøkkel, og det er migrasjonens ene avvik fra §37.**
Grunnen står i §36: fysisk sletting er reservert for feilopprettede objekter, personvernkrav
og administrativt vedlikehold, og «skal i så fall ha særskilt audit». En fremmednøkkel ville
gjort nettopp den auditen umulig — enten ville slettingen blitt blokkert av auditraden,
eller auditraden ville forsvunnet med objektet den dokumenterer. Auditraden bærer derfor et
snapshot framfor bare en peker, og `320_audit_operations_test.sql` demonstrerer egenskapen
ved faktisk å slette rolletildelingen og lese auditsporet etterpå. `actor_id` er derimot en
ekte fremmednøkkel med `RESTRICT`: der er ikke overlevelse spørsmålet, men at en aktør ikke
skal kunne slettes bort under sin egen historikk.

**Loggen daterer, den ordner ikke.** Et løpenummer ville vært den nærliggende måten å gi en
append-only logg en total orden. Den ville vært falsk, av samme grunn som §74.6 slo fast for
publisering: et løpenummer tildeles ved innsetting, ikke ved commit, så to transaksjoner kan
commite i motsatt rekkefølge av tildelingen, og en rullet tilbake transaksjon etterlater
hull. Rekkefølgespørsmål besvares der de har et svar — hendelseskjeden i
`knowledge.publication_events` og gyldighetsintervallene i `workflow.user_roles`.

**Objektpekeren er avledet, ikke oppgitt.** `object_schema` og `object_table` er genererte
kolonner over `operation`, etter samme mønster som `workflow.user_roles.scope_type` og
`knowledge.publication_events.object_type`. Kunne de oppgis uavhengig, kunne de komme i
utakt, og loggen ville kunnet påstå at en rolletildeling skjedde i `knowledge`. Begge er
`NOT NULL`, slik at en enum-verdi som legges til uten at `CASE`-uttrykket utvides feiler ved
innsetting framfor å gi en tom kolonne.

**Vokabularet er domenehandlinger, ikke DML-verb.** «update på `workflow.user_roles`»
forteller ikke den som gjennomgår loggen om en rettighet ble utvidet eller tilbakekalt, og
det er nettopp det spørsmålet loggen finnes for. Prisen er at hver ny auditert operasjon
krever en migrasjon. Det er en villet pris: en logg som stilltiende utvider seg til nye
operasjoner, utvider seg også til operasjoner ingen har tatt stilling til om skal auditeres.

**Produsentene er triggere, og de er bevisst ikke `SECURITY DEFINER`.** §60 navngir
«append-only audit» som en av de få legitime triggerbrukene, og grunnen er at en trigger
ikke kan glemmes av neste skrivevei — rolletildelinger har i dag ingen kontrollert funksjon
over seg i det hele tatt. At auditskriverne kjører med kallerens rettigheter er en
sikkerhetsbeslutning: en auditskriver som er mer privilegert enn operasjonen den
registrerer, er en vei til å skrive falske auditrader. Konsekvensen er at den som ikke kan
skrive auditraden heller ikke får registrert operasjonen. Det er riktig vei å feile, og det
testes med en rolle som får `INSERT` på `workflow.user_roles` og ingenting i `audit`.

**Loggen har ingen lesevei for klientroller.** §47 lister `audit` blant schemaene den
offentlige klinikerflaten aldri skal ha `SELECT` mot. Tabellen har derfor ingen grant, ingen
policy, ingen `usage` på schemaet, og `310_audit_access_test.sql` kontrollerer i tillegg at
ingen view i `api` leser fra den — grantene fra migrasjon 007 virker gjennom viewene, så et
slikt view ville vært en vei forbi alle tre lagene uten at noen grant på `audit.events` var
nødvendig.

**Vaktposten i `040_catalog_structure_test.sql` ble snevret, ikke fjernet.** Den påstod at
`audit` var tomt; den påstår nå at schemaet inneholder nøyaktig én relasjon. Et objekt som
sniker seg inn i `audit` uten en migrasjon som forklarer det, fanges fortsatt.

**Identiteten på en rolletildeling er tatt inn i frysevernet.** Auditloggen peker på
objektet sitt uten fremmednøkkel, og prisen for den friheten er at primærnøkkelen den peker
på må være stabil. For de andre auditerte objektene er den det allerede — `knowledge.claims`
er låst av `ON UPDATE RESTRICT` fra publiseringshendelsen i det øyeblikket det finnes en
auditrad å låse. `workflow.user_roles` har derimot ingen inngående fremmednøkler i det hele
tatt, og `workflow.freeze_role_grant()` fra migrasjon 005 frøs alt *om* tildelingen, men ikke
raden selv. En `UPDATE` som bare endret `id` passerte derfor både frysetriggeren og
auditrigeren, og etterlot rettigheten på en ny uuid uten en eneste auditrad mens
`role_granted` ble hengende på en uuid som ikke lenger fantes. Funnet kom fra en ekstern
review av PR #20, ble reprodusert mot databasen før det ble rettet, og er rettet i rota:
identiteten står nå først i vernet. Å auditere omnummereringen ville ikke løst noe — de gamle
auditradene ville fortsatt pekt på en rad som ikke finnes.

**Mutasjonstesting, og hva den avdekket.** Trettifire mutasjoner ble kjørt mot de nye
testene og mot tallvakten. Alle blir fanget nå, men tre gjorde det ikke i første omgang, og
alle tre av samme grunn: assertionen var *stille sann* framfor sann.

- En `is_empty` over en join mellom auditraden og publiseringshendelsen passerte også når
  joinen ikke traff i det hele tatt — altså nettopp når `occurred_at` var feil. Den er nå
  formulert som en telling.
- Kontrollen av at en uendret oppdatering ikke gir en auditrad kjørte ikke i det hele tatt
  under mutasjonen den skulle fange, fordi oppdateringen da feilet først. Den er nå pakket i
  `lives_ok`.
- Kontrollen av at en operasjon som ikke kan auditeres heller ikke kan utføres, bestod av to
  feil grunner etter hverandre: først fordi et aktøroppslag i testdataene traff
  `permission denied for schema provenance`, og deretter — etter at oppslaget var fjernet —
  fordi RLS på `workflow.user_roles` avviser skrivingen før triggeren i det hele tatt kjører.
  Testen åpner nå alle tre lagene inne i transaksjonen, slik at auditskrivingen er det
  eneste som gjenstår, og kontrollerer feilmeldingen og ikke bare SQLSTATE: `42501` alene
  skiller ikke «kunne ikke skrive auditraden» fra en hvilken som helst annen rettighetsfeil
  på veien.

Tallvakten ble mutert på ytterpunktene og ikke bare i midten (§74.9-lærdommen fra #19):
første ledd, siste ledd, forkortet påstand, ett ledd for langt, og en omformulering som
fjerner påstanden. Alle fem ble fanget.

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

### 74.11 Hva migrasjon 007a innførte

`20260821143000_api_publication_timestamps.sql` innfrir gjeldsposten «Publiseringstidspunkt
og reviewtidspunkt er ikke eksponert i `api`» fra §74.7. Den oppretter ingen tabeller og
ingen data, og publiserer ingenting.

**Governance-beslutningen først, koden etterpå.** Gjeldsposten hadde «viewet som betjener
kliniker-UI-et» som trigger og en beslutning som forutsetning: hvor mye av reviewhistorikken
skal være offentlig? Avgjørelsen er den smaleste av de mulige — **kun tidsstempler**. Ingen
aktøridentitet, ingen beslutningstype, ingen begrunnelse. Den følger
`PRODUCT_INFORMATION_ARCHITECTURE.md` §58: klinikeren ser «sist faglig vurdert», ikke hvem
som vurderte eller hva som ble sagt underveis. At en påstand er publisert, er publisert
innhold; hvem som godkjente den, og hvorfor, er det ikke.

**Gjeldsposten den lukker.** Før 007a fikk en kliniker «sist faglig vurdert» bare gjennom
`last_assessed_at`, som kommer fra evidensvurderingen. Et `deterministic_fact` har per
konstruksjon ingen evidensvurdering (migrasjon 004 tillater den ikke) og sto derfor helt
uten dato. `last_reviewed_at` finnes for alle tre kunnskapstypene, fordi menneskelig
godkjenning kreves for alle tre (publiseringsgaten G11/G12).

**Utformingen er beslutningens viktigste konsekvens.** Den opplagte implementasjonen — en
RLS-policy som slipper gjennom publiseringsgodkjenningene, og et view som bare projiserer
`decided_at` — ville vært feil. Klientrollene har allerede et *tabellvidt* `SELECT`-grant på
`workflow.review_decisions` fra migrasjon 007, gitt for tilbaketrekkingssporet. En policy som
åpner raden, åpner den for hele granten, og reviewers identitet og begrunnelse ville ligget
ett view unna. **RLS er en radgrense, ikke en kolonnegrense.**

Godkjenningstidspunktet fryses derfor på publiseringshendelsen i stedet, av en
BEFORE INSERT-trigger som speiler gaten G11/G12: den gjeldende beslutningen er den siste, og
bare `approved` teller. Det er samme grep som `approved_evidence_set_digest` i migrasjon 006
— en avledet verdi databasen eier, låst til det den beskrev i øyeblikket. `review_decisions`
er ikke rørt, og godkjenningene er fortsatt utenfor klientflaten.

**Fire invarianter herfra:**

1. **Kolonnegrant er en reell fjerde lås.** Et `security_invoker`-view kan ikke projisere en
   kolonne kalleren mangler grant på, uansett hva viewet inneholder. Et policyuttrykk kan
   derimot fritt referere kolonner kalleren ikke har — privilegiene gjelder spørringen, ikke
   policyen — så radgrensen svekkes ikke av at granten er smal. `knowledge.publication_events`
   er åpnet på fire av fjorten kolonner; `reason` og `published_by_actor_id` er ikke blant dem.

2. **Et kolonnegrant er usynlig for `has_table_privilege()` og
   `information_schema.role_table_grants`.** En vaktpost som bare spør om tabellprivilegiet
   svarer «ingen tilgang» også når kolonner er åpnet. Assertionen i
   `270_publication_access_test.sql` som påsto at publiseringshistorikken var utilgjengelig,
   ble derfor *stille sann* i det 007a ga granten, uten å feile. Den kontrollerer nå
   `role_column_grants` i tillegg, uttømmende. Dette er samme feilmodus som §74.10 beskrev
   for `is_empty` over en join: en assertion kan bestå uten å nå det den påstår å måle.

3. **`published_at` og `last_reviewed_at` er to forskjellige ting, og begge er forskjellige
   fra `revision_created_at` og `last_assessed_at`.** Fire tidsbegreper, holdt adskilt som
   `DATABASE_ARCHITECTURE.md` §7.3 krever. NULL i noen av dem betyr ukjent, aldri «nylig
   vurdert» og aldri «ikke vurdert».

4. **Innenfor én transaksjon kan hendelser ikke skilles på tid, og en uuid er ingen
   rekkefølge.** `published_at` og `created_at` er begge `now()`, altså transaksjonens
   starttidspunkt (§74.6). Skjer publisering, avpublisering, ny godkjenning og
   republisering i samme transaksjon, er de to publiseringshendelsene identiske på tid,
   men bærer ulik `approval_decided_at`. En `order by ... id desc` faller da tilbake på en
   tilfeldig uuid og plukket den gamle godkjenningen i 94 av 200 forsøk. Feilen ble funnet
   av den eksterne reviewen på PR #21, etter at CI hadde vært grønn — den ville vært en
   flakete CI-feil, ikke en stabil. Lesemodellen aggregerer derfor med `max()`, som er
   korrekt fordi begge kolonnene er monotont ikke-avtagende: `published_at` kan ikke gå
   bakover, og `approval_decided_at` velges blant append-only beslutninger, så maksimum
   kan bare stige. **Forgjengerkjeden kunne besvart det eksakt, men ikke bak RLS:** et
   «finnes ingen etterfølger»-predikat evalueres over de radene kalleren *ser*, og en
   skjult etterfølger ville fått en tidligere hendelse til å framstå som kjedens hale.
   Den som senere trenger «siste hendelse» under RLS må regne med det.

5. **Verdien er frosset, og det er et valg med utløpsdato.** En senere reviewbeslutning på
   samme revisjon flytter den ikke. I dag er det riktig, fordi det ikke finnes noen
   reviewsyklus å flytte den med. Migrasjonen som innfører `review_due_at` må ta stilling til
   om en fornyet godkjenning skal oppdatere datoen; posten står i §74.7.

**Sporet som nå er åpent.** Med gjeldsposten innfridd har det første kliniker-UI-et (§30,
PR I) ingen gjenstående forutsetning i databasen. Viewene svarer fortsatt `[]` til noe er
publisert, så UI-et må bygges mot en tom projeksjon og behandle den som en førsteklasses
tilstand: «ingen data», «ingen vurderbar evidens» og «lav risiko» skal se forskjellige ut
(`ANTIDEP_CONSTITUTION.md` §6, §17).

### 74.12 Hva lesemodellklienten innførte

`feat: add published read model client` er den første appkoden siden bootstrap (PR A) og
første del av PR I (§30, §68). Den oppretter ingen migrasjon, ingen komponenter og ingen
ruting, og leser ingenting i seg selv: viewene svarer fortsatt `[]`.

Den består av radtypene for de tre api-viewene (`src/types/api.ts`), `Database`-typen
supabase-js parametriseres med (`src/types/database.ts`), klienten (`src/lib/supabase.ts`),
de tre lesefunksjonene (`src/lib/published-read-model.ts`) og avledningen av sikkerhetsgrad
(`src/lib/claim-certainty.ts`).

**Fem beslutninger, i den rekkefølgen de betyr noe klinisk:**

1. **Tomt er en egen tilstand, ikke en tom liste.** Lesefunksjonene returnerer en lukket
   union `ok | empty | error` der `ok` per konstruksjon aldri har null rader. En kaller kan
   ikke rendre et tomt sett som en liste uten først å ha tatt stilling til `empty`, og en
   feil kan ikke forsvinne i den samme tomme listen. Det er den strukturelle formen av
   kravet om at «ingen data» aldri skal se ut som «lav risiko» (`ANTIDEP_CONSTITUTION.md`
   §6, §17), og den gjelder fra første komponent i neste PR.

2. **De to NULL-lignende sikkerhetstilstandene er skilt i én avledning.**
   `describeClaimCertainty()` gir `graded`, `no_assessable_evidence`,
   `not_applicable_deterministic_fact` eller `unknown`. En klient som forgrener direkte på
   `certainty_level` gjør de to første usynlige for hverandre ved første `if (!level)`.
   `unknown` dekker fire kontraktsbrudd — en ukjent kunnskapstype, en evidenssyntese uten
   vurdering, en verdi utenfor vokabularet, og et deterministisk faktum som likevel bærer en
   gradering — og ingen av de fire tilstandene kan renderes som en lav gradering.
   Kunnskapstypen kontrolleres først og på alle veier: den avgjør hvilken sikkerhetstilstand
   som er gyldig, så en fjerde epistemisk kategori med en tilsynelatende gyldig gradering
   skal ikke passere som en ordinær GRADE-vurdert påstand. Den første utformingen kontrollerte
   den bare på NULL-veien; det ble funnet av den eksterne reviewen på PR #22 og er rettet der.

3. **Lukket vokabular bare der klienten forgrener, og med kjøretidskontroll.** Enum-verdiene
   er tekst i kontrakten (§74.5 punkt 1), så en TypeScript-union er en påstand om databasen
   som ingenting håndhever. Linjen er trukket etter klinisk konsekvens: kunnskapstype,
   sikkerhetsgrad, relasjonstype, `*_availability` og kildestatus er lukkede unioner; resten
   er dokumentert `string`, og promoteres av den PR-en som faktisk forgrener på dem. Gjelden
   som følger, står i §74.7.

4. **Evidensen sorteres bevisst nøytralt.** En rekkefølge etter `relationship_type` ville
   satt støttende funn først og gjort presentasjonsrekkefølgen til en vekting av evidensen.
   Motstridende funn skal stå side om side med støttende (§9), så api-laget sorterer bare
   på lenkens id — stabilt mellom kall, uten mening — og overlater rekkefølgen i
   klinikerflaten til visningen, der den er en designbeslutning.

5. **Nøkkelvakten er positiv, ikke en svarteliste.** `assertPublishableKey()` avviser alt
   annet enn `anon` og `authenticated`, ikke bare `service_role`, slik at en framtidig
   privilegert rolle ikke slipper gjennom fordi den ikke var navngitt. Vakten er et
   supplement til at hemmeligheter aldri legges i repoet (`DATABASE_ARCHITECTURE.md` §49),
   ikke en lås; den fanger den dagen noen kopierer feil verdi inn i `.env.local`. Klienten
   er dessuten bundet til `api`, slik at et forsøk på å navngi en kanonisk tabell blir en
   typefeil framfor et 404 i produksjon.

**En stille feilmodus ble truffet under arbeidet, og fanges nå.** supabase-js forkaster en
`Database`-type som ikke oppfyller formen sin — uten feilmelding — og gir da `never` som
radtype. `never` er tilordnbart til alt, så typecheck og tester fortsetter å passere mens
spørringene ikke lenger er typet. To skrivemåter utløser det: en Row deklarert som
`interface` (uten implisitt indekssignatur) og tomme oppslag skrevet som
`Record<string, never>` (som slår ut radtypen til hvert view gjennom snittet
`Tables & Views`). Begge er prøvd mot kompilatoren, ikke antatt, og
`src/lib/published-read-model.test.ts` bærer en kompileringsvakt som gir typefeil hvis
radtypen kollapser igjen. Vakten håndheves av `npm run typecheck`, ikke av vitest, som
fjerner typene — det står i filen, slik at ingen tror testkjøringen dekker den. Dette er
samme kategori som den stille sanne assertionen i §74.11 punkt 2: en kontroll kan slutte å
måle uten å feile.

**Hva som gjenstår av PR I.** Ruting, legemiddelside, claim-komponent, «Hvorfor sier Antidep
dette?» og kildedetalj (§30). Avhengighetsvalgene for ruting og server-state (§7) er ikke
tatt, fordi denne delen ikke trenger dem. Klinikerflaten må bygges mot den tomme
projeksjonen og behandle den som en førsteklasses tilstand — §74.11 sist.

### 74.13 Hva claim-kortet innførte

`feat: add claim card and certainty display` er andre del av PR I (§30, §68) og den første
klinikerflaten. Den oppretter ingen migrasjon, ingen ruting og ingen datahenting, og legger
ingen ny avhengighet til: avhengighetsvalgene i §7 for ruting og server-state er fortsatt
ikke tatt, fordi rene presentasjonskomponenter ikke trenger dem.

Den består av presentasjonsenheten for én publisert påstand
(`src/components/ClaimCard.tsx`), sikkerhetsvisningen (`src/components/ClaimCertainty.tsx`),
avledningen av påstandens strukturerte betydning (`src/lib/claim-effect.ts`) og norsk
gjengivelse av intervaller, tidsstempler og tall (`src/lib/norwegian-format.ts`). Fire
vokabularer er lukket i `src/types/api.ts`, og `tests/api-vocabularies.test.ts` kontrollerer
alle de lukkede vokabularene mot migrasjonene.

**Fem beslutninger, i den rekkefølgen de betyr noe klinisk:**

1. **«Ikke aktuelt» og «mangler» er forskjellige ting, og kunnskapstypen avgjør hvilken.** Et
   deterministisk faktum — et handelsnavn, en legemiddelform — har ingen retning og ingen
   effektstørrelse. Å skrive «størrelsen er ikke tallfestet, og det betyr ikke at effekten er
   null» på «finnes som tablett 50 mg» er en kategorifeil som låner faktumet en epistemisk
   ramme det ikke har (`ANTIDEP_CONSTITUTION.md` §5). De to aksene utelates derfor for et
   deterministisk faktum — men bare når de faktisk er tomme; bærer faktumet likevel en
   retning eller en størrelse, er det noe å vise. Det er samme skille som
   `not_applicable_deterministic_fact` gjør på sikkerhetsaksen. For de to andre
   kunnskapstypene gjelder det motsatte: der er en manglende tallfesting informasjon, og
   stillhet ville vært §17-feilen. Dette ble funnet ved å se på gjengivelsen i nettleseren,
   ikke av en test.

2. **Effektmål og komparator er én påstand, og et uforenlig par tolkes ikke.**
   `comparator_kind = 'none'` betyr ikke «komparator mangler»; migrasjon 004 sier at det betyr
   *en endring fra behandlingsstart*. Det er en påstand om hva tallet måler, og den må stemme
   med effektmålet: `mean_change` måler innenfor én arm, mens `mean_difference`, SMD, RR og OR
   måler mellom to. «Gjennomsnittsforskjell 1,7 kg» med `none` har ingen gruppe å være
   forskjellig fra, og å presentere den som «endring fra behandlingsstart» ville gitt et
   kontraktsbrudd en plausibel, men gal klinisk betydning. Størrelsen avledes derfor med
   komparatoren i hånden, og et uforenlig par kan ikke bli `quantified`: tallet er
   utilgjengelig for visningen framfor å måtte huskes skjult av den. Kontrastiv er
   komplementet til innenfor-arm, ikke en egen liste, så et sjette effektmål krever komparator
   til noen tar stilling til det. Tre tilstander holdes fra hverandre, fordi de krever hver sin
   retting: en gyldig `none` der målet faktisk beskriver endring fra baseline, en komparator
   som selv er brutt, og et par der hvert felt er gyldig men kombinasjonen ikke er det. Hvert
   kontraktsbrudd på størrelsen gir sin egen forklaring framfor et tall.

3. **Ingen skala, og ingen fargeramme over graderingene.** §17 navngir «en tom skala» som
   nettopp det mønsteret som får manglende data til å se ut som lav risiko: en firetrinns
   indikator ville tvunget «ingen vurderbar evidens» og «ukjent sikkerhet» inn på samme akse
   som «svært lav», som et trinn under framfor som noe annet. Teksten bærer betydningen (§20),
   og en visuell skala hører først hjemme når hvert trinn har en definert semantikk å vise
   (§18). «Traffic-light medicine» er dessuten et eksplisitt antimønster (§65), og høy
   sikkerhet i kunnskapsgrunnlaget er ikke et grønt lys — den sier ingenting om hvor gunstig
   funnet er. De ikke-graderte tilstandene skiller seg strukturelt: de bærer ingen
   `data-certainty-level`, og stilsettet henger den graderte drakten på nettopp det
   attributtet, så en ny ikke-gradert tilstand kan ikke arve utseendet til en gradering.

4. **Veien til evidensen er påkrevd, og den er en lenke.** `evidenceHref` er ikke valgfri:
   produktinvariant 9 sier at brukeren alltid skal finne «Hvorfor sier Antidep dette?», og et
   valgfritt felt ville gjort det til noe en kaller kan glemme. At det er en lenke og ikke en
   handling, gjør evidensvisningen delbar og bokmerkbar (§55). URL-en eies av rutingen, ikke
   av kortet, så evidensvisningen kan bygges uten å endre kortet.

5. **Fire vokabularer lukket, alle med kjøretidskontroll.** `claim_direction`,
   `comparator_kind`, `effect_measure` og `estimate_unit` forgrenes det nå på, og regelen fra
   §74.12 punkt 3 er at den PR-en som forgrener, legger til kontrollen samtidig. Påstandens
   `direction` er bevisst ikke evidensfunnets `reported_direction`: det vokabularet har den
   fjerde verdien `not_stated`, og å slå dem sammen ville latt «kilden oppgir ingen retning»
   og «Antidep konkluderer med ingen klar forskjell» bytte plass. `relationship_type`,
   `*_availability` og `source_status` står fortsatt uten kontroll, fordi ingenting forgrener
   på dem ennå.

**Gjeld: én halvpart innfridd, én post lagt til.** `tests/api-vocabularies.test.ts` leser de
versjonerte migrasjonene og krever at hver lukket union i `src/types/api.ts` er nøyaktig sin
enum, og i tillegg at skillet mellom dimensjonale og dimensjonsløse effektmål er det samme som
`claim_revisions_magnitude_unit_check`. Uthentingen leser ikke bare `create type`: en senere
`alter type … add value` eller `rename value` regnes med, og en endringsform testen ikke kan
tolke stopper den framfor å bli ignorert. Uten det ville vaktposten sluttet å måle første gang
et enum ble utvidet — den ville passert mens databasen kunne returnere en verdi unionen ikke
kjenner. Ingen migrasjon bruker `alter type` i dag; kodeveien er derfor prøvd mot syntetisk
SQL, slik at den virker den dagen den trengs. Ingen database trengs; framgangsmåten er den samme som
i `tests/data-api-exposure.test.ts`. Kolonnenavn, nullbarhet og kolonnetyper står fortsatt
ukontrollert, og gjeldsposten i §74.7 er strammet inn til det. Den nye posten er databasens
manglende binding mellom effektmål og komparator.

**Serialiseringen av `interval` er kontrollert, ikke antatt.** PostgREST gir PostgreSQLs egen
tekstform, og Supabase kjører med standardinnstillingen `IntervalStyle = postgres`. Formene er
lest ut av en PostgreSQL 16-instans: `interval '8 weeks'` blir `56 days`, `'3 months'` blir
`3 mons`, `'18 months'` blir `1 year 6 mons`, og `to_json()` gir samme streng som `::text`.
Uker overlever altså ikke, og de regnes ikke tilbake: enheten databasen faktisk bærer er den
som vises. Alt som ikke passer formen — ISO 8601 fra en annen `IntervalStyle`, eller et
negativt intervall — gjengis uendret framfor å tolkes på slump.

**Tre kombinasjonsfeil funnet i sluttgjennomgangen.** Alle tre er samme type: hvert felt er
gyldig for seg, mens paret betyr noe annet enn delene. De ble ikke funnet av mutasjonstesting,
fordi mutasjonene traff koden og ikke antakelsen om at feltene kunne vurderes hver for seg.

1. **`mean_difference` med `comparator_kind = 'none'`.** Kortet skrev
   «Gjennomsnittsforskjell 1,7 kg. Ingen komparator: endring fra behandlingsstart.»
   Den siste setningen er en gyldig lesning av `mean_change + none`, men en helt annen
   påstand for `mean_difference + none` — presentasjonslaget reparerte altså et
   kontraktsbrudd ved å gi det en plausibel, men gal klinisk betydning. Rettet ved at
   størrelsen avledes med komparatoren i hånden (punkt 2 over), og at baselinelesningen
   bare skrives ut når målet lisensierer den.

2. **Tallfestet effekt sammen med `no_assessable_evidence`.** Migrasjon 004 sier at den
   tilstanden betyr at det ikke finnes tilstrekkelig grunnlag til å gjøre en vurdering i det
   hele tatt, og kolonnekommentaren på `magnitude_value` sier selv at en påstand som er mer
   presis enn evidensen under den, er et brudd på `ANTIDEP_CONSTITUTION.md` §4 og §6. Kortet
   viste likevel punktestimatet ved siden av «Ingen vurderbar evidens». Tallet skjules nå, med
   begrunnelsen synlig. Avgrenset til den vurderte tilstanden: `unknown` dekker blant annet en
   kunnskapstype Antidep ikke kjenner, og da er det sikkerhetsvisningen som sier fra.

3. **Deterministisk faktum som likevel bærer retning eller størrelse.** §74.13 punkt 1 utelot
   de to aksene når de er tomme, men viste dem umerket når de ikke er det — og da så en verdi
   som ikke gjelder for kunnskapstypen nøyaktig ut som en som gjør det (§5). Verdien står
   fortsatt, siden det å skjule den ville skjult bruddet, men den er nå merket. Parallellen på
   sikkerhetsaksen er `assessment_on_deterministic_fact`.

**En kontroll ble vurdert og bevisst ikke innført.** Fortegnet på en effektstørrelse kan se ut
til å motsi påstandens retning — `increase` med −0,4 — men modellen registrerer ikke om den
positive retningen på skalaen `magnitude_unit` måler i, peker samme vei som temaet påstanden
handler om. «Økning i vekttap» med en negativ vektforskjell er konsistent, så en fortegnsregel
ville gitt falske utslag på gyldige data. Registrert som gjeld i §74.7 framfor implementert.

**Forsvaret i visningen lukker ikke databaseinvarianten.** Databasen tillater fortsatt begge
kombinasjonene, en redaktør kan skrive dem, og enhver annen leser av `api` ser dem rå. De to
lagene er registrert hver for seg i §74.7.

**Hva som ble verifisert.** 46 mutasjoner ble innført én om gangen og alle fanget: 23 mot
kortet, sikkerhetsvisningen, avledningen og formateringen, ti mot vaktposten på vokabularene,
og tretten mot kombinasjonsreglene over. Én mutasjon overlevde først, og var et funn i seg
selv: `baselineReadingIsLicensed()` kalte `isWithinArmMeasure()` i en gren som avledningen
allerede hadde gjort uoppnåelig. En uprøvbar vakt ser ut som et vern uten å være det, så
grenen ble fjernet framfor at mutasjonen ble notert som et unntak. Typene ble sondert framfor antatt — en tilordning av en verdi utenfor hvert nytt
vokabular gir fire typefeil, og kollapsvakten fra §74.12 slår fortsatt ut når en radtype
skrives om til `interface`. Kortet ble kjørt i Chromium på 1280 og på en ekte 390 px
mobilviewport gjennom devtools-protokollen, fordi `--window-size` klemmes til minst 500 px og
en skjermdump alene ville sett ut som avkuttet tekst uten å være det: ingen horisontal
overflyt, og ingen konsollmeldinger utover en manglende favicon på den midlertidige
forhåndsvisningssiden. En vitest-kontroll fanger dessuten `console.error` fra React på flere
varianter av kortet.

**Hva som gjenstår av PR I.** Ruting, legemiddelsidene `/drugs/sertralin` og
`/drugs/mirtazapin`, temasiden for vekt, evidensvisningen bak «Hvorfor sier Antidep dette?» og
kildedetaljen (§30). Evidensvisningen er en egen PR (§51). Avhengighetsvalgene for ruting og
server-state (§7) hører til den PR-en som først trenger dem. Viewene svarer fortsatt `[]`, så
den første siden må behandle den tomme projeksjonen som en førsteklasses tilstand — `ok` i
lesemodellen har per konstruksjon aldri null rader, nettopp for å tvinge det fram (§74.12
punkt 1).

### 74.14 Hva rutingen og de første sidene innførte

`feat: add routing and first clinician pages` er tredje del av PR I (§30, §68) og den første
navigerbare klinikerflaten. Den oppretter ingen migrasjon. Den består av adressene
(`src/app/routes.ts`), sluggavledningen (`src/lib/slug.ts`), klienttilstanden
(`src/app/antidep-client.ts`), hentingen (`src/app/use-read-model.ts`), fraværs- og
feiltilstandene (`src/components/KnowledgeNotice.tsx`), grupperingen
(`src/app/ClaimGroups.tsx`) og fem sider: forsiden, legemiddelsiden, temasiden, den ennå
ubygde evidensvisningen og en side for ukjent adresse.

**Avhengighetsvalgene i §7 er tatt, og det ene av dem er å la være.**

1. **Ruting: `react-router`, i deklarativ modus.** Én transitiv avhengighet (`cookie-es`), og
   den etablerte standarden. Alternativet — en håndskrevet ruter på History API-et — ville
   spart avhengigheten og kostet nettopp de detaljene en ruter finnes for: at ctrl-, cmd- og
   midtklikk fortsatt åpner i ny fane, at `popstate` og nettleserens fram/tilbake virker, og
   at eksterne lenker ikke fanges. Det er en klasse feil som ser ut som ingenting til den
   dagen den ikke gjør det. Data-modusen (`createBrowserRouter`, loaders) er bevisst ikke tatt
   i bruk: den ville innført et server-state-mønster gjennom bakdøren. Avhengigheten hevet
   dessuten Node-gulvet, og avdekket at `engines.node` allerede var usann: `jsdom` krever
   `^22.22.2`, mens roten erklærte `>=22`, og `npm ci` nøyde seg med en advarsel. Gulvet er
   rettet til det laveste treet faktisk tilfredsstiller, og `.npmrc` gjør avviket til en feil
   framfor en advarsel — en erklæring ingenting håndhever, er den formen for påstand §74.8
   handler om.
2. **Server-state: ingen avhengighet.** §7 ber om at kategorien utsettes til behovet er
   demonstrert. Flaten har tre lesespørringer, ingen mutasjoner, ingen invalidering og ingen
   bakgrunnsoppfriskning. `useReadModel()` er en effekt og en tilstand, og legger nøyaktig én
   ting til lesemodellens tre: at svaret ikke er kommet ennå.
3. **Dypelenker krever en omskrivingsregel på verten.** `vercel.json` sender alle stier til
   `index.html`. Uten den ville `/drugs/sertralin` gitt 404 ved direkte åpning og ved
   oppdatering — altså ville dypelenken virket overalt unntatt der §55 faktisk krever den.
   Regelen ligger i repoet framfor i prosjektinnstillingene hos Vercel, i tråd med §54.

**Fem beslutninger, i den rekkefølgen de betyr noe klinisk:**

1. **Fem tomme skjermer, fem forskjellige utsagn.** En side som leser publisert kunnskap kan
   ende uten innhold av fem grunner, og de betyr ikke det samme: spørringen laster; Antidep
   har ikke publisert noe i det hele tatt; adressen traff ikke noe publisert; adressen er
   tvetydig; spørringen feilet. Alle fem ville vært samme blanke flate, og en blank flate
   leses som «ingenting å bekymre seg for». Hver av dem har derfor sin egen ordlyd, og de
   tre fraværstilstandene bærer den samme setningen om at fravær i Antidep ikke er
   dokumentasjon på fravær av effekt, bivirkning eller risiko (`ANTIDEP_CONSTITUTION.md` §17,
   `PRODUCT_INFORMATION_ARCHITECTURE.md` §32, §65 «No-data-as-zero»). Setningen står ett sted,
   i `KnowledgeNotice.tsx`, fordi den skrevet på nytt per side ville drevet fra hverandre.
   «Laster» er skilt fra «tomt» strukturelt og ikke bare i tekst: `useReadModel()` starter i
   `loading`, og et svar kan ikke vises som en tom liste (§74.12 punkt 1).

2. **En tom projeksjon sier ingenting om virkestoffet i adressen.** `/drugs/sertralin` mot et
   tomt `api.published_drugs` betyr at Antidep ikke har publisert noe — ikke at virkestoffet
   er ukjent, og slett ikke at det er uten risiko. De to utsagnene er skilt: den tomme
   projeksjonen sier «om noe virkestoff», og et treff som mangler sier eksplisitt at det er et
   utsagn om Antideps innhold og ikke om virkestoffet. Overskriften er dessuten aldri sluggen
   fra URL-en; å sette den ville gjort en adresse leseren skrev, til noe Antidep ser ut til å
   hevde.

3. **Adressen er avledet av navnet, og tvetydighet er en tilstand.** `api` eksponerer ingen
   slug (§74.5 punkt 2), så `/drugs/sertralin` finnes ved å avlede sluggen av hvert kanonisk
   navn i det publiserte settet. Avledningen er tapsgivende — norske bokstaver skrives om, så
   to navn kan kollidere — og et oppslag som velger det første treffer riktig nesten alltid og
   viser feil virkestoff resten av tiden. Det siste er en feil som ser ut som et gyldig svar,
   så oppslaget svarer `ambiguous` og siden sier fra. Påstandens identitet er ikke berørt:
   evidensvisningen adresseres med `claim_id`, som overlever en ny publisering.

4. **Rekkefølge er ikke rangering, og to påstander ved siden av hverandre er ikke en
   sammenligning.** «UI-derived recommendations» er et eksplisitt antimønster (§65), og
   invariant 14 sier at visuell orden ikke skal bli en anbefaling ved en tilfeldighet. En
   temaside med to virkestoff under samme overskrift *er* en ordnet liste, og leseren fyller
   inn en mening hvis vi ikke oppgir den. Rekkefølgen er derfor alfabetisk, sorteringen gjøres
   i visningen framfor å arves fra spørringen — `order by` i PostgreSQL bruker databasens
   kollasjon, som ikke er norsk, så en visning som *sier* at rekkefølgen er alfabetisk må selv
   gjøre den alfabetisk — og begge deler skrives ut. En liste bærer dessuten to påstander på én
   gang: rekkefølgen, og at dette er settet. Den andre er den farligste her, fordi to virkestoff
   under et tema leses som at de øvrige ikke har temaet, så begge listene sier hva de er: det
   Antidep har publisert, ikke et fullstendig sett. Temasiden sier i tillegg at påstandene
   ikke er en sammenligning: de kan ha ulik populasjon, ulik komparator og ulik tidsramme, og
   sammenligning er en egen visning med egen semantikk (§21-§24, §29). Kollasjonen er norsk og
   ikke tegnverdi, av samme grunn: en liste en norsk leser leser som usortert, ser ut som en
   liste sortert etter noe annet — for eksempel etter viktighet.

5. **Dokumentstrukturen er en klinisk egenskap, ikke pynt.** Kortet rendret `h3` da det stod
   alene; en side har nå `h2` og gruppene `h3`, så kortet fikk `headingLevel` og ligger på
   `h4` under gruppen sin. Et hopp i nivå gir feil disposisjon for en skjermleser (§50, §53).
   Fokus flyttes til hovedområdet ved hver navigering, men ikke ved første render, fordi en
   klientside-navigering ellers etterlater en skjermleser i forrige side. Hopplenken er
   første fokuserbare element (§49, §52), og dokumenttittelen settes per adresse, slik at et
   bokmerke og en delt lenke har et navn (§55, §57).

**Det som ikke vises, og hvorfor.** Handelsnavn, klasse, norske legemiddelformer og styrker
(§10) finnes ikke i datamodellen ennå og kommer med DrugProduct-fundamentet (§26) og slice 4
(§32); de er utelatt framfor gjettet på. Katalogstatusen på virkestoffet er utelatt av en
annen grunn: kolonnen beskriver Antideps forvaltning og ikke markedsstatus i Norge, og
«aktiv» ved siden av et virkestoffnavn ville blitt lest som det siste. Begge er registrert i
§74.7, den siste som gjeld.

**Evidensadressen finnes, men visningen gjør det ikke.** `/claims/:claimId/evidence` er
registrert som rute og svarer med en side som sier at visningen ikke er bygget. Uten ruten
ville lenken fra hvert kort gitt «siden finnes ikke», som ikke er sant — adressen er riktig,
innholdet mangler. **Produktinvariant 9 er dermed ikke innfridd ennå.** Det er ikke gjeld,
men gjenstående arbeid: evidensvisningen er den neste PR-en (§51).

**Gjeld: tre poster lagt til.** Adressen til et katalogobjekt er avledet av visningsnavnet og
ikke lagret; temasiden laster hele det publiserte settet fordi `api` ikke har noen
temaprojeksjon; katalogstatusen vises ikke. Alle tre står i §74.7 med sin egen trigger. Den
første er den samme avveiningen §74.5 punkt 2 utsatte — utsettelsen er nå gjeld, fordi
behovet den ventet på har meldt seg.

**Vaktposten på PR-tabellen.** §74.2 sin statuskolonne har vært foreldet ved fire
sesjonsstarter på rad. `scripts/verify-counts.sh` kontrollerer nå at hver rad unntatt den
nyeste står som `merget`, og at hver `merget`-rad har sin commit i git-historikken. Den
nyeste raden er unntatt fordi en PR ikke kan kjenne sin egen mergestatus; kontrollen slår
derfor ut i det øyeblikket noen legger til raden under en foreldet rad — som er nøyaktig når
forsømmelsen skjer. CI-jobben henter hele historikken for at den andre halvdelen skal kunne
måle; en avkortet historikk gir feilmelding framfor stillhet.

**Hva som ble verifisert.** `npm run lint`, `npm run format:check`, `npm run typecheck`,
`npm run test` og `npm run build` er kjørt og passerer, sammen med
`./scripts/verify-counts.sh`. Vitest-suiten er utvidet med sider, ruting, sluggavledning,
hentetilstander og gruppering. Mutasjonstesting er kjørt etter mønsteret i §74.13: hver ny
regel er fjernet én om gangen, og testen som påstår å teste den, er kontrollert å feile.
Flaten er kjørt i Chromium på 1280 px og på en ekte 390 px mobilviewport gjennom
devtools-protokollen — ikke gjennom `--window-size`, som klemmes til minst 500 px — uten
horisontal overflyt og uten konsollmeldinger utover en manglende favicon.

**Hva som gjenstår av PR I.** Evidensvisningen bak «Hvorfor sier Antidep dette?» og
kildedetaljen (§30). Evidensvisningen er en egen PR (§51), og kildesiden er en annen visning
enn evidensvisningen (§42). Viewene svarer fortsatt `[]`, så begge må bygges mot den tomme
projeksjonen på samme måte som sidene her. Det som gjenstår for at slice 2 skal være ferdig,
er dermed nøyaktig de to punktene i definition of done som handler om evidens og kilde.

### 74.15 Hva evidensvisningen innførte

`feat: add the claim evidence view` er fjerde del av PR I (§30, §68) og svaret bak «Hvorfor
sier Antidep dette?» (`PRODUCT_INFORMATION_ARCHITECTURE.md` §15). Den oppretter ingen
migrasjon og legger ingen ny avhengighet til. Den består av avledningen av ett evidensfunn
(`src/lib/evidence-item.ts`), presentasjonen av det (`src/components/EvidenceFinding.tsx`),
selve siden (`src/app/pages/ClaimEvidencePage.tsx`, som til nå har vært en plassholder), en
ny lesefunksjon (`fetchPublishedClaimById()`) og de delte vokabularetikettene
(`src/components/vocabulary-labels.ts`).

**`fetchPublishedClaimEvidence()` ble skrevet og testet i #22 og har aldri vært kalt. Nå
kalles den.** Ruten `/claims/:claimId/evidence` og `claimEvidencePath()` kom i #24; adressen
er uendret.

**Sju beslutninger, i den rekkefølgen de betyr noe klinisk:**

1. **Påstanden står øverst, og det er det samme kortet.** §41 begynner med påstanden, og uten
   den er et evidensgrunnlag ikke etterprøvbart: leseren har ingenting å prøve funnene mot
   (`ANTIDEP_CONSTITUTION.md` §4). Evidensradene bærer verken `statement`, `certainty_level`,
   `uncertainty_summary` eller `topic_label`, så påstanden hentes med `fetchPublishedClaimById()`
   — filtrert på `claim_id`, som overlever en ny publisering (§7). `ClaimCard` gjenbrukes
   framfor å få en egen utgave her: kortet bærer regler om scope, størrelse, komparator og
   sikkerhet som en parallell presentasjon ville måttet gjenta og deretter drive fra
   (§65 «Duplicated truth»). Kortets `evidenceHref` er påkrevd og forblir det; på denne
   siden *er* veien videre seksjonen lenger nede, så verdien er et anker og ikke en rute. Å
   gjøre lenken valgfri ville latt et kort et annet sted miste den ved en forglemmelse.

2. **Rekkefølgen er ikke en vekting, og antallet er ikke sikkerhet.** Evidensen kommer sortert
   på `claim_evidence_link_id` — stabilt mellom kall, uten mening (§74.12 punkt 4) — og
   visningen sorterer ikke om. Den grupperer heller ikke støttende og motstridende i egne
   bolker slik §41 foreslår, av to grunner: en rekkefølge etter `relationship_type` ville satt
   støttende funn først og gjort presentasjonsrekkefølgen til en vekting av evidensen
   (`ANTIDEP_CONSTITUTION.md` §9, §20), og en egen bolk for motstridende evidens som står tom,
   leses som «det finnes ingen motstridende evidens» — en påstand om forskningen, ikke om
   Antideps innhold. Hvert funn bærer i stedet relasjonen sin som tekst, øverst og i sitt eget
   tilgjengelige navn, slik at leseren ser den uten å utlede den av plasseringen. Antallet funn
   skrives ikke ut som et tall å veie: «tre støtter, ett motsier» er stemmetelling, og GRADE
   avviser den eksplisitt — sikkerheten i kunnskapsgrunnlaget er en egen vurdering, og den står
   på påstanden (§6). Merknaden over listen sier alle tre delene: at dette er hele grunnlaget
   bak den publiserte revisjonen, at rekkefølgen ikke er en rangering, og at antallet ikke er
   sikkerhet. Skulle en senere PR likevel gruppere, er det en designbeslutning som må skrives
   ned og begrunnes — ikke en sortering som sniker seg inn.

3. **Et fravær sier alltid hvorfor, og et konfidensintervall står aldri uten sin status.** Seks
   kolonner bærer en `*_availability`, og de finnes nettopp for at en tom verdi aldri skal kunne
   leses som en nullverdi (§17, `DATABASE_ARCHITECTURE.md` §19.1). Avledningen deler vokabularet
   i de to halvdelene migrasjon 003 faktisk skiller på — `reported_value`/`uncertain_extraction`
   mot de fire fraværene — og alt annet blir et synlig kontraktsbrudd framfor å havne i «ikke
   rapportert». Listene er skrevet ut og ikke avledet av hverandre, slik at en ny enum-verdi
   tvinger fram en beslutning. De fire grunnene holdes fra hverandre i teksten, fordi de er
   egenskaper ved forskjellige ting: studien, publikasjonen, funnet og ekstraksjonen.
   Presisjonsfeltet er alltid til stede, også når intervallet mangler — samme regel som at
   tallet og komparatoren på kortet er ett felt: et manglende intervall betyr upresist grunnlag,
   ikke et presist estimat. Og et intervall uten nivå vises ikke som et intervall, fordi «0,9
   til 2,5» betyr forskjellige ting på 90 % og på 99 %.

4. **Fem vokabularer lukket, og alle åtte har nå kjøretidskontroll.** §74.12 punkt 3 sa at den
   PR-en som forgrener på et vokabular, legger til kontrollen samtidig. Evidensvisningen
   forgrener på åtte:

   | Vokabular | Hva en feil gren ville gjort |
   |---|---|
   | `relationship_type` | presentert et motstridende funn som støtte (§9) |
   | `directness` | skjult at et funn bare treffer påstanden indirekte |
   | `*_availability` | gjort et registrert fravær til en nullverdi (§17) |
   | `reported_direction` | latt kildens egen retning bli Antideps konklusjon (§5) |
   | `study_design` | gitt et ukjent design en randomisert studies vekt |
   | `source_type` | lest en preparatomtale som en primærstudie |
   | `source_status` | vist en tilbaketrukket kilde som normal (§14) |
   | `date_precision` | vist «2019» som «1. januar 2019», altså falsk presisjon (§6) |

   `reported_direction` er en felle, og den er navngitt i koden: den er **ikke** påstandens
   `direction`. Vokabularet har en fjerde verdi, `not_stated`, og å slå de to sammen ville latt
   «kilden oppgir ingen retning» og «Antidep konkluderer med ingen klar forskjell» bytte plass.
   `tests/api-vocabularies.test.ts` kontrollerer nå alle åtte mot migrasjonene, og har i tillegg
   en vaktpost som krever at de to retningsvokabularene *forblir forskjellige* — målt på
   migrasjonene, ikke på TypeScript-unionene, slik at den også fanger at databasen skulle slå
   dem sammen.

5. **Evidensen er festet til den revisjonen som faktisk står på skjermen.** Begge viewene
   følger `current_published_revision_id`, og de to spørringene er uavhengige. Publiseres en ny
   revisjon mellom dem, svarer `published_claims` med revisjon N og `published_claim_evidence`
   med funnene til revisjon N+1 — og siden ville vist et evidensgrunnlag under en formulering det
   aldri var lenket til. Det er nøyaktig det §4 forbyr: en kilde som omhandler samme tema uten å
   underbygge formuleringen, er ikke støtte. Vinduet er lite, og feilen ser ut som et gyldig svar
   — samme klasse som det foreldede svaret `useReadModel()` gjør strukturelt umulig (§74.14
   punkt 4). Hver evidensrad bærer sin `claim_revision_id`, og settet vises bare når alle hører
   til den viste revisjonen; ellers sier siden at påstanden ble publisert på nytt mens siden
   lastet. Ingen delvis visning: et blandet sett er verre enn ingen. Kontrollen er en
   sammenligning og ikke et filter i spørringen, med hensikt — et `eq('claim_revision_id', …)`
   ville gjort skiftet til et tomt svar, og et tomt svar betyr allerede noe helt annet her (se
   punktet under). De to årsakene må ikke dele ordlyd. Funnet kom fra den eksterne reviewen på
   denne PR-en; det er sjette PR på rad der en gjennomgang finner noe mutasjonstesting ikke
   kunne, og av samme grunn som før: mutasjonene traff implementasjonen, ikke forutsetningen om
   at de to spørringene ser samme revisjon.

6. **En publisert påstand uten evidens er et brudd, ikke et fravær.** Publiseringsgaten G3
   nekter å publisere en revisjon uten minst én evidenslenke (§4), så tilstanden skal ikke
   kunne finnes. Den vises derfor som en feil med `role="alert"` og med beskjed om å behandle
   påstanden som ubekreftet — ikke som en rolig opplysning om at evidens mangler. Det samme
   gjelder to publiserte påstander på samme identitet: `api.published_claims` har én rad per
   påstand, så to rader er ikke en rekkefølge å velge i, og ingen av dem vises.

7. **En tilbaketrukket ekstraksjon merkes, den skjules ikke — og reviewkontrakten utvides
   ikke.** Kortet sier hvor mange evidenslenker som er trukket tilbake; her står det hvilke,
   med tidspunkt og begrunnelse, og funnet blir stående fordi påstanden over det fortsatt er
   publisert (§14). Av reviewhistorikken vises fortsatt bare tidsstempler — ingen
   aktøridentitet, ingen beslutningstype, ingen begrunnelse (§58, §74.11). De fire
   tidsbegrepene holdes adskilt (`DATABASE_ARCHITECTURE.md` §7.3), og
   publiseringstidspunktet, som kortet med vilje utelater, står her.

**Én delt regel, ikke to utgaver.** `describeMeasureUnit()` er skilt ut av
`describeClaimMagnitude()` fordi migrasjon 003 håndhever nøyaktig samme enhetsregel på
evidensfunnene som migrasjon 004 gjør på påstandsrevisjonene. Estimatavledningen kaller
`describeClaimComparator()` og `describeClaimMagnitude()` direkte når statusen sier at et tall
står der, med intervensjonen som subjekt slik virkestoffet er påstandens. Da gjelder også
forsvaret mot et kontrastivt effektmål uten komparator på evidensradene, uten en andre utgave
av regelen. Effektmåletikettene ligger nå i `vocabulary-labels.ts`, av samme grunn: en
oddsratio er en oddsratio uansett hvilken rad den står i.

**Veien tilbake.** Siden lenker til virkestoffet og til det kliniske temaet påstanden hører
til. En delt lenke lander her uten historikk å gå tilbake i, og §55 og §56 krever at
dypelenken virker og at tilbakenavigasjonen bevarer konteksten. Adressene bygges av
`routes.ts`, som ellers på flaten.

**Det som ikke vises, og hvorfor.** §41 avslutter med «Full referanseliste». Den er utelatt som
egen seksjon: hvert funn bærer hele kilderaden allerede, og en liste i tillegg ville vært de
samme dataene to ganger på én side. Behovet §41 peker på — én visning per kilde, med alt
Antidep bruker den til — er `Source`-visningen i §42, og den er en egen PR. Identifikatorene
vises som tekst og ikke som lenke til originalen; en `href` bygget av en streng fra databasen
er en annen beslutning enn å vise strengen, og den hører hjemme sammen med `Source`-visningen.

**Gjeld: ingen nye poster, to eksisterende presisert.** Regelen om at et kontrastivt effektmål
krever en komparator, mangler også på `knowledge.evidence_items` — samme gjeld, én tabell til.
Og kontrollen av `api`-kontrakten mot databasens *kolonner* står fortsatt igjen; innsatsen er
høyere nå, fordi evidensvisningen leser over femti kolonner fra ett view. Vokabularhalvdelen er
til gjengjeld helt lukket: alle åtte lukkede unioner har både en kontroll mot migrasjonene og en
kjøretidskontroll.

**Ingen uprøvbare vakter.** To tidlige utforminger her hadde grener ingen test kunne nå: en
`complete`-tilbakekalling i den generiske feltavledningen ga kallerne en tidsromtype og en
intervalltype med ledd som i praksis aldri var tomme, og visningen måtte likevel forgrene på dem.
Avledningen bygger nå den sammensatte verdien først etter at leddene er kontrollert, så typen
selv sier at begge ledd finnes, og visningen har ingen gren igjen å skrive. Det er samme
opprydding som `baselineReadingIsLicensed()` i §74.13 og de to fjernede grenene i §74.14: en
uprøvbar vakt ser ut som et vern uten å være det. `implausible_value` kom til i samme runde, som
et eget bruddskille fra `incomplete_value` — en utvalgsstørrelse på null og et intervall med
grensene i feil rekkefølge er ikke halve verdier, de er verdier som ikke kan være det de er
registrert som, og rettingen er en annen.

**Hva som ble verifisert.** `npm run lint`, `npm run format:check`, `npm run typecheck`,
`npm run test` og `npm run build` er kjørt og passerer, sammen med `./scripts/verify-counts.sh`.
Vitest-suiten er utvidet fra 408 til 556 tester. Mutasjonstesting er kjørt etter mønsteret i
§74.13 og §74.14: rundt åtti mutasjoner er innført én om gangen over avledningen, komponenten,
siden, de delte reglene og vokabularvaktpostene, og alle fanges nå. Fem av dem overlevde først,
og alle fem var reelle hull i testene framfor i koden:

- Datomønsteret var ikke prøvd på ytterpunktene. En løsere form gjorde «20190301» og «2019-3-1»
  til gyldige datoer uten at noe feilet.
- Mønsteret var heller ikke prøvd uforankret i slutten, og et uforankret mønster ville tatt imot
  et `timestamptz` og stilltiende kuttet klokkeslettet — altså vist en dato som ikke er den
  kolonnen bærer.
- Påstanden om merknaden over evidenslisten var avkortet, slik at **halesetningen** — den som
  sier hvor sikkerheten faktisk står — stod uprøvd.
- En assertion på publiseringstidspunktet var **stille sann**, fordi en annen rad i samme
  tidspunktliste bar nøyaktig samme dato. Fiksturen har nå én dato per felt, og assertionen
  leser det feltet den handler om.
- Teksten for en verdi som ikke kan være det den er registrert som, ble aldri rendret av noen
  test. En utvalgsstørrelse på null kunne dermed vært vist som «0» — nettopp den lesningen §17
  forbyr — uten at noe feilet.

Flaten er kjørt i Chromium på 1280 px og på en ekte 390 px mobilviewport gjennom
devtools-protokollen, med tre funn — ett velformet, ett tilbaketrukket med tilbaketrukket kilde,
ett uten estimat — uten horisontal overflyt (`scrollWidth` lik `clientWidth` på begge bredder) og
uten konsollmeldinger utover en manglende favicon på forhåndsvisningssiden. Overskriftshierarkiet
er kontrollert i nettleseren: h1 produkt, h2 side, h3 seksjon, h4 påstand og funn, h5 kilde.

**En anbefaling til neste PR som rører verktøykjeden.** Skjermdumpskriptet og
mutasjonstestharnessen er nå skrevet fra bunnen av tre ganger — i #23, i #24 og her — fordi de
lever i scratchpad og ikke i repoet. Ingen av dem inneholder klinisk innhold. De hører hjemme i
`scripts/`, men ikke i en ren funksjonalitets-PR (§51), så de er bevisst ikke lagt til her.

**Hva som gjenstår av PR I.** `Source`-visningen (§42): én side per kilde, som beskriver
publikasjonen og lenker til de påstandene Antidep bruker den til. Viewene svarer fortsatt `[]`,
så den må bygges mot den tomme projeksjonen på samme måte som sidene her. Det er det siste
punktet i leveranselisten i §30. Den ble bygget i neste PR; se §74.16.

### 74.16 Hva kildevisningen innførte

`feat: add the source view` er femte del av PR I (§30, §68) og det siste leveransepunktet i
Slice 2: «kildedetalj». Den oppretter ingen migrasjon og legger ingen ny avhengighet til. Den
består av ruten og adressen (`/sources/:sourceId`), en ny lesefunksjon
(`fetchPublishedEvidenceForSource()`), selve siden (`src/app/pages/SourcePage.tsx`), de delte
kildefeltene (`src/components/SourceDetails.tsx`), feltlisten begge kildevisningene nå bruker
(`src/components/DetailList.tsx`) og avledningen fra en registrert identifikator til en adresse
(`src/lib/source-identifier.ts`).

**Slice 2 (§30) er dermed ferdig.** Både definition of done og leveranselisten er innfridd, og
markeringen i §74.1 er flyttet fra `[~]` til `[x]`. `PRODUCT_INFORMATION_ARCHITECTURE.md` §42
er innfridd i begge retninger: fra en påstand til grunnlaget bak den, og fra én publikasjon til
alt Antidep bruker den til. De to visningene lenker til hverandre og er ikke blandet.

**Seks beslutninger, i den rekkefølgen de betyr noe klinisk:**

1. **Kilden er emnet, ikke det kilden konkluderer med.** Kilderaden beskriver dokumentet, og hva
   Antidep mener dokumentet *viser*, ligger i evidensfunnene og påstandene
   (`KNOWLEDGE_MODEL.md` §10). En side om én publikasjon leses lett som en oppsummering av
   publikasjonen, så merknaden over listen sier det eksplisitt: listen er Antideps bruk av
   kilden, ikke kildens innhold. Siden gjentar heller ikke evidensvisningen — hvorfor et funn
   støtter eller motsier en påstand, med populasjon, komparator, resultat og presisjon, står
   der, og herfra går det en lenke dit. Det siden legger til, er kildens eget bidrag til hvert
   funn: relasjonen funnet har til påstanden, hvor i kilden det står, og hvilken hentet versjon
   det ble lest ut av.

2. **Evidensen er festet til den revisjonen som faktisk står på skjermen — og strengere enn på
   evidenssiden.** §74.15 punkt 5 sa at enhver ny side som leser to api-views arver kravet, og
   dette er den første som gjør det. Kildesiden leser `published_claim_evidence` filtrert på
   `source_id` og `published_claims` for formuleringene, og de to spørringene er uavhengige.
   Hver evidensrad sammenlignes derfor mot påstandsraden sin på `claim_revision_id`, og et
   avvik forkaster *hele* listen — ikke bare den påstanden som skiftet. En liste bærer to
   påstander, rekkefølgen og at dette er settet (§74.14 punkt 1), og en liste der én påstand er
   utelatt fordi den skiftet under lastingen, sier at kilden brukes til færre ting enn den gjør.
   Skjevheten har to årsaker med hver sin ordlyd: påstanden ble publisert på nytt, eller den
   stod ikke lenger i det publiserte settet. Ingen av dem deler ordlyd med et tomt svar.

3. **Adressen er kildens `uuid`.** Samme grunn som at evidensvisningen adresseres med
   `claim_id`: uuid-en er kildens stabile identitet (`DATABASE_ARCHITECTURE.md` §8). En slug
   avledet av tittelen ville i tillegg til å bli lang og fremmedspråklig — titler er inntil 600
   tegn og står på kildens eget språk — hatt nøyaktig den svakheten §74.7 allerede fører som
   gjeld for `/drugs/:drugSlug` og `/topics/:topicSlug`: en adresse avledet av et visningsnavn
   er ikke en stabil identitet, avledningen er tapsgivende, og to titler kan kollidere. Gjelden
   er dermed ikke utvidet til et tredje objekt.

4. **Identifikatorene er blitt lenker, og det er en egen beslutning med to forutsetninger.**
   §74.15 satte beslutningen om å bygge en `href` av en databaseverdi til denne PR-en. Svaret er
   å lenke, fordi etterprøvbarhet mot originalkilden er hele poenget med både kilde- og
   evidensvisningen (`ANTIDEP_CONSTITUTION.md` §4, §11; §43). To ting gjør den forsvarlig.
   Formen er håndhevet i databasen — migrasjon 003 legger `CHECK`-betingelser på både DOI og
   PMID, så verdien *er* en identifikator og ikke en URL, et `doi:`-prefiks eller en fritekst —
   og mønstrene kontrolleres likevel i klienten, av samme grunn som vokabularene har
   kjøretidskontroll: en verdi utenfor formen blir en eksplisitt ulenkbar tilstand som vises som
   tekst, aldri en URL ingen har tatt stilling til. Og suffikset prosentkodes framfor å settes
   rått inn: `\S+` tillater `#`, `?`, `<` og `>`, som alle ville gitt en lenke som ser riktig ut
   og peker et annet sted. Bokstavstørrelsen er bevisst *ikke* del av kontrollen — en DOI er
   ikke bokstavstørrelsesfølsom, så en verdi med store bokstaver bryter databasens unikhetsregel
   uten å gjøre lenken feil. Lenkene åpner i samme fane, med `rel="noreferrer"`, og hvert felt
   sier at adressen ligger utenfor Antidep.

5. **En erstattet kilde sier at etterfølgeren ikke kan navngis.** Statusen `superseded` betyr
   per migrasjon 003 at en *bestemt* nyere kilde er registrert:
   `knowledge.sources.superseded_by_source_id` er NOT NULL hvis og bare hvis statusen er den, og
   de to forutsetter hverandre. Pekeren er ikke i api-kontrakten — kontrollert: den finnes verken
   i viewet eller i `src/types/api.ts` — så klienten kan ikke følge den, og etiketten «Erstattet
   av en nyere kilde» alene er en halv sannhet: den sier at det finnes en etterfølger uten å
   kunne navngi den. Valget er å si nettopp det, framfor å la leseren tro at ingen etterfølger er
   registrert. Å utvide viewet ble vurdert og valgt bort: en `uuid` alene er ikke et svar
   klienten kan vise, så projeksjonen måtte båret etterfølgerens tittel også, og den må dessuten
   ta stilling til hva som skjer når etterfølgeren ikke selv er lesbar for klientrollene. Det er
   en migrasjon med sin egen beslutning, og §51 holder den utenfor en funksjonalitets-PR.
   Registrert som ny gjeld i §74.7.

6. **Kildeversjonen står på funnet, ikke på kilden.** `source_version_*` ligger på evidensraden,
   og samme kilde kan være lest i flere versjoner av flere funn. En «versjon»-rad i
   publikasjonsblokken ville derfor vært en sammenslåing datamodellen ikke har. Versjonen står i
   stedet under hvert funn, sammen med stedet i kilden — der den hører til, og der den svarer på
   spørsmålet «hvilken utgave leste Antidep?».

**Én delt presentasjon, ikke to.** Kildefeltene er skilt ut i `SourceDetails.tsx` og brukes av
begge visningene, av samme grunn som `ClaimCard` gjenbrukes på fire sider: samme rad, samme
regler, og en egen utgave hvert sted ville drevet fra hverandre — den ene ville fått en rettelse
den andre ikke fikk (§65 «Duplicated truth»). Det gjelder også merket på en tilbaketrukket
ekstraksjon og relasjonen funnet har til påstanden. `RELATIONSHIP_LABELS` er derfor ikke lenger
eksportert: oppslaget går gjennom `stanceText()`, som tar imot den *avledede* relasjonen og ikke
råverdien, så det finnes ingen vei der en relasjon Antidep ikke kjenner kan slå opp som noe annet
enn ukjent. Påstandskortet gjenbrukes også her: formuleringen alene ville stått uten
sikkerhetsgrad, anvendelsesområde og forbehold, altså som en påstand mer skråsikker enn den er
(§14, invariant 4). Og fordi kildesiden viser påstander om flere virkestoff under én overskrift,
arver den forbeholdet fra `ClaimGroups` om at påstander side om side ikke er en sammenligning —
det samme forbeholdet, ikke en andre utgave av det.

**Ingen nye vokabularer.** Siden forgrener på `source_type`, `source_status` og
`date_precision`, og alle tre ble lukket med kjøretidskontroll i evidensvisningen (§74.15). De
leses gjennom én ny delt avledning, `describeSource()`, slik at kildesiden og evidensfunnet ikke
kan gi hvert sitt svar om samme rad. `tests/api-vocabularies.test.ts` er derfor uendret: de åtte
lukkede unionene er de samme åtte.

**Gjeld: én ny post, tre presisert.** Den nye er `superseded_by_source_id`, over. Presisert:
kildesiden er den andre visningen som laster hele det publiserte settet for å vise ett utsnitt,
og den første som joiner det i klienten; slug-posten er presisert med at kildevisningen bevisst
ikke gjentok avledningen på et tredje objekt; og kolonnekontrollen av api-kontrakten står
fortsatt igjen, nå med to sider som leser det samme brede viewet.

**Interne rutelenker navigerer i klienten.** Lenken fra hvert evidensfunn til kildesiden var
først en vanlig `<a>`, etter mønster av `ClaimCard`. Det gir en full dokumentnavigering: siden
lastes på nytt, og `useFocusMainOnNavigation()` hopper med vilje over fokusflyttingen ved første
render, så leseren havner øverst i et nytt dokument framfor i hovedområdet. På evidenssiden stod
lenken dessuten rett ved lenkene til virkestoffet og temaet, som er `Link` — å navigere ulikt fra
samme avsnitt er en forskjell uten begrunnelse. Skillet som faktisk gjelder, er hva verdien *er*:
`ClaimCard` kan ikke bruke `Link`, fordi dens `evidenceHref` er et anker på samme side
(`#evidensgrunnlaget`) når kortet står på evidensvisningen, mens kildelenken alltid er en rute.
Adressene lages fortsatt bare i `routes.ts`, så §74.13 punkt 4 står uendret.

**Og det er sjuende PR på rad der en gjennomgang finner noe mutasjonstesting ikke kunne** — av
nøyaktig samme grunn som de seks før: mutasjonene traff implementasjonen, ikke forutsetningen. Det
fantes en mutasjon som fjernet lenken, og den ble fanget; men ingen test spurte *hvordan* lenken
navigerer, fordi `Link` og `<a>` gir nøyaktig samme DOM. Testen som nå holder regelen, klikker
lenken og krever at kildesiden faktisk rendres — med en vanlig `<a>` står ruteren stille, og
evidenssiden blir værende.


**Hva som ble verifisert.** `npm run lint`, `npm run format:check`, `npm run typecheck`,
`npm run test` og `npm run build` er kjørt og passerer, sammen med `./scripts/verify-counts.sh`.
Vitest-suiten er utvidet fra 556 til 627 tester over 26 filer. Mutasjonstesting er kjørt etter
mønsteret i §74.13 til §74.15: 60 mutasjoner er innført én om gangen over avledningen, de delte
komponentene, siden, lesefunksjonen, adressene og navigeringsmåten, og alle fanges.

To ting om harnessen er verdt å ta med videre, fordi begge gjør en mutasjonskjøring stille
verdiløs. En avbrutt kjøring kan etterlate filen mutert, og da måler neste kjøring mot en **rød
grunnlinje** der hver eneste mutasjon rapporterer seg som drept — det skjedde her, og hele
batchen måtte forkastes og kjøres om. Harnessen kjører nå grunnlinjen først og avbryter hvis den
er rød, og gjenoppretter filen på signal. Og en assertion kan være svak på nøyaktig samme måte
som testdataene er svake: kollasjonstesten prøvde «Bly» mot «Åpen», som en sortering på tegnverdi
ordner *likt*, så en sortering uten `compareNorwegian()` ville passert. Testdataene inneholder nå
«Aaland», som norsk kollasjon sorterer som «Åland» og altså etter «Bly», og mutasjonen som bytter
til tegnverdisortering fanges.

Flaten er kjørt i Chromium på 1280 px og på en ekte 390 px mobilviewport gjennom
devtools-protokollen, med en kilde brukt til to påstander om to virkestoff, tre funn, ett av dem
med tilbaketrukket ekstraksjon, og en erstattet kilde med to DOI-er og én PMID — uten horisontal
overflyt (`scrollWidth` lik `clientWidth` på begge bredder, ingen element med indre overflyt) og
uten konsollmeldinger utover en manglende favicon på forhåndsvisningssiden. Overskriftshierarkiet
er kontrollert i nettleseren: h1 produkt, h2 kilden, h3 seksjon, h4 påstand. Evidensvisningen er
kjørt på nytt på begge bredder etter uttrekket av de delte feltene, og er uendret bortsett fra de
to nye tingene: lenken til kildesiden og de lenkede identifikatorene.

**Skjermdumpskriptet og mutasjonstestharnessen er nå skrevet fra bunnen av en fjerde gang**, av
samme grunn som før: de lever i scratchpad og ikke i repoet. Anbefalingen fra §74.15 står
uendret og er ikke innfridd her, fordi denne PR-en ikke rører verktøykjeden og §51 krever
enkeltformål.

**Hva som gjenstår.** Slice 2 er ferdig, og PR I er ferdig. Neste vertikale slice er §31
(sammenligning), men det som blokkerer er fortsatt ikke kode: Milepæl B mangler én navngitt
kvalifisert redaktør (§74.4), og viewene svarer `[]` til den finnes. Den mest verdifulle
strukturelle oppryddingen er fortsatt kolonnekontrollen av api-kontrakten (§74.7).

Redaktøren ble navngitt og registrert i neste PR; se §74.17. Setningen over arvet samtidig
feilen §74.4 nå retter: én redaktør var aldri alt som gjenstod for Milepæl B, og viewene
svarer fortsatt `[]`.

### 74.17 Hva registreringen av redaktøren innførte

`db: register the named qualified editor` er migrasjon 005a. Den utvider aktørregisteret fra
migrasjon 005 (§20), står utenfor den planlagte rekken i §18-§27 og får derfor en bokstav,
etter samme konvensjon som 006a og 007a. Den legger ingen ny avhengighet til, oppretter ingen
tabell, ingen enum-type og ingen funksjon. Den setter inn én rad.

**Beslutningen den registrerer.** §74.4 slo fast at neste skritt mot Milepæl B ikke var en
kodeoppgave, men en governance-beslutning: hvem er den navngitte kvalifiserte redaktøren
`ANTIDEP_CONSTITUTION.md` §12 krever? Prosjekteieren, Peder Holman, har utpekt seg selv.
Migrasjonen gjør den beslutningen til en kanonisk rad. En navngitt redaktør som bare finnes i
prosa, er ikke navngitt på en måte databasen kan bruke: aktørraden er festepunktet for all
attribusjon (`DATABASE_ARCHITECTURE.md` §32).

**Fem beslutninger, i den rekkefølgen de betyr noe:**

1. **Aktøren registreres uten brukerkonto, og det er formen modellen er bygget for.**
   `provenance.actors.auth_user_id` har en ekte fremmednøkkel til `auth.users`, og den kontoen
   er en reell Supabase-konto som må opprettes i autentiseringslaget — ikke i en migrasjon. En
   rad med en oppdiktet `uuid` ville enten feilet på fremmednøkkelen eller pekt på en konto
   ingen eier. Kolonnen står derfor `NULL`, og betyr nøyaktig det migrasjon 005 sier: aktøren
   har ikke en konto i dette systemet, ikke at aktøren er ukjent. Dette er ingen omgåelse:
   `provenance.freeze_actor_identity()` fryser aktøridentiteten, men gjør ett eksplisitt
   unntak — `auth_user_id` kan settes én gang fra `NULL`, «fordi en menneskelig aktør kan bli
   registrert før kontoen finnes». Unntaket er håndhevet og testet i begge retninger i
   `200_workflow_immutability_test.sql`: koblingen kan settes én gang, og kan verken fjernes
   eller flyttes etterpå. Den senere koblingen er dermed ikke en antakelse denne migrasjonen
   hviler på uten dekning.

2. **Raden åpner ikke publiseringsgaten, og det er prøvd framfor påstått.** En navngitt
   redaktør i basen leses lett som at godkjenningsveien nå står åpen. Den gjør ikke det, og å
   telle at `workflow.review_decisions` fortsatt er tom ville vært et svakt uttrykk for det —
   tabellen er tom av mange grunner. `220_provenance_seed_test.sql` forsøker derfor faktisk å
   registrere en publiseringsgodkjenning i redaktørens navn, og krever at databasen avviser
   den med `insufficient_privilege` og med den meldingen
   `workflow.enforce_reviewer_qualification()` gir. Assertionen kan ikke bli stille sann:
   slår oppslaget på `actor_key` feil, gir spørringen null rader, `insert`-en lykkes med å
   sette inn ingenting, og `throws_ok` feiler fordi ingen exception ble kastet. Både feilkoden
   og meldingen kontrolleres, slik at en feil på et tidligere lag ikke kan telle som riktig
   avvisning.

3. **Selvtildeling er valgt, og skrevet ned før kolonnen krevde en verdi.**
   `workflow.user_roles.granted_by_actor_id` er `NOT NULL` og peker på en aktør. Når
   `reviewer`-rollen en gang tildeles, finnes bare to muligheter: enten tildeler en KI-aktør
   et menneske faglig godkjenningsrett, eller så tildeler redaktørens egen aktør rollen til
   seg selv. Ingen `CHECK` forbyr selvtildeling, så valget ville ellers blitt tatt i stillhet
   av den som fylte ut kolonnen. Beslutningen er selvtildeling: autoriteten kommer utenfra
   systemet, prosjekteieren *er* den kvalifiserte redaktøren, og det finnes ingen høyere
   menneskelig instans i basen. Alternativet ville gjort en KI-prosess til opphavet til et
   menneskes faglige godkjenningsrett, stikk i strid med §10 og §12. Prisen er at
   selvtildelingen står usikret av en `CHECK`, og den må derfor stå eksplisitt i
   `grant_reason` på tildelingsraden.

4. **Beskrivelsen sier hva aktøren er, ikke hva som er kontrollert.** `description` er
   `NOT NULL` og skal være konkret nok til å være etterprøvbar. Den sier at utpekingen hviler
   på prosjekteierrollen og ikke på et fastsatt kompetansekrav, og at raden ikke i seg selv
   gir godkjenningsrett — den leses fra brukerkonto og `workflow.user_roles`, ikke herfra.
   Uten den siste setningen ville `display_name` «Peder Holman» ved siden av ordet «redaktør»
   kunnet leses som en fullmakt raden ikke gir. Beskrivelsen er bevisst utenfor
   identitetsvernet og kan endres når kompetansekravene finnes; den skal ikke kunne leses som
   en kvalifikasjon Antidep har kontrollert.

5. **Redaktøren har ikke forfattet noe, og det er en forutsetning.**
   `review_decisions_separate_actor_check` nekter en godkjenning der godkjenner og forfatter er
   samme aktør (§10, §12). Stod redaktøren senere som opphav til en revisjon, kunne
   vedkommende ikke godkjent den. Testen påstår derfor at ingen kunnskapsobjekt er attribuert
   til en menneskelig aktør, skrevet over aktørtypen og ikke over `actor_key`, slik at
   assertionen ikke kan bli stille sann av en feilstavet nøkkel.

**Seedtesten er justert, ikke omgått.** `220_provenance_seed_test.sql` sa selv at assertionene
«skal justeres av migrasjonen som registrerer en reell godkjenning og en reell publisering,
ikke omgås». Migrasjon 005a er første gang det skjer. Assertionen om at aktørregisteret
inneholder nøyaktig de to KI-rollene er utvidet til tre rader og bærer nå `display_name` også —
§12 krever en *navngitt* redaktør, og navnet er feltet som bærer navngivingen; uten det ville
testen godtatt en anonym menneskelig aktør. Assertionen om at det finnes null menneskelige
aktører er byttet med en som krever nøyaktig én, og at det er den navngitte. Filen gikk fra 14
til 16 assertions, og databaselaget fra 1096 til 1098.

**Én assertion ble strammet underveis.** Kravet om at hver aktør «forklarer konkret hva den er»
var skrevet som «beskrivelsen er ikke tom eller `NULL`». Databasens `CHECK` krever bare 1-2000
tegn, så en beskrivelse på ett tegn passerte begge. Migrasjon 005 sier hvorfor kolonnen finnes
— «en aktørrad uten beskrivelse ville gjort attribusjonen til en etikett i stedet for en
forklaring» — og en etikett er nettopp det en svært kort beskrivelse er. Assertionen har nå et
lengdegulv, slik at den påstår det den sier den påstår.

**Gjeld: én ny post.** Kompetansekravet for redaktørrollen er ikke definert, og redaktøren er
utpekt av seg selv. §12 krever en «kvalifisert» redaktør uten å definere kvalifikasjonen;
`CONTENT_GOVERNANCE.md` §11 legger den definisjonen til Clinical Lead, og Antidep har ingen.
Samme person er prosjekteier og eneste faglige godkjenner, og modellen har ingen kolonne for
den profesjonelle bindingen §45 og §46 ber om å registrere. Migrasjonen navngir personen
beslutningen allerede har pekt ut; den lukker ikke hullet, og skjuler det ikke heller.

**Hva som ble verifisert.** Migrasjonene er kjørt fra bunnen av og hele pgTAP-suiten er kjørt
mot en lokal PostgreSQL 16 med pgTAP — Docker-registryene svarer 403 gjennom egress-proxyen, så
`npx supabase start` er ikke tilgjengelig; CI kjører den ekte stacken. Grunnlinjen før endringen
var 1096 passerende assertions, etter endringen 1098, uten `not ok` og uten `ERROR`.
`npm run lint`, `npm run format:check`, `npm run typecheck`, `npm run test`, `npm run build` og
`./scripts/verify-counts.sh` er kjørt og passerer. Ti mutasjoner er innført én om gangen; ni
fanges. Den som overlever er lengdegulvet i assertionen over: senkes tallet, blir assertionen
svakere, og ingen test beskytter en annen tests terskelverdi. Mutasjonen som faktisk betyr noe
— en beskrivelse redusert til en etikett i migrasjonen — fanges.

**Den viktigste mutasjonen traff forutsetningen, ikke implementasjonen.** §74.16 slo fast at
sju PR-er på rad hadde fått funn mutasjonstesting ikke kunne finne, hver gang fordi mutasjonene
traff koden og ikke antakelsen den hvilte på. Her ble antakelsen mutert direkte: kravet om
brukerkonto i `workflow.enforce_reviewer_qualification()` ble slått av i migrasjon 005, og den
nye negative testen feilet. Den påstanden er dermed ikke lånt fra gaten — den er kontrollert
mot den.

**Hva som gjenstår.** Milepæl B mangler fire ting, ikke én (§74.4): brukerkonto med
`reviewer`-rolle, ekstraksjonsverifikasjonene, claim-verifikasjonene og godkjenningen. Neste
vertikale slice er §31 (sammenligning). Den mest verdifulle strukturelle oppryddingen er
fortsatt kolonnekontrollen av api-kontrakten (§74.7).

### 74.18 Det hostede Supabase-prosjektet er tomt

> **Overhalt av §74.23.** Migrasjonene er siden kjørt mot det hostede prosjektet, og `api` er
> eksponert. Avsnittet er beholdt som historikk (§71). Det som fortsatt gjelder herfra, er
> forbudet mot `supabase config push` og begrunnelsen for vei a i migrasjon 005b — men
> begrunnelsen for *forbudet* er rettet: tabellen under sammenlignet `config.toml` med
> produksjonsverdier ingen hadde lest. Den kontrollerte sammenligningen står i §74.23.

**Funnet.** Prosjekteieren åpnet Supabase-dashboardet (Integrations → Data API → Settings →
«Exposed schemas») for å gjøre den manuelle synkingen §74.5 punkt 3 ber om. Nedtrekkslisten
der viser de schemaene som faktisk finnes i databasen, og den inneholdt nøyaktig to:
`graphql_public` og `public`. Ingen av Antideps schemaer var der — verken kontraktslaget `api`
eller de kanoniske `catalog`, `knowledge`, `workflow`, `provenance` og `audit`.
**Migrasjonene har aldri vært kjørt mot det hostede prosjektet.** Databasen der er tom.

**Hva som er kontrollert, og av hvem.** Observasjonen kommer fra prosjekteieren i dashboardet.
Ingen med databasetilgang har bekreftet den, og denne sesjonen kan ikke: Supabase-MCP-serveren
krever en autorisasjon som ikke finnes her, og Docker-registryene svarer 403 gjennom
egress-proxyen, så `npx supabase start` kan ikke hente imagene. Påstanden føres derfor med sin
kilde, framfor som et faktum repoet har målt. Det som *er* kontrollert mot kilden her, er de to
tingene funnet gjør noe med: `supabase/config.toml` beskriver en lokal stack og ikke et hostet
prosjekt, og `src/lib/supabase.ts` binder klienten til `api` med `db: { schema: 'api' }`.

**Hvorfor den motsatte påstanden overlevde.** «Det hostede prosjektet» har vært omtalt i denne
planen og i `supabase/README.md` siden migrasjon 007 som noe migrasjonene *lå i* og som
`[api].schemas` skulle synkes *mot*. Ingen kontrollerte det; formuleringen ble ført videre fra
oppdatering til oppdatering. Dette er sjuende gang en påstand i planen har vært arvet framfor
kontrollert (§74.4, §74.8), og den skiller seg fra de seks foregående på ett punkt: de var
tall, som `scripts/verify-counts.sh` etter hvert kunne fange. Denne er en påstand om et system
utenfor repoet, og ingen vaktpost i CI rapporterer schematilstanden der. Det er ikke et
argument for å la den stå ukontrollert — det er grunnen til at den må føres med sin kilde og
ikke som et faktum.

**Konsekvenser, i den rekkefølgen de betyr noe:**

1. **`public` er skrudd av i det hostede prosjektet, og det var trygt.** Schemaet inneholder
   ingen Antidep-objekter — `020_data_api_boundary_test.sql` håndhever det for migrasjonene —
   og i det hostede prosjektet er det tomt uansett. Eksponeringen var derfor tom i begge
   miljøer, og §5 er opt-in.
2. **`api` kan ikke eksponeres ennå.** Schemaet dukker opp i avhukingsmenyen først når
   migrasjonene er kjørt. Synkingen §74.5 punkt 3 ber om, er dermed ikke utsatt av
   forsømmelse: den er ikke mulig ennå.
3. **Rekkefølgen i den listen finnes ikke som begrep, og betyr uansett ingenting for appen.**
   Dashboardets eksponerte schemaer er en avhukingsmeny, ikke en sortert liste. `api` står
   først i `config.toml`, men klienten sender `Accept-Profile: api` uansett (§74.5 punkt 3),
   så standardprofilen er ikke noe appen hviler på.
4. **Ingenting av klinikerflaten peker på det hostede prosjektet ennå, og det er ikke et nytt
   tap.** Ingenting er publisert (§74.4), så en fullt migrert database der ville vist et tomt
   publisert sett — nøyaktig det appen viser i dag.

**Det finnes en Supabase-GitHub-integrasjon på repoet, og den har vært stille hele veien.**
Hver pull request får en `Supabase Preview`-kontroll. På PR-en som skrev dette avsnittet er
utfallet `skipped`, med begrunnelsen «This git branch is not associated with any Supabase
Branch». Kontrollen peker på prosjektet `gxorhbwndpopartjuwbj`, som dermed er det hostede
prosjektet integrasjonen er koblet til. Det er første gang den identiteten står noe sted i
repoet — den finnes ellers bare i CI-overflaten — og den trengs av den som skal kjøre
`supabase link`. To ting kontrollen *ikke* sier, og som ikke må leses inn i den: en preview
branch er en egen database, så et `skipped`-utfall sier ingenting om hva produksjonsdatabasen
inneholder; og at integrasjonen er installert, betyr ikke at noen migrasjon noen gang er kjørt
gjennom den. Supabase Branching er likevel en tredje mulig vei ut for migrasjonene, ved siden
av `supabase db push` og dashboardet, og må vurderes sammen med dem — men den kjører
migrasjonene mot *preview*-databaser og ikke mot produksjon, så den løser ikke oppgaven under
alene.

**Å kjøre migrasjonene mot det hostede prosjektet er en egen oppgave, og den er ikke gjort.**
`supabase link` etterfulgt av `supabase db push` er verktøyet. Oppgaven skal planlegges og
ikke bare utføres: den må ta stilling til §54 — migrasjonene er kilden, ikke dashboardet — og
til advarselen under, som gjelder nabokommandoen. Den hører hjemme hos prosjekteieren og ikke
i en agentsesjon uten tilgang til prosjektet.

**Aldri `supabase config push` mot dette prosjektet.** Kommandoen finnes i den pinnede CLI-en
og ser ut som riktig vei, siden den ville gjort `config.toml` til kilden slik §54 ber om. Den
pusher hele filen, og `config.toml` her er i praksis `supabase init`-standardene for en lokal
stack:

| Nøkkel | Verdi i `config.toml` | Hva et push ville gjort i produksjon |
|---|---|---|
| `auth.site_url` | `http://127.0.0.1:3000` | satt produksjonens site URL til localhost |
| `auth.additional_redirect_urls` | `["https://127.0.0.1:3000"]` | slettet de reelle redirect-URL-ene |
| `auth.minimum_password_length` | `6` | senket passordkravet |
| `db.network_restrictions.allowed_cidrs` | `["0.0.0.0/0"]` | åpnet databasen for alle adresser |

> **Høyrekolonnen er ikke kontrollert, og var det aldri.** Venstre og midtre kolonne er lest
> ut av `config.toml` og stemmer. Høyrekolonnen er en slutning om produksjonsverdier ingen
> hadde lest på det tidspunktet — den ble skrevet 26. august 2026, samme dag som §74.18 slo
> fast at ingen her hadde tilgang til å lese det hostede prosjektet. To av de fire radene viste
> seg senere å beskrive en forskjell som ikke fantes. Tabellen er beholdt som historikk (§71);
> **den kontrollerte sammenligningen mot produksjon står i §74.23**, og det er den som skal
> brukes.

Alle fire treffer autentiseringslaget og nettverksgrensen — altså nøyaktig der redaktørens
brukerkonto ligger. Enkeltinnstillinger settes i dashboardet. Å gjøre `config.toml` til reell
kilde for det hostede prosjektet er en egen, bevisst oppgave der hver seksjon først må settes
til produksjonsverdier. Selve hovedregelen står uendret av rettelsen over, og hviler ikke på
de fire radene: `config.toml` er ikke en produksjonskonfigurasjon, kommandoen pusher hele
filen, og ingen har sammenlignet alle nøklene i den mot produksjon.

**Redaktørens brukerkonto finnes, og tvinger fram et valg.** Prosjekteieren har opprettet
kontoen i det hostede prosjektet (Authentication → Users) og oppgitt dens `uuid`:
`a703ede9-3f58-4de9-8c85-73936d58df1f`. Formen er kontrollert her — gyldig uuid v4 etter
RFC 4122 — men at raden finnes i `auth.users`, er ikke kontrollert av noen med databasetilgang.
Migrasjonen som kobler kontoen til aktørraden fra §74.17 og tildeler `reviewer`-rollen, kan
derfor ikke skrives før dette er avgjort: kontoen finnes bare i det hostede prosjektet, mens
CI starter en fersk lokal stack uten den, og `workflow.user_roles.user_id` er `NOT NULL` med
fremmednøkkel til `auth.users`. Tre veier, og ingen av dem er åpenbart riktig:

| Vei | Hva den gjør | Prisen |
|---|---|---|
| a | Gjør koblingen betinget av at kontoen finnes, slik at migrasjonen ikke skriver raden i miljøer uten den | Migrasjonen gjør forskjellige ting i forskjellige miljøer, og CI kjører aldri den grenen som faktisk kjører i produksjon |
| b | Seeder en tilsvarende konto i `supabase/seed.sql` for lokalt og CI | **Virker ikke** — se under |
| c | Holder kobling og rolletildeling utenfor migrasjonene, som en operasjonell engangshandling mot produksjon | Bryter §54 sitt krav om at durable tilstandsendringer ligger i versjonerte migrasjoner, og gjør rolletildelingen usporbar i repoet |

**Vei b er ikke en vei, og det er kontrollert mot kilden.** `supabase/config.toml` sier det
selv om `[db.seed]`: «If enabled, seeds the database after migrations during a db reset.»
Seedfilen kjøres *etter* migrasjonene. En migrasjon 005b som skriver
`workflow.user_roles.user_id`, ville dermed kjørt før kontoen fantes, og feilet på
fremmednøkkelen til `auth.users` uansett hva `seed.sql` inneholder. Alternativet var ført opp
i hand-offen som ett av tre likeverdige valg; det er det ikke. Skulle kontoen finnes før
migrasjonene er ferdige, måtte den vært opprettet av en *migrasjon* som skriver til
`auth.users` — en kobling til Supabases eget schema som bryter på neste plattformoppgradering,
og som uansett gjør migrasjonen miljøavhengig, altså vei a med et ekstra ledd.

**Valget er delegert, og retningen er vei a.** Prosjekteieren har overlatt avgjørelsen til
denne sesjonen. Det er en teknisk avgjørelse om hvordan en migrasjon oppfører seg i CI, ikke
governance-avgjørelsen om hvem redaktøren er — den ble tatt og registrert i §74.17, og er ikke
rørt her. Begrunnelsen for a: en rad i `auth.users` er per definisjon miljøspesifikk tilstand,
ikke schema. Kontoen kan ikke finnes i en fersk lokal stack, og en oppdiktet konto lokalt ville
gjort at CI kontrollerte en fiksjon. Vei a er den eneste som holder rolletildelingen i en
versjonert migrasjon (§54) *og* lar raden være fraværende der den skal være fraværende.

Prisen i tabellen må da betales eksplisitt, ikke ties i hjel, og migrasjonens PR må gjøre to
ting for å betale den: raden skal ikke stille utebli, men gi en synlig `notice` når kontoen
mangler, og CI skal kontrollere *begge* grenene — den positive ved å opprette en konto inne i
en transaksjon som rulles tilbake, slik testene allerede gjør for alt annet, og den negative
ved å påstå at ingen rolle er tildelt når kontoen ikke finnes. Uten den positive testen ville
produksjonsveien vært ukjørt, og det er nøyaktig innvendingen mot vei a.

Selve innholdet i migrasjonen er ellers avklart: koblingen kan settes nøyaktig én gang fra
`NULL` (§74.17 punkt 1), granten er en selvtildeling som skal stå eksplisitt i `grant_reason`
(§74.17 punkt 3), og `220_provenance_seed_test.sql` må justeres — den negative testen som
krever at gaten avviser en godkjenning fordi aktøren mangler brukerkonto, skal erstattes av en
som påstår den *nye* avvisningsgrunnen, ikke slettes.

**Lærdom: et tall som bare finnes i en hand-off, er utenfor enhver vaktpost.** Hand-offen inn
til §74.17 oppga 56 kildefiler i `src/`. Det korrekte tallet var 57, og hadde vært det siden
`feat: add the source view` — migrasjon 005a rørte ingen fil i `src/`. Feilen er ikke ført inn
i planen her, og skal ikke føres inn: planen har aldri hevdet et slikt tall, og å legge til en
påstand utelukkende for å kunne kontrollere den er seremoni. Poenget er det motsatte, og det
gjelder framover: en påstand som bare lever i en hand-off, kontrolleres av ingen. Skal den
overleve, må den enten inn i et dokument en vaktpost leser, eller kontrolleres mot kilden på
nytt hver gang den brukes.

**Hva denne oppdateringen endret i vaktposten.** `scripts/verify-counts.sh` kontrollerer nå at
`[api].schemas` i `supabase/config.toml` er den verdien §74.5 punkt 3 hevder. Det er den
eneste påstanden i det punktet som *kan* kontrolleres maskinelt: verdien i `config.toml` er
kildekode, mens dashboardets tilstand ikke er det. Kontrollen leser den påståtte verdien ut av
planen framfor å ha den innbakt, slik at en omformulering gir «fant ingen påstand» og ikke en
stille godkjenning — samme form som de øvrige kontrollene i filen.

**Hva som gjenstår.** Milepæl B mangler fortsatt fire ting (§74.4). Sporet etter denne
oppdateringen er ikke rollegranten, men kolonnekontrollen av api-kontrakten (§74.7): den er
den mest verdifulle rent strukturelle oppryddingen, den er uavhengig av alt som krever et
hostet prosjekt eller en brukerkonto, og innsatsen vokser for hver side som legges til over de
samme uprøvde kolonnepåstandene. Ett funn sparer den neste for en blindvei:
`information_schema.columns` rapporterer `is_nullable = 'YES'` for alle kolonner i et view —
PostgreSQL gjør ingen nullbarhetsanalyse gjennom views. Navn og typer kan leses derfra;
nullbarhet kan ikke, og må håndheves på en annen måte som må navngis eksplisitt.

---

### 74.19 Hva kolonnekontrakten av api innførte

`test: verify the api column contract` innfrir den andre halvdelen av gjeldsposten som har
stått siden migrasjon 007: radtypene i `src/types/api.ts` og `Database`-typen i
`src/types/database.ts` er nå bundet til kolonnene `api` faktisk har. Ingen migrasjon, ingen
SQL-endring og ingen endring i `src/` — bare to nye kontroller og en innstrammet gjeldspost.

1. **Kontrakten er erklært ett sted og kontrolleres i to retninger.** `contract`-tabellen i
   `supabase/tests/340_api_column_contract_test.sql` har én rad per kolonne i `api`: view,
   kolonnenavn, SQL-type og nullbarhet. Derfra går kontrollen begge veier, i hver sin CI-jobb:

   | Retning | Hvor | Hva den krever |
   |---|---|---|
   | kontrakt → database | `340_api_column_contract_test.sql` (databasejobben) | at `api` har nøyaktig disse kolonnene, med nøyaktig disse typene |
   | kontrakt → TypeScript | `tests/api-columns.test.ts` (valideringsjobben) | at radtypene har nøyaktig disse egenskapene, med typer som svarer til SQL-typen |

   TypeScript-siden leser `values`-listen ut av pgTAP-filen. **Kryssleseren er ikke en
   bekvemmelighet, den er hele bindingen:** uten den ville de to halvdelene vært to
   uavhengige påstander, og typene ville fortsatt ikke vært knyttet til databasen. Parseren
   krever at hver ikke-tom linje i blokken lar seg lese og kaster ellers, slik at en
   omformatert liste stopper testen framfor å gjøre den stille sann på et avkortet utvalg.
   Det er samme regel som «fant ingen påstand» i `scripts/verify-counts.sh`.

2. **Nullbarhet kan ikke leses ut av katalogen; den må måles.** `information_schema.columns`
   svarer `is_nullable = 'YES'` for *hver* kolonne i et view — PostgreSQL gjør ingen
   nullbarhetsanalyse gjennom views. Den samme visningen kollapser dessuten hver array-kolonne
   til `data_type = 'ARRAY'` og taper elementtypen, som er nettopp det TypeScript-siden må vite
   for å skille `string[]` fra `number[]`. Begge begrensningene er festet som egne assertions
   framfor å stå som en kommentar ingen kontrollerer: skulle en framtidig PostgreSQL-versjon
   begynne å svare presist, feiler de, og da er probe-fiksturen ikke lenger den eneste veien.
   Typen leses derfor med `format_type()` fra `pg_attribute`.

3. **Nullbarheten måles på tre probe-former.** Filen publiserer sitt eget innhold inne i
   transaksjonen og ruller alt tilbake, som 260 og 290 — godkjenningen utføres av en aktør som
   opprettes der, slik at ingen fiktiv godkjenning blir stående (§12 i Constitution).
   Formene er valgt for å spenne ut kontrakten:

   | Form | Hva den demonstrerer |
   |---|---|
   | rik | hver valgfri kolonne bærer verdi; ekstraksjonen trekkes tilbake *etter* publisering, fordi gaten G6 nekter å publisere et underkjent grunnlag |
   | minimal | hver valgfri verdi utelatt, på påstand, evidensfunn og kilde; deterministisk faktum, så hele certainty-blokken er fraværende og ikke bare tom |
   | peker | publiseringspekeren flyttet utenom den kontrollerte operasjonen, som er den dokumenterte grunnen til at `published_at` og `last_reviewed_at` kan være NULL |

   Påstanden som kontrolleres er en `set_eq` i begge retninger: nøyaktig kontraktens nullbare
   kolonner er NULL i minst én probe-rad. En kolonne som blir nullbar dukker opp på venstre
   side; en nullbarhetspåstand uten dekning blir stående alene på høyre. En andre `set_eq`
   krever at hver kolonne bærer verdi et sted — uten den ville en kolonne som *alltid* er NULL,
   et uttrykk koblet til feil sted, passert så lenge kontrakten kalte den nullbar.

   Cellene hentes med `jsonb_each` over hele raden framfor kolonne for kolonne. Settet er da
   utledet av radens egen form, og en kolonne kan ikke glemmes.

4. **Hva målingen ikke beviser, og hva som derfor står igjen som gjeld.** En kolonne som blir
   nullbar fordi joinen, uttrykket eller projeksjonen endres, går NULL i den minimale raden og
   fanges. En basiskolonne som stille mister sin `NOT NULL`, fanges ikke: probe-fiksturen
   navngir kolonnen i sin `insert` og fortsetter å sette en verdi. Det er ført som gjeld i
   §74.7, og erstatter den gamle posten om at kontrakten ikke var kontrollert i det hele tatt.
   Kolonnenavn og kolonnetyper er derimot uttømmende dekket, i begge retninger.

5. **`number` er ett begrep i TypeScript og tre i SQL.** SQL-typen bestemmer hvilke skrevne
   TypeScript-typer som er tillatt, og `integer`, `bigint` og `numeric` tillater alle `number`.
   Det er ikke en slapphet: språket har ikke skillet, og kontrakten kan ikke påstå et skille
   den ikke kan holde. Presisjonen ligger i SQL-typen, som pgTAP-filen kontrollerer mot
   katalogen. En SQL-type kontrakten ikke kjenner kaster framfor å gli forbi.

6. **Typene leses fra AST-en, ikke fra typecheckeren.** `Uuid`, `Timestamptz`, `DateText` og
   `IntervalText` er alle alias for `string`. En typechecker ville løst dem opp og mistet
   nettopp skillet kontrakten handler om — en `uuid` er ikke en `date`. `ts.createSourceFile`
   parser filen uten å typesjekke den, og medlemmets annotasjon leses som skrevet. At de fire
   faktisk *er* alias for `string`, og at de lukkede vokabularene er `(typeof X)[number]` over
   en `as const`-liste, utledes fra samme fil framfor å listes opp — et nytt vokabular blir da
   gjenkjent uten en endring to steder.

7. **Kartet fra view til radtype leses ut av `Database`-typen.** Det er ikke skrevet ned i
   testen. Et nytt view i kontrakten må derfor også være erklært for supabase-js for at
   kontrollen skal gå opp, og et view som fjernes fra `Database` uten å fjernes fra kontrakten
   slår ut på samme måte.

8. **En arvet påstand rettet: «de åtte lukkede unionene» var fjorten.** Gjeldsposten som nå er
   erstattet sa at `tests/api-vocabularies.test.ts` kontrollerer «hver av de åtte lukkede
   unionene». Filen kontrollerer fjorten. Tallet åtte hører til §74.15 punkt 4, der det er
   riktig: åtte er antallet vokabularer *evidensvisningen forgrener på*, og som derfor fikk
   kjøretidskontroll. De to tallene hadde glidd sammen. Feilen er av samme klasse som de sju
   §74.8 og §74.18 beskriver, og ble funnet ved å telle `export const`-listene i `api.ts` —
   ikke ved å lese setningen på nytt.

9. **Mutasjonstesting, og to feller harnessen gikk i.** 44 mutasjoner er innført og 42 drept: mot
   kontraktslisten (navn, type, rad fjernet, rad lagt til, nullbarhet snudd begge veier,
   `date` forvekslet med `timestamptz`, array skrevet som skalar), mot probe-fiksturen
   (pekerraden fjernet, tilbaketrekkingen slått av, `evidence_gap` tømt, kildeversjonen
   fjernet, DOI-en fjernet, testvirkestoffet gitt en ATC-kode), mot viewene og granten i
   migrasjonene (kolonne omdøpt, kolonnetype endret, kolonne gjort alltid NULL, `left join`
   gjort til `join`, ny kolonne lagt til, kolonnegrant fjernet), mot radtypene i `src/types/`
   (egenskap omdøpt, slettet, lagt til, `| null` fjernet og lagt til, alias brutt, vokabular
   gjort til bar `string`, view fjernet fra `Database`) og mot selve assertionene. De to som
   overlever er begge forstått: en bevisst no-op (` and true` føyd til en `where`-betingelse),
   som skal overleve og bekrefter at harnessen ikke rapporterer drap den ikke har gjort; og en
   flytting av den minimale påstanden til et virkestoff med ATC-kode, som overlever fordi
   pekerpåstanden dekker `atc_codes` NULL uansett — den skarpere mutasjonen, som gir
   *testvirkestoffet* en ATC-kode, dreper testen. Harnessen avviste i tillegg en identisk
   erstatning som no-op og tre mønstre med null treff som tvetydige, framfor å telle dem som
   kjørte mutasjoner.

   **Og forutsetningen, ikke bare implementasjonen:** `tests/api-columns.test.ts` hviler på at
   assertion 3 i pgTAP-filen faktisk binder kontrakten til databasen. Slettes den, passerer
   TypeScript-siden mens kjeden er brutt. Mutasjonen ble innført, og pgTAP feiler høyt —
   `plan(11)` stemmer ikke lenger med antall kjørte assertions. Justeres planen med, endrer
   totalen seg, og `scripts/verify-counts.sh` slår ut mot §74.2. Kjeden er dermed lukket i
   begge ledd.

   To feller kostet tid, og begge er verdt å kjenne for neste mutasjonskjøring:

   - **`git checkout --` gjenoppretter ikke en usporet fil.** De to nye filene var ennå ikke
     lagt til i indeksen, så gjenopprettingen feilet stille og lot mutasjonen bli stående.
     Neste mutasjon målte da mot en rød grunnlinje — nøyaktig den tilstanden der *hver*
     mutasjon rapporterer seg som drept. Grunnlinjekontrollen fanget det og avbrøt.
     Harnessen kopierer nå filene til et sikkerhetskopi-katalog framfor å stole på git.
   - **Rå `psql` feiler ikke på en plan som ikke stemmer.** `pg_prove`, som
     `supabase test db` bruker, behandler «Looks like you planned 11 but ran 10» som en feil;
     `psql -f` skriver den som en kommentar og avslutter med 0. Et lokalt harness som bare
     teller `^not ok` er derfor blindt for en slettet assertion. Det var nettopp den
     mutasjonen som skulle måles, og den så ut til å overleve til harnessen ble rettet.

---

### 74.20 Hva autorisasjonen av redaktøren innførte

`db: authorize the named qualified editor` er migrasjon 005b. Den fullfører det 005a bevisst
lot stå åpent: aktørraden knyttes til redaktørens brukerkonto, og `reviewer`-rollen tildeles.
Den oppretter ingen tabell og ingen enum-type. Den legger til én funksjon og skriver to rader
— i miljøer der brukerkontoen finnes.

**Migrasjonen er miljøavhengig, og det er valget §74.18 tok.** `workflow.user_roles.user_id`
er `NOT NULL` med fremmednøkkel til `auth.users`. Kontoen finnes bare i det hostede
prosjektet; CI og lokal utvikling starter en fersk stack uten den. «Vei a» gjør koblingen
betinget av at kontoen finnes, framfor å dikte opp en konto lokalt eller å holde
rolletildelingen utenfor de versjonerte migrasjonene. Prisen i tabellen der — at CI ellers
aldri ville kjørt den grenen som faktisk kjører i produksjon — er betalt på tre måter, og de
henger sammen:

1. **Raden uteblir ikke i stillhet.** Mangler kontoen, returnerer funksjonen statusen
   `account_missing` og gir i tillegg en synlig `notice` i utdataene fra `supabase db push`
   og `supabase db reset`. Det samme gjelder de to andre tilstandene der funksjonen bevisst
   ikke skriver, `role_not_yet_valid` og `role_ended`.

2. **Logikken ligger i én navngitt funksjon, ikke som løse setninger i migrasjonsfilen.**
   `workflow.ensure_named_editor_authorization()` er det ene stedet koblingen og tildelingen
   er beskrevet, og både migrasjonen og testen kaller den. Alternativet — å skrive setningene
   rett i filen og la testen gjenta dem — ville gitt to påstander som kan drive fra
   hverandre, og testen ville da kontrollert en kopi framfor produksjonsveien. Det er samme
   form som kolonnekontrakten i §74.19 punkt 2, av samme grunn.

3. **Begge grenene kjøres i CI.** `350_editor_authorization_test.sql` kaller funksjonen i
   migrert tilstand og krever `account_missing` og at ingenting skrives, oppretter så kontoen
   inne i transaksjonen som rulles tilbake og kjører hele produksjonsveien: kobling,
   tildeling, auditrad, idempotens og virkningen på kvalifikasjonskontrollen.

**Funksjonen blir stående, og det er en del av vei a.** Koblingen kan bli stående ugjort i et
miljø der kontoen kommer senere. Da skal den kunne fullføres med ett kall til, ikke med en ny
migrasjon som bærer en andre kopi av logikken. Funksjonen tar ingen parametere: både kontoens
`uuid` og aktørens `actor_key` er konstanter i kroppen, så den kan bare gjøre denne ene
tildelingen. En parameterisert utgave ville vært en generell «gi hvem som helst
reviewer»-funksjon — en rettighetseskalering med et vennlig navn. `EXECUTE` er trukket fra
`PUBLIC`, og klientrollene har uansett ikke `usage` på `workflow`.

**Tre vakter, fordi en betinget migrasjon har flere måter å ta feil på enn en ubetinget:**

- Mangler aktørraden fra 005a, feiler funksjonen høyt med `no_data_found`. Uten den vakten
  ville en brutt migrasjonskjede sett ut som «kontoen manglet», altså som den normale,
  forventede grenen.
- Peker aktøren allerede på en *annen* brukerkonto, feiler funksjonen med
  `restrict_violation`. Uten den ville rollen blitt tildelt en konto som ikke er bundet til
  redaktøraktøren — en rettighet uten den attribusjonen den hviler på, og
  `provenance.freeze_actor_identity()` ville uansett nektet å flytte koblingen etterpå.
- Et andre kall tildeler ikke rollen på nytt. Uten den vakten ville
  `user_roles_no_overlapping_grant_excl` avvist kallet, og «kjør den én gang til i miljøet der
  kontoen finnes» ville ikke vært en vei.

**Selvtildelingen står i raden, ikke i en kommentar.** Beslutningen ble tatt i §74.17 punkt 3:
`granted_by_actor_id` peker på redaktørens egen aktør, fordi alternativet ville gjort en
KI-aktør til opphavet til et menneskes faglige godkjenningsrett (§10, §12). Ingen `CHECK`
forbyr selvtildeling, så `grant_reason` er hele sikringen. Testen krever at ordet
«Selvtildeling» står *først* i begrunnelsen og ikke bare et sted i den: et treff hvor som
helst i feltet ville også slått ut på en benektelse av det (§74.16-lærdommen om ordlyd).
`scope_id` er `NULL` — «uten avgrensning», ikke «ukjent avgrensning».

**Hva raden ikke gjør.** Den åpner ikke publiseringsgaten. G4/G5, G8/G9 og G13 er urørt, og
assertion 14 prøver det framfor å påstå det: gaten stopper fortsatt på den manglende
ekstraksjonsverifikasjonen. Den lukker heller ikke governance-hullet fra §74.17 —
kompetansekravet for reviewer-scope er fortsatt udefinert, og redaktøren er utpekt av seg
selv. Det står i `grant_reason` framfor å bli borte.

**220 er justert, ikke omgått — og hand-offen inn hit tok feil om hvordan.** Hand-offen sa at
tre assertioner i `220_provenance_seed_test.sql` ville bli røde, og at den negative
throws_ok-testen måtte erstattes fordi godkjenningen etter migrasjonen ville blitt avvist av
en annen grunn. Det stemmer ikke for vei a: i CI finnes ikke kontoen, migrasjonen skriver
ingenting, og alle tre assertionene er like sanne som før. Suiten ble kjørt med migrasjonen på
plass og uten en eneste endring i 220 — 1109 av 1109 passerte. **Dette er niende gang en
påstand som ble ført videre fra en hand-off eller en gjeldspost, har vært feil** (§74.4,
§74.8, §74.18). Den ble funnet ved å kjøre suiten framfor ved å lese setningen på nytt.

**Men den riktige justeringen var en annen, og den var viktigere.** At assertionene i 220
fortsatt er sanne, er nettopp problemet: de ville vært like sanne om migrasjon 005b aldri
hadde kjørt. En påstand om at noe ikke finnes, sier ingenting om koden som valgte å ikke
skrive det. Derfor binder assertion 1-3 i 350 den negative grenen til selve funksjonen ved å
*kalle* den og kreve at kallet ikke skriver noe. 220 beholder sine assertioner om tilstanden
og sier nå i klartekst hva de ikke dekker.

**Beslutningen om `changes_requested` framfor `approved`.** Assertion 13 er speilbildet av den
negative testen i 220: den samme handlingen som avvises uten brukerkonto, skal gå gjennom med
konto og rolle. Beslutningen som registreres er likevel `changes_requested`.
`workflow.enforce_reviewer_qualification()` leser verken beslutningstype eller utfall, så
assertionen blir ikke svakere av det — mens en `approved` ville vært en registrert faglig
godkjenning uten at noen har gjennomgått noe. At transaksjonen rulles tilbake, gjør den ikke
mindre fiktiv mens den står (`ANTIDEP_CONSTITUTION.md` §12).

**Hva som ble verifisert.** Migrasjonene er kjørt fra bunnen av og hele pgTAP-suiten er kjørt
mot en lokal PostgreSQL 16 med pgTAP; Docker-registryene svarer 403 gjennom egress-proxyen, så
`npx supabase start` er ikke tilgjengelig, og CI kjører den ekte stacken. Grunnlinjen før
endringen var 1109 passerende assertions, etter endringen 1136, uten `not ok`, uten planavvik
og uten `ERROR`. `npm run lint`, `npm run format:check`, `npm run typecheck`, `npm run test`,
`npm run build` og `./scripts/verify-counts.sh` er kjørt og passerer.

Trettifem mutasjoner er innført én om gangen — tjueni i SQL, seks i planens tallpåstander — og
trettifire fanges. Den som overlever er `raise notice` degradert til `raise debug`: pgTAP kan
ikke observere en `notice`, så den halvdelen av kravet i §74.18 er ikke maskinelt kontrollert.
Det er registrert som gjeld i §74.7 framfor å bli stående som en kommentar. Statusen
funksjonen returnerer, er den halvdelen som *er* kontrollert, og den er nettopp derfor et
returnert felt og ikke bare en `notice`.

**Vaktposten er lukket i begge ledd, som i §74.19.** Fjernes en assertion fra
`350_editor_authorization_test.sql` uten at planen justeres, feiler pgTAP på «Looks like you
planned 27 tests but ran 26». Justeres `plan()` med, blir pgTAP stille — og da slår
`scripts/verify-counts.sh` ut mot §74.2, fordi summen av `plan(N)` ikke lenger er 1136. Begge
utveier er stengt, og det er prøvd og ikke antatt.

**Den viktigste mutasjonen traff forutsetningen, ikke implementasjonen.** Assertion 13 hviler
på at rolletildelingen er det som gjør kvalifikasjonskontrollen tilfreds. Den påstanden er
lånt hvis ingenting håndhever at rollen er *nødvendig* — en `lives_ok` passerer like godt om
kravet ikke finnes. Rollekravet i `workflow.enforce_reviewer_qualification()` ble derfor slått
av i migrasjon 005, og `190_workflow_constraints_test.sql` feilet på fem assertioner, blant
dem «editor- og admin-rollene gir ikke faglig godkjenningsrett». En variant der `editor` også
kvalifiserte, ble fanget av de samme. Begge ledd er dermed lukket: at rollen åpner kontrollen,
er prøvd her; at den er nødvendig for å åpne den, er prøvd i 190.

**Reviewen fant en feil i «allerede tildelt», og den var reell.** Første utgave av
funksjonen leste en eksisterende tildeling som `valid_to is null`. `workflow.user_roles` er
ikke et flagg, men en gyldighetsmodell: intervallet er halvåpent, og `valid_to` kan være satt
allerede ved tildeling som en planlagt utløpsdato. Tre lovlige tilstander ble derfor håndtert
feil, og alle tre er reprodusert mot databasen før de ble rettet:

| Tilstand | Hva som skjedde | Hva som skjer nå |
|---|---|---|
| Tidsavgrenset, men gyldig nå | Raden ble lest som fraværende, en ny tildeling forsøkt skrevet, og `user_roles_no_overlapping_grant_excl` avviste den. Funksjonen feilet i stedet for å svare — en `supabase db push` ville stoppet | `already_authorized`, ingenting skrives |
| Begynner å gjelde senere | `already_authorized`, mens null tildelinger faktisk var gyldige. En autorisasjonskontroll som svarer «autorisert» om noe som ikke gjelder | `role_not_yet_valid`, ingenting skrives |
| Avsluttet | `authorized`: rettigheten ble stille gjeninnført, og tilbakekallingen omgjort av en migrasjonskjøring | `role_ended`, ingenting skrives |

**Den avsluttede tildelingen var den farligste, og valget der er bevisst.** `DATABASE_ARCHITECTURE.md`
§46 krever at en rettighet skal kunne tilbakekalles umiddelbart, og en tilbakekalling som en
rutinemessig `supabase db push` omgjør, er ingen tilbakekalling. `workflow.freeze_role_grant()`
sier det samme om modellen: en gjeninnføring er en ny tildeling med sin egen begrunnelse — og
en slik begrunnelse kan ikke dikte seg selv opp i en bootstrap. Funksjonen rapporterer derfor
og lar et menneske avgjøre. Det er også det mest reversible: å nekte kan et menneske overstyre,
å gjeninnføre i stillhet kan ingen oppdage.

Returverdiene er utvidet fra tre til fem, og bare `authorized` skriver noe. Presedensen mellom
dem er skrevet ut i funksjonen framfor å falle ut av rekkefølgen på tre uavhengige kontroller:
en løpende tildeling ved siden av en avsluttet betyr at rettigheten gjelder, og det motsatte
svaret ville vært feil på den farligste måten en autorisasjonskontroll kan ta feil.

Gyldighet måles med `statement_timestamp()` og ikke med `now()`. §74.6 ber uttrykkelig den som
skriver ny autorisasjons- eller gyldighetslogikk om å lese skillet først: `now()` er
transaksjonens starttidspunkt, så en tildeling som trådte i kraft mens transaksjonen løp, ville
blitt lest som «gjelder ikke ennå» så lenge transaksjonen varte. Assertion 23 gjør vinduet
deterministisk med `pg_sleep` framfor å hvile på at to setninger tilfeldigvis får ulike
tidsstempler.

To hull til ble funnet av mutasjonstestingen og ikke av reviewen: uten `scope_id is null` og
`role_code = 'reviewer'` i oppslaget ville en *avgrenset* reviewer-tildeling eller en
`editor`-tildeling blitt lest som «allerede autorisert», og redaktøren ville stille sittet igjen
med en smalere rettighet enn migrasjonen skal gi. Begge har nå hver sin assertion.

**En sjette felle for mutasjonsharnessen, funnet her.** `F2` — å slå av vernet mot at en
avsluttet tildeling gjenåpnes — rapporterte seg først som overlevende. Mutasjonen traff
definisjonen i migrasjon 005, men migrasjon 008 gjør `create or replace` på den samme
funksjonen, så den muterte definisjonen var død kode. **En mutasjon av en definisjon en senere
migrasjon erstatter, er en stille no-op som ser ut som et hull i testdekningen.** Kontrollen er
å lese `prosrc` fra `pg_proc` og bekrefte at mutasjonen faktisk står i den lastede kroppen.
Mot den gjeldende definisjonen ble mutasjonen drept.

**Og en syvende: harnessen gjenopprettet filene, men ikke databasen.** Etter siste mutasjon i en
batch lå den muterte funksjonen fortsatt i basen, og neste kjøring målte mot den. To assertioner
så ut til å feile mot kode som var korrekt på disk. Gjenopprettingen må kjøre `reset` til slutt,
ikke bare skrive filene tilbake.

**Hva som gjenstår.** Milepæl B mangler fortsatt fire ting (§74.4). Den første venter ikke
lenger på kode, men på at migrasjonene kjøres mot det hostede prosjektet — en egen oppgave som
hører hos prosjekteieren (§74.18). De neste to, ekstraksjons- og claim-verifikasjonene, kan
være agentproduserte så lenge §10 og §11 holdes; den fjerde, godkjenningen, kan ikke.

### 74.21 Hva den autentiserte leseveien innførte

`db: expose the caller's own actor and roles` er migrasjon 007b. Den utvider api-lesemodellen
fra §24 slik 007a gjorde, og står derfor utenfor den planlagte rekken. Den oppretter to views,
to RLS-policyer og to kolonnegrants. Den oppretter ingen tabell, ingen enum-type og ingen
funksjon, og den skriver ingen rad.

**Hvorfor akkurat denne, og hvorfor nå.** «Manuell adminflyt» er den ene leveransen §29 lister
for Slice 1 som ikke er bygget, og den kan ikke begynne noe sted: hver eneste skjerm i den må
først kunne svare på «hvem er jeg, og hva har jeg lov til?». Fram til nå kunne ingen klient
svare på noen av delene. `workflow.user_roles` og `provenance.actors` var begge helt stengt —
ingen grant, ingen policy, default deny — og det er fortsatt riktig for alt annet enn kallerens
egne rader. Migrasjonen er derfor det minste defensive førstesteget: en ren lesevei, ingen
skrivevei, ingen ny rettighet. Den gjør bare en rettighet som allerede finnes, lesbar for den
som har den.

**To spørsmål, to views, og det er en kardinalitetsbeslutning.** En kaller har null eller én
aktør, og null til mange rolletildelinger. Slått sammen til ett view måtte identiteten enten
forsvinne når det ikke finnes noen rolletildeling — og et tomt svar sier da ingenting om
aktøren, som er nøyaktig feilen §74.14 punkt 6 beskriver — eller bæres som en array. To views
gir i stedet hver sitt tomme tilfelle med entydig betydning:

```text
api.my_actor  tom   ingen aktørrad er knyttet til denne brukerkontoen
api.my_roles  tom   kalleren har ingen rolletildeling som gjelder nå
```

Ingen av dem svarer på det sammensatte spørsmålet «kan jeg utføre handling X». Det er
adminflytens jobb, og den bygges over disse to. En avledet «du har lov»-verdi her ville flyttet
en autorisasjonsbeslutning inn i en projeksjon, og den ville uansett ikke vært den som gjelder:
skriveoperasjonene kontrollerer rettigheten selv, på sin egen setnings tidspunkt.

**Fire lås, og den fjerde er den som avgjør hva av raden som kan leses.** De tre første er de
samme som i §74.9: manglende schema-`usage`, RLS som radgrense, og bare `SELECT`. Den fjerde er
kolonnegranten fra §74.11 punkt 3, og her bærer den mer enn i 007a. Radene policyene slipper
gjennom inneholder også `grant_reason`, `granted_by_actor_id`, `end_reason` og aktørens
`description` og `retirement_note`. Ingen av dem er kallerens svar på «hva har jeg lov til» —
de er governance-tekst om beslutningen, skrevet for en revisor og ikke for innehaveren — og de
er utenfor granten.

**`anon` får ingenting, og det er et valg og ikke en forglemmelse.** Begge policyene gjelder
bare `authenticated`, og ingen av viewene er lesbare for `anon`. En uinnlogget kaller får
avslag framfor et tomt svar, fordi et tomt svar allerede betyr noe helt annet her.

**Eierskapet ligger i policyen, gyldigheten i viewet.** De to predikatene beskytter forskjellige
ting, og det avgjorde hvor de hører hjemme:

| Predikat | Hva det er | Hvor det ligger |
|---|---|---|
| `user_id = auth.uid()` | En sikkerhetsgrense. En kaller skal aldri se en annens rolletildeling | RLS, og gjentatt i viewet slik §74.9 gjentar publiseringspredikatet: hvert lag skal være korrekt alene |
| gyldig nå | En projeksjonsbeslutning. En avsluttet tildeling er kallerens *egen* historikk, ikke en annens data | Viewet. I RLS ville den låst en senere projeksjon av kallerens rollehistorikk ute av sin egen tabell |

**Gyldighetsmodellen er den samme som felte 005b, og den er behandlet deretter.**
`workflow.user_roles` er ikke et flagg: intervallet er halvåpent `[valid_from, valid_to)`, og
`valid_to` kan være satt allerede ved tildeling som en planlagt utløpsdato. Viewet spør derfor
om begge grensene, ikke om `valid_to is null`. Uten den nedre grensen ville en tildeling som
først begynner å gjelde senere blitt lest som gjeldende — en rettighet før den er gitt. Tiden
måles med `statement_timestamp()` og ikke `now()`, etter regelen i §74.6, og det er prøvd og
ikke bare påstått: fiksturen i `360_caller_authorization_test.sql` legger én tildeling som trer
i kraft og én som utløper *mens transaksjonen løper*, og gjør vinduet deterministisk med
`pg_sleep` framfor å hvile på at to setninger tilfeldigvis får ulike tidsstempler. Med `now()`
feiler begge, hver sin vei.

**To kolonner er utelatt fordi en databaseregel gjør dem informasjonsløse, og begge reglene
prøves framfor å telles.** Det er den formen §74.20 etablerte, og den er brukt igjen her:

1. `api.my_actor` projiserer ikke aktørtypen. `actors_auth_user_is_human_check` håndhever at
   bare et menneske kan ha en brukerkonto, så kolonnen ville hatt nøyaktig én mulig verdi for
   hver rad viewet kan vise. Testen forsøker å opprette en KI-aktør med brukerkonto og krever
   at databasen avviser det. Faller regelen bort, feiler testen — og da er kolonnen ikke lenger
   informasjonsløs, for da kan viewet skjule at kalleren er en KI-aktør.
2. `api.my_roles` projiserer ikke tildelingens `id`. Innenfor settet viewet viser, er
   `(role_code, scope_id)` allerede entydig: to tildelinger som begge gjelder nå ville
   overlappet i tid, og `user_roles_no_overlapping_grant_excl` forbyr det. Testen forsøker den
   overlappende innsettingen og krever `23P01`, og forsøker deretter den *avgrensede*
   tildelingen av samme rolle og krever at den går gjennom — avgrensningen er en del av nøkkelen
   og ikke en detalj ved siden av den.

**Vaktposten som ikke så kolonnegrant, ser den nå.** `030_conventions_test.sql` regel 8a og 8b
leste `pg_class.relacl`, som ikke bærer kolonnegrant; `pg_attribute.attacl` gjør det. Regelen
sluttet dermed å måle i det migrasjon 007a tok formen i bruk, uten å feile — en migrasjon kunne
åpnet en enkeltkolonne uten policy under, eller gitt en skriverett på kolonnenivå, og gått
gjennom. Begge grenene leser nå `attacl` i tillegg, og begge er selvtestet med et bevisst brudd
og med den konforme formen ved siden av, slik at reglene ikke kan være trivielt oppfylt ved å
flagge hvert kolonnegrant. Samme blindsone er rettet i `290_api_read_model_access_test.sql`:
inventaret over hvilke kanoniske tabeller `api` har åpnet, sa «tretten» mens seksten var åpnet,
fordi tre av dem bare er åpnet på kolonnenivå.

**Kolonnekontrakten måler nå fem views, og probe-radene er blitt eksplisitte om hvem som leste
dem.** De to nye viewene er ikke lesbare for `anon` og krever hver sin innloggede kaller — én
med en aktør som ikke er trukket tilbake og to tildelinger som til sammen dekker begge formene
av scope og sluttdato, og én med en tilbaketrukket aktør, slik at `retired_at` bærer verdi i
minst én rad. Cellene kan derfor ikke leses i én spørring. De materialiseres i stedet i en
temptabell under den rollen og med det tokenet som faktisk skal kunne lese dem, og sammenlignes
etterpå. Det er en innstramming: før ble cellene lest av en `set_eq` som tilfeldigvis kjørte som
`anon`. En ny assertion krever i tillegg at hvert view i kontrakten faktisk har bidratt med
celler — uten den ville et view som ingen probe-rad traff falt helt ut av begge sammenligningene,
og de to feilene ville pekt hver sin vei og lest som «kontrakten er for lang».

**Hva migrasjonen bevisst ikke gjør.** Den tildeler ingenting, endrer ingenting og oppretter
ingen aktør. En kaller uten aktørrad får et tomt `api.my_actor`, ikke en rad opprettet på
forespørsel: aktørregisteret er festepunktet for all attribusjon (`ANTIDEP_CONSTITUTION.md`
§14), og en aktør som oppstår fordi noen logget inn ville vært en identitet systemet selv fant
på. Skriveveien er urørt og forblir en kontrollert `SECURITY DEFINER`-funksjon
(`DATABASE_ARCHITECTURE.md` §43).

**To poster ført som gjeld (§74.7).** Et tomt `api.my_roles` skiller ikke en utløpt tildeling
fra en som aldri fantes, og `scope_id` kan ikke slås opp til en etikett. Begge er bevisste valg
med en pris, og prisen er skrevet ned framfor å bli oppdaget av den som bygger adminskjermen.

**Mutasjonstestet: 21 mutasjoner innført, 21 drept.** Tretten på migrasjonen — begge
policyene åpnet, `anon` sluppet inn på policy og på view, `grant_reason` og aktørens
`description` lagt til i kolonnegranten, hver av de to gyldighetsgrensene fjernet,
`statement_timestamp()` byttet til `now()`, hvert av de to viewenes eget eierskapspredikat
fjernet, `scope_type` projisert som konstant `NULL`, og `security_invoker` fjernet. To på de
utvidede grenene i regel 8a og 8b, tre på TypeScript-siden, og tre på kolonnekontrakten. Hver
av dem er kontrollert mot hvilken assertion som faktisk felte den, ikke bare mot at *noe*
feilet — en mutasjon drept av en urelatert assertion er et svakere signal enn det ser ut som.
De to som er verdt å nevne særskilt: `valid_to is null` — feilen fra 005b — felles av at den
avgrensede tildelingen med planlagt utløp forsvinner fra `api.my_roles`, og `now()` felles av
begge de to `pg_sleep`-testene, hver sin vei.

**Hva som gjenstår.** Milepæl B mangler fortsatt de samme fire tingene (§74.4). Denne
migrasjonen lukker ingen av dem, og den er heller ikke ment å gjøre det: den åpner det første
leddet i adminflyten, som er der de tre siste faktisk kan utføres.

---

### 74.22 Hva innlogging og min tilgang innførte

`feat: add sign-in and my access` er Steg 1 av «manuell adminflyt» (§29): innlogging, og et
svar på «hvem er jeg, og hva har jeg lov til?», bygget over den autentiserte leseveien
migrasjon 007b åpnet (§74.21). Ingen migrasjon: viewene og grantene fra 007b er nok for Steg 1.
Steg 2 — skriveveien/RPC-laget (DATABASE_ARCHITECTURE.md §43, §48) — og Spor 2 —
verifikasjon/godkjenning — hører til senere PR-er, og er ikke rørt her.

**Én side, ikke to.** `/access` («Min tilgang») er den samme adressen for en uinnlogget og en
innlogget kaller. En uinnlogget kaller ser innloggingsskjemaet der en innlogget kaller ser
svaret, og siden selv — ikke en ruteforgrening — avgjør hvilket av de to som vises
(`src/app/pages/AccessPage.tsx`). To sider, én for hver tilstand, ville latt ordlyden på de to
drive fra hverandre på nøyaktig den måten §74.16 og §74.20 allerede har dokumentert at skjer
når samme sannhet skrives to steder.

**FELLE 1 — sesjonen er en inngang til spørringen, ikke en omgivelse rundt den.**
`useReadModel()` kjører bare på nytt når spørringens referanse endres, og innlogging endrer
ingen parameter på `fetchCallerActor`/`fetchCallerRoles` — samme funksjon, samme referanse.
Uten et eksplisitt grep ville siden fortsatt vist svaret fra før innlogging. Løsningen er
strukturell, ikke en sesjonsnøkkel i en `useCallback`-avhengighet: `AccessPage` forgrener på
innloggingsstatus (`useAuthSession()`, ny hook i `src/app/use-auth-session.ts`, som abonnerer på
`client.auth.onAuthStateChange()`), og komponenten som faktisk kaller de to lesefunksjonene
finnes ikke i treet før kalleren er innlogget. En innlogging bytter dermed hele undertreet, og
en førstegangsmontering er per konstruksjon en frisk spørring — ingen nøkkel å holde i sync.
Testet direkte: `use-auth-session.test.tsx` beviser at hooken oppdager en innlogging og en
utlogging via abonnementet alene, og `AccessPage.test.tsx` beviser at ingen spørring mot
`api.my_actor`/`api.my_roles` kjører før innlogging, og at begge kjører rett etter — mutert ved
å la komponenten montere uforgrenet, som felte fire av ti tester i den filen.

**FELLE 2 — fire tilstander, ikke tre.** `ReadModelResult` er `ok | empty | error`, og
`useReadModel()` legger til `loading`. En uinnlogget kaller mot `api.my_actor` ville fått 42501
fra RLS og blitt lest som `error` — feil beskjed, og nøyaktig den samme sammenblandingen av feil
og fravær §74.12 punkt 1 allerede forbyr på klinikerflaten. Den unngås strukturelt av samme
grep som løser FELLE 1: spørringene kjører aldri før kalleren er innlogget, så en uinnlogget
kaller ser aldri `error` — den ser innloggingsskjemaet. De fire tilstandene `AccessPage` skiller,
med hver sin ordlyd:

```text
ikke innlogget            innloggingsskjemaet
innlogget, ingen aktør    «Kontoen din er ikke knyttet til en person i Antidep»
innlogget, ingen roller   «Du har ingen rettighet nå»
feil                      «Antidep fikk ikke hentet informasjon om tilgangen din»
```

Aktør og roller er to uavhengige spørringer, og siden venter bevisst på at begge er ferdige før
den viser noe annet enn «laster»: et svar som konkluderte «ingen aktør» mens rollene fortsatt
lastet, ville vært en forhastet konklusjon presentert som endelig.

**FELLE 3 — egen modul, ikke `published-read-model.ts`.** Kallerens egne roller er ikke
publisert kunnskap og har en annen tomhetssemantikk: en tom `api.my_actor` betyr «ingen aktør
er knyttet til denne kontoen», en tom `api.my_roles` betyr «ingen rettighet nå» — to navngitte
tomhetsformer, ikke lesemodellens ene generiske `empty`. Fetch-funksjonene ligger derfor i en ny
modul, `src/lib/caller-authorization.ts`, med sin egen resultattype
(`CallerActorResult`/`CallerRolesResult`, med variantene `ok | no_actor | error` og
`ok | no_roles | error`). Sorteringsdoktrinen fra `published-read-model.ts` gjelder heller ikke:
rekkefølgen på en persons roller er ingen vekting, bare en stabil rekkefølge mellom kall
(sortert på `role_code`). `useReadModel()` selv er generalisert til å være generisk over
resultattypen — `Result` utledes nå direkte av spørringens returtype, og trenger ingen egen
`Row`-parameter — slik at hentelogikken (klientoppslag, stale-response-vakten fra §74.14 punkt
4, feilfanging) er felles uten at de to modulenes betydninger flates ut. Ingen eksisterende
kallsted i `published-read-model.ts`-familien trengte å endres: `Result` faller tilbake til
`ReadModelResult<Row>` når ingenting annet er oppgitt.

**FELLE 4 — ingen «du har lov»-boolean i klienten.** Viewene svarer på hva kalleren HAR, ikke
hva kalleren KAN — det sier migrasjon 007b eksplisitt (§74.21), og klienten skal ikke regne ut
en autorisasjonsbeslutning en projeksjon ikke bærer. En tilbaketrukket aktør
(`retired_at` satt) har fortsatt sine rolletildelinger i `api.my_roles`, men
`knowledge.assert_publisher_authorized(uuid, uuid)` avviser den likevel på sitt eget tidspunkt.
Siden viser derfor rollene *og* et eksplisitt varsel side om side når aktøren er tilbaketrukket
— aldri ved å skjule rollene, som ville vært en stille og feil «ingen rettighet», og aldri uten
varselet, som ville lovet en handling systemet avviser.

**To gjeldsposter fra §74.7 er bevisst ikke utvidet.** `api.my_roles.scope_id` kan ikke slås opp
til en etikett, og skiller ikke en utløpt tildeling fra en som aldri fantes. Siden viser
«avgrenset til et bestemt klinisk begrep» uten navnet, med samme ordlydsmønster som
`superseded_by_source_id`-merknaden på kildesiden (§74.16 punkt 5): en identitet klienten ikke
kan slå opp, er ikke et svar. Ingen ny historikk-projeksjon er bygget for Steg 1.

**Nettleserverifisering.** Chromium (`/opt/pw-browsers/chromium`) kjørt headless med
devtools-protokollen direkte over Node 22 sin innebygde `WebSocket` — Playwright er ikke
installert. En midlertidig `preview.html`/`src/preview-main.tsx` rendret `AppLayout` i en
`MemoryRouter` på `/access` med `fakeClient()`, styrt fra en query-parameter, og dekket alle
tilstandene fra FELLE 2 og tilbaketrekkingsvarselet fra FELLE 4 på både mobil- (390px) og
skrivebordsbredde (1280px) — 14 kombinasjoner, ingen `Runtime.exceptionThrown` og ingen
konsollfeil i noen av dem. Innloggingsskjemaet, et avvist forsøk og utlogging ble i tillegg
øvd direkte i nettleseren (skrevet inn med den samme native-verdisetter-teknikken React
kontrollerte felt krever, ikke bare i jsdom), og viste seg identisk med den automatiserte
testpakken. Begge filene er slettet før commit, som instruert.

**Mutasjonstestet.** FELLE 1, FELLE 2 og FELLE 4 er hver mutert og bekreftet fanget: montering
uforgrenet av innloggingsstatus felte fire av ti tester i `AccessPage.test.tsx`; å behandle
`no_actor` som `error` felte den testen som ber om nettopp det skillet; å slutte å rendre
tilbaketrekkingsvarselet felte både den testen og testen som krever at varselet *ikke* vises
for en aktør som ikke er tilbaketrukket. Hele testpakken teller nå 771 passerende tester, opp
fra 740 ved sesjonsstart.

**Rettelse etter teknisk review.** `SignOutButton` kalte først `client.auth.signOut()` uten
`scope`. supabase-js sin standard er `'global'` — logger kalleren ut av *alle* enheter og
nettlesere kontoen er innlogget på, ikke bare denne fanen — en overraskende sideeffekt for en
knapp merket «Logg ut», og ikke et krav noe sted i denne planen. Rettet til
`signOut({ scope: 'local' })`. Faken i `test-support.tsx` registrerer nå det faktiske
`signOut()`-kallet, og en egen test krever `{ scope: 'local' }` — mutert til det opprinnelige
kallet uten `scope` og bekreftet at nettopp den testen feiler.

**Hva som gjenstår.** Steg 2 av adminflyten — den kontrollerte skriveveien admin-RPC-laget
(DATABASE_ARCHITECTURE.md §43, §48) — er ikke bygget. Spor 2 (verifikasjon og godkjenning) er
heller ikke rørt. Milepæl B mangler fortsatt de samme fire tingene den har gjort siden §74.4:
denne PR-en lukker ingen av dem, og er ikke ment å gjøre det.

---

### 74.23 Det hostede prosjektet er migrert, og `api` er eksponert

**Funnet, og det motsier §74.18.** Det hostede prosjektet er ikke tomt. Alle tretten
migrasjonene fra `main` er kjørt der og registrert i `supabase_migrations.schema_migrations`,
med nøyaktig de samme tretten versjonsnumrene og navnene som filene i `supabase/migrations/`.
Schemaene `api`, `catalog`, `knowledge`, `workflow`, `provenance` og `audit` finnes, og `api`
inneholder de fem viewene migrasjon 007, 007a og 007b oppretter. `supabase db push` hadde
dermed ingenting å pushe.

**Hva som er kontrollert, og hvordan.** Denne sesjonen leste tilstanden direkte fra
produksjonsdatabasen med Supabases Management-API og prosjektets access token, som
`read_only`-spørringer: migrasjonshistorikken, objektene per schema, og radtellingene under.
Det er første gang en påstand om det hostede prosjektet er lest fra prosjektet selv framfor
gjengitt fra et dashboardblikk. **Hvem som kjørte migrasjonene, og når, er ikke kjent herfra**
— repoet registrerer det ikke, og historikktabellen bærer bare versjon og navn. Det føres som
et åpent spørsmål, ikke som en antakelse.

**Feilen appen faktisk viste, var eksponeringen — ikke migrasjonene.** `Invalid schema: api`
kommer fra PostgREST, og Data API-ets `db_schema` i det hostede prosjektet var
`public,graphql_public`. Det er nøyaktig den manuelle synkingen §74.5 punkt 3 ber om, og som
§74.18 slo fast ikke var mulig ennå fordi `api` ikke fantes i menyen. Den forutsetningen falt
bort da migrasjonene ble kjørt. Verdien er nå satt til `api,graphql_public` — den samme
verdien `[api].schemas` i `supabase/config.toml` har hatt siden migrasjon 007, og `public` er
ute av eksponeringen begge steder. Endringen er gjort på det ene feltet gjennom
Management-API-et, ikke med `supabase config push`: forbudet mot den kommandoen står uendret,
men begrunnelsen for det er rettet — se «Forbudet mot `config push`» under.

**Grensen er prøvd etter endringen, ikke påstått.** Med publishable-nøkkelen og
`Accept-Profile` mot det hostede prosjektet:

| Forespørsel | Svar |
| --- | --- |
| `api.published_drugs`, `api.published_claims` | `200`, null rader |
| `api.my_roles` som `anon` | `42501 permission denied for view my_roles` |
| `catalog`, `knowledge`, `workflow`, `provenance`, `audit` | `PGRST106 Invalid schema`, «Only the following schemas are exposed: api, graphql\_public» |

Null rader er riktig svar og ikke en mangel: ingenting er publisert (§74.4). Avvisningen av
`anon` på `api.my_roles` er kolonn- og policygrensen fra migrasjon 007b som svarer — bare
`authenticated` har granten. De fem kanoniske schemaene avvises av PostgREST før noen
rettighetskontroll i det hele tatt, som §47 krever.

**Redaktørens autorisasjon tok den positive grenen i produksjon, og det lukker den første av
Milepæl B sine fire.** Aktørregisteret har tre rader, og `workflow.user_roles` har én:
`role_code = 'reviewer'`, uten scopebegrensning, uten sluttdato, gyldig nå og selvtildelt av
`human:peder-holman` — den selvtildelingen §74.17 punkt 3 valgte. Migrasjon 005b skriver bare
når kontoen finnes i `auth.users` (§74.18, §74.20), så raden er selve beviset for at kontoen
finnes der. §74.4 er rettet tilsvarende: **Milepæl B mangler nå tre ting**, ikke fire —
ekstraksjonsverifikasjonene, claim-verifikasjonene og selve godkjenningen.
`knowledge.publication_events` er tom, som ventet.

**Den pinnede CLI-en kan ikke brukes fra en agentsesjon, og det er miljøet og ikke prosjektet.**
`supabase` 2.115.0 kjører en Bun-kompilert binærfil (Bun 1.3.13). Dens `fetch` klarer ikke
TLS-håndtrykket gjennom sesjonens HTTPS-proxy: tunnelen settes opp (`200 Connection
Established`), og forbindelsen brytes deretter. Kontrollert ved å reprodusere feilen med samme
Bun-versjon mot samme URL, og ved at både Node og en nyere Bun lykkes med nøyaktig samme
forespørsel gjennom samme proxy. `supabase link` og `supabase db push` er dermed utilgjengelige
herfra; Management-API-et er ikke det. Dette er en egenskap ved agentmiljøet, ikke ved
CLI-pinningen, og skal ikke leses som en grunn til å endre den.

**Lærdom: en påstand om et system utenfor repoet må kontrolleres på brukstidspunktet.**
§74.18 førte funnet sitt med sin kilde — prosjekteieren i dashboardet — og det var riktig gjort.
Men ingen vaktpost i CI ser på det hostede prosjektet, så påstanden ble usann i det øyeblikket
noen kjørte migrasjonene, uten at noe sted i repoet merket det. Det er ikke et argument for å
legge til enda en påstand: det er grunnen til at neste oppgave som hviler på det hostede
prosjektets tilstand, må lese tilstanden på nytt før den handler.

**Autentiseringsoppsettet er rettet, og verdiene er lest tilbake.** Da denne oppdateringen
begynte, stod `site_url` på `http://localhost:3000`, listen over tillatte redirect-URL-er var
tom, og registrering var åpen for hvem som helst. Prosjekteieren har rettet alle tre i
dashboardet, og verdiene er lest tilbake fra prosjektet etterpå: `site_url` er
`https://antidep.vercel.app`, `uri_allow_list` er `https://antidep.vercel.app/**`, og
`disable_signup` er `true`. Innlogging i appen bruker bare passord (`signInWithPassword`) og
var aldri avhengig av URL-oppsettet; bekreftelses- og tilbakestillingslenker på e-post er det.

**Forbudet mot `config push` står — begrunnelsen for det er rettet.** §74.18 begrunnet forbudet
med fire konkrete forskjeller mot produksjon. De var slutninger, ikke avlesninger: ingen hadde
lest produksjonsverdiene da tabellen ble skrevet. Nå er de lest, 3. september 2026, gjennom
Management-API-et:

| Nøkkel i `config.toml` | Verdi i `config.toml` | Lest i produksjon | Hva et push ville gjort i dag |
|---|---|---|---|
| `auth.site_url` | `http://127.0.0.1:3000` | `https://antidep.vercel.app` | satt site URL til localhost |
| `auth.additional_redirect_urls` | `["https://127.0.0.1:3000"]` | `https://antidep.vercel.app/**` | erstattet den reelle redirect-URL-en |
| `auth.enable_signup` | `true` | registrering avslått | åpnet registrering igjen |
| `auth.minimum_password_length` | `6` | `6` | ingen forskjell |
| `db.network_restrictions.allowed_cidrs` / `_v6` | `["0.0.0.0/0"]` / `["::/0"]` | `0.0.0.0/0`, `::/0` | ingen forskjell i selve listene |

To av §74.18 sine fire rader beskrev altså en forskjell som ikke fantes — passordkravet og
nettverksgrensen er de samme på begge sider. Én rad var usann da den ble skrevet og er sann nå:
redirect-listen var tom 26. august, og et push ville ikke slettet noe; i dag ville det erstattet
den reelle URL-en. Og én forskjell tabellen ikke hadde, er den mest alvorlige: `enable_signup`
er `true` i `config.toml`, så et push ville åpnet registreringen prosjekteieren nettopp lukket.

**Hva som *ikke* er kontrollert, og hvorfor forbudet ikke hviler på tabellen.**
`db.network_restrictions.enabled` er `false` i `config.toml`, og hva et push gjør med selve
håndhevingen av nettverksgrensen — i motsetning til listene — er ikke lest og skal ikke gjettes.
Det samme gjelder resten av filen: `config.toml` har snaut to hundre nøkler, og bare de fem over
er sammenlignet. Hovedregelen er derfor ikke «disse radene er farlige», men den samme som før:
**`supabase config push` skal ikke kjøres før `config.toml` bevisst er gjort til en komplett og
korrekt produksjonskonfigurasjon**, nøkkel for nøkkel. Kommandoen pusher hele filen, og en fil
som er `supabase init`-standardene for en lokal stack, er ikke det. Enkeltinnstillinger settes i
dashboardet eller på det ene feltet gjennom Management-API-et.

**Røyktesten er kjørt, og den leser det samme som databasen.** Prosjekteieren logget inn på
`https://antidep.vercel.app` med redaktørkontoen og åpnet «Min tilgang». Siden viser aktøren
«Peder Holman» med `human:peder-holman`, og én rolle: `reviewer`, «Uavgrenset», gyldig fra
27. august 2026, «Ingen sluttdato er satt». Det er nøyaktig raden som ble lest fra
produksjonsdatabasen over, og datoen er migrasjon 005b sin egen (`20260827090000`). Dermed er
hele kjeden fra `auth.users` gjennom `provenance.actors` og `workflow.user_roles` til
`api.my_actor` og `api.my_roles` prøvd i produksjon, av en innlogget bruker, og ikke bare i
CI: innlogging, den autentiserte leseveien fra migrasjon 007b (§74.21) og klientflaten fra
§74.22 svarer alle som ventet.

**Hva som gjenstår.** Milepæl B mangler tre ting (§74.4): ekstraksjonsverifikasjonene,
claim-verifikasjonene og selve godkjenningen.

---

## 75. Neste steg

> **Merk:** Avsnittet under er skrevet ved planens godkjenning og beskriver oppstarten.
> Det er beholdt som historikk (§71). Planleggingsfasen er avsluttet, og PR A til PR G
> er merget (§74.2). **Gjeldende neste steg står i §74.4, og registrert gjeld i §74.7.**

Når denne planen er godkjent, avsluttes planleggingsfasen som standard arbeidsmodus.

Neste steg er **faktisk implementasjon**, med PR A:

```text
chore: bootstrap Antidep web app
```

Deretter følges PR-rekken og milepælene i dette dokumentet, med planen oppdatert fortløpende etter hvert som prosjektet går fra arkitektur til fungerende klinisk produkt.
