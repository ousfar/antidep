// ============================================================================
// Den strukturerte betydningen bak en publisert påstand
//
// Søsteren til `claim-certainty.ts`, og bygget etter samme regel: en verdi som
// ikke lar seg tolke skal bli en eksplisitt ukjent tilstand, ikke havne i en
// godartet gren. Tre akser holdes fra hverandre fordi de svarer på tre
// forskjellige spørsmål:
//
//   retning      hvilken vei påstanden konkluderer
//   størrelse    hvor mye, når grunnlaget forsvarer en tallfesting
//   komparator   hva det sammenlignes mot
//
// De henger sammen klinisk: et tall uten sitt effektmål betyr ingenting, og et
// effektmål uten komparator er ikke tolkbart
// (PRODUCT_INFORMATION_ARCHITECTURE.md §19). Derfor avledes de sammen, slik at
// en visning ikke kan plukke opp den ene og glemme den andre.
//
// ----------------------------------------------------------------------------
// Tre tilstander som ser like ut og betyr helt forskjellige ting
//
//   no_clear_difference   Antidep har konkludert: grunnlaget viser ingen klar
//                         forskjell. Et resultat.
//   not_expressed         påstanden uttrykker ingen strukturert retning. NULL
//                         i databasen. Ikke et resultat.
//   ingen vurderbar       grunnlaget lar seg ikke gradere. Ligger på
//   evidens               sikkerhetsaksen, ikke her (`claim-certainty.ts`).
//
// Ingen av dem betyr ingen effekt, ingen bivirkning eller ingen risiko
// (ANTIDEP_CONSTITUTION.md §17). En visning som slår dem sammen bryter §6.
//
// ----------------------------------------------------------------------------
// Hva denne koden antar om resten av schemaet, og hva som håndhever det
//
//   verdi krever mål, og mål krever verdi          migrasjon 004 håndhever begge
//   enhet påkrevd for mean_change/mean_difference  migrasjon 004 håndhever det
//   enhet forbudt for de dimensjonsløse målene     migrasjon 004 håndhever det
//   comparator_kind = 'drug' ⇔ komparator oppgitt  migrasjon 004 håndhever det
//   et kontrastivt mål krever en komparator        INGENTING håndhever dette
//
// De fire første kontrolleres likevel her, av samme grunn som i
// `claim-certainty.ts`: klienten leser også en database den ikke selv har
// migrert. Den siste er registrert som gjeld i MVP_IMPLEMENTATION_PLAN.md
// §74.7 — den skjules ikke her, men gjør heller ikke et ellers gyldig tall
// usynlig. Visningen svarer på den ved alltid å vise komparatoren sammen med
// tallet.
// ============================================================================

import {
  CLAIM_DIRECTIONS,
  COMPARATOR_KINDS,
  EFFECT_MEASURES,
  ESTIMATE_UNITS,
  type ClaimDirection,
  type ComparatorKind,
  type EffectMeasure,
  type EstimateUnit,
} from '../types/api'

// ----------------------------------------------------------------------------
// Retning
// ----------------------------------------------------------------------------

export type ClaimDirectionState =
  /** Påstanden konkluderer med en økning. */
  | { readonly kind: 'increase' }
  /** Påstanden konkluderer med en reduksjon. */
  | { readonly kind: 'decrease' }
  /**
   * Påstanden konkluderer med at grunnlaget ikke viser en klar forskjell. Et
   * resultat, og ikke det samme som at retningen ikke er angitt.
   */
  | { readonly kind: 'no_clear_difference' }
  /**
   * Påstanden uttrykker ingen strukturert retning. Ikke et resultat, og
   * spesielt ikke et nullfunn.
   */
  | { readonly kind: 'not_expressed' }
  /** En verdi utenfor vokabularet. Vis ukjent, aldri nøytral. */
  | { readonly kind: 'unknown'; readonly rawDirection: string }

// ----------------------------------------------------------------------------
// Komparator
// ----------------------------------------------------------------------------

