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
// ----------------------------------------------------------------------------
// Effektmål og komparator er én påstand, ikke to
//
// `comparator_kind = 'none'` betyr ikke «komparator mangler». Migrasjon 004 sier
// eksplisitt at det betyr *en endring fra behandlingsstart uten komparator*. Det
// er en påstand om hva tallet måler, og den må stemme med effektmålet:
//
//   mean_change                     endring innenfor én arm     → hører til 'none'
//   mean_difference, SMD, RR, OR    forskjell mellom to armer   → krever komparator
//
// Et par som bryter dette er ikke bare uvanlig, det betyr noe annet.
// «Gjennomsnittsforskjell 1,7 kg» med `none` har ingen gruppe å være forskjellig
// fra, og å presentere den som «endring fra behandlingsstart» ville gitt et
// kontraktsbrudd en plausibel, men gal klinisk betydning. Størrelsen avledes
// derfor med komparatoren i hånden, og et uforenlig par kan ikke bli
// `quantified`: tallet er utilgjengelig for visningen framfor å måtte huskes
// skjult av den.
//
// Kontrastiv er komplementet til innenfor-arm, ikke en egen liste. Et sjette
// effektmål krever dermed komparator til noen tar stilling til det. Feil vei er
// å anta at et mål vi ikke har vurdert er tolkbart uten sammenligningsledd.
//
// Tre tilstander holdes fra hverandre, fordi de krever hver sin retting:
//
//   gyldig 'none'                 målet beskriver faktisk endring fra baseline
//   ukjent/mangelfull komparator  komparatorfeltet er i seg selv brutt
//   uforenlig par                 hvert felt er gyldig, sammen er de ikke
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
//   komparatoren er ikke virkestoffet selv         migrasjon 004 håndhever det
//   et kontrastivt mål krever en komparator        INGENTING håndhever dette
//
// De fem første kontrolleres likevel her, av samme grunn som i
// `claim-certainty.ts`: klienten leser også en database den ikke selv har
// migrert. Den siste er registrert som gjeld i MVP_IMPLEMENTATION_PLAN.md §74.7.
// Databasen tillater den fortsatt; presentasjonslaget nekter å tolke den. De to
// er forskjellige lag, og dette laget lukker ikke det andre.
//
// Migrasjon 003 håndhever de samme reglene på evidensfunnene, og de betyr det
// samme der: et effektmål er det samme uansett hvilken rad det står i.
// `evidence-item.ts` gjenbruker derfor avledningene her framfor å få sin egen
// utgave av dem — se `describeMeasureUnit()`, som er skilt ut nettopp for det.
// ============================================================================

import type { ClaimCertainty } from './claim-certainty'
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

/**
 * Kontraktsbrudd på komparatoren.
 *
 *   `unrecognised_kind`        en komparatorkategori utenfor vokabularet.
 *   `unnamed_comparator_drug`  kategorien er `drug`, men virkestoffet er ikke
 *                              navngitt. Et unavngitt sammenligningsledd gjør
 *                              tallet utolkbart.
 *   `named_drug_without_drug_kind`
 *                              et komparatorvirkestoff er oppgitt på en
 *                              kategori som ikke er `drug`. De to sier
 *                              forskjellige ting om samme påstand.
 *   `comparator_is_subject_drug`
 *                              påstanden sammenlignes med virkestoffet den selv
 *                              handler om. «Sammenlignet med sertralin» på en
 *                              påstand om sertralin er ingen sammenligning.
 */
export type ClaimComparatorFault =
  | 'unrecognised_kind'
  | 'unnamed_comparator_drug'
  | 'named_drug_without_drug_kind'
  | 'comparator_is_subject_drug'

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
  | {
      readonly kind: 'unknown'
      readonly reason: ClaimComparatorFault
      readonly rawComparatorKind: string
      readonly rawComparatorDrugName: string | null
    }

// ----------------------------------------------------------------------------
// Størrelse
// ----------------------------------------------------------------------------

/**
 * Målene som beskriver en endring innenfor én arm, og derfor er meningsfulle
 * uten komparator. Alle andre effektmål uttrykker en forskjell mellom to
 * grupper — se merknaden øverst om hvorfor kontrastiv er komplementet.
 */
const WITHIN_ARM_MEASURES: readonly EffectMeasure[] = ['mean_change']

/** Målene som ikke bærer en enhet, fordi de er dimensjonsløse (migrasjon 004). */
const DIMENSIONLESS_MEASURES: readonly EffectMeasure[] = [
  'standardised_mean_difference',
  'risk_ratio',
  'odds_ratio',
]

/** Om et effektmål måler innenfor én arm framfor mellom to. */
export function isWithinArmMeasure(measure: EffectMeasure): boolean {
  return WITHIN_ARM_MEASURES.includes(measure)
}

