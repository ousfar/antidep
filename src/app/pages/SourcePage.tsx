// ============================================================================
// Kildesiden — `/sources/:sourceId`
//
// Den andre halvdelen av PRODUCT_INFORMATION_ARCHITECTURE.md §42: en
// `Source`-visning beskriver én publikasjon, mens claim-evidensvisningen
// beskriver hvorfor flere evidensfunn samlet støtter én påstand. De skal lenke
// til hverandre, men ikke blandes. Paragrafhenvisninger under er til det
// dokumentet der ikke annet står.
//
// Siden svarer på det motsatte spørsmålet av evidensvisningen. Der spør
// klinikeren «hva hviler denne påstanden på?»; her står hun med en publikasjon
// og spør «hva bruker Antidep denne til?». Det er §41 sitt siste punkt, «full
// referanseliste», besvart som en visning per kilde framfor som en liste under
// hver påstand (§74.15).
//
// ----------------------------------------------------------------------------
// Hva siden ikke er
//
// Den sier ikke hva kilden konkluderer med. Kilderaden beskriver dokumentet, og
// hva Antidep mener dokumentet viser, ligger i evidensfunnene og påstandene
// (KNOWLEDGE_MODEL.md §10). Den gjentar heller ikke evidensvisningen: hvorfor et
// funn støtter eller motsier en påstand — populasjon, komparator, resultat,
// presisjon — står der, og herfra går det en lenke til den. Det siden legger til,
// er kildens eget bidrag til hvert funn: relasjonen funnet har til påstanden,
// hvor i kilden det står, og hvilken hentet versjon det ble lest ut av.
//
// ----------------------------------------------------------------------------
// To spørringer, og hvorfor den andre er hele det publiserte settet
//
// `api` har ingen kildeprojeksjon. `published_claim_evidence` er det eneste
// stedet kildedata finnes, så kilden hentes ved å filtrere evidensradene på
// `source_id`. De radene bærer ikke `statement`, og en liste over «hva Antidep
// bruker denne kilden til» uten påstandsformuleringen ville vært en liste over
// identiteter. Formuleringene hentes derfor med `fetchPublishedClaims()` og
// kobles i klienten.
//
// Det er den samme gjelden temasiden allerede har — hele det publiserte settet
// lastes for å vise ett utsnitt — og her kommer en klientside-join i tillegg.
// Det holder mens settet er lite, og det er registrert som gjeld i
// MVP_IMPLEMENTATION_PLAN.md §74.7 framfor å bli en stille andre forekomst.
// Triggeren er den samme: en projeksjon i `api` som lar oppslaget skje på
// serversiden.
// ============================================================================

import { useCallback, useId } from 'react'
import { Link, useParams } from 'react-router'
import { ClaimCard } from '../../components/ClaimCard'
import { DetailList } from '../../components/DetailList'
import {
  KnowledgeAbsence,
  KnowledgeError,
  KnowledgeLoading,
} from '../../components/KnowledgeNotice'
import {
  ExtractionWithdrawalNote,
  SourceExtractionDetails,
  SourcePublicationDetails,
} from '../../components/SourceDetails'
import { stanceText } from '../../components/vocabulary-labels'
import { describeEvidenceStance } from '../../lib/evidence-item'
import { compareNorwegian } from '../../lib/norwegian-format'
import {
  fetchPublishedClaims,
  fetchPublishedEvidenceForSource,
} from '../../lib/published-read-model'
import { COMPARISON_CAVEAT } from '../ClaimGroups'
import { claimEvidencePath, drugPath, topicPath } from '../routes'
import { useReadModel, type ReadModelState } from '../use-read-model'
import { usePageTitle } from '../use-page-title'
import type { PublishedClaimEvidenceRow, PublishedClaimRow, Uuid } from '../../types/api'

const USAGE_SECTION_ID = 'bruken'

/**
 * Rekkefølgen *og* hva listen er, som på enhver annen liste over kliniske
 * objekter i flaten (§74.14 punkt 1).
 *
 * Den siste setningen er den viktigste her, og den finnes ikke på de andre
 * listene: en side om én publikasjon leses lett som en oppsummering av hva
 * publikasjonen sier. Listen er Antideps bruk av kilden, ikke kildens innhold.
 */
