// ============================================================================
// Evidensvisningen — `/claims/:claimId/evidence`
//
// «Hvorfor sier Antidep dette?» (PRODUCT_INFORMATION_ARCHITECTURE.md §15).
// Paragrafhenvisninger under er til det dokumentet der ikke annet står.
//
// Rekkefølgen følger §41: påstanden først, med sin sikkerhet og sin
// usikkerhetsbegrunnelse, deretter evidensgrunnlaget, og til slutt
// tidspunktene. Uten påstanden øverst er et evidensgrunnlag ikke etterprøvbart
// — leseren har ingenting å prøve funnene mot (ANTIDEP_CONSTITUTION.md §4).
//
// ----------------------------------------------------------------------------
// To spørringer, to tilstandsmaskiner
//
// Påstanden og evidensen ligger i hvert sitt view, og evidensradene bærer ikke
// `statement`, `certainty_level`, `uncertainty_summary` eller `topic_label`.
// Mønsteret er `DrugPage.tsx` sitt: det ytre oppslaget først, det indre inni,
// med hver sin ordlyd. Hver av dem har sine egne fraværstilstander, og de betyr
// ikke det samme.
//
// Ytre oppslag (påstanden):
//
//   laster        vi vet ennå ingenting.
//   tomt          Antidep har ingen publisert påstand med denne identiteten.
//                 Sier ikke at påstanden aldri har eksistert: den kan være
//                 avpublisert, trukket tilbake eller aldri publisert, og
//                 identiteten kan være feilskrevet.
//   flere rader   kontraktsbrudd. `api.published_claims` har én rad per
//                 publisert påstand, så to rader på samme identitet er ikke en
//                 rekkefølge å velge i.
//   feil          spørringen nådde ikke fram.
//
// Indre oppslag (evidensen):
//
//   tomt          også et kontraktsbrudd, og det viktigste på denne siden.
//                 Publiseringsgaten G3 nekter å publisere en revisjon uten minst
//                 én evidenslenke (ANTIDEP_CONSTITUTION.md §4), så en publisert
//                 påstand uten evidens skal ikke kunne finnes. Å vise det som
//                 «ingen evidens registrert» ville gjort et brudd til en rolig
//                 opplysning.
//
// ----------------------------------------------------------------------------
// Rekkefølgen i evidenslisten er ikke en vekting
//
// `fetchPublishedClaimEvidence()` sorterer på lenkens id — stabilt mellom kall,
// uten mening (§74.12 punkt 4). Visningen sorterer ikke om, og grupperer ikke
// støttende og motstridende i egne bolker slik §41 foreslår. To grunner:
//
//   1. En rekkefølge etter `relationship_type` ville satt støttende funn først
//      og gjort presentasjonsrekkefølgen til en vekting av evidensen.
//      Motstridende funn skal stå side om side med støttende
//      (ANTIDEP_CONSTITUTION.md §9, §20).
//   2. En egen bolk for motstridende evidens som står tom, leses som «det finnes
//      ingen motstridende evidens». Det er en påstand om forskningen, ikke om
//      Antideps innhold, og den kan visningen ikke gjøre seg til talsmann for.
//
// Hvert funn bærer i stedet relasjonen sin som tekst, slik at leseren ser den
// uten å måtte utlede den av plasseringen. Skulle en senere PR likevel gruppere,
// er det en designbeslutning som må skrives ned og begrunnes — ikke en sortering
// som sniker seg inn.
//
// Antallet funn skrives heller ikke ut som et tall å veie. «Tre støtter, ett
// motsier» er stemmetelling, og GRADE avviser den eksplisitt: sikkerheten i
// kunnskapsgrunnlaget er en egen vurdering, og den står på påstanden
// (ANTIDEP_CONSTITUTION.md §6).
// ============================================================================

import { useCallback } from 'react'
import { useParams } from 'react-router'
import { ClaimCard } from '../../components/ClaimCard'
import { EvidenceFinding } from '../../components/EvidenceFinding'
import {
  KnowledgeAbsence,
  KnowledgeError,
  KnowledgeLoading,
} from '../../components/KnowledgeNotice'
import { formatTimestampAsDate } from '../../lib/norwegian-format'
import {
  fetchPublishedClaimById,
  fetchPublishedClaimEvidence,
} from '../../lib/published-read-model'
import { useReadModel, type ReadModelState } from '../use-read-model'
import { usePageTitle } from '../use-page-title'
import type { PublishedClaimEvidenceRow, PublishedClaimRow, Uuid } from '../../types/api'

