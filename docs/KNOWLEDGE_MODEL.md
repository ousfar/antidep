# Antidep Knowledge Model

**Versjon:** 0.1  
**Dato:** 18. august 2026  
**Status:** Første arkitekturspesifikasjon  
**Styrende dokument:** [`ANTIDEP_CONSTITUTION.md`](./ANTIDEP_CONSTITUTION.md)

## 1. Formål

Dette dokumentet definerer Antideps kanoniske kunnskapsmodell: hvilke typer kunnskapsobjekter systemet skal inneholde, hvordan de henger sammen, hvordan de versjoneres og hvilke krav som gjelder for evidens, proveniens og faglig godkjenning.

Dokumentet beskriver **domene- og kunnskapsarkitektur**, ikke databaseskjema, API-er, UI-komponenter eller en bestemt KI-leverandør. Senere tekniske implementasjoner skal avledes fra modellen, ikke omvendt.

Målet er at samme kunnskapsbase skal kunne drive blant annet:

- legemiddeloppslag og monografier
- sammenligning av antidepressiver
- søk etter kliniske problemstillinger
- interaksjonsvisning
- nedtrappings- og bytteverktøy
- senere beslutningsstøtte dersom dette vurderes faglig og regulatorisk forsvarlig

---

## 2. Normative begreper

I dette dokumentet betyr:

- **SKAL**: krav som ikke skal brytes uten eksplisitt endring av modellen eller konstitusjonen.
- **BØR**: sterk standard som kan fravikes når det finnes en dokumentert grunn.
- **KAN**: tillatt, men ikke påkrevd.

---

## 3. Grunnmodell

Antideps kunnskap skal konseptuelt følge denne kjeden:

```text
Source
  ↓
EvidenceItem
  ↓
ClaimEvidenceLink
  ↓
Claim + ClaimRevision
  ↓
EvidenceAssessment
  ↓
Published knowledge
  ↓
Views / comparisons / clinical tools
```

Andre objekter — som `Drug`, `DrugProduct`, `ClinicalConcept`, `Population` og `Interaction` — gir struktur og kontekst rundt kjeden.

### 3.1 Viktigste invariant

**En publisert formulering skal aldri være sin egen kunnskapskilde.**

Monografier, tabeller, sammenligninger, kort, sammendrag og verktøytekster skal være presentasjoner av underliggende strukturerte og versjonerte kunnskapsobjekter.

### 3.2 Påstanden er den sentrale kunnskapsenheten

En `Claim` er den minste selvstendige klinisk meningsfulle påstanden Antidep ønsker å kunne:

- vise
- sitere
- sammenligne
- revidere
- utfordre
- godkjenne
- avpublisere
- gjenbruke i flere kontekster

Eksempel:

> Mirtazapin er assosiert med større vektøkning enn placebo ved korttidsbehandling av voksne med depressiv lidelse.

Dette er én påstand. En mer sammensatt tekst som samtidig omtaler vekt, sedasjon og seksuelle bivirkninger skal normalt deles i flere `Claim`-objekter.

---

# Del I — Domeneobjekter

## 4. `Drug`

Representerer et virkestoff, ikke et bestemt norsk produkt.

Eksempler: sertralin, venlafaksin, mirtazapin.

### Minimumsfelter

| Felt | Betydning |
|---|---|
| `drug_id` | Stabil intern identifikator |
| `canonical_name` | Kanonisk virkestoffnavn |
| `status` | Aktiv, historisk, utgått eller annen definert status |
| `created_at` | Opprettelsestidspunkt |
| `updated_at` | Siste metadataendring |

### Relasjoner

Et `Drug` KAN knyttes til:

- ett eller flere `DrugProduct`
- mange `Claim`
- mange `Interaction`
- farmakologiske klassifikasjoner
- aktive metabolitter eller relaterte virkestoffer

Klassifikasjoner som SSRI, SNRI eller TCA BØR være strukturerte relasjoner eller kontrollerte begreper, ikke fritekstfelt.

---

## 5. `DrugProduct`

Representerer en konkret legemiddelpresentasjon eller relevant produktvariant på det norske markedet.

Dette objektet skal brukes for opplysninger som kan variere mellom produkter eller over tid, for eksempel:

- handelsnavn
- legemiddelform
- styrke
- depotformulering
- delbarhet
- administrasjonsvei
- markedsstatus

### Minimumsfelter

