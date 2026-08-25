// ============================================================================
// Temasiden — `/topics/vektendring`
//
// Den kliniske problemstillingen er en egen inngang
// (PRODUCT_INFORMATION_ARCHITECTURE.md §26): klinikeren starter ofte med «jeg
// vil unngå vektøkning» og ikke med et bestemt virkestoff. Siden viser de
// publiserte påstandene om ett klinisk begrep, gruppert på virkestoff, og
// bruker nøyaktig de samme påstandsobjektene som legemiddelsiden (invariant 3).
//
// §28 er eksplisitt på hva siden ikke er: den skal ikke bli en skjult
// anbefalingsmotor. Den kaller derfor ikke noe virkestoff «best», rangerer ikke,
// og sier selv at rekkefølgen er alfabetisk og at påstandene ikke er en
// sammenligning (`ClaimGroups`).
//
// ----------------------------------------------------------------------------
// Hvorfor hele det publiserte settet hentes
//
// `api` har ingen temaprojeksjon, og en slug kan ikke inverteres til en
// etikett. Det eneste stedet `topic_label` finnes, er på påstandsradene, så
// settet hentes i sin helhet og filtreres her. Det holder mens det publiserte
// settet er lite, og er registrert som gjeld i MVP_IMPLEMENTATION_PLAN.md §74.7.
//
// Kandidatene for oppslaget er de *distinkte* kliniske begrepene, ikke radene.
// Et oppslag rett i radene ville meldt «tvetydig» hver gang et tema hadde mer
// enn én påstand — en vaktpost som slår ut på det normale, er en vaktpost som
// blir slått av.
// ============================================================================

import { useParams } from 'react-router'
import { ClaimGroups } from '../ClaimGroups'
import {
  KnowledgeAbsence,
  KnowledgeError,
  KnowledgeLoading,
} from '../../components/KnowledgeNotice'
import { fetchPublishedClaims } from '../../lib/published-read-model'
import { resolveSlug, type SlugResolution, type UnresolvedReadModelState } from '../slug-resolution'
import { useReadModel } from '../use-read-model'
import { usePageTitle } from '../use-page-title'
import type { PublishedClaimRow, Uuid } from '../../types/api'

/** Ett klinisk begrep, slik påstandsradene navngir det. */
interface Topic {
  readonly id: Uuid
  readonly label: string
}

/**
 * De distinkte kliniske begrepene i settet, identifisert på `uuid`.
 *
 * Distinkt på identitet og ikke på etikett: to begreper med samme etikett er
 * fortsatt to begreper, og å slå dem sammen her ville skjult at adressen er
 * tvetydig.
 */
function distinctTopics(claims: readonly PublishedClaimRow[]): Topic[] {
  const topics = new Map<Uuid, Topic>()
  for (const claim of claims) {
    if (!topics.has(claim.topic_concept_id)) {
      topics.set(claim.topic_concept_id, { id: claim.topic_concept_id, label: claim.topic_label })
    }
  }
  return [...topics.values()]
}

function TopicIndexPending({
  state,
}: {
  readonly state: UnresolvedReadModelState<PublishedClaimRow>
}) {
  switch (state.status) {
    case 'loading':
      return <KnowledgeLoading />
    case 'error':
      return <KnowledgeError message={state.message} />
    case 'empty':
      return (
        <KnowledgeAbsence>
          Antidep har ingen publiserte påstander ennå — om noe tema. Denne adressen sier derfor
          ingenting om temaet den navngir.
        </KnowledgeAbsence>
      )
  }
}

type TopicResolution = SlugResolution<PublishedClaimRow, Topic>

function TopicBody({
  resolution,
  slug,
}: {
  readonly resolution: TopicResolution
  readonly slug: string
}) {
  if (resolution.kind === 'unresolved') {
    return <TopicIndexPending state={resolution.state} />
  }

  const { lookup } = resolution
  switch (lookup.kind) {
    case 'not_found':
      return (
        <KnowledgeAbsence>
          Antidep har ingen publiserte påstander om et klinisk tema med adressen «{slug}». Det er et
          utsagn om Antideps innhold, ikke om temaet: adressen kan være feilskrevet, og temaet kan
          være klinisk viktig uten at noe er publisert om det her.
        </KnowledgeAbsence>
      )
    case 'ambiguous':
      return (
        <div className="knowledge-notice knowledge-notice--error" role="alert">
          <p className="knowledge-notice__lead">
            Adressen «{slug}» peker på flere kliniske begreper:{' '}
            {lookup.items.map((item) => item.label).join(', ')}. Antidep viser ikke ett av dem
            framfor et annet, fordi valget ville sett ut som et svar.
          </p>
        </div>
      )
    case 'found': {
      // Minst én rad, per konstruksjon: kandidatene kommer fra radene selv, så
      // et begrep som ble funnet, ble sett på en rad. En vakt mot tomhet her
      // ville vært en gren ingen test kan nå.
      const topicId = lookup.item.id
      return (
        <ClaimGroups
          axis="drug"
          claims={resolution.rows.filter((claim) => claim.topic_concept_id === topicId)}
        />
      )
    }
  }
}

export function TopicPage() {
  const { topicSlug = '' } = useParams()
  const state = useReadModel(fetchPublishedClaims)
  const resolution: TopicResolution = resolveSlug(
    state,
    topicSlug,
    distinctTopics,
    (topic) => topic.label,
  )
  const label =
    resolution.kind === 'resolved' && resolution.lookup.kind === 'found'
      ? resolution.lookup.item.label
      : null

  usePageTitle(label ?? 'Klinisk tema')

  return (
    <>
      {/* Objekttypen skrives ut når adressen traff, slik at «vektendring» ikke
          kan forveksles med et virkestoff (§45). Når den ikke traff, sier
          overskriften det samme, og en gjentakelse ville vært støy. */}
      {label === null ? null : <p className="page-kicker">Klinisk tema</p>}
      <h2 className={label === null ? undefined : 'topic-name'}>{label ?? 'Klinisk tema'}</h2>
      <TopicBody resolution={resolution} slug={topicSlug} />
    </>
  )
}
