import { fireEvent, screen, waitFor, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { claimRow, drugRow, renderRoute } from './test-support'

describe('skallet', () => {
  it('viser produktnavnet i en toppbanner, som vei tilbake til forsiden', () => {
    renderRoute('/')
    const banner = screen.getByRole('banner')
    const heading = within(banner).getByRole('heading', { level: 1, name: 'Antidep' })
    expect(heading).toBeInTheDocument()
    expect(within(heading).getByRole('link')).toHaveAttribute('href', '/')
  })

  it('sier at innholdet ikke skal brukes til kliniske beslutninger ennå', () => {
    // Flaten viser nå klinisk innhold. Da må den også si hva den ikke er.
    renderRoute('/')
    expect(screen.getByRole('banner')).toHaveTextContent(
      /skal ikke brukes som grunnlag for kliniske beslutninger ennå/i,
    )
  })

  it('har en hopplenke til hovedinnholdet som første fokuserbare element', () => {
    // §49 og §52: en tastaturbruker skal slippe å gå gjennom toppen på nytt for
    // hver navigering.
    renderRoute('/')
    const skip = screen.getByRole('link', { name: 'Hopp til hovedinnhold' })
    expect(skip).toHaveAttribute('href', `#${screen.getByRole('main').id}`)
    expect(document.body.querySelector('a')).toBe(skip)
  })
})

describe('rutingen', () => {
  it('forsiden viser den publiserte indeksen', () => {
    renderRoute('/')
    expect(
      screen.getByRole('heading', { level: 2, name: 'Publisert kunnskap' }),
    ).toBeInTheDocument()
  })

  it('en ukjent adresse sier at adressen er ukjent, ikke noe om klinikk', () => {
    renderRoute('/finnes-ikke')
    expect(screen.getByRole('heading', { level: 2, name: 'Ukjent adresse' })).toBeInTheDocument()
    expect(screen.getByRole('main')).toHaveTextContent('/finnes-ikke')
  })

  it('legemiddeladressen fra §30 treffer legemiddelsiden', async () => {
    renderRoute('/drugs/sertralin', {
      api: { published_drugs: [drugRow({ canonical_name: 'sertralin' })] },
    })
    expect(await screen.findByRole('heading', { level: 2, name: 'sertralin' })).toBeInTheDocument()
  })

  it('temaadressen treffer temasiden', async () => {
    renderRoute('/topics/vektendring', { api: { published_claims: [claimRow()] } })
    expect(
      await screen.findByRole('heading', { level: 2, name: 'vektendring' }),
    ).toBeInTheDocument()
  })

  it('evidensadressen finnes, og siden sier at visningen ikke er bygget', () => {
    // Kortet krever `evidenceHref`, så lenken finnes fra første kort. Uten en
    // rute ville den sagt «siden finnes ikke», som ikke er sant: adressen er
    // riktig, innholdet er ikke bygget.
    renderRoute('/claims/11111111-1111-4111-8111-111111111111/evidence')
    expect(screen.getByRole('main')).toHaveTextContent(/Evidensvisningen er ikke bygget ennå/i)
    expect(screen.getByRole('main')).toHaveTextContent('11111111-1111-4111-8111-111111111111')
  })

  it('setter dokumenttittelen per adresse', async () => {
    renderRoute('/drugs/sertralin', {
      api: { published_drugs: [drugRow({ canonical_name: 'sertralin' })] },
    })
    await waitFor(() => {
      expect(document.title).toBe('sertralin – Antidep')
    })
  })
})

describe('navigering', () => {
  it('flytter fokus til hovedinnholdet, men ikke ved første render', async () => {
    // Uten dette blir en skjermleser stående igjen i forrige side.
    renderRoute('/', {
      api: { published_drugs: [drugRow({ canonical_name: 'sertralin' })] },
    })
    const main = screen.getByRole('main')
    expect(main).not.toHaveFocus()

    fireEvent.click(await screen.findByRole('link', { name: 'sertralin' }))

    await waitFor(() => {
      expect(main).toHaveFocus()
    })
  })

  it('lenken fra forsiden går til adressen legemiddelsiden svarer på', async () => {
    renderRoute('/', { api: { published_drugs: [drugRow({ canonical_name: 'sertralin' })] } })
    expect(await screen.findByRole('link', { name: 'sertralin' })).toHaveAttribute(
      'href',
      '/drugs/sertralin',
    )
  })
})