| Felt | Betydning |
|---|---|
| `product_id` | Stabil intern identifikator |
| `drug_id` | Virkestoff |
| `trade_name` | Handelsnavn |
| `form` | Tablett, kapsel, mikstur osv. |
| `strength` | Strukturert styrke med verdi og enhet |
| `market_context` | Normalt Norge |
| `valid_from` | Når opplysningen gjelder fra, når kjent |
| `valid_to` | Når opplysningen opphører, når relevant |
| `source_id` | Autoritativ kilde eller datasett |
| `source_record_id` | Identifikator i kildesystemet når tilgjengelig |

### Prinsipp

Markedssensitive fakta SKAL kunne tidsavgrenses. «Finnes i 50 mg» skal ikke bli et evig, tidløst faktum dersom produktstatus senere endres.

---

## 6. `ClinicalConcept`

Representerer et normalisert klinisk tema som brukes til å kategorisere og gjenfinne kunnskap.

Eksempler:

- vektøkning
- seksuell dysfunksjon
- søvnløshet
- sedasjon
- QT-forlengelse
- hyponatremi
- graviditet
- epilepsi
- leverfunksjon
- seponeringssymptomer

### Formål

`ClinicalConcept` gjør det mulig å stille spørsmål som:

- «Hvilke antidepressiver er mest relevante når vektøkning er viktig?»
- «Vis kunnskapen om sertralin og seksuell dysfunksjon.»
- «Sammenlign disse tre legemidlene på sedasjon og seponeringsproblemer.»

Begrepene BØR organiseres hierarkisk der det gir mening, slik at for eksempel `seksuell dysfunksjon` kan ha underbegreper uten at kunnskapen dupliseres.

---

## 7. `Population`

Representerer populasjonen en påstand eller et evidensfunn gjelder for.

Eksempler:

- voksne med depressiv lidelse
- eldre ≥65 år
- barn og ungdom
- gravide
- personer med bipolar lidelse
- personer med alvorlig nyresvikt

### Prinsipp

Populasjon SKAL ikke reduseres til fritekst dersom den er avgjørende for gyldigheten av påstanden.

Modellen BØR kunne uttrykke relevante dimensjoner separat, for eksempel:

- aldersgruppe
- diagnose/indikasjon
- kjønn når klinisk relevant
- graviditet/amming
- komorbiditet
- organfunksjon
- annen sentral seleksjon

---

# Del II — Påstander

## 8. `Claim`

`Claim` er det stabile identitetsobjektet for en klinisk relevant påstand.

Selve innholdet ligger i versjonerte `ClaimRevision`-objekter. `claim_id` forblir stabilt selv om formuleringen eller vurderingen endres.

### Minimumsfelter på `Claim`

| Felt | Betydning |
|---|---|
| `claim_id` | Stabil identifikator |
| `knowledge_type` | `deterministic_fact`, `evidence_synthesis` eller `clinical_recommendation` |
| `topic_id` | Primært `ClinicalConcept` |
| `current_published_revision_id` | Eksakt publisert revisjon, hvis noen |
| `created_at` | Opprettet |
| `created_by` | Menneske eller agent/prosess |

`Claim` har bevisst **ingen** overordnet statuskolonne. Livssyklusen er avledet av
eksplisitte hendelser og beslutninger — `workflow.review_decisions` og
`knowledge.publication_events` — slik `DATABASE_ARCHITECTURE.md` §15 krever. Et muterbart
statusfelt ville vært en parallell sannhet ved siden av dem, og ville dessuten mistet
mellomtilstandene: at samme revisjon ble kildeverifisert, godkjent, publisert og senere
erstattet, er fire hendelser og ikke fire overskrivinger av ett felt.

Om en påstand er trukket tilbake som helhet, er en egenskap ved identiteten og ikke ved
livssyklusen til en revisjon; det uttrykkes med `retired_at` og en begrunnelse.

### 8.1 `knowledge_type`

Alle klinisk relevante påstander SKAL klassifiseres som én av tre typer:

#### `deterministic_fact`

Opplysning som i hovedsak kan avgjøres direkte mot en autoritativ eller strukturert kilde.

Eksempler:

- et preparat markedsføres i en bestemt styrke
- et produkt er en depottablett
- et virkestoff har en bestemt ATC-kode

Dette betyr ikke at faktumet er evig eller feilfritt; tidsvaliditet og kilde er fortsatt nødvendig.

#### `evidence_synthesis`

En fortolkende sammenfatning av ett eller flere evidensfunn.

Eksempler:

