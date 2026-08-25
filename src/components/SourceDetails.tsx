// ============================================================================
// Kilden, som felter
//
// Felles for de to visningene §42 skiller mellom: evidensvisningen viser kilden
// under hvert funn, kildesiden har den som emne. Samme rad, samme regler. To
// utgaver ville vært to presentasjoner av samme sannhet, og den ene ville fått
// en rettelse den andre ikke fikk (§65 «Duplicated truth»).
//
// Modulen holder de to tingene fra hverandre, fordi de beskriver hvert sitt
// objekt:
//
//   SourcePublicationDetails   dokumentet. Hva slags dokument det er, hvem som
//                              står bak, hvor og når det ble publisert, hvilken
//                              status Antidep har gitt det, og hvilke globale
//                              identifikatorer det har. Ingenting om hva Antidep
//                              mener dokumentet viser — det er evidensfunnenes
//                              og påstandenes oppgave (KNOWLEDGE_MODEL.md §10).
//
//   ExtractionWithdrawalNote   at Antidep har underkjent nettopp denne
//                              ekstraksjonen. Merkingen skjuler ikke funnet: det
//                              står fordi påstanden over det fortsatt er
//                              publisert (ANTIDEP_CONSTITUTION.md §14).
//
//   SourceExtractionDetails    funnets vei inn i dokumentet. Hvor i kilden
//                              funnet står, og hvilken hentet versjon det ble
//                              ekstrahert fra. Begge hører til *funnet*: samme
//                              kilde kan være lest på to steder og i to
//                              versjoner av to forskjellige funn, så en samlet
//                              «versjon» på kilden ville vært en sammenslåing
//                              datamodellen ikke har.
//
// Paragrafhenvisninger er til PRODUCT_INFORMATION_ARCHITECTURE.md der ikke
// annet står.
//
// ----------------------------------------------------------------------------
// To regler modulen er bygget rundt
//
// 1. `active` skrives ut som alle de andre statusene. En status som bare vises
//    når den er avvikende, gjør fravær av merking til en påstand ingen har tatt
//    stilling til, og en tilbaketrukket kilde skal aldri kunne se normal ut
//    (ANTIDEP_CONSTITUTION.md §14).
//
// 2. Datoen står aldri uten sin presisjon. En dato som bare er kjent til året,
//    vist som 1. januar, er falsk presisjon som ikke ser ut som en feil
//    (ANTIDEP_CONSTITUTION.md §6).
// ============================================================================

import { Detail, DetailNote } from './DetailList'
import { SOURCE_STATUS_LABELS, SOURCE_TYPE_LABELS, termText } from './vocabulary-labels'
import { describeSource } from '../lib/evidence-item'
import type { PublicationDateState, SourceDescriptionInput } from '../lib/evidence-item'
import { formatDateAtPrecision, formatTimestampAsDate, renderedText } from '../lib/norwegian-format'
import { describeDoi, describePmid, type SourceIdentifierLink } from '../lib/source-identifier'

/**
 * Feltene komponenten leser fra `api.published_claim_evidence`.
 *
 * Skrevet som en egen form framfor hele radtypen, etter samme mønster som
 * `EvidenceStanceInput` i `evidence-item.ts`: komponenten beskriver kilden, og
 * skal ikke kunne komme til å lese et felt som hører til funnet. Radtypen
 * oppfyller formen strukturelt.
 *
 * Tittelen står ikke her. Den er overskriften i begge visningene, og eies
 * derfor av siden som bestemmer overskriftsnivået.
 */
export interface SourcePublicationInput extends SourceDescriptionInput {
  readonly source_authors_or_issuer: string
  readonly source_publisher_or_journal: string | null
  readonly source_status_note: string | null
  readonly source_dois: readonly string[] | null
  readonly source_pmids: readonly string[] | null
}

/**
 * At statusen er `superseded`, betyr per migrasjon 003 at en *bestemt* nyere
 * kilde er registrert: `knowledge.sources.superseded_by_source_id` er NOT NULL
 * hvis og bare hvis statusen er den. Pekeren er ikke i api-kontrakten, så
 * klienten kan ikke følge den, og etiketten alene ville vært en halv sannhet —
 * den sier at det finnes en etterfølger uten å kunne navngi den.
 *
 * Merknaden sier hva Antidep vet og hva visningen ikke kan vise, framfor å la
 * leseren tro at etterfølgeren ikke er registrert. Registrert som gjeld i
 * MVP_IMPLEMENTATION_PLAN.md §74.7.
 */
