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

## 74. Status etter claim-kortet

**Oppdatert:** 22. august 2026 (etter `feat: add claim card and certainty display`, den første
klinikerflaten; forrige oppdatering etter `feat: add published read model client`, den typede
leseveien fra `api` inn i appen)

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
[~] First clinician UI
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
PR A  chore: bootstrap Antidep web app                        (#9)   merget
PR B  db: add schema and security foundation                  (#10)  merget   migrasjon 001
PR C  db: add drug and clinical concept catalog               (#11)  merget   migrasjon 002
PR D  db: add sources and evidence items                      (#12)  merget   migrasjon 003
PR E  db: add claims and evidence assessments                 (#13)  merget   migrasjon 004
PR F  db: add review and provenance                           (#14)  merget   migrasjon 005
PR G  db: add publication events and gate                     (#15)  merget   migrasjon 006
      docs: record implementation status after migration 006  (#16)  merget   ingen migrasjon
      db: make evidence item content hash unambiguous         (#17)  merget   migrasjon 006a
      db: add api published read model                        (#18)  merget   migrasjon 007
      ci: verify the numeric claims in the plan               (#19)  merget   ingen migrasjon
      db: add audit events                                    (#20)  merget   migrasjon 008
      db: expose publication and review timestamps in api     (#21)  merget   migrasjon 007a
      feat: add published read model client                   (#22)  merget   ingen migrasjon
      feat: add claim card and certainty display              (#23)  åpen     ingen migrasjon
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
enheten for én publisert påstand, uten ruting og uten datahenting (§74.13). Det som gjenstår
av PR I, står sist i §74.13.

Tabellen over er en logg over utført arbeid, og skal føres i den PR-en som gjør arbeidet
ferdig, ikke i en senere. Statuskolonnen beskriver tilstanden da raden ble skrevet, så den
nyeste raden står alltid som `åpen` til neste PR retter den; denne PR-en retter #22. Hva
006a innfridde, står i §74.8; hva 007 innfridde, i §74.9.

**Migrasjonsnumrene i §18-§27 navngir planlagt innhold, ikke filrekkefølge.** Den niende
migrasjonsfilen er migrasjon 008, fordi den sjuende — korreksjonsmigrasjonen 006a — står
utenfor den planlagte rekken og fikk en bokstav. Konvensjonen finnes nettopp for at
«migrasjon 007 — API-lesemodell» (§24) skal bety det samme i plan, migrasjoner og tester.
Den tiende filen er migrasjon 007a av samme grunn: den utvider api-lesemodellen fra §24 og
står utenfor den planlagte rekken, og nummeret 009 er reservert for DrugProduct- og
importfundamentet (§26). Filrekkefølgen er dermed 001, 002, 003, 004, 005, 006, 006a, 007,
008, 007a — sortert på tidsstempel, ikke på migrasjonsnummer.

Databaselaget teller nå 1096 pgTAP-assertions over 33 testfiler.

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

Konsekvens for rekkefølgen: migrasjon 007 (§24) er bygget, og api-projeksjonene viser et
tomt publisert sett. Det er korrekt oppførsel. 007 er testet mot data opprettet inne i en
transaksjon som rulles tilbake — samme mønster som 006 — framfor mot seedet innhold, og
`220_provenance_seed_test.sql` bekrefter fortsatt at ingenting er publisert.

**Det som nå gjenstår for Milepæl B er én ting:** en navngitt kvalifisert redaktør,
registrert som menneskelig aktør med brukerkonto og `reviewer`-rolle. Alt maskineri fra
kilde til klientflate står ferdig og testet rundt det tomrommet.

### 74.5 Beslutninger tatt før migrasjon 007 eksponerte verdier utad

Alle tre er avgjort, og avgjørelsene er nå offentlig kontrakt:

1. **Enum kontra oppslagstabell — utsatt, og gjort billigere å utsette.** Det finnes
   38 enum-typer, fordelt på de ti migrasjonsfilene 001, 002, 003, 004, 005, 006, 006a,
   007, 008 og 007a — i filrekkefølge, ikke i nummerrekkefølge — med henholdsvis
   1, 6, 11, 7, 10, 2, 0, 0, 1 og 0. Tallet er kontrollert mot
   kilden (`grep -cE '^create type ' supabase/migrations/*.sql`) og mot databasen.
   Alle ti ledd er nå oppgitt eksplisitt framfor å la de siste hvile på restpåstanden i
   `scripts/verify-counts.sh`; det er den formen vakten kontrollerer strengest.
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
   og en tom eksponering er fortsatt en eksponering. `api` står først og er dermed
   standardprofilen i PostgREST. Endringen må synkes manuelt mot det hostede prosjektet.

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
| `api`-kontrakten i TypeScript er ikke maskinelt kontrollert mot databasens kolonner | Radtypene og `Database`-typen i `src/types/` er håndskrevne påstander om `api`. En kolonne som skifter navn, blir nullbar eller endrer type gjør dem usanne uten at noe feiler. Vokabularhalvdelen er lukket: `tests/api-vocabularies.test.ts` leser migrasjonene og krever at hver lukket union er nøyaktig sin enum (§74.13). Kolonnenavn, nullbarhet og kolonnetyper står igjen | En kontroll i CI som sammenligner `information_schema.columns` for `api` mot typene — databasejobben har allerede en kjørende stack — eller den første migrasjonen som endrer et api-view |
| Ingen regel binder et kontrastivt effektmål til en komparator | `knowledge.claim_revisions` tillater fortsatt `magnitude_measure = 'mean_difference'` sammen med `comparator_kind = 'none'`, og en redaktør kan skrive kombinasjonen. Presentasjonslaget nekter nå å tolke den (§74.13), men det er et forsvar i visningen, ikke en invariant: dataene er like ugyldige, og enhver annen leser av `api` ser dem rå | Migrasjonen som legger til betingelsen, eller admin-flyten (§29), som er første sted en redaktør kan skrive kombinasjonen. Regelen må ta stilling til `mean_change`, som er en endring fra behandlingsstart og korrekt har `none` |
| Ingen regel binder en tallfestet effekt til at evidensen er graderbar | En revisjon kan bære `magnitude_value` samtidig som vurderingen er `no_assessable_evidence` — som ifølge migrasjon 004 betyr at det ikke finnes tilstrekkelig grunnlag til å gjøre en vurdering i det hele tatt. Kolonnekommentaren på `magnitude_value` sier selv at en påstand som er mer presis enn evidensen under den, er et brudd på `ANTIDEP_CONSTITUTION.md` §4 og §6, men ingen `CHECK` håndhever det på tvers av de to tabellene. Presentasjonslaget skjuler tallet (§74.13); databasen tillater det | Samme migrasjon som over, eller admin-flyten. Regelen krysser `knowledge.claim_revisions` og `knowledge.evidence_assessments`, så den må enten være en trigger eller en betingelse i publiseringsgaten |
| Modellen kan ikke avgjøre om en effektstørrelses fortegn stemmer med påstandens retning | `direction = 'increase'` med `magnitude_value = -0,4` ser motstridende ut, men er det ikke nødvendigvis: fortegnet hører til skalaen `magnitude_unit` måler på, og modellen registrerer ikke om den skalaens positive retning peker samme vei som temaet påstanden handler om. «Økning i vekttap» med en negativ vektforskjell er konsistent. Kontrollen er derfor bevisst ikke innført — den ville gitt falske utslag på gyldige data | Det første objektet som registrerer polariteten til et utfall i forhold til sitt `ClinicalConcept`. Uten det kan verken UI eller en databaseregel bedømme fortegnet |

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

---

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