const USAGE_NOTE =
  'Dette er de publiserte påstandene som hviler på minst ett evidensfunn fra denne kilden. ' +
  'Støttende, motstridende, nøytrale og indirekte funn står side om side, og et funn med ' +
  'tilbaketrukket ekstraksjon står også her. Rekkefølgen er alfabetisk etter påstandens ' +
  'formulering og er verken en rangering eller et uttrykk for hvor tungt kilden veier. ' +
  'Listen sier hva Antidep bruker kilden til, ikke hva kilden selv konkluderer med.'

// ----------------------------------------------------------------------------
// Koblingen mellom funnene og påstandene de hører til
// ----------------------------------------------------------------------------

/** Én publisert påstand, med de funnene fra denne kilden som er lenket til den. */
interface ClaimUsage {
  readonly claim: PublishedClaimRow
  readonly findings: readonly PublishedClaimEvidenceRow[]
}

/**
 * Hvorfor et sett ikke kan vises.
 *
 *   `republished`           en påstand ble publisert på nytt mellom de to
 *                           spørringene. Funnene Antidep hentet, hører til en
 *                           annen revisjon enn den som står publisert nå.
 *   `no_longer_published`   en påstand et funn er lenket til, stod ikke i det
 *                           publiserte settet da det ble hentet. Den kan være
 *                           avpublisert eller trukket tilbake i mellomtiden.
 *
 * De to har hver sin ordlyd, fordi de har hver sin årsak, og ingen av dem deler
 * ordlyd med et tomt svar.
 */
type UsageFault = 'republished' | 'no_longer_published'

type UsageResolution =
  | { readonly kind: 'resolved'; readonly usages: readonly ClaimUsage[] }
  | { readonly kind: 'unresolvable'; readonly reason: UsageFault }

/**
 * Funnene, koblet til påstandene sine.
 *
 * ----------------------------------------------------------------------------
 * Kravet enhver side som leser to api-views arver (§74.15 punkt 5)
 *
 * Begge viewene følger `current_published_revision_id`, og de to spørringene er
 * uavhengige. Publiseres en påstand på nytt mellom dem, svarer
 * `published_claim_evidence` med funnene til revisjon N og `published_claims`
 * med formuleringen i N+1 — eller omvendt — og siden ville vist et funn som
 * grunnlag for en formulering det aldri var lenket til. Det er nøyaktig det
 * `ANTIDEP_CONSTITUTION.md` §4 forbyr.
 *
 * Hver evidensrad bærer sin `claim_revision_id`, og settet vises bare når hver
 * av dem hører til den revisjonen påstandsraden oppgir.
 *
 * ----------------------------------------------------------------------------
 * Ingen delvis liste
 *
 * Et avvik på én påstand forkaster hele listen, ikke bare den påstanden. En
 * liste bærer to påstander — rekkefølgen, og at dette er settet (§74.14 punkt 1)
 * — og en liste der en påstand er utelatt fordi den skiftet under lastingen,
 * sier at kilden brukes til færre ting enn den gjør. Vinduet er lite, og
 * rettingen er å laste siden på nytt.
 *
 * ----------------------------------------------------------------------------
 * Hvorfor et oppslag på `claim_id` ikke kan miste en kobling
 *
 * `api.published_claims` har nøyaktig én rad per publisert påstand: viewet
 * joiner påstanden mot `current_published_revision_id` på primærnøkkelen, og
 * `evidence_assessments` er unik per revisjon (migrasjon 004). To rader med
 * samme `claim_id` og forskjellig revisjon kan dermed ikke oppstå, og et oppslag
 * på identiteten kan ikke velge feil av dem.
 */
function resolveUsages(
  findings: readonly PublishedClaimEvidenceRow[],
  claims: readonly PublishedClaimRow[],
): UsageResolution {
  const byClaimId = new Map(claims.map((claim) => [claim.claim_id, claim]))
  const usages = new Map<
    Uuid,
    { claim: PublishedClaimRow; findings: PublishedClaimEvidenceRow[] }
  >()

  for (const finding of findings) {
    const claim = byClaimId.get(finding.claim_id)
    if (claim === undefined) {
      return { kind: 'unresolvable', reason: 'no_longer_published' }
    }
    if (claim.claim_revision_id !== finding.claim_revision_id) {
      return { kind: 'unresolvable', reason: 'republished' }
    }
    const existing = usages.get(claim.claim_id)
    if (existing === undefined) {
      usages.set(claim.claim_id, { claim, findings: [finding] })
    } else {
      existing.findings.push(finding)
    }
  }

  // Alfabetisk på formuleringen, med norsk kollasjon: en rekkefølge en norsk
  // leser leser som usortert, ser ut som en rekkefølge etter noe annet — for
  // eksempel etter viktighet (invariant 14). Funnene under hver påstand står i
  // den rekkefølgen spørringen ga: stabil mellom kall, uten mening.
  return {
    kind: 'resolved',
    usages: [...usages.values()].sort((a, b) =>
      compareNorwegian(a.claim.statement, b.claim.statement),
    ),
  }
}

