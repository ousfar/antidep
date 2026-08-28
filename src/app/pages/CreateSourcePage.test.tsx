import { fireEvent, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { TEST_USER_IDS, renderRoute } from '../test-support'

function fillRequiredFields() {
  fireEvent.change(screen.getByLabelText('Tittel'), { target: { value: 'Testkilde fra skjema' } })
  fireEvent.change(screen.getByLabelText('Forfattere eller utgiver'), {
    target: { value: 'Testforfatter' },
  })
}

describe('Opprett kilde — ikke innlogget', () => {
  it('viser en henvisning til Min tilgang, ikke skjemaet', async () => {
    const { rpcCalls } = renderRoute('/sources/new')
    expect(await screen.findByText('Du må logge inn for å opprette en kilde.')).toBeInTheDocument()
    expect(screen.queryByLabelText('Tittel')).not.toBeInTheDocument()
    expect(rpcCalls).toEqual([])
  })
})

describe('Opprett kilde — innlogget, ingen rollegate i klienten', () => {
  it('viser skjemaet til enhver innlogget bruker, uansett rolle', async () => {
    // FELLE 4-doktrinen fra AccessPage.tsx gjentatt her: siden spør ikke
    // api.my_roles i det hele tatt før den viser skjemaet. Retten kontrolleres
    // av knowledge.assert_editor_authorized() på serveren.
    const { queries } = renderRoute('/sources/new', { auth: { initialUserId: TEST_USER_IDS.a } })
    expect(await screen.findByLabelText('Tittel')).toBeInTheDocument()
    expect(queries.some((query) => query.view === 'my_roles')).toBe(false)
  })

  it('sender skjemaet som api.create_source(...), med tomme valgfrie felt som null', async () => {
    const { rpcCalls } = renderRoute('/sources/new', { auth: { initialUserId: TEST_USER_IDS.a } })
    await screen.findByLabelText('Tittel')
    fillRequiredFields()
    fireEvent.click(screen.getByRole('button', { name: 'Opprett kilde' }))

    await screen.findByText(/Kilden er opprettet/)
    expect(rpcCalls).toEqual([
      {
        name: 'create_source',
        args: {
          p_source_type: 'journal_article',
          p_title: 'Testkilde fra skjema',
          p_authors_or_issuer: 'Testforfatter',
          p_publisher_or_journal: null,
          p_volume: null,
          p_issue: null,
          p_pages: null,
          p_publication_date: null,
          p_publication_date_precision: null,
        },
      },
    ])
  })

  it('en avvisning fra databasen vises med databasens egen tekst, og skjemaet blir stående utfylt', async () => {
    renderRoute('/sources/new', {
      auth: { initialUserId: TEST_USER_IDS.a },
      api: { create_source: { error: 'Brukeren har ikke gyldig editor-rolle.' } },
    })
    await screen.findByLabelText('Tittel')
    fillRequiredFields()
    fireEvent.click(screen.getByRole('button', { name: 'Opprett kilde' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Brukeren har ikke gyldig editor-rolle.',
    )
    // Ikke tømt: en avvist bruker skal ikke måtte skrive alt på nytt.
    expect(screen.getByLabelText('Tittel')).toHaveValue('Testkilde fra skjema')
  })

  it('skjemaet nullstilles etter en vellykket opprettelse', async () => {
    renderRoute('/sources/new', { auth: { initialUserId: TEST_USER_IDS.a } })
    await screen.findByLabelText('Tittel')
    fillRequiredFields()
    fireEvent.click(screen.getByRole('button', { name: 'Opprett kilde' }))

    await screen.findByText(/Kilden er opprettet/)
    expect(screen.getByLabelText('Tittel')).toHaveValue('')
  })
})

// ----------------------------------------------------------------------------
// Publiseringsdato
//
// Databasen lagrer en årfestet dato som `YYYY-01-01` og en månedsfestet som
// `YYYY-MM-01`. Testene under kontrollerer at brukeren aldri behøver å vite det:
// hver presisjon har sitt eget felt, og kanoniseringen skjer før kallet.
//
// Kanoniseringsreglene i seg selv er dekket i `lib/publication-date.test.ts`.
// Det som prøves her, er at siden faktisk kobler dem på: riktig felt vises for
// riktig presisjon, og verdien som når RPC-et er den kanoniserte.
// ----------------------------------------------------------------------------

/** Argumentene ett `create_source`-kall faktisk fikk. */
function lastCallArgs(rpcCalls: readonly { readonly args: unknown }[]) {
  return rpcCalls.at(-1)?.args as Record<string, unknown> | undefined
}

async function chooseDatePrecision(label: string) {
  fireEvent.change(await screen.findByLabelText('Publiseringsdato'), { target: { value: label } })
}

describe('Opprett kilde — publiseringsdato', () => {
  it('viser ingen datofelt før en presisjon er valgt, og sender begge feltene som null', async () => {
    const { rpcCalls } = renderRoute('/sources/new', { auth: { initialUserId: TEST_USER_IDS.a } })
    await screen.findByLabelText('Tittel')

    // «Ingen dato» er standard, og da finnes det ikke noe datofelt å fylle ut.
    expect(screen.queryByLabelText('År')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Måned og år')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Dato')).not.toBeInTheDocument()

    fillRequiredFields()
    fireEvent.click(screen.getByRole('button', { name: 'Opprett kilde' }))
    await screen.findByText(/Kilden er opprettet/)

    const args = lastCallArgs(rpcCalls)
    expect(args?.['p_publication_date']).toBeNull()
    expect(args?.['p_publication_date_precision']).toBeNull()
  })

  it('bare år: brukeren skriver 2000, databasen får 2000-01-01', async () => {
    const { rpcCalls } = renderRoute('/sources/new', { auth: { initialUserId: TEST_USER_IDS.a } })
    await screen.findByLabelText('Tittel')
    fillRequiredFields()
    await chooseDatePrecision('year')

    // Bare årsfeltet vises — ingen datovelger som ber om en dag brukeren ikke har.
    expect(screen.queryByLabelText('Dato')).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('År'), { target: { value: '2000' } })
    fireEvent.click(screen.getByRole('button', { name: 'Opprett kilde' }))
    await screen.findByText(/Kilden er opprettet/)

    const args = lastCallArgs(rpcCalls)
    expect(args?.['p_publication_date']).toBe('2000-01-01')
    expect(args?.['p_publication_date_precision']).toBe('year')
  })

  it('år og måned: november 2000 blir 2000-11-01', async () => {
    const { rpcCalls } = renderRoute('/sources/new', { auth: { initialUserId: TEST_USER_IDS.a } })
    await screen.findByLabelText('Tittel')
    fillRequiredFields()
    await chooseDatePrecision('month')

    fireEvent.change(screen.getByLabelText('Måned og år'), { target: { value: '2000-11' } })
    fireEvent.click(screen.getByRole('button', { name: 'Opprett kilde' }))
    await screen.findByText(/Kilden er opprettet/)

    const args = lastCallArgs(rpcCalls)
    expect(args?.['p_publication_date']).toBe('2000-11-01')
    expect(args?.['p_publication_date_precision']).toBe('month')
  })

  it('nøyaktig dato sendes uendret', async () => {
    const { rpcCalls } = renderRoute('/sources/new', { auth: { initialUserId: TEST_USER_IDS.a } })
    await screen.findByLabelText('Tittel')
    fillRequiredFields()
    await chooseDatePrecision('day')

    fireEvent.change(screen.getByLabelText('Dato'), { target: { value: '2005-04-07' } })
    fireEvent.click(screen.getByRole('button', { name: 'Opprett kilde' }))
    await screen.findByText(/Kilden er opprettet/)

    const args = lastCallArgs(rpcCalls)
    expect(args?.['p_publication_date']).toBe('2005-04-07')
    expect(args?.['p_publication_date_precision']).toBe('day')
  })

  it('valgt presisjon uten dato: sier fra, og sender ingenting', async () => {
    // Den ene tilstanden UI-et lar oppstå der dato og presisjon ikke henger
    // sammen. Uten dette ville skjemaet sendt en presisjon uten dato, og
    // databasen ville avvist den med et constraint-navn brukeren ikke kan bruke
    // til noe.
    const { rpcCalls } = renderRoute('/sources/new', { auth: { initialUserId: TEST_USER_IDS.a } })
    await screen.findByLabelText('Tittel')
    fillRequiredFields()
    await chooseDatePrecision('year')
    fireEvent.click(screen.getByRole('button', { name: 'Opprett kilde' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(/Fyll inn året/)
    expect(rpcCalls).toEqual([])
  })

  it('en rettet dato går gjennom etter at feilen er vist', async () => {
    // Feilen skal være en tilstand brukeren kommer seg ut av, ikke en blindvei.
    const { rpcCalls } = renderRoute('/sources/new', { auth: { initialUserId: TEST_USER_IDS.a } })
    await screen.findByLabelText('Tittel')
    fillRequiredFields()
    await chooseDatePrecision('month')
    fireEvent.click(screen.getByRole('button', { name: 'Opprett kilde' }))
    await screen.findByRole('alert')

    fireEvent.change(screen.getByLabelText('Måned og år'), { target: { value: '2019-03' } })
    fireEvent.click(screen.getByRole('button', { name: 'Opprett kilde' }))
    await screen.findByText(/Kilden er opprettet/)

    expect(lastCallArgs(rpcCalls)?.['p_publication_date']).toBe('2019-03-01')
  })

  it('et bytte av presisjon beholder det brukeren allerede har skrevet', async () => {
    renderRoute('/sources/new', { auth: { initialUserId: TEST_USER_IDS.a } })
    await screen.findByLabelText('Tittel')

    await chooseDatePrecision('year')
    fireEvent.change(screen.getByLabelText('År'), { target: { value: '2000' } })
    await chooseDatePrecision('day')
    fireEvent.change(screen.getByLabelText('Dato'), { target: { value: '2005-04-07' } })
    await chooseDatePrecision('year')

    expect(screen.getByLabelText('År')).toHaveValue(2000)
  })
})
