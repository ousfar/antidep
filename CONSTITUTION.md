# Antidep Constitution – forskningsbasert forslag

Antidep bør styres av en kort «konstitusjon» som definerer **hva som aldri skal ofres når produktet vokser**: klinisk nytte, epistemisk redelighet, sporbarhet, menneskelig ansvar og regulatorisk bevissthet. Den viktigste arkitektoniske konsekvensen er at Antidep ikke bør bygges som en samling KI-skrevne monografier, men som en **versjonert kunnskapsbase av strukturerte fakta, påstander, evidensobjekter og kilder**, hvor monografier, sammenligninger og kliniske verktøy er ulike visninger eller beregninger over samme kunnskapsgrunnlag. For klinisk relevante evidenssynteser bør sikkerhet i kunnskapsgrunnlaget vurderes eksplisitt og transparent, inspirert av GRADE; KI skal aldri få publisere klinisk innhold gjennom én enkelt genereringsrunde; og pasientspesifikk beslutningsstøtte skal behandles som et eget regulatorisk sprang, fordi programvare som kombinerer medisinsk kunnskap med pasientspesifikke data for å anbefale behandling kan kvalifisere som medisinsk utstyr. citeturn3search1turn4search0turn5search4turn0search0turn0search6

## Produkt, målgruppe og språk

### Prinsipp 1 — Antidep er et klinisk arbeidsverktøy for helsepersonell

**Konstitusjonstekst:**  
Antidep skal primært utvikles for klinikere i Norge som trenger rask, presis og etterprøvbar informasjon om antidepressiver i kliniske beslutningssituasjoner. Produktet skal optimaliseres for praktisk klinisk nytte, ikke for maksimal tekstmengde, generell pasientinformasjon eller akademisk fullstendighet.

**Begrunnelse:**  
Dette avgrenser både målgruppe og tiltenkt bruk, som igjen er viktig for design, evidensnivå og senere regulatorisk vurdering. Helsedirektoratet understreker at formålet og den praktiske bruken av et klinisk beslutningsstøtteverktøy er sentrale når relevant regelverk skal identifiseres. citeturn6search1turn6search6

### Prinsipp 2 — Informasjon skal være lagdelt, konsis og tilgjengelig

**Konstitusjonstekst:**  
Antidep skal vise den minste informasjonsmengden som er tilstrekkelig for den aktuelle oppgaven, med progressiv fordypning til metode, evidens og primærkilder. Alle sentrale funksjoner skal fungere på mobil og desktop, og visuelle indikatorer skal aldri være eneste bærer av klinisk informasjon.

**Begrunnelse:**  
Dette lar klinikeren handle raskt uten å miste muligheten til full etterprøvbarhet. Tilgjengelighet bør behandles som et grunnkrav; W3C anbefaler siste WCAG 2-versjon, og WCAG 2.2 er nå også ISO/IEC 40500:2025. citeturn11search1turn11search2

### Prinsipp 3 — Språk skal være nøkternt, presist og konsekvent

**Konstitusjonstekst:**  
Antidep skal alltid bruke **antidepressiver**, aldri *antidepressiva*. Språket skal være norsk bokmål som standard, klinisk presist, kortfattet og ikke-promoterende; absolutte formuleringer skal bare brukes når evidensgrunnlaget faktisk forsvarer dem.

**Begrunnelse:**  
Et fast språkprinsipp gjør redaksjonelt og KI-generert innhold konsistent og maskinelt testbart. Kravet om å unngå uberettiget sikkerhet følger også produktets overordnede krav om transparens og er særlig viktig fordi generative modeller kan produsere feil som fremstår overbevisende og autoritative. citeturn5search8

## Evidens og kunnskapsmodell

### Prinsipp 4 — Enhver klinisk relevant påstand skal være etterprøvbar

