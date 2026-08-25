// ============================================================================
// Legemiddelsiden — `/drugs/sertralin`
//
// Adressen står ordrett i MVP_IMPLEMENTATION_PLAN.md §30. Siden er en
// projeksjon av publiserte påstander, ikke et dokument
// (PRODUCT_INFORMATION_ARCHITECTURE.md §9), og den komponeres av nøyaktig de
// samme påstandsobjektene temasiden bruker (invariant 3).
//
// ----------------------------------------------------------------------------
// Oppslaget skjer i to trinn, og hvert trinn har sine egne fraværstilstander
//
// `api` eksponerer ingen slug, så virkestoffet finnes ved å avlede sluggen av
// hvert kanoniske navn i den publiserte indeksen (`src/lib/slug.ts`). Trinn to
// henter påstandene med `drug_id`, som er den faktiske identiteten.
//
// Fire tilstander må holdes fra hverandre, og tre av dem ville sett like ut som
// en tom skjerm:
//
//   projeksjonen er tom     Antidep har ikke publisert noe ennå, om noe som
//                           helst. Sier ingenting om dette virkestoffet.
//   sluggen traff ingen     Antidep har ikke publisert om et virkestoff med
//                           denne adressen. Sier ikke at virkestoffet ikke
//                           finnes, og slett ikke at det er uten risiko.
//   sluggen traff flere     Adressen er tvetydig. Å vise den første ville vært
//                           et gyldig utseende svar om feil legemiddel.
//   virkestoffet uten
//   publiserte påstander    Kan ikke skje via `published_drugs`, som per
//                           definisjon bare inneholder virkestoff med minst én
//                           — men leses her fra en database vi ikke selv har
//                           migrert, og håndteres derfor framfor å antas bort.
//
// ----------------------------------------------------------------------------
// Hva som ikke vises, og hvorfor
//
// Handelsnavn, klasse, norske legemiddelformer og styrker (§10) finnes ikke i
// datamodellen ennå; de kommer med DrugProduct-fundamentet i migrasjon 009 og
// slice 4 (§26, §32). De er utelatt framfor gjettet på.
//
// Katalogstatusen (`published_drugs.status`) vises heller ikke. Kolonnen
// beskriver Antideps egen forvaltning av virkestoffet, ikke markedsstatus i
// Norge — det står eksplisitt i kommentaren på `catalog.drug_status` — og
// «aktiv» ved siden av et virkestoffnavn ville blitt lest som det siste. §58
// holder dessuten workflow-status utenfor klinikerflaten. Registrert som gjeld
// i §74.7.
// ============================================================================

import { useCallback } from 'react'
import { useParams } from 'react-router'
import { ClaimGroups } from '../ClaimGroups'
import {
  KnowledgeAbsence,
  KnowledgeError,
  KnowledgeLoading,
} from '../../components/KnowledgeNotice'
import { fetchPublishedClaimsForDrug, fetchPublishedDrugs } from '../../lib/published-read-model'
import { resolveSlug, type SlugResolution, type UnresolvedReadModelState } from '../slug-resolution'
import { useReadModel, type ReadModelState } from '../use-read-model'
import { usePageTitle } from '../use-page-title'
import type { PublishedClaimRow, PublishedDrugRow } from '../../types/api'

/**
 * ATC-kodene. `null` og et tomt sett betyr det samme her: ingen kode er
 * registrert i Antidep. Det er ikke det samme som at virkestoffet mangler en,
 * og formuleringen sier hvem som mangler den.
 */
function atcText(codes: readonly string[] | null): string {
  if (codes === null || codes.length === 0) {
    return 'Ingen ATC-kode er registrert i Antidep'
  }
  return codes.join(', ')
}

