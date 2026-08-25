// ============================================================================
// Testrigg for klinikerflaten
//
// Rendrer skallet på en gitt adresse med en injisert klient, slik at en test
// kan stå på `/drugs/…` uten nettleserhistorikk og uten miljøvariabler.
//
// Den falske klienten svarer på nivået `published-read-model.ts` faktisk
// spør på — `from(view).select().eq().order()` — framfor å stubbe
// lesefunksjonene. Da er det den virkelige spørringen som kjøres, og et filter
// som forsvinner fra en lesefunksjon blir synlig i en sidetest.
//
// ----------------------------------------------------------------------------
// Testdataene er syntetiske, og det er ikke en formalitet
//
// Ingenting her er innhold. Virkelige påstander kommer fra databasen gjennom
// review- og publiseringsgatene (ANTIDEP_CONSTITUTION.md §12), aldri fra en
// fikstur. Virkestoffnavnene i påstandsfiksturene er derfor oppdiktede, og
// formuleringene er merket som testpåstander. De virkelige pilotnavnene brukes
// bare der testen handler om adressen og ikke om innhold.
// ============================================================================

import { render } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { AppLayout } from './App'
import { AntidepClientProvider, type AntidepClientAvailability } from './antidep-client'
import type { AntidepClient } from '../lib/supabase'
import type { PublishedClaimRow, PublishedDrugRow } from '../types/api'

/** Hva ett view svarer: rader, en feil, eller aldri (for ventetilstanden). */
export type FakeOutcome<Row> =
  readonly Row[] | { readonly error: string } | { readonly pending: true }

export interface FakeApi {
  readonly published_drugs?: FakeOutcome<PublishedDrugRow>
  readonly published_claims?: FakeOutcome<PublishedClaimRow>
}

interface RecordedQuery {
  readonly view: string
  readonly filters: [string, unknown][]
  readonly orders: [string, boolean][]
}

function outcomeFor(api: FakeApi, view: string): FakeOutcome<Record<string, unknown>> {
  const outcome = (api as Record<string, FakeOutcome<Record<string, unknown>> | undefined>)[view]
  return outcome ?? []
}

/**
 * En klient som oppfører seg som PostgREST på de tre tingene lesemodellen
 * bruker: kolonnevalg, `eq`-filtre og sortering. Filtrene anvendes faktisk, så
 * en side som slutter å filtrere på `drug_id` vil vise andre virkestoffs
 * påstander i testen — som i produksjon.
 */
export function fakeClient(api: FakeApi = {}): {
  client: AntidepClient
  queries: RecordedQuery[]
} {
  const queries: RecordedQuery[] = []

  const client = {
    from(view: string) {
      const recorded: RecordedQuery = { view, filters: [], orders: [] }
      const builder = {
        select() {
          queries.push(recorded)
          return builder
        },
        eq(column: string, value: unknown) {
          recorded.filters.push([column, value])
          return builder
        },
        order(column: string, options: { ascending: boolean }) {
          recorded.orders.push([column, options.ascending])
          return builder
        },
        then<Result>(resolve: (value: unknown) => Result) {
          const outcome = outcomeFor(api, view)
          if ('pending' in outcome) {
            // Aldri: ventetilstanden er en tilstand som skal kunne observeres.
            return new Promise<Result>(() => undefined)
          }
          if ('error' in outcome) {
            return Promise.resolve({ data: null, error: { message: outcome.error } }).then(resolve)
          }
          const rows = outcome.filter((row) =>
            recorded.filters.every(([column, value]) => row[column] === value),
          )
          return Promise.resolve({ data: rows, error: null }).then(resolve)
        },
      }
      return builder
    },
  }

  return { client: client as unknown as AntidepClient, queries }
}

export interface RenderRouteOptions {
  readonly api?: FakeApi
  /** Overstyrer klienttilstanden helt, for å teste manglende konfigurasjon. */
  readonly availability?: AntidepClientAvailability
}

/** Rendrer hele skallet på én adresse. */
export function renderRoute(path: string, options: RenderRouteOptions = {}) {
  const fake = fakeClient(options.api)
  const availability: AntidepClientAvailability = options.availability ?? {
    status: 'ready',
    client: fake.client,
  }
  const result = render(
    <AntidepClientProvider value={availability}>
      <MemoryRouter initialEntries={[path]}>
        <AppLayout />
      </MemoryRouter>
    </AntidepClientProvider>,
  )
  return { ...result, queries: fake.queries }
}

const DRUG_A = '11111111-1111-4111-8111-111111111111'
const DRUG_B = '11111111-1111-4111-8111-222222222222'
const TOPIC_WEIGHT = '44444444-4444-4444-8444-111111111111'

export const TEST_DRUG_IDS = { a: DRUG_A, b: DRUG_B } as const
export const TEST_TOPIC_IDS = { weight: TOPIC_WEIGHT } as const

export function drugRow(overrides: Partial<PublishedDrugRow> = {}): PublishedDrugRow {
  return {
    drug_id: DRUG_A,
    canonical_name: 'virkestoff a',
    status: 'active',
    atc_codes: ['N06AB99'],
    published_claim_count: 1,
    ...overrides,
  }
}

export function claimRow(overrides: Partial<PublishedClaimRow> = {}): PublishedClaimRow {
  return {
    claim_id: '22222222-2222-4222-8222-111111111111',
    claim_revision_id: '33333333-3333-4333-8333-111111111111',
    revision_number: 1,
    knowledge_type: 'evidence_synthesis',

    drug_id: DRUG_A,
    drug_name: 'virkestoff a',
    topic_concept_id: TOPIC_WEIGHT,
    topic_label: 'vektendring',

    statement: 'Testpåstand: Virkestoff A er assosiert med større vektøkning enn placebo.',
    scope: 'Voksne, korttidsbehandling ved depresjon',

    population_id: null,
    population_label: null,
    timeframe_min: null,
    timeframe_max: null,
    comparator_kind: 'placebo',
    comparator_drug_id: null,
    comparator_drug_name: null,

    direction: 'increase',
    magnitude_measure: null,
    magnitude_value: null,
    magnitude_unit: null,

    qualifiers: null,
    uncertainty_summary: 'Få studier, og kort oppfølgingstid.',

    certainty_framework: 'grade',
    certainty_level: 'moderate',
    certainty_rationale: null,
    evidence_gap: null,
    last_assessed_at: '2026-08-20T10:00:00Z',

    withdrawn_evidence_count: 0,

    content_hash: 'sha256-v1:0000',
    revision_created_at: '2026-08-19T10:00:00Z',
    published_at: '2026-08-20T12:00:00Z',
    last_reviewed_at: '2026-08-21T09:15:00Z',
    ...overrides,
  }
}