**Konstitusjonstekst:**  
Ingen publisert klinisk relevant påstand skal eksistere uten eksplisitt kobling til én eller flere identifiserbare kilder og dokumentasjon av **hvordan** kildene støtter, nyanserer eller motsier påstanden. En referanse som bare omhandler samme tema, men ikke faktisk underbygger formuleringen, skal ikke godtas som støtte.

**Begrunnelse:**  
Kildelisten alene gir ikke reell transparens; forbindelsen mellom evidens og konklusjon må kunne granskes. GRADE bygger nettopp på at vurderingen av evidens skal foregå innenfor en eksplisitt og transparent struktur, og WHO fremhever transparens og etterprøvbarhet som grunnleggende for KI i helse. citeturn3search1turn3search5turn5search4

### Prinsipp 5 — Antidep skal skille tre kunnskapstyper

**Konstitusjonstekst:**  
Alt innhold skal klassifiseres som én av følgende hovedtyper:

1. **Deterministisk faktum** — for eksempel norsk handelsnavn, legemiddelform, styrke eller markedsføringsstatus.
2. **Evidensbasert syntese** — en vurdering av et forskningsgrunnlag, for eksempel relativ risiko for vektøkning.
3. **Klinisk anbefaling** — en normativ vurdering av hva klinikeren bør gjøre.

Disse tre typene skal ha separate valideringsregler og skal aldri presenteres som om de hadde samme epistemiske status.

**Begrunnelse:**  
For norske preparatdata finnes strukturerte, myndighetsforvaltede kilder som FEST og DMPs FHIR-tjeneste, mens vurderinger av effekt eller tolerabilitet krever syntese og skjønn. En anbefaling går ytterligere ett steg fordi evidens må kombineres med kliniske avveininger; den kan derfor ikke reduseres til et enkelt studieutsagn. citeturn7search6turn7search1turn9search10turn3search15

### Prinsipp 6 — Usikkerhet skal graderes, forklares og aldri erstattes av falsk presisjon

**Konstitusjonstekst:**  
Evidensbaserte synteser skal ha en eksplisitt vurdering av sikkerheten i kunnskapsgrunnlaget. Når GRADE er egnet, skal kategoriene **høy, moderat, lav eller svært lav sikkerhet** brukes med eksplisitt vurdering av risiko for systematiske skjevheter, inkonsistens, indirekthet, upresisjon og publiseringsskjevhet; «ingen vurderbar evidens» skal være en separat systemtilstand og ikke fremstilles som «lav risiko» eller som en femte GRADE-kategori.

**Begrunnelse:**  
GRADE skiller graden av sikkerhet i et evidensgrunnlag fra størrelsen eller retningen på selve effekten og krever eksplisitt vurdering av disse domenene. Dette er særlig viktig for visuelle skalaer: lite dokumentasjon må ikke se ut som dokumentasjon for liten effekt eller liten risiko. citeturn3search1turn3search4turn3search15

### Prinsipp 7 — Påstanden, ikke monografien, er kunnskapsbasens grunnenhet

**Konstitusjonstekst:**  
Hver selvstendig klinisk relevant påstand skal være et separat, stabilt identifiserbart objekt med minst: `claim_id`, tema, berørte virkestoffer, presis formulering, anvendelsesområde/populasjon, status, sikkerhetsgrad, versjon, opprettelsestidspunkt og tidspunkt for siste faglige vurdering. Monografitekst skal være en visning av slike objekter, ikke den kanoniske lagringsformen for kunnskapen.

**Begrunnelse:**  
Dette gjør samme kunnskap gjenbrukbar i monografier, sammenligninger, filtrering og senere beslutningsstøtte uten divergerende kopier. Et slikt objektorientert proveniensprinsipp harmonerer med etablerte helsedatamodeller der en ressurs og dens spesifikke versjon kan kobles eksplisitt til proveniens og tidligere versjoner. citeturn4search0turn4search10

### Prinsipp 8 — Evidens og proveniens skal være førsteklasses data

