import { screen, waitFor, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { drugRow, renderRoute } from '../test-support'

function main(): HTMLElement {
  return screen.getByRole('main')
}

describe('forsiden', () => {
  it('viser ventetilstanden, ikke tomhet, mens svaret er underveis', () => {
    renderRoute('/', { api: { published_drugs: { pending: true } } })
    expect(main()).toHaveTextContent(/Henter publisert kunnskap/i)
    expect(main()).not.toHaveTextContent(/ingen publiserte påstander/i)
  })

  it('en tom projeksjon sier at ingenting er publisert, med forbeholdet', async () => {
    renderRoute('/', { api: { published_drugs: [] } })
    await waitFor(() => {
      expect(main()).toHaveTextContent(/Antidep har ingen publiserte påstander ennå/i)
    })
    // Det er denne setningen som skiller «ikke publisert» fra «trygt».
    expect(main()).toHaveTextContent(
      /ikke dokumentasjon på fravær av effekt, bivirkning eller risiko/i,
    )
  })

  it('en feil er en feil, ikke fravær av kunnskap', async () => {
    renderRoute('/', { api: { published_drugs: { error: 'nettverksfeil' } } })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(/teknisk feil, ikke et svar om at kunnskap mangler/i)
    expect(alert).toHaveTextContent('nettverksfeil')
    expect(main()).not.toHaveTextContent(/ingen publiserte påstander ennå/i)
  })

  it('lister virkestoffene med lenke og antall', async () => {
    renderRoute('/', {
      api: {
        published_drugs: [
          drugRow({ canonical_name: 'mirtazapin', published_claim_count: 2 }),
          drugRow({
            drug_id: '99999999-9999-4999-8999-999999999999',
            canonical_name: 'sertralin',
            published_claim_count: 1,
          }),
        ],
      },
    })
    const list = await screen.findByRole('list')
    const items = within(list).getAllByRole('listitem')
    expect(items).toHaveLength(2)
    expect(within(items[0] as HTMLElement).getByRole('link')).toHaveAttribute(
      'href',
      '/drugs/mirtazapin',
    )
    expect(items[0]).toHaveTextContent('2 publiserte påstander')
    expect(items[1]).toHaveTextContent('1 publisert påstand')
  })

  it('sorterer selv, framfor å arve rekkefølgen fra spørringen', async () => {
    // Siden sier at rekkefølgen er alfabetisk. `order by` i PostgreSQL bruker
    // databasens kollasjon, som ikke er norsk, så påstanden må visningen selv
    // kunne innfri.
    renderRoute('/', {
      api: {
        published_drugs: [
          drugRow({ canonical_name: 'åreknute' }),
          drugRow({ drug_id: '99999999-9999-4999-8999-111111111111', canonical_name: 'ødem' }),
          drugRow({ drug_id: '99999999-9999-4999-8999-222222222222', canonical_name: 'sertralin' }),
        ],
      },
    })
    const list = await screen.findByRole('list')
    expect(
      within(list)
        .getAllByRole('link')
        .map((link) => link.textContent),
    ).toEqual(['sertralin', 'ødem', 'åreknute'])
  })

  it('sier at rekkefølgen er alfabetisk og ingen rangering', async () => {
    // En ordnet liste blir en anbefaling hvis ingen sier hva ordenen betyr
    // (produktinvariant 14).
    renderRoute('/', { api: { published_drugs: [drugRow()] } })
    await screen.findByRole('list')
    expect(main()).toHaveTextContent(/alfabetisk og er ingen rangering/i)
  })

  it('sier at listen er Antideps innhold, ikke en oversikt over antidepressiver', async () => {
    renderRoute('/', { api: { published_drugs: [drugRow()] } })
    await screen.findByRole('list')
    expect(main()).toHaveTextContent(/ikke en oversikt over antidepressiver som finnes/i)
  })

  it('et utolkbart antall sies høyt framfor å bli utelatt', async () => {
    // En rad uten tall ville sett ut som en rad uten påstander.
    renderRoute('/', { api: { published_drugs: [drugRow({ published_claim_count: -1 })] } })
    expect(await screen.findByRole('list')).toHaveTextContent(
      /Antallet publiserte påstander er ikke tolkbart \(verdi: -1\)/i,
    )
  })
})
