// ============================================================================
// Vokabularene fra `api`, oversatt til norsk
//
// Ett sted, fordi de samme verdiene står i to rader med to forskjellige
// epistemiske statuser: `magnitude_measure` på en publisert påstand er Antideps
// syntese, `effect_measure` på et evidensfunn er det kilden målte. Målet betyr
// likevel nøyaktig det samme — en oddsratio er en oddsratio uansett hvilken rad
// den står i — og to oversettelser av samme vokabular ville før eller siden
// drevet fra hverandre og latt de to radene se ut som forskjellige størrelser.
//
// Bare oversettelsen ligger her. Hva en verdi *betyr*, og hva som skjer når den
// er ukjent, avgjøres i avledningene (`claim-effect.ts`, `evidence-item.ts`);
// en oppslagstabell er ingen kjøretidskontroll, og en `Record` over en lukket
// union kan ikke slå opp en verdi utenfor den.
// ============================================================================

import type { EffectMeasure, EstimateUnit, KnowledgeType } from '../types/api'

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