const SUPERSEDED_NOTE =
  'Antidep har registrert hvilken nyere kilde som erstatter denne, men lesemodellen ' +
  'eksponerer den ikke, så den kan ikke navngis her.'

const DOI_RESOLVER_NOTE = 'Løses opp hos doi.org, utenfor Antidep.'
const PMID_RESOLVER_NOTE = 'Løses opp hos PubMed, utenfor Antidep.'

/**
 * En identifikator som ikke har den formen databasen registrerer.
 *
 * Migrasjon 003 håndhever formen med en `CHECK`, så tilstanden er et
 * kontraktsbrudd og ikke en variasjon. Verdien vises likevel: en identifikator
 * som forsvinner fordi den ikke lot seg gjøre om til en adresse, ser ut som en
 * kilde uten identifikator.
 */
const UNRESOLVABLE_NOTE =
  'Verdien har ikke den formen Antidep registrerer, og er derfor ikke gjort om til en lenke.'

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

interface IdentifiersProps {
  readonly values: readonly string[] | null
  readonly describe: (value: string) => SourceIdentifierLink
  readonly absent: string
  readonly resolverNote: string
}

/**
 * Identifikatorene for ett system, som liste.
 *
 * Liste og ikke én verdi: kildemodellen tillater flere, ingen av dem er definert
 * som primær, og å velge én ville gjort en vilkårlig kanonisering til det
 * leseren ser. Rekkefølgen er den `api` gir, som er sortert på verdien —
 * alfabetisk på en identifikator er ingen rangering av noe.
 *
 * Lenkene åpner i samme fane. En tvungen ny fane ville overstyrt leserens eget
 * valg, og tilbakeknappen bevarer konteksten (§56). `rel="noreferrer"` holder
 * adressen leseren står på, utenfor forespørselen til den eksterne tjenesten
 * (ANTIDEP_CONSTITUTION.md §18).
 */
function Identifiers({ values, describe, absent, resolverNote }: IdentifiersProps) {
  if (values === null || values.length === 0) {
    return <>{absent}</>
  }
  return (
    <>
      <ul className="identifier-list">
        {values.map((value) => {
          const link = describe(value)
          return (
            <li key={value}>
              {link.kind === 'resolvable' ? (
                <a href={link.href} rel="noreferrer">
                  {link.value}
                </a>
              ) : (
                <>
                  {link.value}
                  <DetailNote>{UNRESOLVABLE_NOTE}</DetailNote>
                </>
              )}
            </li>
          )
        })}
      </ul>
      <DetailNote>{resolverNote}</DetailNote>
    </>
  )
}

export interface SourcePublicationDetailsProps {
  readonly source: SourcePublicationInput
}

/**
 * Feltene, uten `dl`-en rundt.
 *
 * Kalleren eier listen, slik at evidensvisningen kan sette funnets egne felter —
 * sted i kilden og kildeversjon — i den samme listen framfor i en ny.
 */
export function SourcePublicationDetails({ source }: SourcePublicationDetailsProps) {
  const { sourceType, sourceStatus, publicationDate } = describeSource(source)

  return (
    <>
      <Detail label="Dokumenttype">
        {termText(sourceType, SOURCE_TYPE_LABELS, 'dokumenttype')}
      </Detail>
      <Detail label="Forfattere eller utgiver">{source.source_authors_or_issuer}</Detail>
      <Detail label="Tidsskrift eller utgiver">
        {source.source_publisher_or_journal ?? 'Ikke registrert i Antidep'}
      </Detail>
      <Detail label="Publisert">{publicationDateText(publicationDate)}</Detail>
      <Detail label="Kildestatus">
        {termText(sourceStatus, SOURCE_STATUS_LABELS, 'kildestatus')}
        {source.source_status_note === null ? null : (
          <DetailNote>{source.source_status_note}</DetailNote>
        )}
        {sourceStatus.kind === 'known' && sourceStatus.value === 'superseded' ? (
          <DetailNote>{SUPERSEDED_NOTE}</DetailNote>
        ) : null}
      </Detail>
      <Detail label="DOI">
        <Identifiers
          values={source.source_dois}
          describe={describeDoi}
          absent="Ingen DOI er registrert i Antidep"
          resolverNote={DOI_RESOLVER_NOTE}
        />
      </Detail>
      <Detail label="PMID">
        <Identifiers
          values={source.source_pmids}
          describe={describePmid}
          absent="Ingen PMID er registrert i Antidep"
          resolverNote={PMID_RESOLVER_NOTE}
        />
      </Detail>
    </>
  )
}

