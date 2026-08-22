// ============================================================================
// Claim-komponenten
//
// Presentasjonsenheten for én publisert påstand
// (PRODUCT_INFORMATION_ARCHITECTURE.md §13). Paragrafhenvisninger under er til
// det dokumentet der ikke annet står.
//
// Rekkefølgen følger §13: konklusjon, indikator, sikkerhet, detaljer, og til
// slutt veien videre til evidensen.
//
// ----------------------------------------------------------------------------
// Komponenten er ren presentasjon
//
// Den henter ingenting og kjenner ingen ruting. Raden kommer fra
// `api.published_claims` gjennom `fetchPublishedClaimsForDrug()`, og
// tolkningen av den ligger i `claim-certainty.ts` og `claim-effect.ts`. Her
// oversettes tilstandene derfra til norsk tekst, og ingen klinisk beslutning
// tas på nytt.
//
// ----------------------------------------------------------------------------
// Fire regler kortet er bygget rundt
//
// 1. Scope skjules aldri (§14). Anvendelsesområde, populasjon og tidsramme står
//    alltid, også når de er åpne: «ikke avgrenset» skrives ut framfor å bli en
//    rad som mangler. En rad som forsvinner får påstanden til å se universell ut.
//
// 2. Et tall står aldri uten sin komparator (§19). Størrelse og sammenligning
//    er ett felt, og det feltet er alltid til stede. Databasen håndhever ikke at
//    et kontrastivt effektmål har en komparator (se `claim-effect.ts`), så
//    visningen svarer på det ved å gjøre de to uatskillelige.
//
// 3. Kunnskapstypen står øverst (ANTIDEP_CONSTITUTION.md §5). En klinisk
//    anbefaling skal være merket som en anbefaling, ikke leses som et faktum.
//
// 4. Manglende og tilbaketrukket er egne tilstander, aldri stillhet (§17). Et
//    felt som skulle vært utfylt og ikke er det, sier det; en påstand med
//    underkjent grunnlag under seg sier det.
//
// ----------------------------------------------------------------------------
// «Ikke aktuelt» er ikke «mangler», og kunnskapstypen avgjør hvilken det er
//
// Et deterministisk faktum — et handelsnavn, en legemiddelform — har ingen
// retning og ingen effektstørrelse. Feltene er ikke tomme, de gjelder ikke
// (ANTIDEP_CONSTITUTION.md §5). Å skrive «størrelsen er ikke tallfestet, og det
// betyr ikke at effekten er null» på «finnes som tablett 50 mg» er en
// kategorifeil, og den låner faktumet en epistemisk ramme det ikke har.
//
// Derfor utelates de to aksene for et deterministisk faktum — men bare når de
// faktisk er tomme. Bærer et faktum likevel en retning eller en størrelse, er
// det noe å vise, ikke noe å skjule. Dette er samme skille som
// `not_applicable_deterministic_fact` gjør på sikkerhetsaksen.
//
// For de to andre kunnskapstypene gjelder det motsatte: der er en manglende
// tallfesting informasjon, og stillhet ville vært §17-feilen.
//
// Publiseringstidspunktet vises ikke her. §58 lister «sist faglig vurdert» som
// det klinikeren trenger på dette nivået, og kortet skal være kort (§7);
// publiseringsdatoen hører til evidensvisningen (§15).
// ============================================================================

import { useId } from 'react'
import { ClaimCertainty } from './ClaimCertainty'
import { describeClaimCertainty } from '../lib/claim-certainty'
import {
  describeClaimEffect,
  type ClaimComparatorState,
  type ClaimDirectionState,
  type ClaimMagnitudeState,
} from '../lib/claim-effect'
import { formatIntervalText, formatNumber, formatTimestampAsDate } from '../lib/norwegian-format'
import { KNOWLEDGE_TYPES } from '../types/api'
import type { EffectMeasure, EstimateUnit, KnowledgeType, PublishedClaimRow } from '../types/api'

