// ============================================================================
// Ett evidensfunn, som presentasjonsenhet
//
// Søsteren til `ClaimCard`, ett nivå ned: kortet viser hva Antidep hevder,
// dette viser hva ett funn i grunnlaget faktisk sier. Paragrafhenvisninger er
// til PRODUCT_INFORMATION_ARCHITECTURE.md der ikke annet står.
//
// Innholdet følger §41: populasjon, komparator, resultat, presisjon — og for de
// funnene som trekker i en annen retning, hvorfor de gjør det (`relevance_note`).
//
// ----------------------------------------------------------------------------
// Fem regler komponenten er bygget rundt
//
// 1. Antideps vurdering og kildens egen holdes fra hverandre. `relationship_type`
//    er Antideps vurdering av funnet, `reported_direction` er retningen kilden
//    selv oppgir. De står i hvert sitt felt med hver sin ordlyd, fordi de kan
//    peke hver sin vei — og nettopp da er forskjellen klinisk interessant (§9).
//
// 2. Et fravær sier alltid hvorfor. Hvert felt med en `*_availability` skriver ut
//    grunnen — ikke målt, ikke rapportert, ikke aktuelt, ikke uttrekkbar — og
//    ingen av dem kan vises som en tom rad. Det er selve grunnen til at kolonnene
//    finnes (ANTIDEP_CONSTITUTION.md §17, DATABASE_ARCHITECTURE.md §19.1).
//
// 3. Et konfidensintervall står aldri uten sin status. Samme regel som tallet og
//    komparatoren på kortet: et manglende intervall betyr upresist grunnlag, ikke
//    et presist estimat. Feltet er derfor alltid til stede.
//
// 4. En tilbaketrukket ekstraksjon merkes, den skjules ikke. Påstanden over den
//    står fortsatt publisert; kortet sier hvor mange som er trukket tilbake, og
//    her står det hvilke (ANTIDEP_CONSTITUTION.md §14).
//
// 5. En kilde som ikke lenger er i normal bruk sier det. En tilbaketrukket eller
//    erstattet kilde kan bli det etter at påstanden ble publisert, og
//    publiseringsgaten kontrollerer status ved publisering, ikke etterpå.
//
// ----------------------------------------------------------------------------
// Hvorfor denne komponenten kjenner ruteren, når `ClaimCard` ikke gjør det
//
// Lenken til kildesiden er alltid en rute, og den rendres med ruterens `Link`.
// En vanlig `<a>` ville gitt en full dokumentnavigering: siden lastes på nytt,
// og `useFocusMainOnNavigation()` i `App.tsx` hopper med vilje over
// fokusflyttingen ved første render — så leseren havner øverst i et nytt
// dokument framfor i hovedområdet. På evidenssiden står lenken dessuten ved
// siden av lenkene til virkestoffet og temaet, som er `Link`; å navigere ulikt
// fra samme avsnitt er en forskjell uten begrunnelse.
//
// `ClaimCard` kan derimot *ikke* bruke `Link`, og det er ikke en forglemmelse:
// dens `evidenceHref` er et anker på samme side (`#evidensgrunnlaget`) når
// kortet står på evidensvisningen. Skillet er hva verdien er, ikke hvor
// komponenten ligger. Adressene lages fortsatt bare i `routes.ts`.
//
// Funnet av en automatisk review på PR-en som innførte lenken.
// ============================================================================

import { useId } from 'react'
import { Link } from 'react-router'
import { Detail, DetailList, DetailNote } from './DetailList'
import {
  ExtractionWithdrawalNote,
  SourceExtractionDetails,
  SourcePublicationDetails,
} from './SourceDetails'
import {
  MEASURE_LABELS,
  REPORTED_DIRECTION_LABELS,
  STUDY_DESIGN_LABELS,
  UNIT_LABELS,
  VALUE_AVAILABILITY_LABELS,
  stanceText,
  termText,
} from './vocabulary-labels'
import {
  describeEvidenceFinding,
  type AbsentAvailability,
  type AvailabilityFault,
  type EvidenceConfidenceInterval,
  type EvidenceEstimateState,
  type EvidenceStance,
  type EvidenceTimepoint,
  type EvidenceValueState,
} from '../lib/evidence-item'
import { formatIntervalText, formatNumber, renderedText } from '../lib/norwegian-format'
import type { EvidenceDirectness, PublishedClaimEvidenceRow } from '../types/api'