export type ClaimComparatorState =
  /** Sammenlignet med et navngitt virkestoff. */
  | { readonly kind: 'drug'; readonly drugName: string }
  /** Sammenlignet med placebo. */
  | { readonly kind: 'placebo' }
  /**
   * Ingen komparator: påstanden gjelder en endring fra behandlingsstart.
   * Betyr ikke at komparatoren er ukjent.
   */
  | { readonly kind: 'none' }
  /**
   * Kontraktsbrudd.
   *
   *   `unrecognised_kind`        en komparatorkategori utenfor vokabularet.
   *   `unnamed_comparator_drug`  kategorien er `drug`, men virkestoffet er
   *                              ikke navngitt. Et unavngitt sammenligningsledd
   *                              gjør tallet utolkbart.
   *   `named_drug_without_drug_kind`
   *                              et komparatorvirkestoff er oppgitt på en
   *                              kategori som ikke er `drug`. De to sier
   *                              forskjellige ting om samme påstand.
   */
  | {
      readonly kind: 'unknown'
      readonly reason:
        'unrecognised_kind' | 'unnamed_comparator_drug' | 'named_drug_without_drug_kind'
      readonly rawComparatorKind: string
      readonly rawComparatorDrugName: string | null
    }

// ----------------------------------------------------------------------------
// Størrelse
// ----------------------------------------------------------------------------

/** Målene som er dimensjonsløse, og derfor aldri skal bære en enhet. */
const DIMENSIONLESS_MEASURES: readonly EffectMeasure[] = [
  'standardised_mean_difference',
  'risk_ratio',
  'odds_ratio',
]

export type ClaimMagnitudeState =
  /** Tallfestet, med det målet og den enheten tallet krever for å bety noe. */
  | {
      readonly kind: 'quantified'
      readonly measure: EffectMeasure
      readonly value: number
      /** `null` bare for de dimensjonsløse målene, der en enhet ville vært feil. */
      readonly unit: EstimateUnit | null
    }
  /**
   * Påstanden tallfester bevisst ikke størrelsen. Ikke det samme som at
   * effekten er null (§17); tallene fra kildene ligger på evidensfunnene.
   */
  | { readonly kind: 'not_quantified' }
  /**
   * Kontraktsbrudd. Felles konsekvens: vis at størrelsen ikke er tolkbar, og
   * vis aldri tallet alene.
   *
   *   `value_without_measure`   et tall uten effektmål. 1,7 kan være en
   *                             gjennomsnittsforskjell eller en oddsratio.
   *   `measure_without_value`   et effektmål uten tall lover en kvantifisering
   *                             påstanden ikke har.
   *   `unrecognised_measure`    et mål utenfor vokabularet.
   *   `unrecognised_unit`       en enhet utenfor vokabularet.
   *   `missing_unit`            et dimensjonalt mål uten enhet. 1,7 kan være
   *                             kilogram eller prosent.
   *   `unit_on_dimensionless_measure`
   *                             en enhet på et dimensjonsløst mål. «1,7 kg»
   *                             for en oddsratio er en annen påstand.
   */
  | {
      readonly kind: 'unknown'
      readonly reason:
        | 'value_without_measure'
        | 'measure_without_value'
        | 'unrecognised_measure'
        | 'unrecognised_unit'
        | 'missing_unit'
        | 'unit_on_dimensionless_measure'
      readonly rawMeasure: string | null
      readonly rawValue: number | null
      readonly rawUnit: string | null
    }

// ----------------------------------------------------------------------------

export interface ClaimEffect {
  readonly direction: ClaimDirectionState
  readonly magnitude: ClaimMagnitudeState
  readonly comparator: ClaimComparatorState
}

/** Feltene avledningen leser. `PublishedClaimRow` oppfyller den. */
export interface ClaimEffectInput {
  readonly direction: string | null
  readonly comparator_kind: string
  readonly comparator_drug_name: string | null
  readonly magnitude_measure: string | null
  readonly magnitude_value: number | null
  readonly magnitude_unit: string | null
}

function isClaimDirection(value: string): value is ClaimDirection {
  return (CLAIM_DIRECTIONS as readonly string[]).includes(value)
}