// ----------------------------------------------------------------------------
// Ett funn, slik kildesiden viser det
// ----------------------------------------------------------------------------

/**
 * Kildens eget bidrag til ett funn.
 *
 * Relasjonen står øverst og som tekst, slik at et motstridende funn ikke kan
 * leses som støtte fordi det står i en liste over «hva kilden brukes til»
 * (ANTIDEP_CONSTITUTION.md §9). Resten av funnet — populasjon, komparator,
 * resultat, presisjon — hører til evidensvisningen, og lenken til den står på
 * påstandskortet over.
 */
function SourceFinding({ finding }: { readonly finding: PublishedClaimEvidenceRow }) {
  const stance = describeEvidenceStance(finding)

  return (
    <div
      className="source-finding"
      data-withdrawn={finding.extraction_withdrawn ? 'true' : undefined}
    >
      <ExtractionWithdrawalNote extraction={finding} />
      <p className="source-finding__stance">{stanceText(stance)}</p>
      <DetailList>
        <SourceExtractionDetails extraction={finding} />
      </DetailList>
    </div>
  )
}

function ClaimUsageEntry({ usage }: { readonly usage: ClaimUsage }) {
  const findingsId = useId()

  return (
    <div className="source-usage">
      {/* Konteksten påstanden hører til. Kortet bærer den ikke selv — på
          legemiddelsiden er virkestoffet siden, og på temasiden er det
          gruppeoverskriften — men her står påstander om flere virkestoff under
          én overskrift, og da må hver av dem si hvilket (§45). */}
      <p className="source-usage__context">
        Virkestoff <Link to={drugPath(usage.claim.drug_name)}>{usage.claim.drug_name}</Link>, tema{' '}
        <Link to={topicPath(usage.claim.topic_label)}>{usage.claim.topic_label}</Link>.
      </p>
      {/* Samme kort som på de tre andre sidene. Uten det ville formuleringen
          stått her uten sikkerhetsgrad, anvendelsesområde og forbehold — altså
          som en påstand mer skråsikker enn den er (§14, invariant 4), og som en
          parallell presentasjon av samme kliniske sannhet (§65). */}
      <ClaimCard
        claim={usage.claim}
        evidenceHref={claimEvidencePath(usage.claim.claim_id)}
        headingLevel={4}
      />
      <div aria-labelledby={findingsId} className="source-usage__findings" role="group">
        {/* En ekte overskrift, ikke bare en fet linje: funnene er en underdel av
            påstanden over dem, og disposisjonen er en tilgjengelighetsegenskap
            (§50, §53). Samme nivåvalg som «Kilde» under hvert funn på
            evidenssiden — h4 påstand, h5 det som hører til den. */}
        <h5 className="source-usage__findings-heading" id={findingsId}>
          Funn fra denne kilden
        </h5>
        {usage.findings.map((finding) => (
          <SourceFinding key={finding.claim_evidence_link_id} finding={finding} />
        ))}
      </div>
    </div>
  )
}

// ----------------------------------------------------------------------------
// Bruken
// ----------------------------------------------------------------------------

function UsageFaultNotice({ reason }: { readonly reason: UsageFault }) {
  return (
    <div className="knowledge-notice knowledge-notice--error" role="alert">
      <p className="knowledge-notice__lead">
        {reason === 'republished'
          ? 'En av påstandene ble publisert på nytt mens siden lastet. Funnene Antidep hentet fra ' +
            'denne kilden, hører til en annen revisjon enn den som står publisert nå, og listen ' +
            'vises derfor ikke: funnene ville stått som grunnlag for en formulering de ikke er ' +
            'lenket til.'
          : 'En av påstandene denne kilden brukes til, stod ikke lenger i det publiserte settet ' +
            'da Antidep hentet det. Listen vises derfor ikke: den ville sagt at kilden brukes til ' +
            'færre påstander enn funnene viser.'}
      </p>
      <p className="knowledge-notice__detail">
        Last siden på nytt for å se den gjeldende bruken av kilden.
      </p>
    </div>
  )
}