/**
 * Ankeret «Hvorfor sier Antidep dette?» peker på fra påstandskortet.
 *
 * Kortet krever `evidenceHref` — en klinisk relevant påstand skal alltid ha
 * veien videre (produktinvariant 9, §74.13 punkt 4). På denne siden *er* veien
 * videre seksjonen lenger nede, så adressen er et ankernavn og ikke en rute.
 * Alternativet, å gjøre lenken valgfri, ville latt et kort et annet sted miste
 * den ved en forglemmelse.
 */
const EVIDENCE_SECTION_ID = 'evidensgrunnlaget'

const ORDER_NOTE =
  'Dette er hele evidensgrunnlaget bak den revisjonen av påstanden som står publisert: ' +
  'støttende, motstridende, nøytrale og indirekte funn står side om side. Rekkefølgen er ' +
  'den databasen gir, og er verken en rangering etter styrke eller etter hvor godt funnet ' +
  'støtter påstanden. Antall funn er heller ikke et mål på sikkerhet — sikkerheten i ' +
  'kunnskapsgrunnlaget er en egen vurdering, og den står på påstanden over.'

// ----------------------------------------------------------------------------
// Evidensen
// ----------------------------------------------------------------------------

function EvidenceList({ claim }: { readonly claim: PublishedClaimRow }) {
  const query = useCallback(
    (client: Parameters<typeof fetchPublishedClaimEvidence>[0]) =>
      fetchPublishedClaimEvidence(client, claim.claim_id),
    [claim.claim_id],
  )
  const state: ReadModelState<PublishedClaimEvidenceRow> = useReadModel(query)

  switch (state.status) {
    case 'loading':
      return <KnowledgeLoading />
    case 'error':
      return <KnowledgeError message={state.message} />
    case 'empty':
      // Ikke en fraværstilstand: publiseringsgaten G3 gjør den umulig. Vises som
      // det bruddet den er, framfor som en rolig opplysning om at evidens mangler.
      return (
        <div className="knowledge-notice knowledge-notice--error" role="alert">
          <p className="knowledge-notice__lead">
            Antidep viser en publisert påstand uten evidensgrunnlag. Det skal ikke kunne skje: ingen
            påstand kan publiseres uten kobling til minst én identifiserbar kilde. Behandle
            påstanden over som ubekreftet inntil grunnlaget er på plass.
          </p>
        </div>
      )
    case 'ok':
      return (
        <>
          <p className="evidence-list__note">{ORDER_NOTE}</p>
          {state.rows.map((row) => (
            <EvidenceFinding key={row.claim_evidence_link_id} finding={row} headingLevel={4} />
          ))}
        </>
      )
  }
}

// ----------------------------------------------------------------------------
// Tidspunktene
// ----------------------------------------------------------------------------

function timestampText(raw: string | null): string {
  if (raw === null) {
    // «Ukjent» er ikke «ikke gjort», og ikke en fersk dato (§58).
    return 'Ukjent'
  }
  const rendered = formatTimestampAsDate(raw)
  return rendered.kind === 'formatted' ? rendered.text : `${rendered.text} (ikke tolkbar som dato)`
}

/**
 * Tidspunktene, som de fire adskilte begrepene de er
 * (DATABASE_ARCHITECTURE.md §7.3). De besvarer forskjellige spørsmål, og en
 * felles «sist oppdatert» ville slått dem sammen til et svar ingen av dem gir.
 *
 * Bare tidsstempler. Reviewhistorikken er ellers ikke offentlig: ingen
 * aktøridentitet, ingen beslutningstype, ingen begrunnelse (§58). Å utvide det
 * er en governance-endring, ikke en UI-oppgave.
 */