- relativ risiko for seksuell dysfunksjon
- sannsynlig forskjell i effekt mellom to antidepressiver
- vurdering av seponeringsrisiko

Denne typen krever eksplisitt evidensvurdering.

#### `clinical_recommendation`

En normativ påstand om hva en kliniker bør vurdere eller gjøre.

Eksempel:

> Ved betydelig risiko for hyponatremi bør serumnatrium vurderes kontrollert etter oppstart hos utsatte pasienter.

Anbefalinger skal behandles strengere enn beskrivende kunnskap og krever særskilt menneskelig faglig godkjenning.

---

## 9. `ClaimRevision`

Representerer én uforanderlig versjon av en `Claim`.

Når innhold som påvirker betydningen endres, SKAL en ny revisjon opprettes. Historiske revisjoner skal ikke overskrives.

### Minimumsfelter

| Felt | Betydning |
|---|---|
| `claim_revision_id` | Unik revisjons-ID |
| `claim_id` | Stabil overordnet Claim-ID |
| `revision_number` | Monotont versjonsnummer |
| `statement` | Kort kanonisk formulering |
| `scope` | Hva påstanden eksplisitt gjelder for |
| `population_id` | Populasjon når relevant |
| `timeframe` | Tidsramme når relevant |
| `comparator` | Komparator når relevant |
| `direction` | Retning når dette kan struktureres |
| `magnitude` | Effektstørrelse eller annen kvantifisering når forsvarlig |
| `qualifiers` | Nødvendige forbehold |
| `uncertainty_summary` | Kort eksplisitt usikkerhetstekst |
| `created_at` | Opprettet |
| `created_by` | Menneske eller agent/prosess |
| `supersedes_revision_id` | Forrige revisjon når relevant |

Som `Claim` har heller ikke `ClaimRevision` en egen statuskolonne, av samme grunn: en
revisjons livssyklus er avledet av review- og publiseringshendelsene som gjelder den
(`DATABASE_ARCHITECTURE.md` §15). Hvilken revisjon som er publisert nå, står ett sted —
`current_published_revision_id` på `Claim`.

### 9.1 Atomisitet

En `ClaimRevision` BØR uttrykke én påstand som kan være sann, falsk eller usikker uavhengig av nabopåstander.

**Dårlig:**

> Sertralin er effektivt, gir lite vektøkning og er et godt valg hos eldre.

**Bedre:**

Tre separate påstander om henholdsvis effekt, vekt og klinisk anbefaling hos eldre.

### 9.2 Struktur før fritekst

Informasjon som er viktig for sammenligning, filtrering eller sikker tolkning BØR lagres strukturert i tillegg til den menneskelesbare formuleringen.

`statement` skal ikke være eneste sted hvor for eksempel populasjon, komparator eller tidsramme finnes.

---

# Del III — Kilder og evidens

## 10. `Source`

Representerer en identifiserbar informasjonskilde.

Eksempler:

- randomisert studie
- systematisk oversikt
- metaanalyse
- retningslinje
- preparatomtale
- offentlig legemiddeldatasett
- regulatorisk sikkerhetsmelding

### Minimumsfelter

| Felt | Betydning |
|---|---|
| `source_id` | Stabil intern ID |
| `source_type` | Kontrollert kildetype |
| `title` | Tittel |
| `authors_or_issuer` | Forfattere eller utgiver |
| `publication_date` | Publiseringsdato når relevant |
| `persistent_identifier` | DOI, PMID, URL, dokument-ID e.l. |
| `version_or_access_date` | Viktig for levende/dynamiske kilder |
| `bibliographic_metadata` | Nødvendig metadata |
| `availability` | Fulltekst, sammendrag, datasett osv. |
| `source_status` | Aktiv, utdatert, trukket tilbake, erstattet osv. |

### Prinsipp

`Source` sier **hva kilden er**. Den sier ikke i seg selv hva Antidep mener at kilden viser.

---

## 11. `EvidenceItem`

Representerer et konkret evidensfunn ekstrahert fra en `Source`.

Dette er laget mellom originalkilden og Antideps syntese.

Eksempel:

En metaanalyse kan være én `Source`, men kan gi flere `EvidenceItem` — ett for respons, ett for remisjon, ett for vektendring osv.

### Minimumsfelter når relevant

