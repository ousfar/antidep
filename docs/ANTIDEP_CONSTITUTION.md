# Antidep Constitution

**Versjon:** 0.1  
**Dato:** 18. august 2026

Dette dokumentet definerer de overordnede prinsippene som skal styre Antidep over tid. Prinsippene skal ha forrang foran kortsiktige implementasjonsvalg. Endringer i konstitusjonen skal være eksplisitte, versjonskontrollerte og faglig gjennomgått; kode, KI-agenter eller automatiserte prosesser skal aldri endre dokumentet på egen hånd.

## 1. Antidep er et klinisk arbeidsverktøy for helsepersonell

Antidep skal primært utvikles for klinikere i Norge som trenger rask, presis og etterprøvbar informasjon om antidepressiver i kliniske beslutningssituasjoner. Produktet skal optimaliseres for praktisk klinisk nytte, ikke for maksimal tekstmengde, generell pasientinformasjon eller akademisk fullstendighet.

## 2. Informasjon skal være lagdelt, konsis og tilgjengelig

Antidep skal vise den minste informasjonsmengden som er tilstrekkelig for den aktuelle oppgaven, med progressiv fordypning til metode, evidens og primærkilder. Alle sentrale funksjoner skal fungere på mobil og desktop. Visuelle indikatorer skal supplere tekst, men aldri være eneste bærer av klinisk informasjon.

## 3. Språk skal være nøkternt, presist og konsekvent

Antidep skal alltid bruke **antidepressiver**, aldri *antidepressiva*. Norsk bokmål er standardspråk. Formuleringer skal være klinisk presise, kortfattede og ikke-promoterende. Absolutte formuleringer skal bare brukes når evidensgrunnlaget forsvarer dem.

## 4. Enhver klinisk relevant påstand skal være etterprøvbar

Ingen publisert klinisk relevant påstand skal eksistere uten eksplisitt kobling til én eller flere identifiserbare kilder og dokumentasjon av hvordan kildene støtter, nyanserer eller motsier påstanden. En kilde som bare omhandler samme tema, men ikke faktisk underbygger formuleringen, skal ikke godtas som støtte.

## 5. Antidep skal skille mellom tre kunnskapstyper

Alt innhold skal klassifiseres som én av følgende hovedtyper:

1. **Deterministisk faktum** — for eksempel handelsnavn, legemiddelform, styrke eller markedsføringsstatus.
2. **Evidensbasert syntese** — en vurdering av et forskningsgrunnlag, for eksempel relativ risiko for vektøkning.
3. **Klinisk anbefaling** — en normativ vurdering av hva klinikeren bør gjøre.

Typene skal ha separate valideringsregler og skal aldri presenteres som om de hadde samme epistemiske status.

## 6. Usikkerhet skal graderes og forklares

Usikkerhet skal aldri skjules eller erstattes av falsk presisjon. Evidensbaserte synteser skal ha en eksplisitt vurdering av sikkerheten i kunnskapsgrunnlaget. Når GRADE er egnet, skal kategoriene **høy, moderat, lav eller svært lav sikkerhet** brukes med eksplisitt vurdering av relevante domener. **Ingen vurderbar evidens** skal være en separat systemtilstand og aldri fremstilles som lav risiko eller liten effekt.

## 7. Påstanden, ikke monografien, er kunnskapsbasens grunnenhet

Hver selvstendig klinisk relevant påstand skal være et separat, stabilt identifiserbart og versjonert objekt. Objektet skal minst kunne beskrive tema, berørte virkestoffer, presis formulering, anvendelsesområde eller populasjon, status, sikkerhetsgrad og tidspunkt for siste faglige vurdering. Monografier skal være visninger av kunnskapsbasen, ikke den kanoniske lagringsformen for kunnskapen.

## 8. Evidens og proveniens skal være førsteklasses data

Koblingen mellom kilde og påstand skal lagres som et eget evidensobjekt, ikke bare som en referanseliste. Det skal være mulig å spore hvilken kilde, hvilken del av kilden, hvilke data og hvilke vurderinger som førte til en bestemt påstand og versjon, samt hvem eller hva som ekstraherte og verifiserte informasjonen.

## 9. Motstridende evidens skal bevares

