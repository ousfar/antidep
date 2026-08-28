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
import type {
  MyActorRow,
  MyRoleRow,
  PublishedClaimEvidenceRow,
  PublishedClaimRow,
  PublishedDrugRow,
} from '../types/api'

/** Hva ett view svarer: rader, en feil, eller aldri (for ventetilstanden). */
export type FakeOutcome<Row> =
  readonly Row[] | { readonly error: string } | { readonly pending: true }

export interface FakeApi {
  readonly published_drugs?: FakeOutcome<PublishedDrugRow>
  readonly published_claims?: FakeOutcome<PublishedClaimRow>
  readonly published_claim_evidence?: FakeOutcome<PublishedClaimEvidenceRow>
  readonly my_actor?: FakeOutcome<MyActorRow>
  readonly my_roles?: FakeOutcome<MyRoleRow>
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

// ----------------------------------------------------------------------------
// Fake `auth`, for Min tilgang (§74.22)
//
// Nok til å teste det klientkoden faktisk gjør mot `client.auth`: lese
// sesjonen ved montering, abonnere på endringer, logge inn og logge ut. Faken
// validerer *ikke* e-post/passord mot noe — det er Supabases jobb på ekte, ikke
// vår klientkodes — så et vellykket forsøk er standard, og
// `FakeAuthOptions.signInError` gjør forsøket avvist når en test trenger det.
// ----------------------------------------------------------------------------

interface FakeSession {
  readonly user: { readonly id: string }
}

type FakeAuthListener = (event: string, session: FakeSession | null) => void

export interface FakeAuthOptions {
  /** Sesjonen når rendringen starter. `null` (standard) betyr ikke innlogget. */
  readonly initialUserId?: string | null
  /**
   * Gjør et innloggingsforsøk avvist med denne meldingen, uansett hva som er
   * skrevet inn. Utelatt (standard) betyr at forsøket lykkes.
   */
  readonly signInError?: string
  /** Identiteten et vellykket innloggingsforsøk gir. */
  readonly signInUserId?: string
}

export const TEST_USER_IDS = {
  a: '99999999-9999-4999-8999-111111111111',
  b: '99999999-9999-4999-8999-222222222222',
} as const

/**
 * Ett registrert `signOut()`-kall, slik det faktisk ble gjort mot faken.
 *
 * Finnes for å teste `scope` eksplisitt: supabase-js sin standard er
 * `'global'` — logger kalleren ut av *alle* enheter — og en «Logg ut»-knapp
 * skal ikke ha den sideeffekten uten at det er et bevisst produktvalg. Uten en
 * assertion på det faktiske kallet kunne `AccessPage.tsx` sluttet å sende
 * `scope: 'local'` uten at noen test merket det.
 */
export interface FakeSignOutCall {
  readonly scope?: string
}

function fakeAuth(options: FakeAuthOptions, signOutCalls: FakeSignOutCall[]) {
  let session: FakeSession | null =
    options.initialUserId == null ? null : { user: { id: options.initialUserId } }
  const listeners = new Set<FakeAuthListener>()

  function emit(event: string) {
    for (const listener of listeners) {
      listener(event, session)
    }
  }

  return {
    getSession: () => Promise.resolve({ data: { session } }),
    onAuthStateChange: (callback: FakeAuthListener) => {
      listeners.add(callback)
      return { data: { subscription: { unsubscribe: () => listeners.delete(callback) } } }
    },
    // Ingen parameter: faken validerer aldri e-post/passord mot noe — det er
    // Supabases jobb på ekte, ikke klientkodens. Se doc-kommentaren over.
    signInWithPassword: () => {
      if (options.signInError !== undefined) {
        return Promise.resolve({
          data: { session: null, user: null },
          error: { message: options.signInError },
        })
      }
      session = { user: { id: options.signInUserId ?? TEST_USER_IDS.a } }
      emit('SIGNED_IN')
      return Promise.resolve({ data: { session, user: session.user }, error: null })
    },
    signOut: (signOutOptions?: FakeSignOutCall) => {
      signOutCalls.push(signOutOptions ?? {})
      session = null
      emit('SIGNED_OUT')
      return Promise.resolve({ error: null })
    },
  }
}

/**
 * En klient som oppfører seg som PostgREST på de tre tingene lesemodellen
 * bruker: kolonnevalg, `eq`-filtre og sortering. Filtrene anvendes faktisk, så
 * en side som slutter å filtrere på `drug_id` vil vise andre virkestoffs
 * påstander i testen — som i produksjon.
 */
export function fakeClient(
  api: FakeApi = {},
  authOptions: FakeAuthOptions = {},
): {
  client: AntidepClient
  queries: RecordedQuery[]
  signOutCalls: FakeSignOutCall[]
} {
  const queries: RecordedQuery[] = []
  const signOutCalls: FakeSignOutCall[] = []

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
    auth: fakeAuth(authOptions, signOutCalls),
  }

  return { client: client as unknown as AntidepClient, queries, signOutCalls }
}

export interface RenderRouteOptions {
  readonly api?: FakeApi
  readonly auth?: FakeAuthOptions
  /** Overstyrer klienttilstanden helt, for å teste manglende konfigurasjon. */
  readonly availability?: AntidepClientAvailability
}