| Felt | Betydning |
|---|---|
| `evidence_item_id` | Stabil identifikator |
| `source_id` | Opphavskilde |
| `population` | Studert populasjon |
| `design` | Studiedesign |
| `sample_size` | N når relevant |
| `intervention` | Intervensjon og dose |
| `comparator` | Komparator |
| `outcome` | Endepunkt |
| `timepoint` | Oppfølgingstid |
| `effect_measure` | RR, OR, MD, SMD osv. |
| `estimate` | Estimat |
| `uncertainty_interval` | Typisk KI, når rapportert |
| `absolute_effect` | Når tilgjengelig og relevant |
| `adjustment` | Viktige modeller/justeringer |
| `limitations` | Kildespesifikke begrensninger |
| `source_locator` | Side, tabell, figur, avsnitt eller annet presist sted |
| `extraction_method` | Manuell, KI-assistert, deterministisk import osv. |
| `extracted_by` | Aktør/prosess |
| `verified_by` | Verifikator når utført |
| `verification_status` | Status for kontroll |

### 11.1 Minimal syntese i ekstraksjonslaget

`EvidenceItem` BØR ligge så nær det kilden faktisk rapporterer som praktisk mulig. Fortolkning på tvers av studier hører hjemme i `Claim` og `EvidenceAssessment`.

### 11.2 Presis kildepeker

For forskningsartikler og dokumenter SKAL evidensfunnet så langt mulig ha en locator til det konkrete stedet som underbygger ekstraksjonen.

---

## 12. `ClaimEvidenceLink`

Representerer Antideps eksplisitte vurdering av **hvordan** et bestemt `EvidenceItem` forholder seg til en bestemt `ClaimRevision`.

En enkel mange-til-mange-relasjon mellom påstand og kilde er ikke tilstrekkelig.

### Minimumsfelter

| Felt | Betydning |
|---|---|
| `claim_evidence_link_id` | Identifikator |
| `claim_revision_id` | Eksakt påstandsrevisjon |
| `evidence_item_id` | Konkret evidensfunn |
| `stance` | `supports`, `partially_supports`, `contradicts`, `neutral/contextual` |
| `directness` | Direkte eller indirekte evidens |
| `relevance` | Relevans for påstandens populasjon/spørsmål |
| `rationale` | Hvorfor evidensen har denne relasjonen |
| `created_by` | Menneske eller agent |
| `verified_by` | Kontrollør når relevant |

### Invariant

En kilde SKAL ikke kunne vises som støtte for en påstand bare fordi den handler om samme tema.

---

## 13. `EvidenceAssessment`

Representerer den eksplisitte vurderingen av hvor sikkert evidensgrunnlaget støtter en `ClaimRevision` av typen `evidence_synthesis` eller `clinical_recommendation`.

### Minimumsfelter

| Felt | Betydning |
|---|---|
| `assessment_id` | Identifikator |
| `claim_revision_id` | Vurdert revisjon |
| `framework` | GRADE eller annen eksplisitt metode |
| `certainty_level` | Standardisert nivå |
| `domains` | Strukturerte delvurderinger |
| `overall_rationale` | Begrunnelse |
| `evidence_gap` | Om vesentlig kunnskap mangler |
| `assessed_by` | Aktør(er) |
| `human_approved_by` | Faglig godkjenner når påkrevd |
| `assessed_at` | Tidspunkt |

### 13.1 Standardtilstander

Når GRADE er egnet, skal følgende kunne uttrykkes:

- høy sikkerhet
- moderat sikkerhet
- lav sikkerhet
- svært lav sikkerhet

I tillegg SKAL systemet ha en separat tilstand for:

- **ingen vurderbar evidens / utilstrekkelig grunnlag for vurdering**

Denne tilstanden er ikke det samme som «svært lav risiko», «ingen effekt» eller «ingen forskjell».

### 13.2 Uenighet

Dersom relevante evidensfunn peker i ulike retninger, skal dette kunne representeres eksplisitt. Systemet skal ikke kreve at alle `ClaimEvidenceLink` har samme `stance`.

---

# Del IV — Kliniske anbefalinger og strukturerte relasjoner

## 14. `RecommendationProfile`

En klinisk anbefaling er fortsatt en `Claim` med `knowledge_type = clinical_recommendation`, men kan ha et tilknyttet `RecommendationProfile` med strukturerte normative egenskaper.

### Aktuelle felter

- målgruppe
- klinisk situasjon
- anbefalt handling
- styrke på anbefaling
- alternativer
- unntak
- forutsetninger
- eksplisitte nytte–risiko-vurderinger
- relevante pasientpreferanser eller verdier
- regulatorisk/faglig kildegrunnlag

