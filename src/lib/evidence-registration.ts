// ============================================================================
// Evidensregistrering: fra det redaktøren fyller ut, til det databasen krever
//
// Søsteren til `publication-date.ts`, og bygget på nøyaktig samme skille:
//
//   Dette er IKKE feltvalidering som dupliserer databasens CHECK-constraints.
//   De er fasiten (DATABASE_ARCHITECTURE.md §43, §48, §57), og en verdi som er
//   umulig — et estimat utenfor sitt eget konfidensintervall, en komparator som
//   er intervensjonen selv — avvises av databasen og ikke her.
//
//   Kontrollene under svarer på et annet og snevrere spørsmål: *har skjemaet i
//   det hele tatt fått nok input til å danne en verdi?* Er svaret nei, finnes
//   det ingen verdi å sende, og et halvt utfylt felt skal ikke sendes som om
//   det var en verdi.
//
// ----------------------------------------------------------------------------
// Null/ukjent-semantikken er formens bærende idé, ikke et tillegg
//
// `knowledge.evidence_items` parer hvert klinisk viktig felt med en
// `*_availability`, og håndhever deklarativt at verdien finnes hvis og bare hvis
// statusen sier det (DATABASE_ARCHITECTURE.md §19.1). Regelen er
// konstitusjonell: et manglende estimat er ikke et estimat på null, og «ikke
// målt», «ikke rapportert» og «ingen klar forskjell» er tre forskjellige
// tilstander (ANTIDEP_CONSTITUTION.md §6).
//
// Skjemaet uttrykker derfor paret som ett valg og ett felt: redaktøren sier
// først hvorfor feltet har eller ikke har en verdi, og fyller så ut verdien
// bare når svaret er at kilden faktisk oppgir den. Formen kan da ikke danne et
// par databasen ville avvist — ikke fordi den kjenner constrainten, men fordi
// den bygger verdien ut fra statusen framfor å kontrollere at de to stemmer.
//
// ----------------------------------------------------------------------------
// Tall skrives med komma
//
// Feltene er `text` med `inputMode`, ikke `type="number"`. En `number`-input
// leverer tom streng når innholdet ikke er et gyldig flyttall etter HTML-ens
// regler, og «1,7» er nettopp et slikt tilfelle — en norsk kliniker som skriver
// tallet slik hen skriver det ellers, ville fått «fyll inn verdien» tilbake
// uten å se hva som var galt. Komma og punktum godtas derfor begge, og
// oversettes her.
//
// ----------------------------------------------------------------------------
// Og tallet blir *aldri* et JavaScript-tall
//
// Kanoniseringen returnerer den validerte teksten, ikke resultatet av
// `Number(...)`. Grunnen er at PostgreSQL sin `numeric` er vilkårlig presis
// mens et JavaScript-tall er en IEEE-754 double: `Number('0.12345678901234567')`
// er `0.12345678901234566`, og et estimat som ble avrundet på vei inn ville
// blitt lagret — og hashet — som en annen verdi enn den kilden oppgir.
//
// Prøvd mot stacken, ikke antatt: PostgREST tar imot en JSON-streng for en
// `numeric`- eller `integer`-parameter og lar PostgreSQL gjøre casten, og
// verdien over kom da tilbake fra databasen uendret. Sendt som JSON-tall ble
// den avrundet.
//
// Tallet er allerede kontrollert på form her, så strengen som sendes videre er
// et gyldig desimaltall — ikke vilkårlig tekst. Selve tolkningen gjør
// databasen, som den gjør for alle de andre feltene (§43, §57).
// ============================================================================

import { AVAILABILITY_PARTITION } from './evidence-item'
import type { ValueAvailability } from '../types/api'

/**
 * Om statusen sier at en verdi står i feltet.
 *
 * Utledet av `AVAILABILITY_PARTITION` framfor skrevet ut på nytt: delingen i
 * «verdien finnes» og «verdien finnes ikke» er den samme regelen visningen av
 * et funn bygger på, og to kopier av den ville kunnet drive fra hverandre.
 */
