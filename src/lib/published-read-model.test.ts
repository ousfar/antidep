import { describe, expect, it } from 'vitest'
import {
  fetchPublishedClaimById,
  fetchPublishedClaimEvidence,
  fetchPublishedClaims,
  fetchPublishedClaimsForDrug,
  fetchPublishedDrugs,
} from './published-read-model'
import type { AntidepClient } from './supabase'
import type { PublishedClaimEvidenceRow, PublishedClaimRow, PublishedDrugRow } from '../types/api'

// ----------------------------------------------------------------------------
// En falsk klient som registrerer hva som faktisk ble spurt om
// ----------------------------------------------------------------------------

interface RecordedQuery {
  view: string
  columns: string
  filters: [string, unknown][]
  orders: [string, { ascending: boolean }][]
}

function fakeClient(outcome: { data: unknown[] | null; error: { message: string } | null }) {
  const queries: RecordedQuery[] = []
  const client = {
    from(view: string) {
      const recorded: RecordedQuery = { view, columns: '', filters: [], orders: [] }
      const builder = {
        select(columns: string) {
          recorded.columns = columns
          queries.push(recorded)
          return builder
        },
        eq(column: string, value: unknown) {
          recorded.filters.push([column, value])
          return builder
        },
        order(column: string, options: { ascending: boolean }) {
          recorded.orders.push([column, options])
          return builder
        },
        then<Result>(resolve: (value: typeof outcome) => Result) {
          return Promise.resolve(outcome).then(resolve)
        },
      }
      return builder
    },
  }
  return { client: client as unknown as AntidepClient, queries }
}

const DRUG_ID = '11111111-1111-4111-8111-111111111111'
const CLAIM_ID = '22222222-2222-4222-8222-222222222222'

describe('tomt er en egen tilstand', () => {
  it('en tom projeksjon er empty, ikke ok med null rader', () => {
    // Viewene svarer [] til noe faktisk er publisert. Skal «ingen data» aldri
    // kunne se ut som «ingen risiko», må tomheten være umulig å overse.
    return expect(
      fetchPublishedDrugs(fakeClient({ data: [], error: null }).client),
    ).resolves.toEqual({ status: 'empty' })
  })

  it('data null uten feil er også empty', () => {
    return expect(
      fetchPublishedDrugs(fakeClient({ data: null, error: null }).client),
    ).resolves.toEqual({ status: 'empty' })
  })

  it('en feil er en feil, ikke fravær av kunnskap', () => {
    return expect(
      fetchPublishedDrugs(fakeClient({ data: null, error: { message: 'nettverksfeil' } }).client),
    ).resolves.toEqual({ status: 'error', message: 'nettverksfeil' })
  })

  it('en feil vinner over rader som måtte følge med', () => {
    // PostgREST kan svare med både data og error ved delvise feil. Å vise
    // radene ville presentert et ufullstendig sett som komplett.
    const { client } = fakeClient({ data: [{ drug_id: DRUG_ID }], error: { message: 'avvist' } })
    return expect(fetchPublishedDrugs(client)).resolves.toEqual({
      status: 'error',
      message: 'avvist',
    })
  })
})

describe('fetchPublishedDrugs', () => {
  it('leser api.published_drugs sortert på navn', async () => {
    const { client, queries } = fakeClient({
      data: [{ drug_id: DRUG_ID, canonical_name: 'sertralin' }],
      error: null,
    })
    const result = await fetchPublishedDrugs(client)

    expect(result).toEqual({
      status: 'ok',
      rows: [{ drug_id: DRUG_ID, canonical_name: 'sertralin' }],
    })
    expect(queries).toEqual([
      {
        view: 'published_drugs',
        columns: '*',
        filters: [],
        orders: [['canonical_name', { ascending: true }]],
      },
    ])
  })
})

describe('fetchPublishedClaimsForDrug', () => {
  it('filtrerer på virkestoffet og sorterer nøytralt', async () => {
    const { client, queries } = fakeClient({ data: [{ claim_id: CLAIM_ID }], error: null })
    await fetchPublishedClaimsForDrug(client, DRUG_ID)

    expect(queries).toEqual([
      {
        view: 'published_claims',
        columns: '*',
        filters: [['drug_id', DRUG_ID]],
        orders: [
          ['topic_label', { ascending: true }],
          ['statement', { ascending: true }],
        ],
      },
    ])
  })
})

describe('fetchPublishedClaimById', () => {
  it('filtrerer på den stabile identiteten, ikke på revisjonen', async () => {
    // Identiteten overlever en ny publisering (ANTIDEP_CONSTITUTION.md §7), så
    // en delt lenke fortsetter å peke på påstanden. Et filter på
    // claim_revision_id ville frosset lenken til én revisjon.
    const { client, queries } = fakeClient({ data: [{ claim_id: CLAIM_ID }], error: null })
    await fetchPublishedClaimById(client, CLAIM_ID)

    expect(queries).toEqual([
      {
        view: 'published_claims',
        columns: '*',
        filters: [['claim_id', CLAIM_ID]],
        orders: [],
      },
    ])
  })

  it('en tom projeksjon er empty, ikke en påstand med tomme felter', async () => {
    await expect(
      fetchPublishedClaimById(fakeClient({ data: [], error: null }).client, CLAIM_ID),
    ).resolves.toEqual({ status: 'empty' })
  })

  it('gir hele settet videre, slik at to rader er synlige for kalleren', async () => {
    // `published_claims` har én rad per publisert påstand. To rader er et
    // kontraktsbrudd, og lesefunksjonen skal ikke velge én av dem: kalleren må
    // kunne se at det er flere.
    const { client } = fakeClient({
      data: [{ claim_id: CLAIM_ID }, { claim_id: CLAIM_ID }],
      error: null,
    })
    const result = await fetchPublishedClaimById(client, CLAIM_ID)
    expect(result.status === 'ok' ? result.rows : []).toHaveLength(2)
  })
})