### Invariant

En `RecommendationProfile` skal aldri eksistere som en parallell anbefaling uten en versjonert `ClaimRevision`.

---

## 15. `Interaction`

Representerer en strukturert relasjon mellom et antidepressiv og ett eller flere andre legemidler, substanser eller kliniske forhold.

`Interaction` er et organiserende domeneobjekt. Kliniske utsagn om interaksjonen skal fortsatt uttrykkes som `Claim`.

### Modellen BØR kunne uttrykke

- involverte substanser
- retning
- mekanisme
- farmakokinetisk og/eller farmakodynamisk type
- påvirket enzym, transportør eller fysiologisk mekanisme
- forventet konsekvens
- forventet størrelsesorden
- klinisk relevans
- anbefalt håndtering
- sikkerhet i evidensen

### Invariant

**Fravær av registrert interaksjon er ikke bevis for fravær av interaksjon.**

Datamodellen SKAL skille mellom:

- vurdert og ikke påvist
- utilstrekkelig dokumentasjon
- ikke vurdert
- kjent interaksjon

---

## 16. `ClinicalRule`

Representerer en eksplisitt og versjonert regel som brukes i et klinisk verktøy, for eksempel nedtrapping, bytte eller doseberegning.

Dette er ikke det samme som en fritekstanbefaling.

### Minimumsfelter

| Felt | Betydning |
|---|---|
| `rule_id` | Stabil identifikator |
| `rule_revision_id` | Uforanderlig regelversjon |
| `purpose` | Hva regelen brukes til |
| `inputs` | Eksplisitte inputvariabler og enheter |
| `preconditions` | Når regelen gjelder |
| `logic` | Maskinlesbar, deterministisk logikk |
| `outputs` | Mulige resultater |
| `dependencies` | Claims, produktdata og andre regler den avhenger av |
| `exceptions` | Kjente unntak |
| `validation_cases` | Definerte testtilfeller |
| `status` | Livssyklusstatus |
| `human_approved_by` | Obligatorisk faglig godkjenner |

### Invariant

En språkmodell skal ikke alene produsere den endelige beregningslogikken som kjøres i et klinisk verktøy. KI kan foreslå, forklare og teste regler; produksjonsregelen skal være eksplisitt, deterministisk der det er mulig, versjonert og testbar.

---

# Del V — Proveniens, aktører og versjonering

## 17. `Actor`

Representerer hvem eller hva som utførte en kunnskapsoperasjon.

Aktørtyper kan være:

- kvalifisert fagredaktør
- annen menneskelig bidragsyter
- KI-agent
- deterministisk importjobb
- systemprosess

For KI-agenter BØR relevante metadata kunne peke til:

- leverandør
- modell
- modellversjon når tilgjengelig
- agentrolle
- prompt-/workflowversjon
- kjøremiljø eller pipelineversjon

Kanoniske kunnskapsobjekter skal ikke være avhengige av én bestemt modellleverandørs identifikatorer.

---

## 18. `ProvenanceEvent`

Representerer en hendelse som opprettet, endret, verifiserte, godkjente, publiserte eller trakk tilbake et kunnskapsobjekt.

### Minimumsfelter

- berørt objekt og eksakt revisjon
- handling
- aktør
- tidspunkt
- begrunnelse
- inputobjekter eller kilder
- pipeline-/verktøyversjon når relevant
- eventuell overordnet review eller endringssak

### Invariant

Det skal være mulig å svare på:

> «Hvorfor sier Antidep dette akkurat nå?»

med en sporbar kjede fra publisert visning tilbake til eksakt påstandsrevisjon, evidensfunn, kilder, vurderinger og godkjenning.

---

## 19. Revisjonsmodell

### 19.1 Stabil ID + uforanderlige revisjoner

Objekter med klinisk betydning BØR følge mønsteret:

```text
stable_object_id
  ├── revision 1
  ├── revision 2
  └── revision 3  ← current published
```

En publisert revisjon skal ikke endres in-place når betydningen påvirkes. En ny revisjon opprettes i stedet.

### 19.2 Hva krever ny revisjon?

Ny revisjon SKAL normalt opprettes ved endring i:

- klinisk betydning
- populasjon eller scope
- estimat eller effektstørrelse
- sikkerhetsgrad
- evidensgrunnlag når dette påvirker vurderingen
- anbefalt handling
- vesentlige forbehold
- regel-/beregningslogikk