export function availabilityHasValue(availability: ValueAvailability): boolean {
  return (AVAILABILITY_PARTITION.present as readonly string[]).includes(availability)
}

/** Utfallet av en kanonisering: en verdi, eller beskjed om hva som mangler. */
type Canonical<Value> =
  ({ readonly status: 'ok' } & Value) | { readonly status: 'incomplete'; readonly message: string }

// Formen et desimaltall kan ha etter at komma er oversatt til punktum.
// Formkontroll, ikke gyldighetskontroll: at 9,9 ligger utenfor sitt eget
// konfidensintervall er databasens svar å gi.
const DECIMAL_SHAPE = /^-?\d+(\.\d+)?$/
const WHOLE_NUMBER_SHAPE = /^\d+$/

/** Den validerte teksten, aldri et JS-tall. Se hodekommentaren for hvorfor. */
function toDecimalText(raw: string): string | null {
  const normalised = raw.trim().replace(',', '.')
  return DECIMAL_SHAPE.test(normalised) ? normalised : null
}

function toWholeNumberText(raw: string): string | null {
  const normalised = raw.trim()
  return WHOLE_NUMBER_SHAPE.test(normalised) ? normalised : null
}

// ----------------------------------------------------------------------------
// Ett tallfelt med sin status
// ----------------------------------------------------------------------------

/** Det skjemaet holder på for et tallfelt: hvorfor det har en verdi, og verdien. */
export interface EvidenceNumberDraft {
  readonly availability: ValueAvailability
  /** Rå input. Tom streng betyr «ikke skrevet», ikke «null». */
  readonly value: string
}

export const EMPTY_NUMBER_DRAFT: EvidenceNumberDraft = {
  availability: 'not_reported',
  value: '',
}

export type CanonicalNumber = Canonical<{ readonly value: string | null }>

/**
 * Tallet skjemaet skal sende, eller beskjed om at det mangler.
 *
 * `whole` gjør feltet til et positivt heltall — utvalgsstørrelsen er et antall
 * deltakere, og «240,5 deltakere» er ikke en verdi.
 */
export function canonicalNumber(
  draft: EvidenceNumberDraft,
  options: { readonly missingMessage: string; readonly whole?: boolean },
): CanonicalNumber {
  if (!availabilityHasValue(draft.availability)) {
    // Statusen sier at feltet er tomt. Da sendes NULL, uansett hva som måtte
    // stå igjen i inputen fra et tidligere valg.
    return { status: 'ok', value: null }
  }
  const parsed =
    options.whole === true ? toWholeNumberText(draft.value) : toDecimalText(draft.value)
  if (parsed === null) {
    return { status: 'incomplete', message: options.missingMessage }
  }
  return { status: 'ok', value: parsed }
}

// ----------------------------------------------------------------------------
// Populasjonen: en kobling til katalogen, med sin status
// ----------------------------------------------------------------------------

export interface EvidencePopulationDraft {
  readonly availability: ValueAvailability
  /** Tom streng betyr «ingen populasjon er valgt». */
  readonly populationId: string
}

export const EMPTY_POPULATION_DRAFT: EvidencePopulationDraft = {
  availability: 'not_reported',
  populationId: '',
}

export type CanonicalPopulation = Canonical<{ readonly populationId: string | null }>

export function canonicalPopulation(draft: EvidencePopulationDraft): CanonicalPopulation {
  if (!availabilityHasValue(draft.availability)) {
    return { status: 'ok', populationId: null }
  }
  if (draft.populationId.length === 0) {
    return {
      status: 'incomplete',
      message: 'Velg populasjonen funnet skal indekseres under, eller si hvorfor den mangler.',
    }
  }
  return { status: 'ok', populationId: draft.populationId }
}

