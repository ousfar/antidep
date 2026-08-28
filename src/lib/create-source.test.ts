import { describe, expect, it } from 'vitest'
import { createSource } from './create-source'
import type { AntidepClient } from './supabase'
import type { CreateSourceInput } from './create-source'

interface RecordedCall {
  name: string
  args: unknown
}

function fakeClient(outcome: { data: unknown; error: { message: string } | null }) {
  const calls: RecordedCall[] = []
  const client = {
    rpc(name: string, args: unknown) {
      calls.push({ name, args })
      return Promise.resolve(outcome)
    },
  }
  return { client: client as unknown as AntidepClient, calls }
}

const MINIMAL_INPUT: CreateSourceInput = {
  sourceType: 'journal_article',
  title: 'Testkilde',
  authorsOrIssuer: 'Testforfatter',
  publisherOrJournal: null,
  volume: null,
  issue: null,
  pages: null,
  publicationDate: null,
  publicationDatePrecision: null,
}

describe('createSource', () => {
  it('kaller api.create_source med feltene oversatt til p_-parametrene', async () => {
    const sourceId = '00000000-0000-4000-8000-222222222222'
    const { client, calls } = fakeClient({ data: sourceId, error: null })

    const result = await createSource(client, {
      ...MINIMAL_INPUT,
      publisherOrJournal: 'Testtidsskriftet',
      volume: '3',
      issue: '4',
      pages: '10-20',
      publicationDate: '2024-06-01',
      publicationDatePrecision: 'month',
    })

    expect(result).toEqual({ status: 'ok', sourceId })
    expect(calls).toEqual([
      {
        name: 'create_source',
        args: {
          p_source_type: 'journal_article',
          p_title: 'Testkilde',
          p_authors_or_issuer: 'Testforfatter',
          p_publisher_or_journal: 'Testtidsskriftet',
          p_volume: '3',
          p_issue: '4',
          p_pages: '10-20',
          p_publication_date: '2024-06-01',
          p_publication_date_precision: 'month',
        },
      },
    ])
  })

  it('sender null for valgfrie felter som ikke er utfylt, ikke tomstreng', async () => {
    const { client, calls } = fakeClient({
      data: '00000000-0000-4000-8000-333333333333',
      error: null,
    })

    await createSource(client, MINIMAL_INPUT)

    const args = calls[0]?.args as Record<string, unknown>
    expect(args['p_publisher_or_journal']).toBeNull()
    expect(args['p_volume']).toBeNull()
    expect(args['p_issue']).toBeNull()
    expect(args['p_pages']).toBeNull()
    expect(args['p_publication_date']).toBeNull()
    expect(args['p_publication_date_precision']).toBeNull()
  })

  it('en avvisning fra databasen kommer tilbake som error, ikke som et kastet unntak', async () => {
    // Verken en manglende aktør, en manglende editor-rolle eller en
    // constraint-avvisning skal håndteres som en programmeringsfeil her —
    // se doc-kommentaren i create-source.ts.
    const { client } = fakeClient({
      data: null,
      error: { message: 'Brukeren har ikke gyldig editor-rolle.' },
    })

    const result = await createSource(client, MINIMAL_INPUT)

    expect(result).toEqual({
      status: 'error',
      message: 'Brukeren har ikke gyldig editor-rolle.',
    })
  })
})