Rene rettskrivingsendringer uten betydningsendring KAN behandles lettere, men skal fortsatt være auditerbare dersom de skjer i publisert klinisk innhold.

### 19.3 Referanser peker til revisjoner

Evidensvurderinger, godkjenninger og publiserte visninger SKAL så langt mulig peke til eksakte revisjoner, ikke bare stabile objekter.

---

# Del VI — Livssyklus og godkjenning

## 20. Standard livssyklus

Klinisk innhold skal minst støtte følgende logiske livssyklus:

```text
draft
  ↓
source-verified
  ↓
human-approved
  ↓
published
  ↓
review-due
  ↓
retired / superseded
```

Tilstander kan implementeres mer detaljert senere, men betydningen skal bevares.

### 20.1 `draft`

Objektet kan være ufullstendig, KI-generert eller ikke kontrollert.

### 20.2 `source-verified`

Det er verifisert at kildehenvisninger og evidensekstraksjoner faktisk støtter den representasjonen systemet hevder at de gjør.

Dette er **ikke** det samme som faglig godkjenning av syntesen.

### 20.3 `human-approved`

En kvalifisert menneskelig fagredaktør har eksplisitt godkjent innholdet for publisering innenfor definert scope.

### 20.4 `published`

Revisjonen kan brukes i sluttbrukervisninger og produksjonsverktøy.

### 20.5 `review-due`

Objektet er fortsatt historisk identifiserbart, men systemet har grunn til å kreve ny vurdering, for eksempel på grunn av alder eller nye kilder.

Hvorvidt `review-due` fortsatt kan vises til sluttbruker skal avgjøres eksplisitt etter risikoklasse.

### 20.6 `retired` / `superseded`

Objektet er ikke lenger gjeldende, men beholdes for revisjonshistorikk og sporbarhet.

---

## 21. Godkjenningsmatrise

Minimumskravene skal være risikobaserte.

| Kunnskapstype | KI kan opprette utkast | Automatisk kildeverifikasjon mulig | Menneskelig godkjenning før første publisering |
|---|---:|---:|---:|
| Deterministisk faktum fra autoritativ strukturert kilde | Ja | Ja | Ikke nødvendigvis for hvert enkelt datapunkt dersom importen som system er validert |
| Evidensbasert syntese | Ja | Delvis | **Ja** |
| Klinisk anbefaling | Ja | Delvis | **Ja, eksplisitt** |
| ClinicalRule / dose-, bytte- eller nedtrappingslogikk | Ja, som forslag | Ja, gjennom tester og kildekontroll | **Ja, eksplisitt** |

Automatisering skal aldri brukes til å omklassifisere høyrisikoinnhold til en lavere godkjenningsklasse bare for å redusere manuelt arbeid.

---

# Del VII — Presentasjon som avledet lag

## 22. `ViewDefinition`

En visning beskriver hvordan eksisterende kunnskapsobjekter velges, ordnes og presenteres. Den skal ikke være en ny sannhetskilde.

Eksempler:

- monografi for sertralin
- sammenligning av sertralin, escitalopram og mirtazapin
- «seksuell dysfunksjon»-visning
- «graviditet»-visning
- interaksjonsoversikt

### Prinsipp

En visning KAN ha redaksjonelle overskrifter, sortering, prioritering og korte sammendrag, men den skal kunne spores tilbake til de underliggende objektene.

Hvis et sammendrag introduserer en ny klinisk meningsfull påstand som ikke allerede finnes i kunnskapsbasen, skal denne opprettes som en `Claim` før sammendraget publiseres.

---

## 23. Sammenligninger

Sammenligninger skal bygges på standardiserte dimensjoner og de samme `Claim`-objektene som øvrige visninger.

Eksempel:

```text
ClinicalConcept: weight_change
              │
      ┌───────┼─────────┐
      │       │         │
 sertraline  mirtazapine  bupropion
      │       │         │
    Claims  Claims     Claims
```

### 23.1 Ingen falsk rangering

Visuelle skalaer eller rangeringer skal bare genereres når den underliggende kunnskapen faktisk tillater sammenligning.

Systemet SKAL skille mellom:

- dokumentert lavere risiko/effekt
- omtrent lik risiko/effekt
- dokumentert høyere risiko/effekt
- utilstrekkelig eller inkommensurabel evidens

«Ukjent» skal ikke automatisk sorteres som «lavt».

---

# Del VIII — Valideringsregler

## 24. Globale invariants