describe('fetchPublishedClaimEvidence', () => {
  it('henter hele evidenssettet for påstanden', async () => {
    const { client, queries } = fakeClient({ data: [{ claim_id: CLAIM_ID }], error: null })
    await fetchPublishedClaimEvidence(client, CLAIM_ID)

    expect(queries).toEqual([
      {
        view: 'published_claim_evidence',
        columns: '*',
        filters: [['claim_id', CLAIM_ID]],
        orders: [['claim_evidence_link_id', { ascending: true }]],
      },
    ])
  })

  it('sorterer ikke på relasjonstype, som ville vektet evidensen', async () => {
    // Motstridende evidens skal stå side om side med støttende
    // (ANTIDEP_CONSTITUTION.md §9). En rekkefølge etter relationship_type ville
    // gjort presentasjonsrekkefølgen til en vurdering.
    const { client, queries } = fakeClient({ data: [], error: null })
    await fetchPublishedClaimEvidence(client, CLAIM_ID)

    const columns = queries[0]?.orders.map(([column]) => column) ?? []
    expect(columns).not.toContain('relationship_type')
    expect(columns).not.toContain('directness')
  })

  it('filtrerer ikke bort noen relasjonstype', async () => {
    const { client, queries } = fakeClient({ data: [], error: null })
    await fetchPublishedClaimEvidence(client, CLAIM_ID)

    const filtered = queries[0]?.filters.map(([column]) => column) ?? []
    expect(filtered).toEqual(['claim_id'])
  })
})

// ----------------------------------------------------------------------------
// Kompileringsvakt: at radtypene faktisk når fram
//
// supabase-js forkaster stille en Database-type som ikke oppfyller formen sin,
// og gir da `never` som radtype. `never` er tilordnbart til alt, så både
// typecheck og testene over fortsetter å passere mens spørringene ikke lenger
// er typet i det hele tatt. Nøyaktig samme feilmodus som en stille sann pgTAP-
// assertion, og den ble faktisk truffet under arbeidet med denne filen:
// `Tables: Record<string, never>` slo ut radtypen til hvert view uten at noe
// feilet.
//
// Konstantene under blir typefeil når radtypen kollapser. Vakten håndheves av
// `npm run typecheck`, ikke av vitest — vitest fjerner typene, og testen nederst
// ville passert uansett. Den finnes for å holde konstantene i bruk og for at
// vakten skal være synlig der lesemodellen testes. Mutasjonskontrollert: med
// `Tables: Record<string, never>` gir tsc fire feil, vitest ingen.
// ----------------------------------------------------------------------------

type MutuallyAssignable<A, B> = [A] extends [B] ? ([B] extends [A] ? true : false) : false

function drugsQuery(client: AntidepClient) {
  return client.from('published_drugs').select('*')
}
function claimsQuery(client: AntidepClient) {
  return client.from('published_claims').select('*')
}
function evidenceQuery(client: AntidepClient) {
  return client.from('published_claim_evidence').select('*')
}

const drugRowReachesTheClient: MutuallyAssignable<
  Awaited<ReturnType<typeof drugsQuery>>['data'],
  PublishedDrugRow[] | null
> = true

const claimRowReachesTheClient: MutuallyAssignable<
  Awaited<ReturnType<typeof claimsQuery>>['data'],
  PublishedClaimRow[] | null
> = true

const evidenceRowReachesTheClient: MutuallyAssignable<
  Awaited<ReturnType<typeof evidenceQuery>>['data'],
  PublishedClaimEvidenceRow[] | null
> = true

describe('kontrakttypene når fram til klienten', () => {
  it('gir radtypene fra api-viewene, ikke never', async () => {
    const { client, queries } = fakeClient({ data: [], error: null })
    await drugsQuery(client)
    await claimsQuery(client)
    await evidenceQuery(client)

    expect(queries.map((query) => query.view)).toEqual([
      'published_drugs',
      'published_claims',
      'published_claim_evidence',
    ])
    expect([
      drugRowReachesTheClient,
      claimRowReachesTheClient,
      evidenceRowReachesTheClient,
    ]).toEqual([true, true, true])
  })
})

describe('alle publiserte påstander', () => {
  it('leser hele viewet uten filter', async () => {
    // Temasiden må kunne slå opp et klinisk begrep fra en slug, og `api` har
    // ingen temaprojeksjon. Et filter her ville avgrenset settet slugen kan
    // slås opp i.
    const { client, queries } = fakeClient({ data: [], error: null })
    await fetchPublishedClaims(client)
    expect(queries).toHaveLength(1)
    expect(queries[0]?.view).toBe('published_claims')
    expect(queries[0]?.filters).toEqual([])
  })

  it('sorterer stabilt på virkestoff, tema og formulering', () => {
    const { client, queries } = fakeClient({ data: [], error: null })
    return fetchPublishedClaims(client).then(() => {
      expect(queries[0]?.orders).toEqual([
        ['drug_name', { ascending: true }],
        ['topic_label', { ascending: true }],
        ['statement', { ascending: true }],
      ])
    })
  })

  it('en tom projeksjon er empty, ikke ok', () => {
    return expect(
      fetchPublishedClaims(fakeClient({ data: [], error: null }).client),
    ).resolves.toEqual({ status: 'empty' })
  })

  it('en feil er en feil', () => {
    return expect(
      fetchPublishedClaims(fakeClient({ data: null, error: { message: 'avvist' } }).client),
    ).resolves.toEqual({ status: 'error', message: 'avvist' })
  })
})