// ----------------------------------------------------------------------------
// Oppfølgingstiden
//
// Lagres som `interval` nettopp for at tall og enhet ikke skal kunne komme fra
// hverandre (migrasjon 003). Skjemaet spør derfor om enheten og ett eller to
// tall, og setter strengen sammen her — framfor å be redaktøren skrive «8
// weeks» i et fritekstfelt.
//
// Ett oppgitt tidspunkt gir lik nedre og øvre grense, slik migrasjon 003 sier
// eksplisitt. Et spenn beholdes som et spenn: «26 til 32 uker» skal ikke
// avrundes til falsk presisjon (ANTIDEP_CONSTITUTION.md §6).
// ----------------------------------------------------------------------------

export const TIMEPOINT_UNITS = ['days', 'weeks', 'months', 'years'] as const
export type TimepointUnit = (typeof TIMEPOINT_UNITS)[number]

export interface EvidenceTimepointDraft {
  readonly availability: ValueAvailability
  readonly unit: TimepointUnit
  /** Nedre grense, eller det ene tidspunktet. */
  readonly from: string
  /** Øvre grense. Tom betyr «ett tidspunkt, ikke et spenn». */
  readonly to: string
}

export const EMPTY_TIMEPOINT_DRAFT: EvidenceTimepointDraft = {
  availability: 'not_reported',
  unit: 'weeks',
  from: '',
  to: '',
}

export type CanonicalTimepoint = Canonical<{
  readonly min: string | null
  readonly max: string | null
}>

export function canonicalTimepoint(draft: EvidenceTimepointDraft): CanonicalTimepoint {
  if (!availabilityHasValue(draft.availability)) {
    // Paret er alltid begge satt eller begge NULL
    // (evidence_items_timepoint_pairing_check).
    return { status: 'ok', min: null, max: null }
  }
  const from = toDecimalText(draft.from)
  if (from === null) {
    return {
      status: 'incomplete',
      message: 'Fyll inn oppfølgingstiden, eller si hvorfor den mangler.',
    }
  }
  if (draft.to.trim().length === 0) {
    const single = `${from} ${draft.unit}`
    return { status: 'ok', min: single, max: single }
  }
  const to = toDecimalText(draft.to)
  if (to === null) {
    return {
      status: 'incomplete',
      message: 'Øvre grense for oppfølgingstiden må være et tall, eller stå tom.',
    }
  }
  return { status: 'ok', min: `${from} ${draft.unit}`, max: `${to} ${draft.unit}` }
}

// ----------------------------------------------------------------------------
// Konfidensintervallet
//
// Tre verdier som står og faller sammen: nedre grense, øvre grense og nivået
// (evidence_items_confidence_interval_pairing_check og
// evidence_items_confidence_level_pairing_check). Nivået har 95 som
// standardverdi fordi det er det kilder oftest oppgir — men det er en
// utfylling redaktøren kan endre, ikke en antakelse skjemaet gjør på kildens
// vegne når feltet står tomt.
// ----------------------------------------------------------------------------

export interface EvidenceConfidenceIntervalDraft {
  readonly availability: ValueAvailability
  readonly lower: string
  readonly upper: string
  readonly level: string
}

export const EMPTY_CONFIDENCE_INTERVAL_DRAFT: EvidenceConfidenceIntervalDraft = {
  availability: 'not_reported',
  lower: '',
  upper: '',
  level: '95',
}

export type CanonicalConfidenceInterval = Canonical<{
  readonly lower: string | null
  readonly upper: string | null
  readonly level: string | null
}>

export function canonicalConfidenceInterval(
  draft: EvidenceConfidenceIntervalDraft,
): CanonicalConfidenceInterval {
  if (!availabilityHasValue(draft.availability)) {
    return { status: 'ok', lower: null, upper: null, level: null }
  }
  const lower = toDecimalText(draft.lower)
  const upper = toDecimalText(draft.upper)
  const level = toDecimalText(draft.level)
  if (lower === null || upper === null) {
    return {
      status: 'incomplete',
      message:
        'Fyll inn både nedre og øvre grense for konfidensintervallet, eller si hvorfor det mangler.',
    }
  }
  if (level === null) {
    return { status: 'incomplete', message: 'Fyll inn konfidensnivået, for eksempel 95.' }
  }
  return { status: 'ok', lower, upper, level }
}