// ----------------------------------------------------------------------------
// Funnets vei inn i kilden
// ----------------------------------------------------------------------------

/** Feltene som sier hvor og i hvilken versjon ett funn ble lest ut av kilden. */
export interface SourceExtractionInput {
  readonly source_locator: string
  readonly source_version_id: string | null
  readonly source_version_retrieved_at: string | null
  readonly source_version_retrieved_from: string | null
  readonly source_version_external_version: string | null
}

/**
 * Den hentede kildeversjonen funnet ble ekstrahert fra.
 *
 * `null` betyr at ingen versjon er registrert — ikke at kilden er uendret siden
 * ekstraksjonen. For en levende kilde er hentetidspunktet det `source_locator`
 * faktisk peker inn i.
 */
function sourceVersionText(extraction: SourceExtractionInput): string {
  if (extraction.source_version_id === null) {
    return 'Ingen kildeversjon er registrert. Det betyr ikke at kilden er uendret siden ekstraksjonen.'
  }
  const parts: string[] = []
  if (extraction.source_version_retrieved_at !== null) {
    const retrieved = renderedText(
      formatTimestampAsDate(extraction.source_version_retrieved_at),
      'dato',
    )
    parts.push(`Hentet ${retrieved}`)
  }
  if (extraction.source_version_external_version !== null) {
    parts.push(`Versjon ${extraction.source_version_external_version}`)
  }
  if (extraction.source_version_retrieved_from !== null) {
    parts.push(`Fra ${extraction.source_version_retrieved_from}`)
  }
  return parts.length === 0 ? 'Registrert, uten nærmere opplysninger.' : parts.join('. ')
}

export interface SourceExtractionDetailsProps {
  readonly extraction: SourceExtractionInput
}

/**
 * Hvor i kilden funnet står, og hvilken versjon det ble lest ut av.
 *
 * Uten pekeren er en kontroll mot originalen upraktisk, og etterprøvbarheten er
 * poenget med både evidensvisningen og kildesiden (ANTIDEP_CONSTITUTION.md §4,
 * PRODUCT_INFORMATION_ARCHITECTURE.md §43).
 */
export function SourceExtractionDetails({ extraction }: SourceExtractionDetailsProps) {
  return (
    <>
      <Detail label="Sted i kilden">{extraction.source_locator}</Detail>
      <Detail label="Kildeversjon">{sourceVersionText(extraction)}</Detail>
    </>
  )
}

/** Feltene tilbaketrekkingsmerket leser. */
export interface ExtractionWithdrawalInput {
  readonly extraction_withdrawn: boolean
  readonly extraction_withdrawn_at: string | null
  readonly extraction_withdrawal_rationale: string | null
}

export interface ExtractionWithdrawalNoteProps {
  readonly extraction: ExtractionWithdrawalInput
}

/**
 * Merket på en ekstraksjon Antidep har trukket tilbake — eller ingenting, når
 * ingen tilbaketrekking er registrert.
 *
 * Funnet skjules ikke. Beslutningen er append-only og kan komme etter
 * publiseringen, så påstanden over funnet kan stå publisert mens deler av
 * grunnlaget er underkjent; da er merkingen det eneste som skiller de to
 * tilstandene (ANTIDEP_CONSTITUTION.md §14). Begge visningene bruker den samme,
 * slik at et funn ikke kan se gyldig ut det ene stedet og underkjent det andre.
 */
export function ExtractionWithdrawalNote({ extraction }: ExtractionWithdrawalNoteProps) {
  if (!extraction.extraction_withdrawn) {
    return null
  }
  const withdrawnAt =
    extraction.extraction_withdrawn_at === null
      ? ''
      : ` ${renderedText(formatTimestampAsDate(extraction.extraction_withdrawn_at), 'dato')}`
  return (
    <p className="extraction-withdrawal" role="note">
      Antidep har trukket tilbake denne ekstraksjonen{withdrawnAt}. Funnet står ikke lenger som
      gyldig evidens, men vises fordi påstanden over det fortsatt er publisert.
      {extraction.extraction_withdrawal_rationale === null
        ? ''
        : ` Begrunnelse: ${extraction.extraction_withdrawal_rationale}`}
    </p>
  )
}