// ----------------------------------------------------------------------------
// Vokabularene, oversatt
// ----------------------------------------------------------------------------

const DIRECTNESS_LABELS: Record<EvidenceDirectness, string> = {
  direct: 'Treffer påstandens populasjon, endepunkt, komparator og tidsrom direkte',
  indirect: 'Treffer påstanden indirekte',
}

/**
 * De fire grunnene til at et felt står tomt. Hver av dem er en egenskap ved
 * noe forskjellig — studien, publikasjonen, funnet, ekstraksjonen — og ingen av
 * dem betyr null.
 *
 * Oppslaget er det delte `VALUE_AVAILABILITY_LABELS`, smalnet til de fire
 * fraværsverdiene: `AbsentAvailability` er en delmengde av `ValueAvailability`,
 * så oppslaget er typesikkert, og registreringsskjemaet og denne visningen kan
 * ikke få hver sin oversettelse av «ikke målt».
 */
const ABSENCE_LABELS: Record<AbsentAvailability, string> = VALUE_AVAILABILITY_LABELS

const AVAILABILITY_FAULT_LABELS: Record<AvailabilityFault, string> = {
  unrecognised_availability:
    'Grunnen til at verdien mangler er utenfor vokabularet Antidep kjenner',
  missing_value: 'Registreringen sier at kilden oppgir en verdi, men verdien mangler',
  unexpected_value:
    'Registreringen sier at kilden ikke oppgir en verdi, samtidig som det står en verdi. ' +
    'Verdien vises ikke',
  incomplete_value: 'Verdien er bare delvis registrert, og halve verdien er ikke en verdi',
  implausible_value:
    'Verdien kan ikke være det den er registrert som, og vises derfor ikke. Vist som tall ville ' +
    'den sett ut som et resultat',
}

const UNCERTAIN_EXTRACTION_NOTE =
  'Verdien er lest ut av kilden, men ekstraksjonen er registrert som usikker.'

// ----------------------------------------------------------------------------
// Fellesformer
// ----------------------------------------------------------------------------

/** Ett felt med sin status, oversatt. `render` gjelder bare den rapporterte verdien. */
function valueText<Value>(
  state: EvidenceValueState<Value>,
  render: (value: Value) => string,
): string {
  switch (state.kind) {
    case 'reported':
      return state.uncertainExtraction
        ? `${render(state.value)} — ${UNCERTAIN_EXTRACTION_NOTE}`
        : render(state.value)
    case 'absent':
      return ABSENCE_LABELS[state.reason]
    case 'unknown':
      return `${AVAILABILITY_FAULT_LABELS[state.reason]} («${state.rawAvailability}»).`
  }
}

// ----------------------------------------------------------------------------
// Feltene
// ----------------------------------------------------------------------------

/**
 * Hvorfor en relasjon ikke lot seg tolke.
 *
 * Skrives ut, fordi alternativet er en påstand som ser vurdert ut uten å være
 * det. Et funn Antidep ikke kan si relasjonen til, må ikke kunne leses som
 * støtte (§9).
 */
function stanceFaultText(stance: EvidenceStance): string | null {
  if (stance.kind === 'known') {
    return null
  }
  const raw = `Registrert som «${stance.rawRelationship}» / «${stance.rawDirectness}».`
  switch (stance.reason) {
    case 'unrecognised_relationship':
      return `Relasjonstypen er utenfor vokabularet Antidep kjenner. ${raw} Funnet står med i grunnlaget, men skal ikke leses som støtte for påstanden.`
    case 'unrecognised_directness':
      return `Direktheten er utenfor vokabularet Antidep kjenner. ${raw}`
    case 'indirect_relationship_claiming_directness':
      return `Relasjonen sier at funnet bare kan bedømmes indirekte, mens direktheten hevder at det treffer påstanden direkte. De to sier forskjellige ting om samme lenke. ${raw}`
  }
}