/** Rendrer hele skallet på én adresse. */
export function renderRoute(path: string, options: RenderRouteOptions = {}) {
  const fake = fakeClient(options.api, options.auth)
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
  return { ...result, queries: fake.queries, signOutCalls: fake.signOutCalls }
}

const DRUG_A = '11111111-1111-4111-8111-111111111111'
const DRUG_B = '11111111-1111-4111-8111-222222222222'
const TOPIC_WEIGHT = '44444444-4444-4444-8444-111111111111'
const CLAIM_A = '22222222-2222-4222-8222-111111111111'
const CLAIM_B = '22222222-2222-4222-8222-222222222222'
const CLAIM_C = '22222222-2222-4222-8222-333333333333'
const REVISION_A = '33333333-3333-4333-8333-111111111111'
const SOURCE_A = '88888888-8888-4888-8888-111111111111'

export const TEST_DRUG_IDS = { a: DRUG_A, b: DRUG_B } as const
export const TEST_TOPIC_IDS = { weight: TOPIC_WEIGHT } as const
export const TEST_CLAIM_IDS = { a: CLAIM_A, b: CLAIM_B, c: CLAIM_C } as const
export const TEST_REVISION_IDS = { a: REVISION_A } as const
export const TEST_SOURCE_IDS = { a: SOURCE_A } as const

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
    claim_id: CLAIM_A,
    claim_revision_id: REVISION_A,
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

/**
 * Én evidenslenke, i den formen `api.published_claim_evidence` gir den.
 *
 * Grunnformen er den enkleste raden som er gyldig etter migrasjon 003: et
 * rapportert funn med et tolkbart estimat, et konfidensintervall og en kilde
 * uten avvikende status. Testene overstyrer nøyaktig det de handler om, slik at
 * en rad som mangler noe, mangler det med hensikt.
 */
export function evidenceRow(
  overrides: Partial<PublishedClaimEvidenceRow> = {},
): PublishedClaimEvidenceRow {
  return {
    claim_id: CLAIM_A,
    claim_revision_id: REVISION_A,
    claim_evidence_link_id: '55555555-5555-4555-8555-111111111111',

    relationship_type: 'supports',
    directness: 'direct',
    relevance_note: 'Testnotat: funnet måler samme endepunkt i samme populasjon.',

    evidence_item_id: '66666666-6666-4666-8666-111111111111',
    study_design: 'randomized_controlled_trial',

    population_id: '77777777-7777-4777-8777-111111111111',
    population_label: 'voksne med depresjon',
    population_detail: 'Voksne 18–65 år i poliklinisk behandling.',
    population_availability: 'reported_value',
    sample_size: 240,
    sample_size_availability: 'reported_value',

    intervention_drug_id: DRUG_A,
    intervention_drug_name: 'virkestoff a',
    intervention_detail: null,
    comparator_kind: 'placebo',
    comparator_drug_id: null,
    comparator_drug_name: null,
    comparator_detail: null,

    outcome_concept_id: TOPIC_WEIGHT,
    outcome_label: 'vektendring',
    outcome_detail: 'Endring i kroppsvekt fra baseline.',
    timepoint_min: '56 days',
    timepoint_max: '56 days',
    timepoint_availability: 'reported_value',

    reported_direction: 'increase',
    effect_measure: 'mean_difference',
    estimate: 1.7,
    estimate_unit: 'kg',
    estimate_availability: 'reported_value',
    ci_lower: 0.9,
    ci_upper: 2.5,
    ci_level_percent: 95,
    confidence_interval_availability: 'reported_value',

    limitations_text: null,
    source_locator: 'Tabell 2, side 114',

    extraction_withdrawn: false,
    extraction_withdrawn_at: null,
    extraction_withdrawal_rationale: null,

    source_version_id: null,
    source_version_retrieved_at: null,
    source_version_retrieved_from: null,
    source_version_external_version: null,
    source_version_content_hash: null,

    source_id: SOURCE_A,
    source_type: 'journal_article',
    source_title: 'Testkilde A: vektendring ved åtte uker',
    source_authors_or_issuer: 'Testforfatter m.fl.',
    source_publisher_or_journal: 'Testtidsskrift',
    source_publication_date: '2019-03-01',
    source_publication_date_precision: 'month',
    source_status: 'active',
    source_status_note: null,
    source_dois: ['10.0000/test.a'],
    source_pmids: null,
    ...overrides,
  }
}

// ----------------------------------------------------------------------------
// Kallerens eget (migrasjon 007b), for Min tilgang (§74.22)
// ----------------------------------------------------------------------------

const ACTOR_A = '00000000-0000-4000-8000-111111111111'

export const TEST_ACTOR_IDS = { a: ACTOR_A } as const

/** Kallerens egen aktørrad, slik `api.my_actor` gir den. */
export function myActorRow(overrides: Partial<MyActorRow> = {}): MyActorRow {
  return {
    actor_id: ACTOR_A,
    actor_key: 'human:testredaktor',
    display_name: 'Test Redaktør',
    retired_at: null,
    ...overrides,
  }
}

/** Én rolletildeling som gjelder nå, slik `api.my_roles` gir den. */
export function myRoleRow(overrides: Partial<MyRoleRow> = {}): MyRoleRow {
  return {
    role_code: 'reviewer',
    scope_id: null,
    scope_type: null,
    valid_from: '2026-08-20T10:00:00Z',
    valid_to: null,
    ...overrides,
  }
}