**Konstitusjonstekst:**  
En kobling mellom kilde og påstand skal lagres som et eget **evidensobjekt**, ikke bare som en referanseliste. Evidensobjektet skal minst angi `claim_id`, `source_id`, relasjon (`supports`, `qualifies`, `contradicts`, `background`), eksakt lokalisering i kilden, relevant studiedesign/populasjon/intervensjon/komparator/endepunkt/tidshorisont, eventuelt effektestimat og usikkerhet, hvem eller hva som ekstraherte informasjonen, hvem som verifiserte den, samt versjoner og tidsstempler.

**Begrunnelse:**  
FHIRs Provenance-modell er uttrykkelig laget for å spore hvilke agenter, aktiviteter og kilder som førte til en bestemt ressursversjon og fremhever at versjonsidentifikasjon er nødvendig når historikken skal være entydig. Antidep trenger tilsvarende sporbarhet på påstandsnivå for at klinikere og redaktører faktisk skal kunne undersøke hvordan en konklusjon oppsto. citeturn4search0turn4search3

### Prinsipp 9 — Motstridende evidens skal bevares, ikke «løses bort»

**Konstitusjonstekst:**  
Kilder og evidensobjekter som motsier en publisert syntese skal beholdes og merkes som motstridende evidens. Ved reell uenighet i forskningen skal Antidep beskrive uenigheten, mulige årsaker til den og hvordan den påvirker sikkerheten i konklusjonen; en KI-agent skal aldri få fjerne relevant motstridende evidens bare fordi en annen konklusjon er foretrukket.

**Begrunnelse:**  
Inkonsistens mellom studier er et eksplisitt domene i GRADE og skal redusere sikkerheten når forskjellene er relevante. Et system som bare samler støtte for sin foreløpige konklusjon vil i praksis bygge bekreftelsesskjevhet inn i kunnskapsbasen. citeturn3search1turn3search5

## KI, verifikasjon og innholdsforvaltning

### Prinsipp 10 — KI-arbeidet skal deles i eksplisitte roller

**Konstitusjonstekst:**  
Agentpipen skal minst skille logisk mellom **kildesøk**, **kildekvalitetsvurdering**, **data-/evidensekstraksjon**, **påstandsformulering/syntese**, **motargumenterende kontroll**, **sitat-/kildestøtteverifikasjon** og **redaksjonell komprimering**. Én agentkjøring skal aldri alene få gå direkte fra kildefunn til publisert klinisk innhold.

**Begrunnelse:**  
Separasjon gjør feil lettere å oppdage og gir definerte kontrollpunkter for testing, evaluering, validering og verifikasjon. NIST anbefaler eksplisitte TEVV-prosesser for KI, mens WHO anbefaler at KI i helse brukes med ekspertkontroll og grundig evaluering fremfor ukritisk automatisering. citeturn5search1turn5search7turn5search8

### Prinsipp 11 — Verifikasjon skal forsøke å falsifisere, ikke bare bekrefte

**Konstitusjonstekst:**  
Før en KI-generert syntese kan godkjennes, skal en separat kontrollfase aktivt forsøke å finne: feilsitering, overtolkning, manglende forbehold, motstridende forskning, feil populasjon eller endepunkt, utdaterte kilder og numeriske avvik. Verifikatoren skal ha tilgang til kildematerialet og skal ikke godkjenne en påstand ut fra tidligere agenters sammendrag alene.

**Begrunnelse:**  
Dette er et bevisst vern mot at flere agenter bare viderefører samme opprinnelige feil. WHO fremhever både risikoen for plausible, men feilaktige LLM-resultater og behovet for menneskelig verifikasjon og «living evidence»-arbeidsflyter rundt KI. citeturn5search8turn5search12

### Prinsipp 12 — KI kan foreslå; ansvarlige mennesker skal kunne stanse og overstyre

**Konstitusjonstekst:**  
KI skal aldri være endelig faglig autoritet. Evidenssynteser skal ha menneskelig faglig godkjenning før første publisering, og alle kliniske anbefalinger, doseringsregler, bytte-/nedtrappingsregler og andre endringer med direkte potensial til å påvirke behandling skal kreve eksplisitt godkjenning fra en navngitt kvalifisert redaktør.