function timepointText(timepoint: EvidenceTimepoint): string {
  // Begge ledd finnes: avledningen bygger paret først når begge står, så det er
  // ingen gren her for et enslig ledd — og en gren ingen test kan nå, ser ut som
  // et vern uten å være det.
  const from = renderedText(formatIntervalText(timepoint.min), 'varighet')
  const to = renderedText(formatIntervalText(timepoint.max), 'varighet')
  return from === to ? from : `${from} til ${to}`
}

function confidenceIntervalText(ci: EvidenceConfidenceInterval): string {
  // Alle tre ledd finnes, av samme grunn som over: nivået hører til intervallet,
  // og et intervall uten nivå slipper aldri gjennom avledningen.
  const lower = renderedText(formatNumber(ci.lower), 'tall')
  const upper = renderedText(formatNumber(ci.upper), 'tall')
  const level = renderedText(formatNumber(ci.levelPercent), 'tall')
  return `${level} % KI: ${lower} til ${upper}`
}

function estimateText(estimate: EvidenceEstimateState): string {
  switch (estimate.kind) {
    case 'quantified': {
      const value = renderedText(formatNumber(estimate.value), 'tall')
      const unit = estimate.unit === null ? '' : ` ${UNIT_LABELS[estimate.unit]}`
      const text = `${MEASURE_LABELS[estimate.measure]} ${value}${unit}`
      return estimate.uncertainExtraction ? `${text} — ${UNCERTAIN_EXTRACTION_NOTE}` : text
    }
    case 'absent': {
      const absence = ABSENCE_LABELS[estimate.reason]
      return estimate.measure === null
        ? `${absence}. Ingen effektstørrelse er registrert for dette funnet, og det betyr ikke at effekten er null.`
        : `${MEASURE_LABELS[estimate.measure]}: ${absence.toLowerCase()}. Det betyr ikke at effekten er null.`
    }
    case 'unknown':
      // Tallet vises ikke. Et estimat som ikke lar seg feste til et mål, en
      // enhet eller en komparator er ikke et estimat (se `claim-effect.ts`).
      return 'Effektstørrelsen er ikke tolkbar, og vises derfor ikke.'
  }
}

// ----------------------------------------------------------------------------

export interface EvidenceFindingProps {
  readonly finding: PublishedClaimEvidenceRow
  /**
   * Veien til kildesiden: én publikasjon, og alt Antidep bruker den til (§42).
   * Påkrevd, ikke valgfri, av samme grunn som `evidenceHref` på `ClaimCard`:
   * de to visningene skal kunne lenke til hverandre, og en valgfri lenke kan
   * falle bort ved en forglemmelse. URL-en eies fortsatt av rutingen — strengen
   * lages i `routes.ts`, ikke her (§74.13 punkt 4).
   *
   * Til forskjell fra `evidenceHref` er dette *alltid* en rute, aldri et anker
   * på samme side, og den rendres derfor med ruterens `Link`. Se merknaden om
   * navigeringsmåte øverst.
   */
  readonly sourceHref: string
  /**
   * Nivået kildetittelen får som overskrift. Siden eier hierarkiet, slik den
   * gjør for `ClaimCard`: en overskrift som hopper over et nivå gir feil
   * disposisjon for skjermlesere (§50, §53).
   */
  readonly headingLevel: 3 | 4 | 5
}

