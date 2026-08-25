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
// ============================================================================

import { useId, type ReactNode } from 'react'
import { MEASURE_LABELS, UNIT_LABELS } from './vocabulary-labels'
import {
  describeEvidenceFinding,
  type AbsentAvailability,
  type AvailabilityFault,
  type EvidenceConfidenceInterval,
  type EvidenceEstimateState,
  type EvidenceStance,
  type EvidenceTimepoint,
  type EvidenceValueState,
  type PublicationDateState,
  type VocabularyTerm,
} from '../lib/evidence-item'
import {
  formatDateAtPrecision,
  formatIntervalText,
  formatNumber,
  formatTimestampAsDate,
  type RenderedValue,
} from '../lib/norwegian-format'
import type {
  EvidenceDirectness,
  EvidenceRelationshipType,
  PublishedClaimEvidenceRow,
  ReportedDirection,
  SourceStatus,
  SourceType,
  StudyDesign,
} from '../types/api'

// ----------------------------------------------------------------------------
// Vokabularene, oversatt
// ----------------------------------------------------------------------------

const RELATIONSHIP_LABELS: Record<EvidenceRelationshipType, string> = {
  supports: 'Støtter påstanden',
  partially_supports: 'Støtter deler av påstanden',
  contradicts: 'Motsier påstanden',
  neutral_contextual: 'Verken for eller mot påstanden',
  indirect: 'Bare indirekte bedømbart mot påstanden',
}

const DIRECTNESS_LABELS: Record<EvidenceDirectness, string> = {
  direct: 'Treffer påstandens populasjon, endepunkt, komparator og tidsrom direkte',
  indirect: 'Treffer påstanden indirekte',
}

const STUDY_DESIGN_LABELS: Record<StudyDesign, string> = {
  randomized_controlled_trial: 'Randomisert kontrollert studie',
}