/**
 * Om et effektmål og en enhet er et forenlig par.
 *
 * Skilt ut fordi regelen ikke hører til påstandsraden: migrasjon 003 håndhever
 * nøyaktig det samme paret på evidensfunnene, og et effektmål betyr det samme
 * uansett hvilken rad det står i. `evidence-item.ts` bruker den der en verdi
 * mangler og størrelsesavledningen under derfor ikke kan kjøres, slik at de to
 * lagene ikke får hver sin utgave av enhetsregelen.
 */
export type MeasureUnitPairing =
  | { readonly kind: 'ok'; readonly unit: EstimateUnit | null }
  | {
      readonly kind: 'unknown'
      readonly reason: 'unrecognised_unit' | 'missing_unit' | 'unit_on_dimensionless_measure'
    }

export function describeMeasureUnit(
  measure: EffectMeasure,
  unit: string | null,
): MeasureUnitPairing {
  const dimensionless = DIMENSIONLESS_MEASURES.includes(measure)
  if (unit === null) {
    // Et dimensjonsløst mål *skal* stå uten enhet; et dimensjonalt mål uten
    // enhet er klinisk tvetydig — 1,7 kan være kilogram eller prosent.
    return dimensionless ? { kind: 'ok', unit: null } : { kind: 'unknown', reason: 'missing_unit' }
  }
  if (dimensionless) {
    return { kind: 'unknown', reason: 'unit_on_dimensionless_measure' }
  }
  if (!isEstimateUnit(unit)) {
    return { kind: 'unknown', reason: 'unrecognised_unit' }
  }
  return { kind: 'ok', unit }
}

/**
 * Kontraktsbrudd på størrelsen. Felles konsekvens: vis at størrelsen ikke er
 * tolkbar, og vis aldri tallet alene.
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
 *                             en enhet på et dimensjonsløst mål. «1,7 kg» for
 *                             en oddsratio er en annen påstand.
 *   `contrastive_measure_without_comparator`
 *                             et mål som uttrykker forskjell mellom to grupper,
 *                             uten noen gruppe å være forskjellig fra.
 *   `within_arm_measure_with_comparator`
 *                             en endring innenfor én arm, presentert som om den
 *                             var en sammenligning mot noe annet.
 *   `comparator_not_interpretable`
 *                             komparatoren er selv brutt, så tallet kan ikke
 *                             festes til noe.
 *   `precision_exceeds_assessable_evidence`
 *                             en tallfestet effekt på en påstand der grunnlaget
 *                             er vurdert som ikke graderbart. Migrasjon 004 sier
 *                             at `no_assessable_evidence` betyr at det ikke
 *                             finnes tilstrekkelig grunnlag til å gjøre en
 *                             vurdering i det hele tatt, og at «en påstand som
 *                             er mer presis enn evidensen under den, er et brudd
 *                             på ANTIDEP_CONSTITUTION.md §4 og §6».
 */
export type ClaimMagnitudeFault =
  | 'value_without_measure'
  | 'measure_without_value'
  | 'unrecognised_measure'
  | 'unrecognised_unit'
  | 'missing_unit'
  | 'unit_on_dimensionless_measure'
  | 'contrastive_measure_without_comparator'
  | 'within_arm_measure_with_comparator'
  | 'comparator_not_interpretable'
  | 'precision_exceeds_assessable_evidence'