function SourceUsage({ findings }: { readonly findings: readonly PublishedClaimEvidenceRow[] }) {
  const state: ReadModelState<PublishedClaimRow> = useReadModel(fetchPublishedClaims)

  switch (state.status) {
    case 'loading':
      return <KnowledgeLoading />
    case 'error':
      return <KnowledgeError message={state.message} />
    case 'empty':
      // Ikke en fraværstilstand. Et evidensfunn står i `api` bare fordi det er
      // lenket til en publisert påstand, så et tomt påstandssett samtidig med
      // funn fra denne kilden er et kontraktsbrudd — og det må ikke se ut som
      // en rolig opplysning om at kilden ikke brukes til noe.
      return (
        <div className="knowledge-notice knowledge-notice--error" role="alert">
          <p className="knowledge-notice__lead">
            Antidep fant evidensfunn fra denne kilden, men ingen publiserte påstander. Det skal ikke
            kunne skje: et funn vises bare fordi det er lenket til en publisert påstand. Hva kilden
            brukes til, kan derfor ikke navngis her.
          </p>
        </div>
      )
    case 'ok': {
      const resolution = resolveUsages(findings, state.rows)
      if (resolution.kind === 'unresolvable') {
        return <UsageFaultNotice reason={resolution.reason} />
      }
      return (
        <>
          <div className="source-usage__notes">
            <p className="source-usage__note">{USAGE_NOTE}</p>
            <p className="source-usage__note">{COMPARISON_CAVEAT}</p>
          </div>
          {resolution.usages.map((usage) => (
            <ClaimUsageEntry key={usage.claim.claim_id} usage={usage} />
          ))}
        </>
      )
    }
  }
}

// ----------------------------------------------------------------------------
// Siden
// ----------------------------------------------------------------------------

function SourceBody({
  sourceId,
  state,
}: {
  readonly sourceId: Uuid
  readonly state: ReadModelState<PublishedClaimEvidenceRow>
}) {
  switch (state.status) {
    case 'loading':
      return <KnowledgeLoading />
    case 'error':
      return <KnowledgeError message={state.message} />
    case 'empty':
      return (
        <KnowledgeAbsence>
          Antidep har ingen publisert kunnskap som bygger på en kilde med identiteten «{sourceId}».
          Det er et utsagn om Antideps innhold: identiteten kan være feilskrevet, kilden kan være
          registrert uten at noe publisert hviler på den, og en publisering som brukte den kan ha
          blitt trukket tilbake.
        </KnowledgeAbsence>
      )
    case 'ok': {
      // Kildefeltene er de samme på hver rad: spørringen filtrerer på
      // `source_id`, og viewet joiner hver evidensrad mot nøyaktig én rad i
      // `knowledge.sources`. Databasen håndhever at de er like, så den første
      // raden beskriver kilden like godt som enhver annen.
      const [first] = state.rows

      return (
        <>
          <section aria-labelledby="publikasjonen">
            <h3 id="publikasjonen">Publikasjonen</h3>
            <DetailList>
              <SourcePublicationDetails source={first} />
            </DetailList>
          </section>

          <section aria-labelledby={USAGE_SECTION_ID}>
            <h3 id={USAGE_SECTION_ID}>Hva Antidep bruker kilden til</h3>
            <SourceUsage findings={state.rows} />
          </section>
        </>
      )
    }
  }
}

export function SourcePage() {
  const { sourceId = '' } = useParams()
  const query = useCallback(
    (client: Parameters<typeof fetchPublishedEvidenceForSource>[0]) =>
      fetchPublishedEvidenceForSource(client, sourceId),
    [sourceId],
  )
  const state = useReadModel(query)
  const title = state.status === 'ok' ? state.rows[0].source_title : null

  // Tittelen er dokumentets egen, og den er en tittel og ingen klinisk påstand —
  // i motsetning til påstandsformuleringen, som evidensvisningen med vilje
  // holder ute av faneraden. Uten et treff står den nøytralt: identiteten fra
  // URL-en som tittel ville gjort en adresse leseren skrev, til noe Antidep ser
  // ut til å ha.
  usePageTitle(title ?? 'Kilde')

  return (
    <>
      {/* Objekttypen skrives ut når adressen traff, slik at en kildetittel ikke
          kan forveksles med en påstand (§45). Traff den ikke, sier overskriften
          det samme, og en gjentakelse ville vært støy. */}
      {title === null ? null : <p className="page-kicker">Kilde</p>}
      <h2 className={title === null ? undefined : 'source-title'}>{title ?? 'Kilde'}</h2>
      <SourceBody sourceId={sourceId} state={state} />
    </>
  )
}