Relevant evidens som motsier en publisert syntese skal ikke fjernes eller skjules. Ved reell uenighet i forskningen skal Antidep beskrive uenigheten, mulige årsaker og hvordan den påvirker sikkerheten i konklusjonen. Systemet skal aktivt motvirke bekreftelsesskjevhet.

## 10. KI-arbeidet skal deles i eksplisitte roller

Agentarbeid skal minst skille logisk mellom:

- kildesøk
- kildekvalitetsvurdering
- data- og evidensekstraksjon
- påstandsformulering og syntese
- motargumenterende kontroll
- sitat- og kildestøtteverifikasjon
- redaksjonell komprimering

Én agentkjøring skal aldri alene få gå direkte fra kildefunn til publisert klinisk innhold.

## 11. Verifikasjon skal forsøke å falsifisere

Før en KI-generert syntese kan godkjennes, skal en separat kontrollfase aktivt lete etter feilsitering, overtolkning, manglende forbehold, motstridende forskning, feil populasjon eller endepunkt, utdaterte kilder og numeriske avvik. Verifikatoren skal ha tilgang til kildematerialet og skal ikke godkjenne påstander ut fra andre agenters sammendrag alene.

## 12. KI kan foreslå; mennesker har det faglige ansvaret

KI skal aldri være endelig faglig autoritet. Evidenssynteser skal ha menneskelig faglig godkjenning før første publisering. Kliniske anbefalinger, doseringsregler, bytte- og nedtrappingsregler og andre endringer med direkte potensial til å påvirke behandling skal kreve eksplisitt godkjenning fra en navngitt kvalifisert redaktør.

## 13. Alt publisert innhold skal ha en eksplisitt livssyklus

Innhold skal minst kunne bevege seg gjennom følgende tilstander:

`draft → source-verified → human-approved → published → review-due → retired/superseded`

Tidligere publiserte versjoner skal bevares i revisjonshistorikken. Oppdateringsfrekvens skal tilpasses kunnskapstypen og risikoen ved å være utdatert. Nye sentrale data eller sikkerhetssignaler skal kunne utløse tidligere revurdering.

## 14. Endringer skal være reversible, attribuerte og rapporterbare

Enhver endring i påstander, evidensobjekter, kilder, anbefalinger eller verktøyregler skal registrere hvem eller hvilken agent som gjorde endringen, når den ble gjort, hvorfor den ble gjort og hvilken tidligere versjon den erstattet. Brukere skal kunne rapportere mulig feil direkte fra relevante visninger, knyttet til det konkrete objektet eller den konkrete versjonen.

## 15. Admin-UX er et kjerneprodukt

Kvalifiserte redaktører skal uten bruk av Claude, ChatGPT eller direkte databaseinngrep kunne utføre vanlige faglige innholdsendringer: opprette og redigere påstander, godkjenne eller forkaste KI-forslag, overstyre KI-vurderinger, håndtere kilder og evidensrelasjoner, korrigere ekstraksjoner, markere konflikt og usikkerhet, publisere og avpublisere, se diff og historikk og rulle tilbake endringer.

## 16. Samme kunnskapsbase skal drive alle visninger

Monografier, sammenligninger, søk, kliniske problemstillinger og senere verktøy skal gjenbruke den samme strukturerte kunnskapen. Parallelle fritekstkopier av samme kunnskap skal unngås. Sammenligninger skal beregnes eller genereres fra de samme underliggende dimensjonene og påstandsobjektene som legemiddeloppslagene.

## 17. Kliniske beregninger skal være transparente og deterministiske der det er mulig

Nedtrapping, bytte, doseberegninger og andre produksjonsnære kliniske beregninger skal baseres på eksplisitte, versjonerte og faglig godkjente regler, norske tilgjengelige styrker og formuleringer og relevante farmakokinetiske forutsetninger. Et språkmodellkall skal ikke alene generere den faktiske planen som presenteres som klinisk verktøy.

Fravær av registrert interaksjon eller evidens skal aldri presenteres som bevist fravær av risiko.

## 18. Antidep skal være personvernminimerende som standard