Følgende regler skal håndheves av applikasjon, valideringslag eller publiseringspipeline så langt det er teknisk mulig:

1. En publisert klinisk relevant `ClaimRevision` skal ha minst én relevant kilde eller eksplisitt markering av hvorfor en kilde ikke er anvendelig.
2. `evidence_synthesis` skal ha en `EvidenceAssessment` før publisering.
3. `clinical_recommendation` skal ha menneskelig faglig godkjenning før publisering.
4. En `ClinicalRule` skal ha menneskelig faglig godkjenning og definerte valideringstester før produksjonsbruk.
5. En evidenslenke skal angi relasjonens retning; «koblet til» er ikke nok.
6. Motstridende evidens skal kunne lagres uten å bli overskrevet av støttende evidens.
7. Ingen visning skal tolke manglende data som lav risiko, liten effekt eller fravær av interaksjon.
8. Publisert innhold skal peke til eksakte revisjoner.
9. Historiske publiserte revisjoner skal bevares.
10. Alle klinisk relevante endringer skal ha attribuert proveniens.
11. Markedssensitive norske produktdata skal ha kilde og kunne tidsavgrenses.
12. Samme kliniske påstand skal ikke kopieres til flere uavhengige fritekstfelt dersom den kan gjenbrukes som samme `Claim`.
13. KI-generert tekst som tilfører en ny klinisk påstand skal gjennom samme kunnskapsløp som annen klinisk kunnskap.
14. Fravær av evidens skal representeres eksplisitt og separat fra negativ evidens.
15. Alle strukturerte numeriske verdier skal ha eksplisitt enhet når enhet er relevant.

---

# Del IX — Eksempel

## 25. Forenklet eksempel: mirtazapin og vekt

Dette er kun et struktur-eksempel, ikke en ferdig faglig påstand.

```yaml
drug:
  drug_id: drug_mirtazapine
  canonical_name: Mirtazapin

clinical_concept:
  concept_id: weight_change
  label: Vektendring

claim:
  claim_id: claim_mirtazapine_weight_001
  knowledge_type: evidence_synthesis

claim_revision:
  claim_revision_id: claim_mirtazapine_weight_001_r3
  revision_number: 3
  statement: >
    Mirtazapin er assosiert med større vektøkning enn placebo
    ved korttidsbehandling av voksne med depressiv lidelse.
  population: adults_major_depressive_disorder
  comparator: placebo
  timeframe: short_term
  direction: increase
  uncertainty_summary: "..."
  status: published

source:
  source_id: source_abc
  source_type: systematic_review
  persistent_identifier: "..."

evidence_item:
  evidence_item_id: evidence_abc_weight
  source_id: source_abc
  population: adults_major_depressive_disorder
  outcome: body_weight_change
  effect_measure: mean_difference
  estimate: "..."
  uncertainty_interval: "..."
  source_locator: "..."

claim_evidence_link:
  claim_revision_id: claim_mirtazapine_weight_001_r3
  evidence_item_id: evidence_abc_weight
  stance: supports
  directness: direct
  rationale: "..."

evidence_assessment:
  claim_revision_id: claim_mirtazapine_weight_001_r3
  framework: GRADE
  certainty_level: moderate
  overall_rationale: "..."
```

Den samme `ClaimRevision` kan deretter inngå i:

- mirtazapinmonografien
- en sammenligning med sertralin
- visningen «vektøkning»
- en filtrert klinisk situasjon for pasienter der vekt er særlig viktig

uten at fire separate tekstkopier blir fire separate sannhetskilder.

---

# Del X — Agentgrensesnitt

## 26. Hva agentene skal produsere

Agentpipen skal arbeide mot eksplisitte objekter og kontrakter, ikke «skrive ferdige nettsider».

En mulig logisk arbeidsdeling er:

```text
DiscoveryAgent
  → Source candidates

SourceAssessmentAgent
  → Source quality/status metadata

ExtractionAgent
  → EvidenceItem drafts

ClaimAgent
  → Claim / ClaimRevision drafts

AdversarialAgent
  → contradictory evidence + challenge report

VerificationAgent
  → verified ClaimEvidenceLinks / extraction checks

SynthesisAssessmentAgent
  → EvidenceAssessment draft

EditorialAgent
  → concise wording without changing meaning

HumanReviewer
  → approve / reject / revise
```

### 26.1 Agentoutput skal være validerbart

For hver agentrolle BØR det senere defineres:

