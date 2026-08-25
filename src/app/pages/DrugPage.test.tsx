import { screen, waitFor } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { TEST_DRUG_IDS, claimRow, drugRow, renderRoute } from '../test-support'

function main(): HTMLElement {
  return screen.getByRole('main')
}

const SERTRALIN = drugRow({ canonical_name: 'sertralin', atc_codes: ['N06AB06'] })

describe('legemiddelsiden — tilstandene før virkestoffet er funnet', () => {
  it('venter, og viser ikke fravær mens den venter', () => {
    renderRoute('/drugs/sertralin', { api: { published_drugs: { pending: true } } })
    expect(main()).toHaveTextContent(/Henter publisert kunnskap/i)
    expect(main()).not.toHaveTextContent(/ingen publiserte påstander om/i)
  })

  it('en tom projeksjon sier at ingenting er publisert — ikke at virkestoffet er ukjent', async () => {
    // De to er forskjellige utsagn. Å slå dem sammen ville latt et tomt Antidep
    // uttale seg om et virkestoff.
    renderRoute('/drugs/sertralin', { api: { published_drugs: [] } })
    await waitFor(() => {
      expect(main()).toHaveTextContent(/ingen publiserte påstander ennå — om noe virkestoff/i)
    })
    expect(main()).toHaveTextContent(/sier derfor ingenting om virkestoffet den navngir/i)
  })

  it('en feil er en feil', async () => {
    renderRoute('/drugs/sertralin', { api: { published_drugs: { error: 'tidsavbrudd' } } })
    expect(await screen.findByRole('alert')).toHaveTextContent('tidsavbrudd')
  })

  it('en adresse uten treff sier at det gjelder Antideps innhold, ikke virkestoffet', async () => {
    renderRoute('/drugs/fluoksetin', { api: { published_drugs: [SERTRALIN] } })
    await waitFor(() => {
      expect(main()).toHaveTextContent(/adressen «fluoksetin»/i)
    })
    expect(main()).toHaveTextContent(/utsagn om Antideps innhold, ikke om virkestoffet/i)
    expect(main()).toHaveTextContent(
      /ikke dokumentasjon på fravær av effekt, bivirkning eller risiko/i,
    )
  })

  it('en tvetydig adresse velger ikke ett virkestoff framfor et annet', async () => {
    renderRoute('/drugs/vektokning', {
      api: {
        published_drugs: [
          drugRow({ canonical_name: 'vektøkning' }),
          drugRow({ drug_id: TEST_DRUG_IDS.b, canonical_name: 'vektokning' }),
        ],
      },
    })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(/peker på flere virkestoff/i)
    expect(alert).toHaveTextContent('vektøkning')
    expect(alert).toHaveTextContent('vektokning')
  })

  it('overskriften er ikke sluggen fra URL-en når adressen ikke traff', async () => {
    // Ellers ville en adresse leseren skrev, sett ut som noe Antidep hevder.
    renderRoute('/drugs/fluoksetin', { api: { published_drugs: [SERTRALIN] } })
    await waitFor(() => {
      expect(screen.getByRole('heading', { level: 2 })).toHaveTextContent('Virkestoff')
    })
    expect(screen.getByRole('heading', { level: 2 })).not.toHaveTextContent('fluoksetin')
  })
})

describe('legemiddelsiden — virkestoffet funnet', () => {
  const api = {
    published_drugs: [SERTRALIN],
    published_claims: [claimRow({ drug_id: SERTRALIN.drug_id, drug_name: 'sertralin' })],
  }

  it('viser det kanoniske navnet som overskrift, merket som virkestoff', async () => {
    renderRoute('/drugs/sertralin', { api })
    expect(await screen.findByRole('heading', { level: 2, name: 'sertralin' })).toBeInTheDocument()
    expect(main()).toHaveTextContent('Virkestoff')
  })

  it('viser ATC-koden', async () => {
    renderRoute('/drugs/sertralin', { api })
    await screen.findByRole('heading', { level: 2, name: 'sertralin' })
    expect(main()).toHaveTextContent('N06AB06')
  })

  it('sier at ATC-koden mangler i Antidep, ikke at virkestoffet mangler en', async () => {
    renderRoute('/drugs/sertralin', {
      api: { ...api, published_drugs: [drugRow({ canonical_name: 'sertralin', atc_codes: null })] },
    })
    await screen.findByRole('heading', { level: 2, name: 'sertralin' })
    expect(main()).toHaveTextContent('Ingen ATC-kode er registrert i Antidep')
  })

  it('viser ikke katalogstatusen, som beskriver Antideps forvaltning og ikke markedsstatus', async () => {
    renderRoute('/drugs/sertralin', {
      api: {
        ...api,
        published_drugs: [drugRow({ canonical_name: 'sertralin', status: 'withdrawn' })],
      },
    })
    await screen.findByRole('heading', { level: 2, name: 'sertralin' })
    expect(main()).not.toHaveTextContent('withdrawn')
  })

  it('henter bare dette virkestoffets påstander, filtrert på identiteten', async () => {
    const { queries } = renderRoute('/drugs/sertralin', { api })
    await screen.findByRole('article')
    const claimQuery = queries.find((query) => query.view === 'published_claims')
    expect(claimQuery?.filters).toEqual([['drug_id', SERTRALIN.drug_id]])
  })

  it('viser ikke et annet virkestoffs påstander', async () => {
    renderRoute('/drugs/sertralin', {
      api: {
        published_drugs: [SERTRALIN],
        published_claims: [
          claimRow({ drug_id: SERTRALIN.drug_id, drug_name: 'sertralin' }),
          claimRow({
            claim_id: '22222222-2222-4222-8222-999999999999',
            drug_id: TEST_DRUG_IDS.b,
            drug_name: 'virkestoff b',
            statement: 'Testpåstand: skal ikke vises her.',
          }),
        ],
      },
    })
    expect(await screen.findAllByRole('article')).toHaveLength(1)
    expect(main()).not.toHaveTextContent('skal ikke vises her')
  })

  it('grupperer påstandene på tema, med lenke videre til temasiden', async () => {
    renderRoute('/drugs/sertralin', { api })
    const topicLink = await screen.findByRole('link', { name: 'vektendring' })
    expect(topicLink).toHaveAttribute('href', '/topics/vektendring')
  })

  it('et virkestoff uten publiserte påstander sier det, med virkestoffets navn', async () => {
    renderRoute('/drugs/sertralin', { api: { published_drugs: [SERTRALIN], published_claims: [] } })
    await waitFor(() => {
      expect(main()).toHaveTextContent(/Antidep har ingen publiserte påstander om sertralin/i)
    })
    expect(main()).toHaveTextContent(
      /ikke dokumentasjon på fravær av effekt, bivirkning eller risiko/i,
    )
  })

  it('en feil på påstandene skjuler ikke virkestoffet, og blir ikke tomhet', async () => {
    renderRoute('/drugs/sertralin', {
      api: { published_drugs: [SERTRALIN], published_claims: { error: 'avvist' } },
    })
    expect(await screen.findByRole('alert')).toHaveTextContent('avvist')
    expect(screen.getByRole('heading', { level: 2, name: 'sertralin' })).toBeInTheDocument()
    expect(main()).not.toHaveTextContent(/ingen publiserte påstander om sertralin/i)
  })
})