Antidep skal ikke kreve mer person- eller pasientinformasjon enn funksjonen strengt tatt trenger. MVP-en skal ikke kreve pasientidentitet, fritekstjournal, personnummer eller permanent pasientprofil. Kliniske parametere som brukes i kalkulatorer skal som standard ikke lagres permanent eller sendes til tredjeparts KI-, analyse- eller sporingstjenester. Funksjoner som senere behandler identifiserbare helseopplysninger skal vurderes særskilt før utvikling eller produksjonssetting.

## 19. Regulatorisk grense skal vurderes før funksjoner blir pasientspesifikke

Antidep skal til enhver tid ha et eksplisitt dokumentert tiltenkt formål. Før en funksjon lanseres som kombinerer pasientspesifikke data med algoritmer for å anbefale valg, bytte, dose eller annen behandling, skal det gjennomføres og arkiveres en særskilt vurdering av om funksjonen kvalifiserer som medisinsk utstyr og hvilke regulatoriske krav som eventuelt utløses. Et merke som «kun til informasjon» skal aldri brukes som erstatning for vurdering av funksjonens reelle tiltenkte bruk.

Regulatoriske forutsetninger skal revurderes ved større funksjonsendringer.

## 20. Kunnskapsmodellen og agentpipen skal være leverandøruavhengige

Claude Code Routines kan være første kjøreplattform, men ingen kanonisk Antidep-data, arbeidsflytstatus eller faglig regel skal være avhengig av Claude-spesifikke konsepter. Modellleverandører skal ligge bak utskiftbare adaptere. Prompts, agentroller, modeller, modellversjoner og pipelinekonfigurasjon skal være versjonert. Kunnskapsbasen skal kunne prosesseres av andre modeller eller deterministiske tjenester uten redesign av datamodellen.

---

## Styringsregel

Ved konflikt mellom et kortsiktig implementasjonsvalg og disse prinsippene skal implementasjonen endres, med mindre selve konstitusjonen eksplisitt revideres gjennom faglig gjennomgang og versjonskontroll.

## Metodisk og regulatorisk grunnlag

Konstitusjonen er blant annet inspirert av prinsipper og veiledning fra:

- GRADE Working Group og Cochrane om transparent vurdering av sikkerhet i evidensgrunnlaget.
- WHO om etikk, styring, menneskelig kontroll og verifikasjon ved bruk av KI i helse.
- HL7 FHIR Provenance om sporbarhet, versjoner, aktører og opphav.
- NIST AI Risk Management Framework om testing, evaluering, verifikasjon og validering av KI-systemer.
- Direktoratet for medisinske produkter (DMP) om strukturerte norske legemiddeldata, FEST/FHIR, interaksjonsdata og programvare som medisinsk utstyr.
- Helsedirektoratet om klinisk beslutningsstøtte og regelverk for KI i helse.
- Datatilsynet og GDPR om dataminimering og innebygd personvern.
- W3C WCAG om tilgjengelighet og om at farge eller andre visuelle signaler ikke alene skal formidle viktig informasjon.

### Utvalgte kilder

- Cochrane Handbook, Chapter 14: https://www.cochrane.org/authors/handbooks-and-manuals/handbook/current/chapter-14
- GRADE Working Group: https://www.gradeworkinggroup.org/
- WHO, Ethics and governance of artificial intelligence for health: https://www.who.int/publications/i/item/9789240029200
- HL7 FHIR Provenance: https://hl7.org/fhir/provenance.html
- NIST AI Risk Management Framework: https://www.nist.gov/itl/ai-risk-management-framework
- DMP, FEST: https://www.dmp.no/om-oss/distribusjon-av-legemiddeldata/fest
- DMP, FHIR-tjenesten: https://www.dmp.no/om-oss/distribusjon-av-legemiddeldata/FHIR-tjenesten
- DMP, programvare som medisinsk utstyr: https://www.dmp.no/medisinsk-utstyr/utvikling-og-produksjon/programvare-som-medisinsk-utstyr
- Helsedirektoratet, regelverket for utvikling av kunstig intelligens: https://www.helsedirektoratet.no/rundskriv/regelverket-for-utvikling-av-kunstig-intelligens
- Datatilsynet, personvernprinsippene: https://www.datatilsynet.no/rettigheter-og-plikter/personvernprinsippene/
- W3C, WCAG 2: https://www.w3.org/WAI/standards-guidelines/wcag/