function DrugClaims({ drug }: { readonly drug: PublishedDrugRow }) {
  const query = useCallback(
    (client: Parameters<typeof fetchPublishedClaimsForDrug>[0]) =>
      fetchPublishedClaimsForDrug(client, drug.drug_id),
    [drug.drug_id],
  )
  const state: ReadModelState<PublishedClaimRow> = useReadModel(query)

  switch (state.status) {
    case 'loading':
      return <KnowledgeLoading />
    case 'error':
      return <KnowledgeError message={state.message} />
    case 'empty':
      return (
        <KnowledgeAbsence>
          Antidep har ingen publiserte påstander om {drug.canonical_name}.
        </KnowledgeAbsence>
      )
    case 'ok':
      return <ClaimGroups axis="topic" claims={state.rows} />
  }
}

/** Ventetilstandene for indeksoppslaget, med ordlyden legemiddelsiden trenger. */
function DrugIndexPending({
  state,
}: {
  readonly state: UnresolvedReadModelState<PublishedDrugRow>
}) {
  switch (state.status) {
    case 'loading':
      return <KnowledgeLoading />
    case 'error':
      return <KnowledgeError message={state.message} />
    case 'empty':
      return (
        <KnowledgeAbsence>
          Antidep har ingen publiserte påstander ennå — om noe virkestoff. Denne adressen sier
          derfor ingenting om virkestoffet den navngir.
        </KnowledgeAbsence>
      )
  }
}

/**
 * Innholdet under overskriften, som én uttømmende forgrening.
 *
 * Samlet i én `switch` med hensikt: tre uavhengige betingelser ville latt et
 * nytt oppslagsutfall gli gjennom som en tom skjerm, og en tom skjerm er
 * nettopp den feillesningen §17 forbyr.
 */
function DrugBody({
  resolution,
  slug,
}: {
  readonly resolution: DrugResolution
  readonly slug: string
}) {
  if (resolution.kind === 'unresolved') {
    return <DrugIndexPending state={resolution.state} />
  }

  const { lookup } = resolution
  switch (lookup.kind) {
    case 'not_found':
      return (
        <KnowledgeAbsence>
          Antidep har ingen publiserte påstander om et virkestoff med adressen «{slug}». Det er et
          utsagn om Antideps innhold, ikke om virkestoffet: adressen kan være feilskrevet, og
          virkestoffet kan finnes uten at noe er publisert om det her.
        </KnowledgeAbsence>
      )
    case 'ambiguous':
      return (
        <div className="knowledge-notice knowledge-notice--error" role="alert">
          <p className="knowledge-notice__lead">
            Adressen «{slug}» peker på flere virkestoff:{' '}
            {lookup.items.map((item) => item.canonical_name).join(', ')}. Antidep viser ikke ett av
            dem framfor et annet, fordi valget ville sett ut som et svar.
          </p>
        </div>
      )
    case 'found':
      return (
        <>
          <dl className="drug-facts">
            <div className="drug-facts__item">
              <dt>ATC</dt>
              <dd>{atcText(lookup.item.atc_codes)}</dd>
            </div>
          </dl>
          <DrugClaims drug={lookup.item} />
        </>
      )
  }
}

type DrugResolution = SlugResolution<PublishedDrugRow, PublishedDrugRow>

export function DrugPage() {
  const { drugSlug = '' } = useParams()
  const state = useReadModel(fetchPublishedDrugs)
  const resolution: DrugResolution = resolveSlug(
    state,
    drugSlug,
    (rows) => rows,
    (drug) => drug.canonical_name,
  )
  const name =
    resolution.kind === 'resolved' && resolution.lookup.kind === 'found'
      ? resolution.lookup.item.canonical_name
      : null

  usePageTitle(name ?? 'Virkestoff')

  return (
    <>
      {/* Objekttypen skrives ut når adressen traff (§45). Overskriften er det
          kanoniske navnet når det finnes, og ellers et nøytralt ord: å sette
          sluggen fra URL-en som overskrift ville gjort en adresse leseren
          skrev, til noe Antidep ser ut til å hevde. */}
      {name === null ? null : <p className="page-kicker">Virkestoff</p>}
      <h2 className={name === null ? undefined : 'drug-name'}>{name ?? 'Virkestoff'}</h2>
      <DrugBody resolution={resolution} slug={drugSlug} />
    </>
  )
}