**Begrunnelse:**  
WHO anbefaler at mennesker beholder kontroll over medisinske beslutninger, og EU-regelverket for høyrisiko-KI bruker effektiv menneskelig overvåkning, forståelse og mulighet for overstyring som et sentralt sikkerhetsprinsipp. Dette er en god styringsstandard selv når Antidep-funksjonen ikke juridisk er et høyrisiko-KI-system. citeturn5search4turn5search0

### Prinsipp 13 — Alt publisert innhold skal ha en eksplisitt livssyklus

**Konstitusjonstekst:**  
Innhold skal følge minst følgende tilstander:

`draft → source-verified → human-approved → published → review-due → retired/superseded`

Tidligere publiserte versjoner skal aldri destrueres fra revisjonshistorikken. Deterministiske DMP-data skal kontrolleres automatisk for ny versjon minst nattlig; sikkerhetskritisk innhold skal ha hendelsesstyrt overvåkning og minst kvartalsvis faglig kontroll; øvrige publiserte evidenssynteser skal gjennomgås minst årlig eller tidligere når ny sentral evidens identifiseres.

**Begrunnelse:**  
DMP anbefaler eksplisitt at systemer automatisk kontrollerer FEST for oppdateringer hver natt, blant annet fordi ekstraordinære publiseringer kan forekomme. For forskningssynteser viser Cochrane at viktige og dynamiske spørsmål kan kreve kontinuerlig evidensovervåkning, mens oppdateringsfrekvensen bør være forhåndsdefinert og transparent. citeturn9search0turn9search11turn10search1turn10search8

### Prinsipp 14 — Endringer skal være reversible, attribuerte og rapporterbare

**Konstitusjonstekst:**  
Enhver endring i påstander, evidensobjekter, kilder, anbefalinger eller verktøyregler skal registrere hvem eller hvilken agent som gjorde endringen, når den ble gjort, hvorfor den ble gjort og hvilken tidligere versjon den erstattet. Brukere skal fra relevante visninger kunne **rapportere mulig feil**, og rapporten skal kunne kobles direkte til det konkrete objektet eller den konkrete versjonen den gjelder.

**Begrunnelse:**  
Proveniens og audit trail er nødvendige for å kunne undersøke opphav og pålitelighet etter en feil eller faglig uenighet. FHIR skiller tilsvarende mellom Provenance for opphav til informasjon og AuditEvent for hendelser og revisjonsspor. citeturn4search0

## Redaktørflate og MVP

### Prinsipp 15 — Admin-UX er et kjerneprodukt, ikke et sekundært CMS

**Konstitusjonstekst:**  
Kvalifiserte redaktører skal uten bruk av Claude, ChatGPT eller direkte databaseinngrep kunne: opprette og redigere påstander; godkjenne, forkaste og overstyre KI-forslag; legge til, fjerne og erstatte kilder; endre kilde–påstand-relasjoner; korrigere evidensekstraksjoner; slå sammen duplikate påstander; splitte sammensatte påstander; markere konflikt/usikkerhet; publisere/avpublisere; se diff og historikk; og rulle tilbake en publisert endring.

**Begrunnelse:**  
Dette er nødvendig dersom menneskelig kontroll skal være reell snarere enn symbolsk. WHO legger ansvar hos identifiserbare aktører og anbefaler mekanismer for kontroll, ansvarlighet og korreksjon når KI brukes i helse. citeturn5search4turn5search5

### Prinsipp 16 — MVP skal prioritere oppslag og sammenligning over bred funksjonsmengde

**Konstitusjonstekst:**  
Første funksjonelle kjerne skal bestå av:

**globalt søk → virkestoffoppslag/monografivisning → standardisert sammenligningsmatrise → kilde/evidensvisning.**

