import { screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { TEST_CLAIM_IDS, claimRow, evidenceRow, renderRoute, type FakeApi } from '../test-support'

// ============================================================================
// Evidensvisningen som side: to spørringer, to tilstandsmaskiner, og de
// fraværstilstandene som ellers ville vært samme tomme skjerm.
// ============================================================================

const CLAIM_ID = TEST_CLAIM_IDS.a
const PATH = `/claims/${CLAIM_ID}/evidence`

function renderEvidence(api: FakeApi) {
  return renderRoute(PATH, { api })
}

/** Seksjonen én av sidens tre h3-er står i. */
function section(heading: string): HTMLElement {
  const element = screen.getByRole('heading', { level: 3, name: heading }).parentElement
  if (element === null) {
    throw new Error(`overskriften «${heading}» har ingen seksjon rundt seg`)
  }
  return element
}

/**
 * Evidensfunnene, i den rekkefølgen de står i evidensseksjonen.
 *
 * Avgrenset til seksjonen, fordi `ClaimCard` også er en `article`: et
 * `getAllByRole('article')` over hele siden ville talt påstandskortet som et
 * evidensfunn, og en test på rekkefølgen ville målt kortet framfor funnene.
 *
 * Ventingen står på kildeoverskriften og ikke på rollen, av samme grunn: kortet
 * er der med én gang, så en venting på `article` ville løst seg før evidensen
 * var hentet — og deretter målt et sett som ennå ikke var komplett.
 */
async function findings(): Promise<HTMLElement[]> {
  await screen.findAllByRole('heading', { level: 4, name: /Testkilde/ })
  return within(section('Evidensgrunnlaget')).getAllByRole('article')
}

const WELL_FORMED: FakeApi = {
  published_claims: [claimRow()],
  published_claim_evidence: [evidenceRow()],
}

describe('påstanden står øverst', () => {
  it('viser påstandens formulering, ikke bare evidensen', async () => {
    // Uten påstanden over seg er et evidensgrunnlag ikke etterprøvbart: leseren
    // har ingenting å prøve funnene mot (§4).
    renderEvidence(WELL_FORMED)
    expect(
      await screen.findByRole('heading', { level: 4, name: /Testpåstand/ }),
    ).toBeInTheDocument()
  })

  it('viser sikkerheten i evidensen sammen med påstanden', async () => {
    renderEvidence(WELL_FORMED)
    expect(await screen.findByText(/Moderat sikkerhet/i)).toBeInTheDocument()
  })

  it('slår opp påstanden på sin stabile identitet', async () => {
    const { queries } = renderEvidence(WELL_FORMED)
    await screen.findByRole('heading', { level: 4, name: /Testpåstand/ })
    const claimQuery = queries.find((query) => query.view === 'published_claims')
    expect(claimQuery?.filters).toEqual([['claim_id', CLAIM_ID]])
  })

  it('lenken «Hvorfor sier Antidep dette?» peker på evidensseksjonen på siden', async () => {
    // Kortet krever `evidenceHref`, og på denne siden *er* veien videre
    // seksjonen lenger nede. Å gjøre lenken valgfri ville latt et kort et annet
    // sted miste den ved en forglemmelse.
    renderEvidence(WELL_FORMED)
    const link = await screen.findByRole('link', { name: /Hvorfor sier Antidep dette\?/ })
    const section = screen.getByRole('heading', { level: 3, name: 'Evidensgrunnlaget' })
    expect(link).toHaveAttribute('href', `#${section.id}`)
  })
})

describe('evidensen', () => {
  it('henter evidensen på samme identitet som påstanden', async () => {
    const { queries } = renderEvidence(WELL_FORMED)
    await findings()
    const evidenceQuery = queries.find((query) => query.view === 'published_claim_evidence')
    expect(evidenceQuery?.filters).toEqual([['claim_id', CLAIM_ID]])
  })

  it('viser støttende og motstridende funn i samme liste', async () => {
    // §9: motstridende evidens skal stå side om side med støttende, ikke i en
    // egen bolk under den.
    renderEvidence({
      published_claims: [claimRow()],
      published_claim_evidence: [
        evidenceRow({ claim_evidence_link_id: 'a', relationship_type: 'supports' }),
        evidenceRow({ claim_evidence_link_id: 'b', relationship_type: 'contradicts' }),
      ],
    })
    const shown = await findings()
    expect(shown).toHaveLength(2)
    expect(shown[0]).toHaveTextContent('Støtter påstanden')
    expect(shown[1]).toHaveTextContent('Motsier påstanden')
  })

  it('sorterer ikke støttende funn først', async () => {
    // Rekkefølgen kommer fra spørringen og bærer ingen mening. En sortering på
    // relasjonstype ville gjort presentasjonsrekkefølgen til en vekting.
    renderEvidence({
      published_claims: [claimRow()],
      published_claim_evidence: [
        evidenceRow({ claim_evidence_link_id: 'a', relationship_type: 'contradicts' }),
        evidenceRow({ claim_evidence_link_id: 'b', relationship_type: 'supports' }),
      ],
    })
    const shown = await findings()
    expect(shown).toHaveLength(2)
    expect(shown[0]).toHaveTextContent('Motsier påstanden')
    expect(shown[1]).toHaveTextContent('Støtter påstanden')
  })

  it('sier at rekkefølgen ikke er en rangering, og at antallet ikke er sikkerhet', async () => {
    renderEvidence(WELL_FORMED)
    await findings()
    const main = screen.getByRole('main')
    expect(main).toHaveTextContent(/verken en rangering/i)
    expect(main).toHaveTextContent(/Antall funn er heller ikke et mål på sikkerhet/i)
  })

  it('sier at dette er hele grunnlaget bak den publiserte revisjonen', async () => {
    // En liste bærer to påstander: rekkefølgen, og at dette er settet.
    renderEvidence(WELL_FORMED)
    await findings()
    expect(screen.getByRole('main')).toHaveTextContent(/hele evidensgrunnlaget/i)
  })
})

describe('fraværstilstandene', () => {
  it('venter framfor å si at det ikke finnes evidens', () => {
    renderEvidence({ published_claims: { pending: true } })
    expect(screen.getByRole('main')).toHaveTextContent(/Henter publisert kunnskap/i)
  })

  it('en ukjent identitet er et utsagn om Antideps innhold, ikke om påstanden', async () => {
    renderEvidence({ published_claims: [] })
    const main = screen.getByRole('main')
    expect(await within(main).findByRole('note')).toHaveTextContent(
      /ingen publisert påstand med identiteten/i,
    )
    expect(main).toHaveTextContent(/utsagn om Antideps innhold/i)
    expect(main).toHaveTextContent(/ikke dokumentasjon på fravær av effekt/i)
  })

  it('en feil er en feil, ikke fravær av kunnskap', async () => {
    renderEvidence({ published_claims: { error: 'nettverksfeil' } })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(/teknisk feil, ikke et svar om at kunnskap mangler/i)
    expect(alert).toHaveTextContent('nettverksfeil')
  })

  it('en publisert påstand uten evidens vises som bruddet det er', async () => {
    // Publiseringsgaten G3 gjør tilstanden umulig. Å vise den som «ingen
    // evidens registrert» ville gjort et brudd til en rolig opplysning.
    renderEvidence({ published_claims: [claimRow()], published_claim_evidence: [] })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(/publisert påstand uten evidensgrunnlag/i)
    expect(alert).toHaveTextContent(/skal ikke kunne skje/i)
  })

  it('to publiserte påstander på samme identitet er et brudd, ikke et valg', async () => {
    renderEvidence({
      published_claims: [claimRow(), claimRow({ claim_revision_id: 'annen' })],
      published_claim_evidence: [evidenceRow()],
    })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(/skal ikke kunne skje/i)
    // Ingen av dem vises: valget ville sett ut som et svar.
    expect(screen.queryByRole('heading', { level: 4, name: /Testpåstand/ })).toBeNull()
  })

  it('en evidensfeil tar ikke ned påstanden over den', async () => {
    renderEvidence({
      published_claims: [claimRow()],
      published_claim_evidence: { error: 'tidsavbrudd' },
    })
    expect(
      await screen.findByRole('heading', { level: 4, name: /Testpåstand/ }),
    ).toBeInTheDocument()
    expect(await screen.findByRole('alert')).toHaveTextContent('tidsavbrudd')
  })
})

describe('tidspunktene', () => {
  it('viser publiseringstidspunktet, som kortet med vilje utelater', async () => {
    renderEvidence(WELL_FORMED)
    await findings()
    expect(section('Tidspunkter')).toHaveTextContent('20. august 2026')
  })

  it('«ukjent» er ikke «ikke vurdert» og ikke en fersk dato', async () => {
    renderEvidence({
      published_claims: [claimRow({ published_at: null, last_reviewed_at: null })],
      published_claim_evidence: [evidenceRow()],
    })
    await findings()
    expect(section('Tidspunkter')).toHaveTextContent('Ukjent')
  })

  it('sier hvilken revisjon evidensgrunnlaget hører til', async () => {
    renderEvidence({
      published_claims: [claimRow({ revision_number: 3 })],
      published_claim_evidence: [evidenceRow()],
    })
    await findings()
    expect(screen.getByRole('main')).toHaveTextContent('Revisjon 3 av påstanden')
  })

  it('nevner ingen aktør og ingen beslutningstype fra reviewhistorikken', async () => {
    // §58: bare tidsstempler er offentlig. Å utvide det er en
    // governance-endring, ikke en UI-oppgave.
    renderEvidence(WELL_FORMED)
    await findings()
    const main = screen.getByRole('main')
    expect(main).not.toHaveTextContent(/godkjent av/i)
    expect(main).not.toHaveTextContent(/redaktør/i)
    expect(main).not.toHaveTextContent(/changes_requested|source_verified/i)
  })
})

describe('overskriftshierarkiet', () => {
  it('legger seksjonene på h3 og påstanden på h4', async () => {
    // h1 er produktet, h2 er siden, h3 er seksjonen, h4 er påstanden og funnet.
    renderEvidence(WELL_FORMED)
    await findings()
    expect(
      screen.getByRole('heading', { level: 2, name: /Hvorfor sier Antidep dette/ }),
    ).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 3, name: 'Påstanden' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 4, name: /Testpåstand/ })).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 4, name: /Testkilde A/ })).toBeInTheDocument()
  })
})

describe('dokumenttittelen', () => {
  it('navngir hva evidensen gjelder, ikke identiteten fra adressen', async () => {
    renderEvidence(WELL_FORMED)
    await findings()
    expect(document.title).toBe('vektendring – virkestoff a – Antidep')
  })

  it('står nøytralt når identiteten ikke traff', async () => {
    renderEvidence({ published_claims: [] })
    await screen.findByRole('note')
    expect(document.title).toBe('Evidensgrunnlag – Antidep')
    expect(document.title).not.toContain(CLAIM_ID)
  })
})
