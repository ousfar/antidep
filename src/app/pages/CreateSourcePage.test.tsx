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
