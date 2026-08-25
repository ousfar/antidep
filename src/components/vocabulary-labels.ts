// ============================================================================
// Vokabularene fra `api`, oversatt til norsk
//
// Ett sted, fordi de samme verdiene står i flere rader og i flere visninger.
// `magnitude_measure` på en publisert påstand er Antideps syntese,
// `effect_measure` på et evidensfunn er det kilden målte; målet betyr likevel
// nøyaktig det samme — en oddsratio er en oddsratio uansett hvilken rad den står
// i — og to oversettelser av samme vokabular ville før eller siden drevet fra
// hverandre og latt de to radene se ut som forskjellige størrelser. Det samme
// gjelder kildens dokumenttype og status, som nå står både på hvert evidensfunn
// og på kildesiden (PRODUCT_INFORMATION_ARCHITECTURE.md §42).
//
// Oversettelsen ligger her, og det gjør også `termText()`: gjengivelsen av en
// term som *ikke* lot seg kjenne igjen er en del av oversettelsen, og den må
// være den samme overalt. Hva en verdi *betyr*, og hvordan det avgjøres om den
// er kjent, hører fortsatt hjemme i avledningene (`claim-effect.ts`,
// `evidence-item.ts`); en oppslagstabell er ingen kjøretidskontroll, og en
// `Record` over en lukket union kan ikke slå opp en verdi utenfor den.
// ============================================================================

import type { EvidenceStance, VocabularyTerm } from '../lib/evidence-item'
import type {
  EffectMeasure,
  EstimateUnit,
  EvidenceRelationshipType,
  KnowledgeType,
  SourceStatus,
  SourceType,
} from '../types/api'

/**
 * En vokabularverdi, oversatt — eller sagt at den er ukjent, aldri gjettet.
 *
 * Råverdien skrives ut sammen med meldingen. Uten den ville en klient som møter
 * en ny enum-verdi bare kunne si «ukjent», og den som skal rette feilen måtte
 * lete i databasen etter hva som faktisk stod der.
 */
export function termText<Term extends string>(
  term: VocabularyTerm<Term>,
  labels: Record<Term, string>,
  what: string,
): string {
  return term.kind === 'known' ? labels[term.value] : `Ukjent ${what} («${term.raw}»)`
}

export const KNOWLEDGE_TYPE_LABELS: Record<KnowledgeType, string> = {
  deterministic_fact: 'Deterministisk faktum',
  evidence_synthesis: 'Evidensbasert syntese',
  clinical_recommendation: 'Klinisk anbefaling',
}

export const MEASURE_LABELS: Record<EffectMeasure, string> = {
  mean_change: 'Gjennomsnittlig endring',
  mean_difference: 'Gjennomsnittsforskjell',
  standardised_mean_difference: 'Standardisert gjennomsnittsforskjell (SMD)',
  risk_ratio: 'Relativ risiko (RR)',
  odds_ratio: 'Oddsratio (OR)',
}

export const UNIT_LABELS: Record<EstimateUnit, string> = {
  kg: 'kg',
  percent: '%',
}

/**
 * Antideps vurdering av hvordan ett evidensfunn forholder seg til påstanden.
 *
 * Formulert som utsagn om påstanden, ikke som etiketter: «Støtter» alene ville
 * ikke sagt hva funnet støtter.
 *
 * Bevisst ikke eksportert. Oppslaget går gjennom `stanceText()`, som tar imot
 * den avledede relasjonen og ikke råverdien — da finnes det ingen vei der en
 * relasjon Antidep ikke kjenner, kan slå opp som noe annet enn ukjent, og et
 * motstridende funn kan ikke presenteres som støtte (ANTIDEP_CONSTITUTION.md §9).
 */
const RELATIONSHIP_LABELS: Record<EvidenceRelationshipType, string> = {
  supports: 'Støtter påstanden',
  partially_supports: 'Støtter deler av påstanden',
  contradicts: 'Motsier påstanden',
  neutral_contextual: 'Verken for eller mot påstanden',
  indirect: 'Bare indirekte bedømbart mot påstanden',
}

/**
 * Relasjonen ett funn har til påstanden, som tekst.
 *
 * Den ukjente tilstanden har sin egen setning og deler ingen ordlyd med de fem
 * kjente. Begge visningene som viser et funn — evidensvisningen og kildesiden —
 * bruker denne, slik at «motsier påstanden» ikke kan bli til noe annet det ene
 * stedet (§9). Hvorfor relasjonen ikke lot seg tolke, hører til
 * evidensvisningen, som har plass til hele forklaringen.
 */
export function stanceText(stance: EvidenceStance): string {
  return stance.kind === 'known'
    ? RELATIONSHIP_LABELS[stance.relationship]
    : 'Antideps vurdering av dette funnet er ikke tolkbar'
}

/** Hva slags dokument kilden er. Egen akse fra studiedesignet funnet er hentet fra. */
export const SOURCE_TYPE_LABELS: Record<SourceType, string> = {
  journal_article: 'Fagfellevurdert artikkel',
  clinical_guideline: 'Klinisk retningslinje',
  summary_of_product_characteristics: 'Preparatomtale (SPC)',
  regulatory_communication: 'Regulatorisk melding',
  public_dataset: 'Offentlig datasett',
}

/**
 * Kildestatusene, formulert som utsagn om dokumentet. `active` skrives ut som
 * alle de andre: en status som bare vises når den er avvikende, gjør fravær av
 * merking til en påstand ingen har tatt stilling til.
 */
export const SOURCE_STATUS_LABELS: Record<SourceStatus, string> = {
  active: 'I bruk',
  outdated: 'Utdatert, uten at en bestemt etterfølger er registrert',
  superseded: 'Erstattet av en nyere kilde',
  retracted: 'Trukket tilbake av tidsskrift eller utgiver',
  withdrawn: 'Tatt ut av bruk av utgiveren',
}
