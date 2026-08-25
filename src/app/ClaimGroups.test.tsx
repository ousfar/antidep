import { render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { describe, expect, it } from 'vitest'
import { ClaimGroups, type ClaimGroupAxis } from './ClaimGroups'
import { TEST_DRUG_IDS, claimRow } from './test-support'
import type { PublishedClaimRow } from '../types/api'

function renderGroups(claims: readonly PublishedClaimRow[], axis: ClaimGroupAxis) {
  return render(
    <MemoryRouter>
      <ClaimGroups axis={axis} claims={claims} />
    </MemoryRouter>,
  )
}

const A = claimRow({ drug_name: 'sertralin', topic_label: 'vektendring' })
const B = claimRow({
  claim_id: '22222222-2222-4222-8222-222222222222',
  drug_id: TEST_DRUG_IDS.b,
  drug_name: 'mirtazapin',
  topic_concept_id: '44444444-4444-4444-8444-222222222222',
  topic_label: 'sedasjon',
  statement: 'Testpåstand B.',
})

function headings(): (string | null)[] {
  return screen.getAllByRole('heading', { level: 3 }).map((heading) => heading.textContent)
}

describe('gruppering', () => {
  it('sorterer alfabetisk uavhengig av rekkefølgen den fikk inn', () => {
    // Påstanden om rekkefølgen skal være sann uten å hvile på spørringen.
    renderGroups([A, B], 'drug')
    expect(headings()).toEqual(['mirtazapin', 'sertralin'])
  })

  it('sorterer også når rekkefølgen inn allerede er motsatt', () => {
    renderGroups([B, A], 'topic')
    expect(headings()).toEqual(['sedasjon', 'vektendring'])
  })

  it('sorterer påstandene innenfor en gruppe alfabetisk', () => {
    const first = claimRow({ statement: 'Alfa testpåstand.' })
    const second = claimRow({
      claim_id: '22222222-2222-4222-8222-777777777777',
      statement: 'Beta testpåstand.',
    })
    renderGroups([second, first], 'topic')
    const statements = screen
      .getAllByRole('heading', { level: 4 })
      .map((heading) => heading.textContent)
    expect(statements).toEqual(['Alfa testpåstand.', 'Beta testpåstand.'])
  })

  it('sorterer etter norsk alfabet, ikke etter tegnverdi', () => {
    // æ, ø, å står sist og i den rekkefølgen i norsk. En sortering på
    // tegnverdi ville gitt å før ø, og en liste en norsk leser leser som
    // usortert, ser ut som en liste sortert etter noe annet — for eksempel
    // etter viktighet (produktinvariant 14).
    const edema = claimRow({
      topic_concept_id: '44444444-4444-4444-8444-555555555555',
      topic_label: 'ødem',
    })
    const dyspnea = claimRow({
      claim_id: '22222222-2222-4222-8222-666666666666',
      topic_concept_id: '44444444-4444-4444-8444-666666666666',
      topic_label: 'åndenød',
    })
    renderGroups([dyspnea, edema], 'topic')
    expect(headings()).toEqual(['ødem', 'åndenød'])
  })

  it('grupperer på identitet, ikke på etikett', () => {
    // To virkestoff med samme navn er fortsatt to virkestoff. Å slå dem sammen
    // ville gjort to rader til én overskrift.
    const sameName = claimRow({
      claim_id: '22222222-2222-4222-8222-888888888888',
      drug_id: TEST_DRUG_IDS.b,
      drug_name: 'sertralin',
      statement: 'Testpåstand fra et annet virkestoff med samme navn.',
    })
    renderGroups([A, sameName], 'drug')
    expect(screen.getAllByRole('heading', { level: 3 })).toHaveLength(2)
  })

  it('gruppeoverskriften er inngangen til den andre aksen', () => {
    const byTopic = renderGroups([A], 'topic')
    expect(within(byTopic.container).getByRole('link', { name: 'vektendring' })).toHaveAttribute(
      'href',
      '/topics/vektendring',
    )
    byTopic.unmount()

    const byDrug = renderGroups([A], 'drug')
    expect(within(byDrug.container).getByRole('link', { name: 'sertralin' })).toHaveAttribute(
      'href',
      '/drugs/sertralin',
    )
  })

  it('påstanden ligger under gruppen sin i overskriftshierarkiet', () => {
    // h1 produkt, h2 side, h3 gruppe, h4 påstand. Et hopp gir feil disposisjon
    // for en skjermleser (§50, §53).
    renderGroups([A], 'topic')
    const group = screen.getByRole('region')
    expect(within(group).getByRole('heading', { level: 3 })).toHaveTextContent('vektendring')
    expect(within(group).getByRole('heading', { level: 4 })).toHaveTextContent(A.statement)
  })

  it('sier at rekkefølgen ikke er en rangering på begge akser', () => {
    const byTopic = renderGroups([A], 'topic')
    expect(byTopic.container).toHaveTextContent(
      /Rekkefølgen er ikke en prioritering av klinisk viktighet/i,
    )
    byTopic.unmount()

    const byDrug = renderGroups([A], 'drug')
    expect(byDrug.container).toHaveTextContent(/Rekkefølgen er ingen rangering/i)
  })

  it('sier at listen er Antideps innhold, ikke et fullstendig sett', () => {
    // En liste er to påstander på én gang: rekkefølgen, og at dette er settet.
    // Den andre er den farligste — to virkestoff under et tema leses som at de
    // øvrige ikke har temaet (§65 «No-data-as-zero»).
    const byTopic = renderGroups([A], 'topic')
    expect(byTopic.container).toHaveTextContent(
      /ingen fullstendig oversikt over kliniske forhold ved virkestoffet/i,
    )
    byTopic.unmount()

    const byDrug = renderGroups([A], 'drug')
    expect(byDrug.container).toHaveTextContent(
      /at et virkestoff ikke står her, betyr ikke at temaet ikke gjelder for det/i,
    )
  })

  it('sammenligningsforbeholdet står bare der flere virkestoff stilles opp', () => {
    // Under ett virkestoff er flere temaer ikke en sammenligning, og
    // forbeholdet ville vært støy som svekker det der det gjelder.
    const byDrug = renderGroups([A, B], 'drug')
    expect(byDrug.container).toHaveTextContent(/ikke en sammenligning/i)
    byDrug.unmount()

    const byTopic = renderGroups([A, B], 'topic')
    expect(byTopic.container).not.toHaveTextContent(/ikke en sammenligning/i)
  })

  it('hvert kort har veien til evidensen, adressert med påstandens identitet', () => {
    renderGroups([A], 'topic')
    expect(screen.getByRole('link', { name: /Hvorfor sier Antidep dette\?/i })).toHaveAttribute(
      'href',
      `/claims/${A.claim_id}/evidence`,
    )
  })
})
