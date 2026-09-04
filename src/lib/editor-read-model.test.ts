import { describe, expect, it } from 'vitest'
import {
  fetchEditorDrugs,
  fetchEditorEvidenceItems,
  fetchEditorOutcomes,
  fetchEditorPopulations,
  fetchEditorSourceVersions,
  fetchEditorSources,
} from './editor-read-model'
import type { AntidepClient } from './supabase'

// ----------------------------------------------------------------------------
// En falsk klient som registrerer hva som faktisk ble spurt om. Samme rigg som
// i published-read-model.test.ts: da er det den virkelige spørringen som
// prøves, og et filter som forsvinner blir synlig.
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

const SOURCE_ID = '88888888-8888-4888-8888-222222222222'

describe('tomt er en egen tilstand, og den heter noe annet enn lesemodellens', () => {
  it('et tomt svar er none, ikke ok med null rader', async () => {
    // `none` betyr «du ser ingenting her»: enten mangler kalleren
    // editor-rollen, eller registeret er tomt. Viewene skiller ikke de to, og
    // en klient som påsto å vite hvilken, ville hevdet mer enn svaret sier.
    const { client } = fakeClient({ data: [], error: null })
    expect(await fetchEditorSources(client)).toEqual({ status: 'none' })
  })

  it('null rader fra PostgREST er også none', async () => {
    const { client } = fakeClient({ data: null, error: null })
    expect(await fetchEditorDrugs(client)).toEqual({ status: 'none' })
  })

  it('en avvist spørring er error, aldri none', async () => {
    const { client } = fakeClient({
      data: null,
      error: { message: 'permission denied for view editor_sources' },
    })
    expect(await fetchEditorSources(client)).toEqual({
      status: 'error',
      message: 'permission denied for view editor_sources',
    })
  })

  it('ok bærer minst én rad', async () => {
    const { client } = fakeClient({ data: [{ source_id: SOURCE_ID }], error: null })
    const result = await fetchEditorSources(client)
    expect(result.status).toBe('ok')
    if (result.status === 'ok') {
      expect(result.rows).toHaveLength(1)
    }
  })
})

describe('spørringene', () => {
  it('kildene sorteres på tittel', async () => {
    const { client, queries } = fakeClient({ data: [], error: null })
    await fetchEditorSources(client)
    expect(queries).toEqual([
      {
        view: 'editor_sources',
        columns: '*',
        filters: [],
        orders: [['title', { ascending: true }]],
      },
    ])
  })

  it('kildeversjonene filtreres på kilden, med nyeste henting først', async () => {
    const { client, queries } = fakeClient({ data: [], error: null })
    await fetchEditorSourceVersions(client, SOURCE_ID)
    expect(queries[0]?.view).toBe('editor_source_versions')
    expect(queries[0]?.filters).toEqual([['source_id', SOURCE_ID]])
    expect(queries[0]?.orders).toEqual([['retrieved_at', { ascending: false }]])
  })

  it('katalogoppslagene sorteres alfabetisk', async () => {
    const { client, queries } = fakeClient({ data: [], error: null })
    await fetchEditorDrugs(client)
    await fetchEditorOutcomes(client)
    await fetchEditorPopulations(client)
    expect(queries.map((query) => [query.view, query.orders[0]?.[0]])).toEqual([
      ['editor_drugs', 'canonical_name'],
      ['editor_outcomes', 'canonical_label'],
      ['editor_populations', 'canonical_label'],
    ])
  })

  it('evidensfunnene filtreres på kilden, med det nyest registrerte først', async () => {
    // Rekkefølgen er registreringstid og ikke en vurdering: bekreftelsen etter
    // en registrering skal vise funnet som nettopp ble lagt inn.
    const { client, queries } = fakeClient({ data: [], error: null })
    await fetchEditorEvidenceItems(client, SOURCE_ID)
    expect(queries[0]?.view).toBe('editor_evidence_items')
    expect(queries[0]?.filters).toEqual([['source_id', SOURCE_ID]])
    expect(queries[0]?.orders).toEqual([['created_at', { ascending: false }]])
  })
})
