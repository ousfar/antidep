// ============================================================================
// Sikkerhet i evidensen, som synlig tekst
//
// Viser tilstandene fra `describeClaimCertainty()`. Paragrafhenvisninger er til
// PRODUCT_INFORMATION_ARCHITECTURE.md der ikke annet står.
//
// ----------------------------------------------------------------------------
// Tre valg som er tatt bevisst
//
// 1. Ingen skala. §17 navnger «en tom skala» som nettopp det mønsteret som får
//    manglende data til å se ut som lav risiko. En firetrinns indikator ville
//    tvunget «ingen vurderbar evidens» og «ukjent» inn på samme akse som
//    «svært lav» — som et trinn under, ikke som noe annet. Teksten bærer
//    betydningen, og en visuell skala hører først hjemme når hvert trinn har en
//    definert semantikk å vise (§18).
//
// 2. Ingen fargeramme over graderingene. «Traffic-light medicine» står som et
//    eksplisitt antimønster (§65), og høy sikkerhet er ikke et grønt lys:
//    sikkerheten i kunnskapsgrunnlaget sier ingenting om hvor gunstig funnet
//    er. Alle graderingene deler derfor nøytral farge og skilles på tekst.
//
// 3. De ikke-graderte tilstandene skiller seg i art, ikke i grad. De bærer
//    ingen `data-certainty-level`, og stilsettet henger den graderte drakten på
//    nettopp det attributtet. En ny ikke-gradert tilstand kan dermed ikke arve
//    utseendet til en gradering ved et uhell — den mangler kroken.
//
// Rammeverket (`grade`) vises ikke her. Kortet skal være kort (§7), og
// metoden bak vurderingen hører til evidensvisningen (§15) sammen med
// begrunnelsen.
// ============================================================================

import type { ClaimCertainty } from '../lib/claim-certainty'
import type { GradedCertaintyLevel } from '../lib/claim-certainty'

/** Ordlyden §16 foreskriver. Endres den, endres et produktkrav. */
const GRADED_LABELS: Record<GradedCertaintyLevel, string> = {
  high: 'Høy sikkerhet',
  moderate: 'Moderat sikkerhet',
  low: 'Lav sikkerhet',
  very_low: 'Svært lav sikkerhet',
}

const UNKNOWN_REASONS: Record<
  Extract<ClaimCertainty, { kind: 'unknown' }>['reason'],
  (certainty: Extract<ClaimCertainty, { kind: 'unknown' }>) => string
> = {
  unrecognised_knowledge_type: (certainty) =>
    `Antidep kjenner ikke kunnskapstypen «${certainty.rawKnowledgeType}», og kan derfor ikke ` +
    'avgjøre hvilken sikkerhetsvurdering som gjelder for påstanden.',
  missing_assessment: () =>
    'Påstanden mangler den sikkerhetsvurderingen kunnskapstypen krever. Grunnlaget er ikke ' +
    'vurdert som ikke-graderbart — det er ikke vurdert.',
  unrecognised_level: (certainty) =>
    `Sikkerhetsverdien «${certainty.rawCertaintyLevel}» er utenfor vokabularet Antidep kjenner.`,
  assessment_on_deterministic_fact: (certainty) =>
    `Påstanden er et deterministisk faktum, men bærer graderingen ` +
    `«${certainty.rawCertaintyLevel}». GRADE gjelder ikke for kunnskapstypen.`,
}

interface Presentation {
  /** Verdien leseren ser. Aldri tom: en manglende sikkerhet er selv en tilstand. */
  readonly value: string
  /** Utdypning under verdien, der tilstanden ellers kan leses feil. */
  readonly note: string | null
  /** Satt bare for de faktiske graderingene, og er kroken stilsettet henger på. */
  readonly level: GradedCertaintyLevel | null
}

function present(certainty: ClaimCertainty): Presentation {
  switch (certainty.kind) {
    case 'graded':
      return { value: GRADED_LABELS[certainty.level], note: null, level: certainty.level }
    case 'no_assessable_evidence':
      return {
        value: 'Ingen vurderbar evidens',
        // Uten denne setningen er tilstanden lett å lese som en svak gradering.
        // Den er en vurdert tilstand: grunnlaget er sett på og lar seg ikke
        // gradere (ANTIDEP_CONSTITUTION.md §6).
        note:
          certainty.evidenceGap ??
          'Grunnlaget er vurdert og lar seg ikke gradere. Hva som mangler, er ikke oppgitt.',
        level: null,
      }
    case 'not_applicable_deterministic_fact':
      return {
        value: 'Ikke aktuelt',
        note:
          'GRADE gjelder ikke for deterministiske fakta. Fraværet av gradering er korrekt her, ' +
          'ikke en manglende vurdering.',
        level: null,
      }
    case 'unknown':
      return {
        value: 'Ukjent sikkerhet',
        note: UNKNOWN_REASONS[certainty.reason](certainty),
        level: null,
      }
  }
}

export interface ClaimCertaintyProps {
  readonly certainty: ClaimCertainty
}

export function ClaimCertainty({ certainty }: ClaimCertaintyProps) {
  const { value, note, level } = present(certainty)

  return (
    <div
      className="claim-certainty"
      data-certainty-kind={certainty.kind}
      {...(level === null ? {} : { 'data-certainty-level': level })}
    >
      <span className="claim-certainty__label">Sikkerhet i evidensen</span>
      <span className="claim-certainty__value">{value}</span>
      {note === null ? null : <p className="claim-certainty__note">{note}</p>}
      {level === null ? (
        // Den eneste setningen som gjentas på alle de ikke-graderte
        // tilstandene, fordi det er den ene feillesningen de deler
        // (ANTIDEP_CONSTITUTION.md §17).
        <p className="claim-certainty__caveat">
          Dette betyr ikke lav risiko, ingen effekt eller ingen bivirkning.
        </p>
      ) : null}
    </div>
  )
}