Monografier skal genereres som konsistente visninger av den strukturerte kunnskapsbasen; sammenligningsmatrisen skal bruke de samme underliggende dimensjonene og påstandsobjektene og skal aldri vedlikeholdes som et separat sett med tekstlige sammenligninger.

**Begrunnelse:**  
Denne prioriteringen validerer den viktigste arkitektoniske antakelsen først: at samme kunnskap kan gjenbrukes på tvers av visninger. DMPs egen utvikling av strukturert legemiddelinformasjon via FHIR/ISO IDMP illustrerer verdien av standardiserte grunndata fremfor gjentatte fritekstdokumenter. citeturn7search1turn9search10turn9search12

### Prinsipp 17 — Nedtrapping, bytte og interaksjoner skal være transparente beregninger, ikke runtime-KI-råd

**Konstitusjonstekst:**  
MVP-en skal etter grunnleggende oppslag og sammenligning prioritere et **nedtrappings-/bytteverktøy** og en **interaksjonsutforsker**. Pasientspesifikke doseringsforløp skal beregnes deterministisk fra eksplisitte, versjonerte og faglig godkjente regler, norske tilgjengelige styrker/formuleringer og relevante farmakokinetiske forutsetninger; et språkmodellkall skal ikke generere den faktiske planen i produksjon.

For interaksjoner skal fravær av registrert interaksjon aldri presenteres som bevist fravær av interaksjon.

**Begrunnelse:**  
DMP tilbyr både strukturerte norske legemiddeldata og en forvaltet interaksjonsdatabase, men understreker selv at databasens inklusjonskriterier gjør at enkelte teoretiske eller dårlig dokumenterte interaksjoner ikke finnes der, slik at «ingen treff» ikke alltid betyr «ingen risiko». Dette taler for å bruke KI til evidensarbeid og forklaring, men deterministiske regler for selve kliniske beregningen. citeturn7search6turn8search0turn8search1turn8search2

## Personvern, regelverk og skalerbarhet

### Prinsipp 18 — Antidep skal være personvernminimerende som standard

**Konstitusjonstekst:**  
MVP-en skal ikke kreve pasientidentitet, fritekstjournal, personnummer, fødselsdato eller permanent pasientprofil. Kliniske parametere som tastes inn i kalkulatorer skal som standard behandles uten varig lagring og skal ikke sendes til tredjeparts analyse-, sporings- eller KI-tjenester; enhver senere funksjon som behandler identifiserbare pasient- eller helseopplysninger skal gjennom en dokumentert vurdering av behandlingsgrunnlag, dataminimering, innebygd personvern, databehandlere, sikkerhet og behov for DPIA **før** utvikling eller produksjonssetting.

**Begrunnelse:**  
Helseopplysninger er en særlig kategori personopplysninger etter GDPR artikkel 9, og GDPR/Datatilsynet krever blant annet formålsbegrensning, dataminimering, innebygd personvern og risikovurdering; DPIA kreves der behandlingen sannsynligvis medfører høy risiko. Helsedirektoratets KI-rundskriv fremhever de samme kravene for helse- og KI-prosjekter. citeturn2search10turn2search13turn1search12turn6search2

### Prinsipp 19 — Regulatorisk grense skal vurderes før funksjoner blir pasientspesifikke

**Konstitusjonstekst:**  
Antidep skal til enhver tid ha et eksplisitt dokumentert **tiltenkt formål**. Før en funksjon lanseres som kombinerer pasientspesifikke data med algoritmer for å anbefale valg, bytte, dose eller annen behandling, skal det gjennomføres og arkiveres en særskilt vurdering av om funksjonen kvalifiserer som medisinsk utstyr, hvilken risikoklasse som eventuelt gjelder, og hvilke regulatoriske krav dette utløser; betegnelser som «kun til informasjon» skal aldri brukes som substitutt for vurdering av funksjonens reelle tiltenkte bruk.