const SOURCE_TYPE_LABELS: Record<SourceType, string> = {
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
const SOURCE_STATUS_LABELS: Record<SourceStatus, string> = {
  active: 'I bruk',
  outdated: 'Utdatert, uten at en bestemt etterfølger er registrert',
  superseded: 'Erstattet av en nyere kilde',
  retracted: 'Trukket tilbake av tidsskrift eller utgiver',
  withdrawn: 'Tatt ut av bruk av utgiveren',
}

/**
 * Retningen kilden selv rapporterer. `not_stated` er den fjerde verdien
 * påstandens eget retningsvokabular ikke har, og formuleringen sier eksplisitt
 * at det er kilden som ikke oppgir noe — ikke at det ikke ble funnet noe.
 */
const REPORTED_DIRECTION_LABELS: Record<ReportedDirection, string> = {
  increase: 'Kilden rapporterer en økning',
  decrease: 'Kilden rapporterer en reduksjon',
  no_clear_difference: 'Kilden fant ingen klar forskjell',
  not_stated: 'Kilden oppgir ingen retning',
}

/**
 * De fire grunnene til at et felt står tomt. Hver av dem er en egenskap ved
 * noe forskjellig — studien, publikasjonen, funnet, ekstraksjonen — og ingen av
 * dem betyr null.
 */
const ABSENCE_LABELS: Record<AbsentAvailability, string> = {
  not_measured: 'Ikke målt i studien',
  not_reported: 'Ikke rapportert i kilden',
  not_applicable: 'Ikke aktuelt for dette funnet',
  not_extractable: 'Står i kilden, men lar seg ikke lese entydig ut',
}

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

/**
 * Én formatert databaseverdi som tekst.
 *
 * En verdi som ikke lot seg tolke, bærer databaseverdien uendret
 * (`norwegian-format.ts`), og den merkes framfor å bli borte: et felt som
 * forsvinner fordi formateringen feilet, ser ut som fravær av data.
 */
function renderedText(value: RenderedValue, what: string): string {
  return value.kind === 'formatted' ? value.text : `${value.text} (ikke tolkbar som ${what})`
}

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

/** En vokabularverdi, oversatt — eller sagt at den er ukjent, aldri gjettet. */
function termText<Term extends string>(
  term: VocabularyTerm<Term>,
  labels: Record<Term, string>,
  what: string,
): string {
  return term.kind === 'known' ? labels[term.value] : `Ukjent ${what} («${term.raw}»)`
}

interface DetailProps {
  readonly label: string
  readonly children: ReactNode
}

function Detail({ label, children }: DetailProps) {
  return (
    <div className="evidence-finding__detail">
      <dt>{label}</dt>
      <dd>{children}</dd>
    </div>
  )
}

// ----------------------------------------------------------------------------
// Feltene
// ----------------------------------------------------------------------------

function stanceText(stance: EvidenceStance): string {
  return stance.kind === 'known'
    ? RELATIONSHIP_LABELS[stance.relationship]
    : 'Antideps vurdering av dette funnet er ikke tolkbar'
}

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

function publicationDateText(date: PublicationDateState): string {
  switch (date.kind) {
    case 'dated':
      // Presisjonen bestemmer hvor mye av datoen som skrives ut. En dato som
      // bare er kjent til året, skal ikke vises som 1. januar (§6).
      return renderedText(formatDateAtPrecision(date.date, date.precision), 'dato')
    case 'undated':
      return 'Ingen publiseringsdato er registrert i Antidep'
    case 'unknown':
      return `Publiseringsdatoen er ikke tolkbar uten et kjent presisjonsnivå (dato «${
        date.rawDate ?? '—'
      }», presisjon «${date.rawPrecision ?? '—'}»).`
  }
}

/** Identifikatorene, som sortert liste. Ingen er definert som primær. */
function identifierText(values: readonly string[] | null): string | null {
  return values === null || values.length === 0 ? null : values.join(', ')
}

// ----------------------------------------------------------------------------

export interface EvidenceFindingProps {
  readonly finding: PublishedClaimEvidenceRow
  /**
   * Nivået kildetittelen får som overskrift. Siden eier hierarkiet, slik den
   * gjør for `ClaimCard`: en overskrift som hopper over et nivå gir feil
   * disposisjon for skjermlesere (§50, §53).
   */
  readonly headingLevel: 3 | 4 | 5
}

export function EvidenceFinding({ finding, headingLevel }: EvidenceFindingProps) {
  const stanceId = useId()
  const headingId = useId()

  const Heading = `h${headingLevel}` as const
  const SourceHeading = `h${(headingLevel + 1) as 4 | 5 | 6}` as const

  const derived = describeEvidenceFinding(finding)
  const stanceFault = stanceFaultText(derived.stance)
  const dois = identifierText(finding.source_dois)
  const pmids = identifierText(finding.source_pmids)
  const withdrawnAt =
    finding.extraction_withdrawn_at === null
      ? null
      : renderedText(formatTimestampAsDate(finding.extraction_withdrawn_at), 'dato')

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
      {finding.extraction_withdrawn ? (
        <p className="evidence-finding__withdrawn" role="note">
          Antidep har trukket tilbake denne ekstraksjonen
          {withdrawnAt === null ? '' : ` ${withdrawnAt}`}. Funnet står ikke lenger som gyldig
          evidens, men vises fordi påstanden over det fortsatt er publisert.
          {finding.extraction_withdrawal_rationale === null
            ? ''
            : ` Begrunnelse: ${finding.extraction_withdrawal_rationale}`}
        </p>
      ) : null}

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

      <dl className="evidence-finding__details">
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
          <span className="evidence-finding__detail-note">{finding.population_detail}</span>
        </Detail>

        <Detail label="Utvalgsstørrelse">
          {valueText(derived.sampleSize, (size) => `${renderedText(formatNumber(size), 'tall')}`)}
        </Detail>

        <Detail label="Intervensjon">
          {finding.intervention_drug_name}
          {finding.intervention_detail === null ? null : (
            <span className="evidence-finding__detail-note">{finding.intervention_detail}</span>
          )}
        </Detail>

        <Detail label="Komparator">
          {comparatorText(derived.comparator)}
          {finding.comparator_detail === null ? null : (
            <span className="evidence-finding__detail-note">{finding.comparator_detail}</span>
          )}
        </Detail>

        <Detail label="Endepunkt">
          {finding.outcome_label}
          <span className="evidence-finding__detail-note">{finding.outcome_detail}</span>
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
      </dl>

      <section className="evidence-finding__source">
        <SourceHeading className="evidence-finding__source-heading">Kilde</SourceHeading>
        <dl className="evidence-finding__details">
          <Detail label="Dokumenttype">
            {termText(derived.sourceType, SOURCE_TYPE_LABELS, 'dokumenttype')}
          </Detail>
          <Detail label="Forfattere eller utgiver">{finding.source_authors_or_issuer}</Detail>
          <Detail label="Tidsskrift eller utgiver">
            {finding.source_publisher_or_journal ?? 'Ikke registrert i Antidep'}
          </Detail>
          <Detail label="Publisert">{publicationDateText(derived.publicationDate)}</Detail>
          <Detail label="Kildestatus">
            {termText(derived.sourceStatus, SOURCE_STATUS_LABELS, 'kildestatus')}
            {finding.source_status_note === null ? null : (
              <span className="evidence-finding__detail-note">{finding.source_status_note}</span>
            )}
          </Detail>
          <Detail label="DOI">{dois ?? 'Ingen DOI er registrert i Antidep'}</Detail>
          <Detail label="PMID">{pmids ?? 'Ingen PMID er registrert i Antidep'}</Detail>
          {/* §16 i konstitusjonen: uten pekeren er en kontroll mot originalen
              upraktisk, og etterprøvbarheten er poenget med hele visningen. */}
          <Detail label="Sted i kilden">{finding.source_locator}</Detail>
          <Detail label="Kildeversjon">{sourceVersionText(finding)}</Detail>
        </dl>
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

/**
 * Den hentede kildeversjonen funnet ble ekstrahert fra.
 *
 * `null` betyr at ingen versjon er registrert — ikke at kilden er uendret siden
 * ekstraksjonen. For en levende kilde er hentetidspunktet det `source_locator`
 * faktisk peker inn i.
 */
function sourceVersionText(finding: PublishedClaimEvidenceRow): string {
  if (finding.source_version_id === null) {
    return 'Ingen kildeversjon er registrert. Det betyr ikke at kilden er uendret siden ekstraksjonen.'
  }
  const parts: string[] = []
  if (finding.source_version_retrieved_at !== null) {
    parts.push(
      `Hentet ${renderedText(formatTimestampAsDate(finding.source_version_retrieved_at), 'dato')}`,
    )
  }
  if (finding.source_version_external_version !== null) {
    parts.push(`Versjon ${finding.source_version_external_version}`)
  }
  if (finding.source_version_retrieved_from !== null) {
    parts.push(`Fra ${finding.source_version_retrieved_from}`)
  }
  return parts.length === 0 ? 'Registrert, uten nærmere opplysninger.' : parts.join('. ')
}