- eksplisitt inputskjema
- eksplisitt outputskjema
- tillatte handlinger
- forbudte handlinger
- automatiske valideringsregler
- når menneskelig eskalering kreves

### 26.2 Ingen agent skal eie sannheten

Agentenes produkter er forslag eller mellomprodukter. Kanonisk kunnskap oppstår først gjennom Antideps versjonerte objekter og nødvendige kontroll-/godkjenningssteg.

---

# Del XI — Admin- og redaktørmodell

## 27. Redaktøren skal arbeide med kunnskapsobjekter

Admin-UI-et bør bygges rundt arbeidsoppgaver som:

- opprette eller redigere en påstand
- inspisere kilde og konkret evidensfunn side om side
- endre `ClaimEvidenceLink` fra `supports` til `partially_supports` eller `contradicts`
- korrigere et ekstrahert tall
- registrere en ny kilde
- markere en kilde som erstattet eller trukket tilbake
- sammenligne revisjoner
- be om ny KI-analyse
- se agentens begrunnelse og provenance
- godkjenne eller forkaste
- publisere eller avpublisere
- markere «review due»
- rulle tilbake til tidligere revisjon

Redaktøren skal normalt ikke måtte åpne en stor monografitekst og manuelt finne alle steder der én endret opplysning er duplisert.

---

# Del XII — Hva modellen bevisst ikke bestemmer ennå

## 28. Uavklarte implementasjonsvalg

Denne versjonen skal **ikke** låse følgende beslutninger:

- eksakt PostgreSQL/Supabase-tabellstruktur
- om enkelte underobjekter lagres relasjonelt eller som validerte dokumentfelter
- endelige kodeverk eller ontologier for kliniske begreper
- eksakt GRADE-implementasjon for alle spørsmålstyper
- hvilke kilder som kan autoimporteres
- konkrete KI-modeller eller leverandører
- endelig agentorkestrering
- endelig tilgangs- og rollemodell
- regulatorisk klassifisering av fremtidige pasientspesifikke funksjoner
- eksakte terskler for automatisk versus individuell menneskelig review av deterministiske fakta

Disse valgene skal tas i senere spesifikasjoner når kunnskapsmodellen er tilstrekkelig stabil.

---

# Del XIII — Neste avledede spesifikasjoner

## 29. Dokumenter som bør følge etter denne modellen

Når denne modellen er godkjent, bør arbeidet gå videre til følgende separate dokumenter, i denne rekkefølgen:

1. **`EVIDENCE_PIPELINE.md`**  
   Definer kildesøk, kildevurdering, ekstraksjon, syntese, adversarial kontroll, verifikasjon og menneskelig godkjenning.

2. **`DATABASE_ARCHITECTURE.md`**  
   Oversett den godkjente kunnskapsmodellen til konkret Supabase/PostgreSQL-skjema, constraints, indekser, RLS og migreringsstrategi.

3. **`CONTENT_GOVERNANCE.md`**  
   Definer roller, review-frister, publiseringsmyndighet, feilhåndtering, revisjonsrutiner og policy for utdaterte data.

4. **`PRODUCT_INFORMATION_ARCHITECTURE.md`**  
   Definer hvilke sluttbrukervisninger Antidep skal ha og hvordan de projiserer kunnskapsbasen uten å duplisere kunnskap.

5. **`CLINICAL_TOOLS_SPEC.md`**  
   Definer senere nedtrappings-, bytte-, dose- og interaksjonsverktøy samt krav til determinisme, tester og faglig validering.

---

## 30. Akseptansekriterium for kunnskapsmodellen

Modellen er moden nok til databasearbeid når teamet kan ta en realistisk klinisk opplysning og entydig svare på:

1. Hva er den kanoniske `Claim`-en?
2. Hvilken kunnskapstype er den?
3. Hvilken populasjon og hvilket scope gjelder den for?
4. Hvilke konkrete `EvidenceItem` underbygger eller motsier den?
5. Hvordan er hvert evidensfunn koblet til påstanden?
6. Hvor sikker er syntesen, og hvorfor?
7. Hvem eller hva opprettet og verifiserte den?
8. Hvem godkjente publisering?
9. Hvilken revisjon ser sluttbrukeren nå?
10. Hvilke andre visninger kan gjenbruke samme kunnskap uten kopiering?

Hvis disse spørsmålene ikke kan besvares uten å ty til løs fritekst eller implisitt kunnskap, er modellen eller implementasjonen ikke ferdig.