**Begrunnelse:**  
DMP beskriver beslutningsstøtte som kombinerer medisinske databaser og algoritmer med pasientspesifikke data og gir behandlingsanbefalinger som eksempel på programvare som kvalifiserer som medisinsk utstyr, mens generell litteratur, generelle behandlingsløp og enkelt søk kan falle utenfor. Dersom programvaren først kvalifiserer som medisinsk utstyr og gir informasjon brukt til terapeutiske beslutninger, sier MDR vedlegg VIII regel 11 at utgangspunktet er klasse IIa, med IIb eller III ved beslutninger med potensielt mer alvorlige konsekvenser. citeturn0search0turn6search9turn0search6

Det bør samtidig ligge en eksplisitt regel i prosjektet om at regulatoriske forutsetninger må kontrolleres på nytt ved større funksjonsendringer. Per **18. august 2026** arbeider norske myndigheter fortsatt med innlemmelse av EUs KI-forordning i norsk rett; regjeringen opplyste 4. august 2026 at den norske KI-loven skal på ny høring høsten 2026, med sikte på fremleggelse for Stortinget våren 2027. Antidep bør derfor følge utviklingen, men ikke bygge dagens compliance-logikk på den uriktige antakelsen at KI-forordningen allerede er gjennomført som norsk lov. citeturn1search2turn1search3

### Prinsipp 20 — Kunnskapsmodellen og agentpipen skal være leverandøruavhengige

**Konstitusjonstekst:**  
Claude Code Routines kan være første kjøreplattform, men ingen kanonisk Antidep-data, arbeidsflytstatus eller faglig regel skal være avhengig av Claude-spesifikke konsepter. Modellleverandører skal ligge bak utskiftbare adaptere; prompts, agentroller, modeller, modellversjoner og pipelinekonfigurasjon skal være versjonert; og samme kunnskapsbase skal kunne prosesseres av en annen modell, lokal modell eller deterministisk tjeneste uten redesign av datamodellen.

**Begrunnelse:**  
Dette skiller produktets varige kunnskapsinfrastruktur fra dagens rimeligste implementasjonsvalg og gjør samtidig KI-arbeidet mer reproduserbart og testbart. NISTs risikostyringsramme behandler testing, evaluering, verifikasjon og validering som livssyklusfunksjoner snarere enn egenskaper ved én bestemt modellleverandør. citeturn5search1turn5search7

## Anbefalt lagring i GitHub

Repoet `peohol/antidep` har allerede en `main`-gren og en svært enkel `README.md` som beskriver prosjektet som «En app om antidepressiver med nyttige funksjoner og informasjon for klinikere». fileciteturn1file0L2-L2 fileciteturn2file0L2-L4 Det gjør det naturlig å legge konstitusjonen under `docs/` og behandle fremtidige endringer i den som dokumenterte pull requests fremfor som uformelle tekstendringer.

Jeg anbefaler:

**Fil:** `docs/ANTIDEP_CONSTITUTION.md`  
**Arbeidsgren:** `docs/antidep-constitution`  
**Commit:** `docs: add Antidep Constitution`

En liten, men viktig styringsregel bør skrives inn i selve filen: **Endringer i Constitution skal alltid skje gjennom eksplisitt versjonskontroll og faglig gjennomgang; kode eller KI-prompts skal ikke få endre konstitusjonen automatisk.** På den måten blir dokumentet faktisk overordnet implementasjonen, snarere enn bare nok en konfigurasjonsfil.

```json
{
  "repository": "peohol/antidep",
  "base_branch": "main",
  "branch": "docs/antidep-constitution",
  "file_path": "docs/ANTIDEP_CONSTITUTION.md",
  "commit_message": "docs: add Antidep Constitution",
  "commands": [
    "git switch main",
    "git pull --ff-only",
    "git switch -c docs/antidep-constitution",
    "mkdir -p docs",
    "git add docs/ANTIDEP_CONSTITUTION.md",
    "git commit -m \"docs: add Antidep Constitution\"",
    "git push -u origin docs/antidep-constitution"
  ]
}
```