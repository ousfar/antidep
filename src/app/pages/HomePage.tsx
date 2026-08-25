// ============================================================================
// Forsiden — hvilke virkestoff Antidep har publisert kunnskap om
//
// §66 A i PRODUCT_INFORMATION_ARCHITECTURE.md tegner flyten forside → søk →
// legemiddelside. Søket er slice 6 (MVP_IMPLEMENTATION_PLAN.md §34), så
// forsiden er inntil videre en indeks: den listen søket senere blir en raskere
// vei inn i.
//
// Indeksen er `api.published_drugs`, altså virkestoff med minst én publisert
// påstand. Den er ikke en katalog over antidepressiver, og sier ikke noe om hva
// som finnes — bare hva Antidep har publisert. Det skillet må stå, ellers blir
// en kort liste lest som et kort felt.
// ============================================================================

import { Link } from 'react-router'
import {
  KnowledgeAbsence,
  KnowledgeError,
  KnowledgeLoading,
} from '../../components/KnowledgeNotice'
import { fetchPublishedDrugs } from '../../lib/published-read-model'
import { compareNorwegian, formatNumber } from '../../lib/norwegian-format'
import { drugPath } from '../routes'
import { useReadModel, type ReadModelState } from '../use-read-model'
import { usePageTitle } from '../use-page-title'
import type { PublishedDrugRow } from '../../types/api'

/**
 * Antall publiserte påstander, som tekst.
 *
 * Et utolkbart antall sies høyt framfor å bli utelatt. En rad uten tall ville
 * sett ut som en rad uten påstander, og det er en annen ting.
 */
function claimCountText(count: number): string {
  if (!Number.isInteger(count) || count < 0) {
    return `Antallet publiserte påstander er ikke tolkbart (verdi: ${String(count)})`
  }
  if (count === 1) {
    return '1 publisert påstand'
  }
  return `${formatNumber(count).text} publiserte påstander`
}

function DrugIndex({ drugs }: { readonly drugs: readonly PublishedDrugRow[] }) {
  // Sorteres her, ikke bare i spørringen: siden *sier* at rekkefølgen er
  // alfabetisk, og `order by` i PostgreSQL bruker databasens kollasjon, som
  // ikke er norsk. En påstand om rekkefølge må visningen selv kunne innfri.
  const sorted = [...drugs].sort((a, b) => compareNorwegian(a.canonical_name, b.canonical_name))

  return (
    <ul className="drug-index">
      {sorted.map((drug) => (
        <li className="drug-index__item" key={drug.drug_id}>
          <Link className="drug-index__link" to={drugPath(drug.canonical_name)}>
            {drug.canonical_name}
          </Link>
          <span className="drug-index__count">{claimCountText(drug.published_claim_count)}</span>
        </li>
      ))}
    </ul>
  )
}

function DrugIndexState({ state }: { readonly state: ReadModelState<PublishedDrugRow> }) {
  switch (state.status) {
    case 'loading':
      return <KnowledgeLoading />
    case 'error':
      return <KnowledgeError message={state.message} />
    case 'empty':
      return (
        <KnowledgeAbsence>
          Antidep har ingen publiserte påstander ennå. Kunnskapsbasen bygges opp, og en påstand
          publiseres først når en kvalifisert redaktør har godkjent den.
        </KnowledgeAbsence>
      )
    case 'ok':
      return <DrugIndex drugs={state.rows} />
  }
}

export function HomePage() {
  usePageTitle('Publisert kunnskap')
  const state = useReadModel(fetchPublishedDrugs)

  return (
    <>
      <h2>Publisert kunnskap</h2>
      <p className="page-lead">
        Virkestoffene Antidep har publisert minst én faglig godkjent påstand om. Listen er sortert
        alfabetisk og er ingen rangering. Den er ikke en oversikt over antidepressiver som finnes,
        bare over det Antidep har publisert.
      </p>
      <DrugIndexState state={state} />
    </>
  )
}