// ----------------------------------------------------------------------------
// Vokabularene, oversatt
// ----------------------------------------------------------------------------

const KNOWLEDGE_TYPE_LABELS: Record<KnowledgeType, string> = {
  deterministic_fact: 'Deterministisk faktum',
  evidence_synthesis: 'Evidensbasert syntese',
  clinical_recommendation: 'Klinisk anbefaling',
}

const MEASURE_LABELS: Record<EffectMeasure, string> = {
  mean_change: 'Gjennomsnittlig endring',
  mean_difference: 'Gjennomsnittsforskjell',
  standardised_mean_difference: 'Standardisert gjennomsnittsforskjell (SMD)',
  risk_ratio: 'Relativ risiko (RR)',
  odds_ratio: 'Oddsratio (OR)',
}

const UNIT_LABELS: Record<EstimateUnit, string> = {
  kg: 'kg',
  percent: '%',
}

/**
 * Pilen er et supplement til teksten, aldri bæreren av den (§20). Bare de to
 * entydige retningene får et symbol: en pil for «ingen klar forskjell» ville
 * lett blitt lest som «likt», og en for «ingen retning angitt» ville gitt en
 * manglende verdi et innhold den ikke har.
 */
const DIRECTION_SYMBOLS: Partial<Record<ClaimDirectionState['kind'], string>> = {
  increase: '↑',
  decrease: '↓',
}

function directionText(direction: ClaimDirectionState): string {
  switch (direction.kind) {
    case 'increase':
      return 'Økning'
    case 'decrease':
      return 'Reduksjon'
    case 'no_clear_difference':
      // Et resultat. Formuleringen sier at grunnlaget er sett på.
      return 'Ingen klar forskjell'
    case 'not_expressed':
      // Ikke et resultat. Må ikke kunne leses som linjen over.
      return 'Påstanden angir ingen retning'
    case 'unknown':
      return `Ukjent retning («${direction.rawDirection}»)`
  }
}

function magnitudeText(magnitude: ClaimMagnitudeState): string {
  switch (magnitude.kind) {
    case 'quantified': {
      const value = formatNumber(magnitude.value)
      const unit = magnitude.unit === null ? '' : ` ${UNIT_LABELS[magnitude.unit]}`
      return `${MEASURE_LABELS[magnitude.measure]} ${value.text}${unit}.`
    }
    case 'not_quantified':
      return 'Størrelsen er ikke tallfestet.'
    case 'unknown':
      return 'Størrelsen er ikke tolkbar.'
  }
}

const MAGNITUDE_FAULTS: Record<
  Extract<ClaimMagnitudeState, { kind: 'unknown' }>['reason'],
  string
> = {
  value_without_measure:
    'Tallet står uten effektmålet som gir det betydning, og vises derfor ikke. ' +
    'Samme tall kan være en gjennomsnittsforskjell eller en oddsratio.',
  measure_without_value: 'Effektmålet står uten tallverdi, og lover en kvantifisering som mangler.',
  unrecognised_measure: 'Effektmålet er utenfor vokabularet Antidep kjenner.',
  unrecognised_unit: 'Enheten er utenfor vokabularet Antidep kjenner.',
  missing_unit:
    'Effektmålet krever en enhet, og enheten mangler. Uten den er tallet klinisk tvetydig.',
  unit_on_dimensionless_measure:
    'Effektmålet er dimensjonsløst og skal ikke bære en enhet. Tallet vises derfor ikke.',
}

function magnitudeNote(magnitude: ClaimMagnitudeState): string | null {
  switch (magnitude.kind) {
    case 'quantified':
      return null
    case 'not_quantified':
      // ANTIDEP_CONSTITUTION.md §17: en manglende tallfesting er ikke en effekt
      // på null. Tallene fra kildene ligger på evidensfunnene.
      return (
        'Påstanden tallfester bevisst ikke størrelsen. Det betyr ikke at effekten er null. ' +
        'Tallene fra kildene ligger på evidensfunnene.'
      )
    case 'unknown':
      return MAGNITUDE_FAULTS[magnitude.reason]
  }
}