function isComparatorKind(value: string): value is ComparatorKind {
  return (COMPARATOR_KINDS as readonly string[]).includes(value)
}

function isEffectMeasure(value: string): value is EffectMeasure {
  return (EFFECT_MEASURES as readonly string[]).includes(value)
}

function isEstimateUnit(value: string): value is EstimateUnit {
  return (ESTIMATE_UNITS as readonly string[]).includes(value)
}

export function describeClaimDirection(direction: string | null): ClaimDirectionState {
  if (direction === null) {
    return { kind: 'not_expressed' }
  }
  if (!isClaimDirection(direction)) {
    return { kind: 'unknown', rawDirection: direction }
  }
  // Vokabularet er lukket, så grenene under er uttømmende. Skrevet ut framfor
  // som en gjennomstikking, slik at en femte verdi blir en typefeil her.
  switch (direction) {
    case 'increase':
      return { kind: 'increase' }
    case 'decrease':
      return { kind: 'decrease' }
    case 'no_clear_difference':
      return { kind: 'no_clear_difference' }
  }
}

export function describeClaimComparator(
  kind: string,
  drugName: string | null,
): ClaimComparatorState {
  const raw = { rawComparatorKind: kind, rawComparatorDrugName: drugName } as const

  if (!isComparatorKind(kind)) {
    return { kind: 'unknown', reason: 'unrecognised_kind', ...raw }
  }
  if (kind === 'drug') {
    if (drugName === null) {
      return { kind: 'unknown', reason: 'unnamed_comparator_drug', ...raw }
    }
    return { kind: 'drug', drugName }
  }
  // Den andre halvdelen av «kategorien er drug hvis og bare hvis et virkestoff
  // er oppgitt». Uten den ville et navn på en placebo-sammenligning blitt borte.
  if (drugName !== null) {
    return { kind: 'unknown', reason: 'named_drug_without_drug_kind', ...raw }
  }
  return kind === 'placebo' ? { kind: 'placebo' } : { kind: 'none' }
}

export function describeClaimMagnitude(
  measure: string | null,
  value: number | null,
  unit: string | null,
): ClaimMagnitudeState {
  const raw = { rawMeasure: measure, rawValue: value, rawUnit: unit } as const

  if (measure === null) {
    // Et tall uten sitt mål er ikke en størrelse, og skal ikke vises som ett.
    if (value !== null) {
      return { kind: 'unknown', reason: 'value_without_measure', ...raw }
    }
    // Uten mål og uten verdi er en enhet alene også et brudd.
    if (unit !== null) {
      return { kind: 'unknown', reason: 'unit_on_dimensionless_measure', ...raw }
    }
    return { kind: 'not_quantified' }
  }

  if (!isEffectMeasure(measure)) {
    return { kind: 'unknown', reason: 'unrecognised_measure', ...raw }
  }
  if (value === null) {
    return { kind: 'unknown', reason: 'measure_without_value', ...raw }
  }
  if (!Number.isFinite(value)) {
    return { kind: 'unknown', reason: 'value_without_measure', ...raw }
  }

  const dimensionless = DIMENSIONLESS_MEASURES.includes(measure)
  if (unit === null) {
    if (!dimensionless) {
      return { kind: 'unknown', reason: 'missing_unit', ...raw }
    }
    return { kind: 'quantified', measure, value, unit: null }
  }
  if (dimensionless) {
    return { kind: 'unknown', reason: 'unit_on_dimensionless_measure', ...raw }
  }
  if (!isEstimateUnit(unit)) {
    return { kind: 'unknown', reason: 'unrecognised_unit', ...raw }
  }
  return { kind: 'quantified', measure, value, unit }
}

export function describeClaimEffect(claim: ClaimEffectInput): ClaimEffect {
  return {
    direction: describeClaimDirection(claim.direction),
    magnitude: describeClaimMagnitude(
      claim.magnitude_measure,
      claim.magnitude_value,
      claim.magnitude_unit,
    ),
    comparator: describeClaimComparator(claim.comparator_kind, claim.comparator_drug_name),
  }
}
