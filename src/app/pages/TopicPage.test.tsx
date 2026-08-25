import { screen, waitFor, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { TEST_DRUG_IDS, TEST_TOPIC_IDS, claimRow, renderRoute } from '../test-support'

function main(): HTMLElement {
  return screen.getByRole('main')
}

const WEIGHT_A = claimRow({ drug_name: 'sertralin' })
const WEIGHT_B = claimRow({
  claim_id: '22222222-2222-4222-8222-222222222222',
  drug_id: TEST_DRUG_IDS.b,
  drug_name: 'mirtazapin',
  statement: 'Testpåstand: Virkestoff B er assosiert med vektøkning.',
})
const OTHER_TOPIC = claimRow({
  claim_id: '22222222-2222-4222-8222-333333333333',
  topic_concept_id: '44444444-4444-4444-8444-222222222222',
  topic_label: 'sedasjon',
  statement: 'Testpåstand: hører til et annet tema.',
})

describe('temasiden', () => {
  it('venter, og viser ikke fravær mens den venter', () => {
    renderRoute('/topics/vektendring', { api: { published_claims: { pending: true } } })
    expect(main()).toHaveTextContent(/Henter publisert kunnskap/i)
  })

  it('en tom projeksjon sier at ingenting er publisert — ikke at temaet er ukjent', async () => {
    renderRoute('/topics/vektendring', { api: { published_claims: [] } })
    await waitFor(() => {
      expect(main()).toHaveTextContent(/ingen publiserte påstander ennå — om noe tema/i)
    })
  })

  it('en adresse uten treff sier at temaet kan være viktig likevel', async () => {
    renderRoute('/topics/sedasjon', { api: { published_claims: [WEIGHT_A] } })
    await waitFor(() => {
      expect(main()).toHaveTextContent(/adressen «sedasjon»/i)
    })
    expect(main()).toHaveTextContent(/temaet kan være klinisk viktig uten at noe er publisert/i)
  })

  it('flere påstander om samme tema er ikke en tvetydig adresse', async () => {
    // Kandidatene er de distinkte begrepene, ikke radene. Et oppslag i radene
    // ville meldt tvetydighet hver gang et tema hadde mer enn én påstand — en
    // vaktpost som slår ut på det normale, blir slått av.
    renderRoute('/topics/vektendring', { api: { published_claims: [WEIGHT_A, WEIGHT_B] } })
    expect(
      await screen.findByRole('heading', { level: 2, name: 'vektendring' }),
    ).toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('to forskjellige begreper med kolliderende slug er tvetydig', async () => {
    renderRoute('/topics/vektokning', {
      api: {
        published_claims: [
          claimRow({ topic_label: 'vektøkning' }),
          claimRow({
            claim_id: '22222222-2222-4222-8222-444444444444',
            topic_concept_id: '44444444-4444-4444-8444-333333333333',
            topic_label: 'vektokning',
          }),
        ],
      },
    })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(/peker på flere kliniske begreper/i)
  })

  it('viser bare påstandene om dette temaet', async () => {
    renderRoute('/topics/vektendring', {
      api: { published_claims: [WEIGHT_A, OTHER_TOPIC] },
    })
    expect(await screen.findAllByRole('article')).toHaveLength(1)
    expect(main()).not.toHaveTextContent(/hører til et annet tema/i)
  })

  it('grupperer på virkestoff, alfabetisk, med lenke til legemiddelsiden', async () => {
    renderRoute('/topics/vektendring', { api: { published_claims: [WEIGHT_A, WEIGHT_B] } })
    const groups = await screen.findAllByRole('region')
    expect(
      groups.map((group) => within(group).getByRole('heading', { level: 3 }).textContent),
    ).toEqual(['mirtazapin', 'sertralin'])
    expect(
      within(groups[0] as HTMLElement).getByRole('link', { name: 'mirtazapin' }),
    ).toHaveAttribute('href', '/drugs/mirtazapin')
  })

  it('sier at rekkefølgen ikke er en rangering, og at siden ikke er en sammenligning', async () => {
    // §28: temasiden skal ikke bli en skjult anbefalingsmotor. To virkestoff
    // under samme overskrift ser ut som en sammenligning hvis ingen sier noe.
    renderRoute('/topics/vektendring', { api: { published_claims: [WEIGHT_A, WEIGHT_B] } })
    await screen.findAllByRole('article')
    expect(main()).toHaveTextContent(/alfabetisk rekkefølge. Rekkefølgen er ingen rangering/i)
    expect(main()).toHaveTextContent(/Påstandene under er ikke en sammenligning/i)
    expect(main()).toHaveTextContent(/ulike populasjoner, ulike komparatorer og ulike tidsrammer/i)
  })

  it('merker at objektet er et klinisk tema', async () => {
    // §45: leseren skal forstå hva slags objekt som er åpnet.
    renderRoute('/topics/vektendring', { api: { published_claims: [WEIGHT_A] } })
    await screen.findByRole('heading', { level: 2, name: 'vektendring' })
    expect(main()).toHaveTextContent('Klinisk tema')
  })

  it('bruker samme påstandsobjekter som legemiddelsiden', async () => {
    // Invariant 3: ingen egen tekst for temavisningen.
    renderRoute('/topics/vektendring', { api: { published_claims: [WEIGHT_A] } })
    const article = await screen.findByRole('article')
    expect(article).toHaveTextContent(WEIGHT_A.statement)
  })

  it('temaidentiteten avgjør, ikke etiketten', async () => {
    // To rader med samme etikett, men ulik identitet, er to begreper.
    renderRoute('/topics/vektendring', {
      api: {
        published_claims: [
          WEIGHT_A,
          claimRow({
            claim_id: '22222222-2222-4222-8222-555555555555',
            topic_concept_id: '44444444-4444-4444-8444-999999999999',
            topic_label: 'vektendring',
          }),
        ],
      },
    })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(/peker på flere kliniske begreper/i)
    expect(TEST_TOPIC_IDS.weight).not.toBe('44444444-4444-4444-8444-999999999999')
  })
})