function comparatorText(comparator: ClaimComparatorState): string {
  switch (comparator.kind) {
    case 'drug':
      return `Sammenlignet med ${comparator.drugName}.`
    case 'placebo':
      return 'Sammenlignet med placebo.'
    case 'none':
      // «none» er en registrert tilstand, ikke en manglende verdi.
      return 'Ingen komparator: endring fra behandlingsstart.'
    case 'unknown':
      return 'Komparatoren er ikke tolkbar.'
  }
}

// ----------------------------------------------------------------------------
// Feltene som kan komme tomme eller uparede
// ----------------------------------------------------------------------------

/**
 * Migrasjon 004 krever at `statement` og `scope` er trimmet og ikke tomme. Vi
 * leser likevel også en database vi ikke selv har migrert, og en tom overskrift
 * er verre enn en synlig mangel.
 */
function textOrFault(value: string, fault: string): string {
  return value.trim().length === 0 ? fault : value
}

/**
 * Tidsrammen. Databasen parer `timeframe_min` og `timeframe_max`, så et enslig
 * ledd er et brudd og sies høyt framfor å bli halve sannheten.
 */
function timeframeText(min: string | null, max: string | null): string {
  if (min === null && max === null) {
    // Skrives ut. En rad som mangler får påstanden til å se tidløs ut (§14).
    return 'Ikke tidsavgrenset'
  }
  if (min === null || max === null) {
    const present = min ?? max ?? ''
    return `Ufullstendig registrert tidsramme: ${formatIntervalText(present).text}`
  }
  const from = formatIntervalText(min).text
  const to = formatIntervalText(max).text
  return from === to ? from : `${from} til ${to}`
}

function withdrawalText(count: number): string | null {
  if (!Number.isInteger(count) || count < 0) {
    // En benign gren her ville gjort et utolkbart antall til «ingenting å si».
    return `Antallet tilbaketrukne evidenslenker er ikke tolkbart (verdi: ${String(count)}).`
  }
  if (count === 0) {
    return null
  }
  const lead =
    count === 1
      ? 'Én av evidenslenkene bak denne påstanden er trukket tilbake etter publisering.'
      : `${formatNumber(count).text} av evidenslenkene bak denne påstanden er trukket tilbake ` +
        'etter publisering.'
  return `${lead} Påstanden står fortsatt publisert, men deler av grunnlaget er underkjent.`
}

function isKnowledgeType(value: string): value is KnowledgeType {
  return (KNOWLEDGE_TYPES as readonly string[]).includes(value)
}

// ----------------------------------------------------------------------------

export interface ClaimCardProps {
  readonly claim: PublishedClaimRow
  /**
   * Veien til «Hvorfor sier Antidep dette?» (§15). Påkrevd, ikke valgfri: en
   * klinisk relevant påstand skal alltid ha den (produktinvariant 9), og en
   * lenke framfor en handling gjør evidensvisningen delbar og bokmerkbar (§55).
   * URL-en eies av rutingen, ikke av kortet.
   */
  readonly evidenceHref: string
}

