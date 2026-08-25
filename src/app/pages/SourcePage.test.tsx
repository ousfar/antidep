import { screen, waitFor, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import {
  TEST_CLAIM_IDS,
  TEST_DRUG_IDS,
  TEST_REVISION_IDS,
  TEST_SOURCE_IDS,
  claimRow,
  evidenceRow,
  renderRoute,
  type FakeApi,
} from '../test-support'

// ============================================================================
// Kildesiden som side.
//
// To spørringer, som evidensvisningen — men den andre er hele det publiserte
// settet, og koblingen skjer i klienten. Testene her handler derfor like mye om
// koblingen som om presentasjonen: en påstand som skifter mellom de to
// spørringene, må ikke kunne gi et funn under feil formulering.
// ============================================================================

const SOURCE_ID = TEST_SOURCE_IDS.a
const PATH = `/sources/${SOURCE_ID}`

function renderSource(api: FakeApi) {
  return renderRoute(PATH, { api })
}

/** Seksjonen én av sidens to h3-er står i. */
function section(heading: string): HTMLElement {
  const element = screen.getByRole('heading', { level: 3, name: heading }).parentElement
  if (element === null) {
    throw new Error(`overskriften «${heading}» har ingen seksjon rundt seg`)
  }
  return element
}

/** Teksten i `<dd>`-en som hører til én `<dt>`, innenfor ett område. */
function detail(scope: HTMLElement, label: string): string {
  const terms = [...scope.querySelectorAll('dt')]
  const term = terms.find((dt) => dt.textContent === label)
  if (term === undefined) {
    throw new Error(
      `fant ingen detalj «${label}». Detaljene som finnes: ${terms
        .map((dt) => dt.textContent)
        .join(', ')}`,
    )
  }
  return term.nextElementSibling?.textContent ?? ''
}

/**
 * Funnene fra denne kilden, gruppert per påstand.
 *
 * Avgrenset til gruppene, fordi `ClaimCard` er en `article`: et
 * `getAllByRole('article')` over seksjonen ville talt påstandskortene som funn.
 */
async function usageGroups(): Promise<HTMLElement[]> {
  await screen.findAllByRole('group', { name: 'Funn fra denne kilden' })
  return screen.getAllByRole('group', { name: 'Funn fra denne kilden' })
}

/** Den ene gruppen, når testen forutsetter at det bare er én. */
async function onlyUsageGroup(): Promise<HTMLElement> {
  const groups = await usageGroups()
  const [group] = groups
  if (group === undefined || groups.length !== 1) {
    throw new Error(`ventet nøyaktig én bruk av kilden, fant ${groups.length}`)
  }
  return group
}

const WELL_FORMED: FakeApi = {
  published_claims: [claimRow()],
  published_claim_evidence: [evidenceRow()],
}

describe('forutsetningene testene hviler på', () => {
  it('grunnfiksturen gir en kilde med én bruk og ingen kontraktsbrudd', async () => {
    // Uten denne kunne testene under passert fordi *alt* ble en feiltilstand.
    renderSource(WELL_FORMED)
    expect(
      await screen.findByRole('heading', {
        level: 2,
        name: 'Testkilde A: vektendring ved åtte uker',
      }),
    ).toBeInTheDocument()
    expect(await usageGroups()).toHaveLength(1)
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })
})

describe('oppslaget', () => {
  it('henter kilden ved å filtrere evidensradene på kildens identitet', async () => {
    const { queries } = renderSource(WELL_FORMED)
    await usageGroups()
    const evidence = queries.find((query) => query.view === 'published_claim_evidence')
    expect(evidence?.filters).toEqual([['source_id', SOURCE_ID]])
    // Stabil rekkefølge mellom kall, uten mening: rekkefølgen leseren ser,
    // settes i visningen.
    expect(evidence?.orders).toEqual([['claim_evidence_link_id', true]])
  })

  it('en kilde uten publisert bruk er et utsagn om Antideps innhold', async () => {
    renderSource({ published_claim_evidence: [] })
    const notice = await screen.findByRole('note')
    expect(notice).toHaveTextContent(SOURCE_ID)
    expect(notice).toHaveTextContent(/utsagn om Antideps innhold/)
    // Forbeholdet som skiller «ikke publisert» fra «trygt».
    expect(notice).toHaveTextContent(/ikke dokumentasjon på fravær av effekt/)
  })

  it('en feil er en feil, ikke fravær av kunnskap', async () => {
    renderSource({ published_claim_evidence: { error: 'nettverket svarte ikke' } })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent('nettverket svarte ikke')
    expect(alert).toHaveTextContent(/teknisk feil, ikke et svar om at kunnskap mangler/)
  })

  it('ventetilstanden er ikke tomhet', () => {
    renderSource({ published_claim_evidence: { pending: true } })
    expect(screen.getByText(/Henter publisert kunnskap/)).toBeInTheDocument()
  })

  it('setter dokumenttittelen til kildens tittel', async () => {
    renderSource(WELL_FORMED)
    await waitFor(() => {
      expect(document.title).toBe('Testkilde A: vektendring ved åtte uker – Antidep')
    })
  })

  it('en adresse uten treff gir ingen tittel Antidep ser ut til å hevde', async () => {
    renderSource({ published_claim_evidence: [] })
    await screen.findByRole('note')
    expect(document.title).toBe('Kilde – Antidep')
    expect(screen.getByRole('heading', { level: 2, name: 'Kilde' })).toBeInTheDocument()
  })
})

describe('publikasjonen', () => {
  it('beskriver dokumentet, ikke hva Antidep mener det viser', async () => {
    renderSource(WELL_FORMED)
    await usageGroups()
    const publication = section('Publikasjonen')
    expect(detail(publication, 'Dokumenttype')).toBe('Fagfellevurdert artikkel')
    expect(detail(publication, 'Forfattere eller utgiver')).toBe('Testforfatter m.fl.')
    expect(detail(publication, 'Tidsskrift eller utgiver')).toBe('Testtidsskrift')
  })

  it('viser datoen med nøyaktig den presisjonen den har', async () => {
    // Fiksturen er månedspresis. Vist som hel dato ville «mars 2019» blitt
    // «1. mars 2019» — falsk presisjon som ikke ser ut som en feil (§6).
    renderSource(WELL_FORMED)
    await usageGroups()
    expect(detail(section('Publikasjonen'), 'Publisert')).toBe('mars 2019')
  })

  it('skriver ut kildestatusen også når den er normal', async () => {
    // En status som bare vises når den er avvikende, gjør fravær av merking til
    // en påstand ingen har tatt stilling til.
    renderSource(WELL_FORMED)
    await usageGroups()
    expect(detail(section('Publikasjonen'), 'Kildestatus')).toBe('I bruk')
  })

  it('en tilbaketrukket kilde vises som tilbaketrukket, med begrunnelsen', async () => {
    renderSource({
      published_claims: [claimRow()],
      published_claim_evidence: [
        evidenceRow({
          source_status: 'retracted',
          source_status_note: 'Trukket av tidsskriftet i 2021.',
        }),
      ],
    })
    await usageGroups()
    const status = detail(section('Publikasjonen'), 'Kildestatus')
    expect(status).toContain('Trukket tilbake av tidsskrift eller utgiver')
    expect(status).toContain('Trukket av tidsskriftet i 2021.')
  })

  it('en erstattet kilde sier at etterfølgeren ikke kan navngis her', async () => {
    // Statusen betyr at en *bestemt* nyere kilde er registrert, men pekeren er
    // ikke i api-kontrakten. Etiketten alene ville vært en halv sannhet.
    renderSource({
      published_claims: [claimRow()],
      published_claim_evidence: [
        evidenceRow({
          source_status: 'superseded',
          source_status_note: 'Erstattet av 2024-utgaven.',
        }),
      ],
    })
    await usageGroups()
    const status = detail(section('Publikasjonen'), 'Kildestatus')
    expect(status).toContain('Erstattet av en nyere kilde')
    expect(status).toContain('lesemodellen eksponerer den ikke, så den kan ikke navngis her')
  })

  it('gjør identifikatorene om til lenker til originalen', async () => {
    renderSource({
      published_claims: [claimRow()],
      published_claim_evidence: [
        evidenceRow({ source_dois: ['10.1000/abc'], source_pmids: ['12345678'] }),
      ],
    })
    await usageGroups()
    const publication = section('Publikasjonen')
    expect(within(publication).getByRole('link', { name: '10.1000/abc' })).toHaveAttribute(
      'href',
      'https://doi.org/10.1000/abc',
    )
    expect(within(publication).getByRole('link', { name: '12345678' })).toHaveAttribute(
      'href',
      'https://pubmed.ncbi.nlm.nih.gov/12345678/',
    )
    // Leseren skal vite at lenken går ut av Antidep.
    expect(detail(publication, 'DOI')).toContain('utenfor Antidep')
  })

  it('en identifikator utenfor den registrerte formen vises, men lenkes ikke', async () => {
    renderSource({
      published_claims: [claimRow()],
      published_claim_evidence: [evidenceRow({ source_dois: ['ikke-en-doi'] })],
    })
    await usageGroups()
    const publication = section('Publikasjonen')
    expect(within(publication).queryByRole('link', { name: 'ikke-en-doi' })).not.toBeInTheDocument()
    expect(detail(publication, 'DOI')).toContain('ikke-en-doi')
    expect(detail(publication, 'DOI')).toContain('ikke gjort om til en lenke')
  })

  it('sier at ingen identifikator er registrert i Antidep', async () => {
    // Ikke det samme som at kilden mangler en.
    renderSource(WELL_FORMED)
    await usageGroups()
    expect(detail(section('Publikasjonen'), 'PMID')).toContain('registrert i Antidep')
  })
})

describe('hva Antidep bruker kilden til', () => {
  it('viser påstanden med sikkerhetsgraden sin, ikke bare formuleringen', async () => {
    // Formuleringen alene ville stått uten sikkerhet, anvendelsesområde og
    // forbehold — altså som en påstand mer skråsikker enn den er.
    renderSource(WELL_FORMED)
    await usageGroups()
    const usage = section('Hva Antidep bruker kilden til')
    expect(
      within(usage).getByRole('heading', {
        level: 4,
        name: /Virkestoff A er assosiert med større vektøkning/,
      }),
    ).toBeInTheDocument()
    expect(usage).toHaveTextContent(/[Mm]oderat sikkerhet/)
    expect(usage).toHaveTextContent('Voksne, korttidsbehandling ved depresjon')
  })

  it('lenker videre til evidensvisningen for påstanden', async () => {
    renderSource(WELL_FORMED)
    await usageGroups()
    const link = within(section('Hva Antidep bruker kilden til')).getByRole('link', {
      name: /Hvorfor sier Antidep dette\?/,
    })
    expect(link).toHaveAttribute('href', `/claims/${TEST_CLAIM_IDS.a}/evidence`)
  })

  it('navngir virkestoffet og temaet påstanden hører til', async () => {
    // Kortet bærer dem ikke selv, og her står påstander om flere virkestoff
    // under én overskrift.
    renderSource(WELL_FORMED)
    await usageGroups()
    const usage = section('Hva Antidep bruker kilden til')
    expect(within(usage).getByRole('link', { name: 'virkestoff a' })).toHaveAttribute(
      'href',
      '/drugs/virkestoff-a',
    )
    expect(within(usage).getByRole('link', { name: 'vektendring' })).toHaveAttribute(
      'href',
      '/topics/vektendring',
    )
  })

  it('sier hva listen er, at rekkefølgen ikke er en rangering, og hva den ikke er', async () => {
    renderSource(WELL_FORMED)
    await usageGroups()
    const usage = section('Hva Antidep bruker kilden til')
    expect(usage).toHaveTextContent(
      /de publiserte påstandene som hviler på minst ett evidensfunn fra denne kilden/,
    )
    expect(usage).toHaveTextContent(
      /verken en rangering eller et uttrykk for hvor tungt kilden veier/,
    )
    // Halesetningen: siden er Antideps bruk av kilden, ikke kildens innhold.
    expect(usage).toHaveTextContent(
      /Listen sier hva Antidep bruker kilden til, ikke hva kilden selv konkluderer med/,
    )
  })

  it('sier at påstandene ikke er en sammenligning', async () => {
    renderSource(WELL_FORMED)
    await usageGroups()
    expect(section('Hva Antidep bruker kilden til')).toHaveTextContent(
      /Påstandene under er ikke en sammenligning/,
    )
  })

  it('et motstridende funn står som motstridende, ikke som støtte', async () => {
    renderSource({
      published_claims: [claimRow()],
      published_claim_evidence: [evidenceRow({ relationship_type: 'contradicts' })],
    })
    const group = await onlyUsageGroup()
    expect(group).toHaveTextContent('Motsier påstanden')
    expect(group).not.toHaveTextContent('Støtter påstanden')
  })

  it('en ukjent relasjonstype leses ikke som støtte', async () => {
    renderSource({
      published_claims: [claimRow()],
      published_claim_evidence: [
        evidenceRow({
          relationship_type: 'endorses' as never,
        }),
      ],
    })
    const group = await onlyUsageGroup()
    expect(group).toHaveTextContent('ikke tolkbar')
    expect(group).not.toHaveTextContent('Støtter påstanden')
  })

  it('viser hvor i kilden funnet står, og hvilken versjon det ble lest ut av', async () => {
    renderSource(WELL_FORMED)
    const group = await onlyUsageGroup()
    expect(detail(group, 'Sted i kilden')).toBe('Tabell 2, side 114')
    expect(detail(group, 'Kildeversjon')).toContain('betyr ikke at kilden er uendret')
  })

  it('gjentar ikke evidensvisningen', async () => {
    // §42 skiller de to: hvorfor funnet støtter påstanden — populasjon,
    // komparator, resultat, presisjon — hører til evidenssiden, og herfra går
    // det en lenke dit.
    renderSource(WELL_FORMED)
    const group = await onlyUsageGroup()
    expect(group).not.toHaveTextContent('Gjennomsnittsforskjell')
    expect(group).not.toHaveTextContent('voksne med depresjon')
  })

  it('en tilbaketrukket ekstraksjon merkes, den skjules ikke', async () => {
    renderSource({
      published_claims: [claimRow()],
      published_claim_evidence: [
        evidenceRow({
          extraction_withdrawn: true,
          extraction_withdrawn_at: '2026-08-22T08:00:00Z',
          extraction_withdrawal_rationale: 'Feil kolonne lest ut av tabellen.',
        }),
      ],
    })
    const group = await onlyUsageGroup()
    expect(group).toHaveTextContent(/trukket tilbake denne ekstraksjonen/i)
    expect(group).toHaveTextContent('22. august 2026')
    expect(group).toHaveTextContent('Feil kolonne lest ut av tabellen.')
    // Funnet står fortsatt: påstanden over det er fortsatt publisert.
    expect(detail(group, 'Sted i kilden')).toBe('Tabell 2, side 114')
  })

  it('to funn fra samme kilde på samme påstand står under ett kort', async () => {
    renderSource({
      published_claims: [claimRow()],
      published_claim_evidence: [
        evidenceRow({ source_locator: 'Tabell 2, side 114' }),
        evidenceRow({
          claim_evidence_link_id: '55555555-5555-4555-8555-222222222222',
          evidence_item_id: '66666666-6666-4666-8666-222222222222',
          source_locator: 'Tabell 5, side 120',
        }),
      ],
    })
    const groups = await usageGroups()
    expect(groups).toHaveLength(1)
    expect(groups[0]).toHaveTextContent('Tabell 2, side 114')
    expect(groups[0]).toHaveTextContent('Tabell 5, side 120')
  })

  it('sorterer påstandene alfabetisk med norsk kollasjon', async () => {
    // «Aaland» skal sorteres som «Åland» og dermed stå etter «Bly», mens en
    // sortering på tegnverdi ville satt den først. En liste en norsk leser leser
    // som usortert, ser ut som en liste sortert etter noe annet — for eksempel
    // etter hvor tungt kilden veier.
    renderSource({
      published_claims: [
        claimRow({ statement: 'Åpen testpåstand om virkestoff A.' }),
        claimRow({ claim_id: TEST_CLAIM_IDS.b, statement: 'Bly-testpåstand om virkestoff A.' }),
        claimRow({ claim_id: TEST_CLAIM_IDS.c, statement: 'Aaland-testpåstand om virkestoff A.' }),
      ],
      published_claim_evidence: [
        evidenceRow(),
        evidenceRow({
          claim_id: TEST_CLAIM_IDS.b,
          claim_evidence_link_id: '55555555-5555-4555-8555-333333333333',
        }),
        evidenceRow({
          claim_id: TEST_CLAIM_IDS.c,
          claim_evidence_link_id: '55555555-5555-4555-8555-666666666666',
        }),
      ],
    })
    await usageGroups()
    const headings = within(section('Hva Antidep bruker kilden til'))
      .getAllByRole('heading', { level: 4 })
      .map((heading) => heading.textContent)
    expect(headings).toEqual([
      'Bly-testpåstand om virkestoff A.',
      'Aaland-testpåstand om virkestoff A.',
      'Åpen testpåstand om virkestoff A.',
    ])
  })

  it('påstander om ulike virkestoff navngir hvert sitt', async () => {
    renderSource({
      published_claims: [
        claimRow({ statement: 'A-testpåstand.' }),
        claimRow({
          claim_id: TEST_CLAIM_IDS.b,
          drug_id: TEST_DRUG_IDS.b,
          drug_name: 'virkestoff b',
          statement: 'B-testpåstand.',
        }),
      ],
      published_claim_evidence: [
        evidenceRow(),
        evidenceRow({
          claim_id: TEST_CLAIM_IDS.b,
          claim_evidence_link_id: '55555555-5555-4555-8555-444444444444',
        }),
      ],
    })
    await usageGroups()
    const usage = section('Hva Antidep bruker kilden til')
    expect(within(usage).getByRole('link', { name: 'virkestoff a' })).toBeInTheDocument()
    expect(within(usage).getByRole('link', { name: 'virkestoff b' })).toBeInTheDocument()
  })
})

describe('de to spørringene kan se hver sin tilstand', () => {
  it('et funn fra en annen revisjon enn den publiserte vises ikke', async () => {
    // Publiseres påstanden på nytt mellom de to spørringene, ville funnet stått
    // som grunnlag for en formulering det aldri var lenket til (§4).
    renderSource({
      published_claims: [claimRow()],
      published_claim_evidence: [
        evidenceRow({ claim_revision_id: '33333333-3333-4333-8333-999999999999' }),
      ],
    })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(/publisert på nytt mens siden lastet/)
    expect(alert).toHaveTextContent(/Last siden på nytt/)
    expect(screen.queryByRole('group', { name: 'Funn fra denne kilden' })).not.toBeInTheDocument()
  })

  it('hele listen forkastes, ikke bare den påstanden som skiftet', async () => {
    // En liste der én påstand er utelatt, sier at kilden brukes til færre ting
    // enn den gjør. Et blandet sett er verre enn ingen.
    renderSource({
      published_claims: [
        claimRow(),
        claimRow({ claim_id: TEST_CLAIM_IDS.b, statement: 'Uberørt testpåstand.' }),
      ],
      published_claim_evidence: [
        evidenceRow({ claim_revision_id: '33333333-3333-4333-8333-999999999999' }),
        evidenceRow({
          claim_id: TEST_CLAIM_IDS.b,
          claim_evidence_link_id: '55555555-5555-4555-8555-555555555555',
        }),
      ],
    })
    await screen.findByRole('alert')
    expect(screen.queryByText('Uberørt testpåstand.')).not.toBeInTheDocument()
  })

  it('en påstand som ikke lenger står publisert, har sin egen ordlyd', async () => {
    // En annen årsak enn en ny revisjon, og de to må ikke dele ordlyd.
    renderSource({
      published_claims: [claimRow({ claim_id: TEST_CLAIM_IDS.b })],
      published_claim_evidence: [evidenceRow()],
    })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(/stod ikke lenger i det publiserte settet/)
    expect(alert).not.toHaveTextContent(/publisert på nytt/)
  })

  it('funn uten noen publiserte påstander i det hele tatt er et kontraktsbrudd', async () => {
    // Et funn står i `api` bare fordi det er lenket til en publisert påstand.
    // Vist som en rolig opplysning ville bruddet sett ut som at kilden ikke
    // brukes til noe.
    renderSource({ published_claims: [], published_claim_evidence: [evidenceRow()] })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(/skal ikke kunne skje/)
    expect(alert).toHaveTextContent(/ingen publiserte påstander/)
  })

  it('en feil i påstandsspørringen tar ikke ned publikasjonen', async () => {
    renderSource({
      published_claims: { error: 'tidsavbrudd' },
      published_claim_evidence: [evidenceRow()],
    })
    expect(await screen.findByRole('alert')).toHaveTextContent('tidsavbrudd')
    expect(detail(section('Publikasjonen'), 'Dokumenttype')).toBe('Fagfellevurdert artikkel')
  })

  it('sammenligningen er på revisjonen, ikke et filter i spørringen', async () => {
    // Et `eq('claim_revision_id', …)` ville gjort skiftet til et tomt svar, og
    // tomt betyr allerede noe helt annet her.
    const { queries } = renderSource(WELL_FORMED)
    await usageGroups()
    const claims = queries.find((query) => query.view === 'published_claims')
    expect(claims?.filters).toEqual([])
  })
})

describe('overskriftshierarkiet', () => {
  it('h2 er siden, h3 er seksjonene, h4 er påstanden, h5 er funnene under den', async () => {
    renderSource(WELL_FORMED)
    await usageGroups()
    const main = screen.getByRole('main')
    expect(
      within(main).getByRole('heading', {
        level: 2,
        name: 'Testkilde A: vektendring ved åtte uker',
      }),
    ).toBeInTheDocument()
    expect(
      within(main)
        .getAllByRole('heading', { level: 3 })
        .map((heading) => heading.textContent),
    ).toEqual(['Publikasjonen', 'Hva Antidep bruker kilden til'])
    expect(within(main).getAllByRole('heading', { level: 4 })).toHaveLength(1)
    expect(
      within(main).getByRole('heading', { level: 5, name: 'Funn fra denne kilden' }),
    ).toBeInTheDocument()
  })
})

describe('vaktpost på fiksturen', () => {
  it('revisjonen fiksturen bruker, er den samme i begge radene', () => {
    // Vaktpost for testene over: skilte fiksturene lag, ville skjevhetstestene
    // ha målt en skjevhet som alltid var der.
    expect(claimRow().claim_revision_id).toBe(TEST_REVISION_IDS.a)
    expect(evidenceRow().claim_revision_id).toBe(TEST_REVISION_IDS.a)
  })
})
