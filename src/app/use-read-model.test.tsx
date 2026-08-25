import { render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { AntidepClientProvider, type AntidepClientAvailability } from './antidep-client'
import { useReadModel, type ReadModelQuery, type ReadModelState } from './use-read-model'
import { fakeClient } from './test-support'
import type { ReadModelResult } from '../lib/published-read-model'

interface Row {
  readonly id: string
}

function Probe({ query }: { readonly query: ReadModelQuery<Row> }) {
  const state: ReadModelState<Row> = useReadModel(query)
  return <output>{describe_(state)}</output>
}

function describe_(state: ReadModelState<Row>): string {
  switch (state.status) {
    case 'loading':
      return 'laster'
    case 'empty':
      return 'tomt'
    case 'error':
      return `feil: ${state.message}`
    case 'ok':
      return `ok: ${state.rows.map((row) => row.id).join(',')}`
  }
}

const READY: AntidepClientAvailability = { status: 'ready', client: fakeClient().client }

function renderProbe(query: ReadModelQuery<Row>, availability = READY) {
  return render(
    <AntidepClientProvider value={availability}>
      <Probe query={query} />
    </AntidepClientProvider>,
  )
}

function state(): string {
  return screen.getByRole('status').textContent ?? ''
}

const rows = (...ids: string[]): ReadModelResult<Row> =>
  ids.length === 0
    ? { status: 'empty' }
    : { status: 'ok', rows: [{ id: ids[0] as string }, ...ids.slice(1).map((id) => ({ id }))] }

describe('useReadModel', () => {
  it('starter i laster, ikke i tomt', async () => {
    // «Laster» og «tomt» må aldri se like ut: det ene vet vi ingenting om ennå,
    // det andre er et svar om at Antidep ikke har publisert noe.
    const query: ReadModelQuery<Row> = () => new Promise(() => undefined)
    renderProbe(query)
    expect(state()).toBe('laster')
  })

  it('gir resultatet når spørringen svarer', async () => {
    renderProbe(() => Promise.resolve(rows('a')))
    await waitFor(() => {
      expect(state()).toBe('ok: a')
    })
  })

  it('en avvist promise blir feil, aldri tomt', async () => {
    renderProbe(() => Promise.reject(new Error('nettverket falt ut')))
    await waitFor(() => {
      expect(state()).toBe('feil: nettverket falt ut')
    })
  })

  it('en kastet verdi som ikke er en Error blir også feil', async () => {
    renderProbe(() => Promise.reject('noe gikk galt'))
    await waitFor(() => {
      expect(state()).toBe('feil: noe gikk galt')
    })
  })

  it('en klient som ikke lot seg opprette er en feil, ikke en tom flate', () => {
    renderProbe(() => Promise.resolve(rows('a')), {
      status: 'unavailable',
      message: 'VITE_SUPABASE_URL mangler',
    })
    expect(state()).toBe('feil: VITE_SUPABASE_URL mangler')
  })

  it('viser laster igjen når spørringen byttes, ikke forrige svar', async () => {
    // Uten dette ville forrige virkestoffs påstander stått under det nyes
    // overskrift i det halvsekundet før svaret kom.
    const first: ReadModelQuery<Row> = () => Promise.resolve(rows('a'))
    const { rerender } = renderProbe(first)
    await waitFor(() => {
      expect(state()).toBe('ok: a')
    })

    const second: ReadModelQuery<Row> = () => new Promise(() => undefined)
    rerender(
      <AntidepClientProvider value={READY}>
        <Probe query={second} />
      </AntidepClientProvider>,
    )
    expect(state()).toBe('laster')
  })

  it('et foreldet svar kan ikke vises, uansett når det kommer', async () => {
    // Den kritiske rekkefølgen: spørring 1 svarer ETTER at spørring 2 er stilt.
    let resolveFirst: ((value: ReadModelResult<Row>) => void) | undefined
    const first: ReadModelQuery<Row> = () =>
      new Promise<ReadModelResult<Row>>((resolve) => {
        resolveFirst = resolve
      })
    const { rerender } = renderProbe(first)

    const second: ReadModelQuery<Row> = () => Promise.resolve(rows('ny'))
    rerender(
      <AntidepClientProvider value={READY}>
        <Probe query={second} />
      </AntidepClientProvider>,
    )
    await waitFor(() => {
      expect(state()).toBe('ok: ny')
    })

    resolveFirst?.(rows('gammel'))
    await Promise.resolve()
    expect(state()).toBe('ok: ny')
  })

  it('kjører ikke spørringen på nytt når referansen er uendret', async () => {
    let calls = 0
    const query: ReadModelQuery<Row> = () => {
      calls += 1
      return Promise.resolve(rows('a'))
    }
    const { rerender } = renderProbe(query)
    await waitFor(() => {
      expect(state()).toBe('ok: a')
    })
    const before = calls
    rerender(
      <AntidepClientProvider value={READY}>
        <Probe query={query} />
      </AntidepClientProvider>,
    )
    expect(calls).toBe(before)
  })
})