export type ClaimMagnitudeState =
  /**
   * Tallfestet, med det målet og den enheten tallet krever for å bety noe — og
   * med en komparator som stemmer med målet. Konstruksjonen er den samme som
   * for `ok` i lesemodellen: den ugyldige kombinasjonen finnes ikke i denne
   * grenen, så en visning kan ikke glemme å sjekke den.
   */
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
  | {
      readonly kind: 'unknown'
      readonly reason: ClaimMagnitudeFault
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

/** Feltene komparatoravledningen leser. `PublishedClaimRow` oppfyller den. */
export interface ClaimComparatorInput {
  readonly drug_id: string
  readonly comparator_kind: string
  readonly comparator_drug_id: string | null
  readonly comparator_drug_name: string | null
}

/** Feltene størrelsesavledningen leser. `PublishedClaimRow` oppfyller den. */
export interface ClaimMagnitudeInput {
  readonly magnitude_measure: string | null
  readonly magnitude_value: number | null
  readonly magnitude_unit: string | null
}

/** Feltene hele avledningen leser. `PublishedClaimRow` oppfyller den. */
export interface ClaimEffectInput extends ClaimComparatorInput, ClaimMagnitudeInput {
  readonly direction: string | null
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

export function describeClaimComparator(claim: ClaimComparatorInput): ClaimComparatorState {
  const kind = claim.comparator_kind
  const drugName = claim.comparator_drug_name
  const raw = { rawComparatorKind: kind, rawComparatorDrugName: drugName } as const

  if (!isComparatorKind(kind)) {
    return { kind: 'unknown', reason: 'unrecognised_kind', ...raw }
  }
  if (kind === 'drug') {
    if (drugName === null) {
      return { kind: 'unknown', reason: 'unnamed_comparator_drug', ...raw }
    }
    // En påstand kan ikke sammenlignes med seg selv. Identiteten avgjør, ikke
    // navnet: to katalogoppføringer kan bære samme visningsnavn.
    if (claim.comparator_drug_id !== null && claim.comparator_drug_id === claim.drug_id) {
      return { kind: 'unknown', reason: 'comparator_is_subject_drug', ...raw }
    }
    return { kind: 'drug', drugName }
  }
  // Den andre halvdelen av «kategorien er drug hvis og bare hvis et virkestoff
  // er oppgitt». Uten den ville et navn på en placebo-sammenligning blitt borte.
  if (drugName !== null || claim.comparator_drug_id !== null) {
    return { kind: 'unknown', reason: 'named_drug_without_drug_kind', ...raw }
  }
  return kind === 'placebo' ? { kind: 'placebo' } : { kind: 'none' }
}

export function describeClaimMagnitude(
  claim: ClaimMagnitudeInput,
  comparator: ClaimComparatorState,
): ClaimMagnitudeState {
  const measure = claim.magnitude_measure
  const value = claim.magnitude_value
  const unit = claim.magnitude_unit
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
    // Ingen tallfesting. Komparatoren står for seg selv, og «none» er da bare
    // kategorien påstanden faktisk bærer — ingenting å motsi.
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

  const pairing = describeMeasureUnit(measure, unit)
  if (pairing.kind === 'unknown') {
    return { kind: 'unknown', reason: pairing.reason, ...raw }
  }

  // Til slutt paret: tallet er velformet i seg selv, men betyr det målet sier
  // bare hvis komparatoren sier det samme. Se merknaden øverst.
  const withinArm = isWithinArmMeasure(measure)
  if (comparator.kind === 'unknown') {
    return { kind: 'unknown', reason: 'comparator_not_interpretable', ...raw }
  }
  if (comparator.kind === 'none' && !withinArm) {
    return { kind: 'unknown', reason: 'contrastive_measure_without_comparator', ...raw }
  }
  if (comparator.kind !== 'none' && withinArm) {
    return { kind: 'unknown', reason: 'within_arm_measure_with_comparator', ...raw }
  }

  return { kind: 'quantified', measure, value, unit: pairing.unit }
}

/**
 * Alle tre aksene, avledet sammen. Dette er inngangen en visning skal bruke:
 * `describeClaimComparator()` og `describeClaimMagnitude()` er eksportert for
 * tester og for smalere bruk, men bare her møtes alle beskrankningene på tvers.
 *
 * Sikkerhetsvurderingen kommer inn som argument framfor å bli avledet her, slik
 * at `claim-certainty.ts` fortsatt er den ene veien til sikkerhetsgrad og de to
 * modulene ikke får hver sin utgave av den.
 */
export function describeClaimEffect(
  claim: ClaimEffectInput,
  certainty: ClaimCertainty,
): ClaimEffect {
  // Komparatoren først: størrelsen kan ikke avgjøres uten den.
  const comparator = describeClaimComparator(claim)
  const magnitude = describeClaimMagnitude(claim, comparator)

  return {
    direction: describeClaimDirection(claim.direction),
    magnitude: withEvidencePrecisionChecked(magnitude, certainty),
    comparator,
  }
}

/**
 * Siste beskrankning, og den går på tvers av aksene: en tallfestet effekt kan
 * ikke stå på en påstand der evidensgrunnlaget er vurdert som ikke graderbart.
 *
 * `no_assessable_evidence` betyr, med migrasjon 004 sine ord, at det ikke finnes
 * tilstrekkelig grunnlag til å gjøre en vurdering i det hele tatt. Et
 * punktestimat ved siden av den tilstanden er falsk presisjon
 * (ANTIDEP_CONSTITUTION.md §6), og migrasjonen sier det rett ut om
 * `magnitude_value`: en påstand som er mer presis enn evidensen under den, er et
 * brudd på §4 og §6. Databasen håndhever det ikke.
 *
 * Avgrenset til `no_assessable_evidence` med vilje. `unknown` dekker blant annet
 * en kunnskapstype Antidep ikke kjenner, og da vet vi ikke hvilken presisjon som
 * er forsvarlig — der er det sikkerhetsvisningen som sier fra, ikke denne.
 */
function withEvidencePrecisionChecked(
  magnitude: ClaimMagnitudeState,
  certainty: ClaimCertainty,
): ClaimMagnitudeState {
  if (magnitude.kind !== 'quantified' || certainty.kind !== 'no_assessable_evidence') {
    return magnitude
  }
  return {
    kind: 'unknown',
    reason: 'precision_exceeds_assessable_evidence',
    rawMeasure: magnitude.measure,
    rawValue: magnitude.value,
    rawUnit: magnitude.unit,
  }
}