export function ClaimCard({ claim, evidenceHref }: ClaimCardProps) {
  const headingId = useId()
  const linkId = useId()

  const effect = describeClaimEffect(claim)
  const withdrawal = withdrawalText(claim.withdrawn_evidence_count)
  const reviewed =
    claim.last_reviewed_at === null ? null : formatTimestampAsDate(claim.last_reviewed_at)
  const magnitudeNoteText = magnitudeNote(effect.magnitude)
  const directionSymbol = DIRECTION_SYMBOLS[effect.direction.kind]

  // Se merknaden øverst: for et deterministisk faktum er en tom retning og en
  // tom størrelse ikke aktuelle, ikke manglende.
  const deterministic = claim.knowledge_type === 'deterministic_fact'
  const showDirection = !(deterministic && effect.direction.kind === 'not_expressed')
  const showMagnitude = !(
    deterministic &&
    effect.magnitude.kind === 'not_quantified' &&
    effect.comparator.kind === 'none'
  )

  // Usikkerhetsteksten er påkrevd for evidenssynteser og kliniske anbefalinger
  // (migrasjon 004). Mangler den likevel, sies det — også for en kunnskapstype
  // Antidep ikke kjenner, som ikke kan antas å være unntatt.
  const uncertaintyExempt = claim.knowledge_type === 'deterministic_fact'
  const uncertainty =
    claim.uncertainty_summary ??
    (uncertaintyExempt ? null : 'Usikkerhetsvurderingen mangler, og skulle vært utfylt.')

  return (
    <article className="claim-card" aria-labelledby={headingId}>
      <p className="claim-card__knowledge-type">
        {isKnowledgeType(claim.knowledge_type)
          ? KNOWLEDGE_TYPE_LABELS[claim.knowledge_type]
          : `Ukjent kunnskapstype («${claim.knowledge_type}»)`}
      </p>

      <h3 className="claim-card__statement" id={headingId}>
        {textOrFault(claim.statement, 'Påstanden mangler formulering.')}
      </h3>

      {showDirection ? (
        <p className="claim-card__direction" data-direction={effect.direction.kind}>
          {directionSymbol === undefined ? null : (
            <span aria-hidden="true" className="claim-card__direction-symbol">
              {directionSymbol}
            </span>
          )}
          {directionText(effect.direction)}
        </p>
      ) : null}

      <ClaimCertainty certainty={describeClaimCertainty(claim)} />

      {withdrawal === null ? null : (
        <p className="claim-card__withdrawal" role="note">
          {withdrawal}
        </p>
      )}

      <dl className="claim-card__details">
        <div className="claim-card__detail">
          <dt>Gjelder</dt>
          <dd>{textOrFault(claim.scope, 'Anvendelsesområdet mangler.')}</dd>
        </div>

        <div className="claim-card__detail">
          <dt>Populasjon</dt>
          {/* NULL betyr uavgrenset, ikke ukjent. De to må ikke bytte plass. */}
          <dd>{claim.population_label ?? 'Ikke avgrenset til en registrert populasjon'}</dd>
        </div>

        <div className="claim-card__detail">
          <dt>Tidsramme</dt>
          <dd>{timeframeText(claim.timeframe_min, claim.timeframe_max)}</dd>
        </div>

        {showMagnitude ? (
          <div className="claim-card__detail">
            <dt>Størrelse og sammenligning</dt>
            {/* Ett felt, med hensikt: tallet skal ikke kunne stå uten komparatoren. */}
            <dd>
              {`${magnitudeText(effect.magnitude)} ${comparatorText(effect.comparator)}`}
              {magnitudeNoteText === null ? null : (
                <span className="claim-card__detail-note">{magnitudeNoteText}</span>
              )}
            </dd>
          </div>
        ) : null}

        {claim.qualifiers === null ? null : (
          <div className="claim-card__detail">
            <dt>Forbehold</dt>
            <dd>{claim.qualifiers}</dd>
          </div>
        )}

        {uncertainty === null ? null : (
          <div className="claim-card__detail">
            <dt>Usikkerhet</dt>
            <dd>{uncertainty}</dd>
          </div>
        )}
      </dl>

      <footer className="claim-card__footer">
        <p className="claim-card__reviewed">
          {/* «Ukjent» er ikke «ikke vurdert» og ikke en fersk dato (§58). */}
          Sist faglig vurdert: {reviewed === null ? 'Ukjent' : reviewed.text}
        </p>
        <a
          className="claim-card__evidence-link"
          href={evidenceHref}
          id={linkId}
          // Uten dette heter hver lenke på en side med flere kort det samme.
          aria-labelledby={`${linkId} ${headingId}`}
        >
          Hvorfor sier Antidep dette?
        </a>
      </footer>
    </article>
  )
}