function EvidenceTimeline({ claim }: { readonly claim: PublishedClaimRow }) {
  return (
    <dl className="evidence-timeline">
      <div className="evidence-timeline__item">
        <dt>Sist faglig vurdert</dt>
        <dd>{timestampText(claim.last_reviewed_at)}</dd>
      </div>
      <div className="evidence-timeline__item">
        <dt>Sist evidensvurdert</dt>
        <dd>
          {claim.knowledge_type === 'deterministic_fact' && claim.last_assessed_at === null
            ? 'Ikke aktuelt for et deterministisk faktum'
            : timestampText(claim.last_assessed_at)}
        </dd>
      </div>
      <div className="evidence-timeline__item">
        <dt>Publisert</dt>
        <dd>{timestampText(claim.published_at)}</dd>
      </div>
      <div className="evidence-timeline__item">
        <dt>Revisjon</dt>
        {/* Evidensgrunnlaget hører til revisjonen, ikke til identiteten:
            en ny publisering kan ha et annet grunnlag (§7). */}
        <dd>Revisjon {claim.revision_number} av påstanden</dd>
      </div>
    </dl>
  )
}

// ----------------------------------------------------------------------------
// Siden
// ----------------------------------------------------------------------------

function ClaimEvidenceBody({
  claimId,
  state,
}: {
  readonly claimId: Uuid
  readonly state: ReadModelState<PublishedClaimRow>
}) {
  switch (state.status) {
    case 'loading':
      return <KnowledgeLoading />
    case 'error':
      return <KnowledgeError message={state.message} />
    case 'empty':
      return (
        <KnowledgeAbsence>
          Antidep har ingen publisert påstand med identiteten «{claimId}». Det er et utsagn om
          Antideps innhold: identiteten kan være feilskrevet, og påstanden kan ha vært publisert
          tidligere uten å være det nå.
        </KnowledgeAbsence>
      )
    case 'ok': {
      const [claim, ...rest] = state.rows
      if (rest.length > 0) {
        return (
          <div className="knowledge-notice knowledge-notice--error" role="alert">
            <p className="knowledge-notice__lead">
              Identiteten «{claimId}» gir {state.rows.length} publiserte påstander. Det skal ikke
              kunne skje: én identitet har én publisert revisjon. Antidep viser ingen av dem, fordi
              valget ville sett ut som et svar.
            </p>
          </div>
        )
      }
      return (
        <>
          <section aria-labelledby="paastanden">
            <h3 id="paastanden">Påstanden</h3>
            {/* Samme kort som på legemiddel- og temasiden, med de samme reglene
                om scope, størrelse og sikkerhet. En egen utgave her ville vært
                en parallell presentasjon av samme kliniske sannhet (§65
                «Duplicated truth»). */}
            <ClaimCard claim={claim} evidenceHref={`#${EVIDENCE_SECTION_ID}`} headingLevel={4} />
          </section>

          <section aria-labelledby={EVIDENCE_SECTION_ID}>
            <h3 id={EVIDENCE_SECTION_ID}>Evidensgrunnlaget</h3>
            <EvidenceList claim={claim} />
          </section>

          <section aria-labelledby="tidspunkter">
            <h3 id="tidspunkter">Tidspunkter</h3>
            <EvidenceTimeline claim={claim} />
          </section>
        </>
      )
    }
  }
}

export function ClaimEvidencePage() {
  const { claimId = '' } = useParams()
  const query = useCallback(
    (client: Parameters<typeof fetchPublishedClaimById>[0]) =>
      fetchPublishedClaimById(client, claimId),
    [claimId],
  )
  const state = useReadModel(query)
  const claim = state.status === 'ok' && state.rows.length === 1 ? state.rows[0] : null

  // Tittelen navngir hva evidensen gjelder, ikke selve formuleringen: en
  // påstandssetning i faneraden blir avkortet og leses da som noe annet enn den
  // er. Uten et treff står den nøytralt — identiteten fra URL-en som tittel
  // ville gjort en adresse leseren skrev, til noe Antidep ser ut til å hevde.
  usePageTitle(claim === null ? 'Evidensgrunnlag' : `${claim.topic_label} – ${claim.drug_name}`)

  return (
    <>
      <p className="page-kicker">Evidensgrunnlag</p>
      <h2>Hvorfor sier Antidep dette?</h2>
      <ClaimEvidenceBody claimId={claimId} state={state} />
    </>
  )
}