export function EvidenceFinding({ finding, sourceHref, headingLevel }: EvidenceFindingProps) {
  const stanceId = useId()
  const headingId = useId()
  const sourceLinkId = useId()

  const Heading = `h${headingLevel}` as const
  const SourceHeading = `h${(headingLevel + 1) as 4 | 5 | 6}` as const

  const derived = describeEvidenceFinding(finding)
  const stanceFault = stanceFaultText(derived.stance)
  return (
    <article
      className="evidence-finding"
      // Navnet på funnet er relasjonen *og* kilden. Uten relasjonen ville to
      // funn fra samme kilde hett det samme for en skjermleser, og et
      // motstridende funn hett nøyaktig som et støttende.
      aria-labelledby={`${stanceId} ${headingId}`}
      data-relationship={derived.stance.kind === 'known' ? derived.stance.relationship : 'unknown'}
      data-withdrawn={finding.extraction_withdrawn ? 'true' : undefined}
    >
      <ExtractionWithdrawalNote extraction={finding} />

      <p className="evidence-finding__stance" id={stanceId}>
        {stanceText(derived.stance)}
      </p>

      <Heading className="evidence-finding__source-title" id={headingId}>
        {finding.source_title}
      </Heading>

      <p className="evidence-finding__relevance">{finding.relevance_note}</p>

      {stanceFault === null ? null : (
        <p className="evidence-finding__fault" role="note">
          {stanceFault}
        </p>
      )}

      <DetailList>
        <Detail label="Direkthet">
          {derived.stance.kind === 'known'
            ? DIRECTNESS_LABELS[derived.stance.directness]
            : `Ikke tolkbar («${derived.stance.rawDirectness}»)`}
        </Detail>

        <Detail label="Studiedesign">
          {termText(derived.studyDesign, STUDY_DESIGN_LABELS, 'studiedesign')}
        </Detail>

        <Detail label="Populasjon">
          {valueText(derived.population, (label) => label)}
          <DetailNote>{finding.population_detail}</DetailNote>
        </Detail>

        <Detail label="Utvalgsstørrelse">
          {valueText(derived.sampleSize, (size) => `${renderedText(formatNumber(size), 'tall')}`)}
        </Detail>

        <Detail label="Intervensjon">
          {finding.intervention_drug_name}
          {finding.intervention_detail === null ? null : (
            <DetailNote>{finding.intervention_detail}</DetailNote>
          )}
        </Detail>

        <Detail label="Komparator">
          {comparatorText(derived.comparator)}
          {finding.comparator_detail === null ? null : (
            <DetailNote>{finding.comparator_detail}</DetailNote>
          )}
        </Detail>

        <Detail label="Endepunkt">
          {finding.outcome_label}
          <DetailNote>{finding.outcome_detail}</DetailNote>
        </Detail>

        <Detail label="Måletidspunkt">{valueText(derived.timepoint, timepointText)}</Detail>

        <Detail label="Rapportert retning">
          {termText(derived.reportedDirection, REPORTED_DIRECTION_LABELS, 'rapportert retning')}
        </Detail>

        <Detail label="Resultat">{estimateText(derived.estimate)}</Detail>

        {/* Alltid til stede: et manglende intervall betyr upresist grunnlag, ikke
            et presist estimat. Feltet kan derfor ikke utelates når det er tomt. */}
        <Detail label="Presisjon">
          {valueText(derived.confidenceInterval, confidenceIntervalText)}
        </Detail>

        <Detail label="Begrensninger">
          {finding.limitations_text ?? 'Ingen begrensninger er registrert for dette funnet.'}
        </Detail>
      </DetailList>

      <section className="evidence-finding__source">
        <SourceHeading className="evidence-finding__source-heading">Kilde</SourceHeading>
        <DetailList>
          {/* Publikasjonen selv, i den samme formen kildesiden viser den. Én
              utgave, ikke to: samme rad, samme regler (§65 «Duplicated truth»). */}
          <SourcePublicationDetails source={finding} />
          {/* De to feltene som hører til *funnet* og ikke til kilden: hvor i
              kilden funnet står, og hvilken hentet versjon det ble ekstrahert
              fra. */}
          <SourceExtractionDetails extraction={finding} />
        </DetailList>
        {/* Veien til den andre visningen. §42 skiller dem: her står kilden under
            ett funn, der står den med alt Antidep bruker den til. */}
        <p className="evidence-finding__source-link">
          <Link to={sourceHref} id={sourceLinkId} aria-labelledby={`${sourceLinkId} ${headingId}`}>
            Alt Antidep bruker denne kilden til
          </Link>
        </p>
      </section>
    </article>
  )
}

/**
 * Komparatoren funnet selv har.
 *
 * `none` betyr her det samme som på påstandskortet: et armspesifikt funn uten
 * sammenligningsledd, ikke en komparator som mangler. Migrasjon 003 sier det
 * eksplisitt.
 */
function comparatorText(comparator: ReturnType<typeof describeEvidenceFinding>['comparator']) {
  switch (comparator.kind) {
    case 'drug':
      return comparator.drugName
    case 'placebo':
      return 'Placebo'
    case 'none':
      return 'Ingen komparator: funnet gjelder én behandlingsarm'
    case 'unknown':
      return `Komparatoren er ikke tolkbar («${comparator.rawComparatorKind}»)`
  }
}
