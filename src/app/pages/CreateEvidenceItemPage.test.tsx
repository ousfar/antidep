import { fireEvent, screen, waitFor, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import {
  TEST_EDITOR_IDS,
  TEST_USER_IDS,
  editorDrugRow,
  editorEvidenceItemRow,
  editorOutcomeRow,
  editorPopulationRow,
  editorSourceRow,
  editorSourceVersionRow,
  renderRoute,
  type FakeApi,
} from '../test-support'
import type { RecordedRpcCall } from '../test-support'

// ============================================================================
// Registrer evidensfunn — steg 3 av adminflyten (§29).
//
// Testene dekker fire ting: innloggingsgaten, at oppslagene faktisk styrer
// skjemaet, at null/ukjent-semantikken ikke kan brytes fra skjemaet, og at
// bekreftelsen viser funnet under riktig kilde.
// ============================================================================

const LOOKUPS: FakeApi = {
  editor_sources: [editorSourceRow()],
  editor_drugs: [editorDrugRow()],
  editor_outcomes: [editorOutcomeRow()],
  editor_populations: [editorPopulationRow()],
}

function lastCallArgs(calls: readonly RecordedRpcCall[]): Record<string, unknown> | undefined {
  return calls.at(-1)?.args as Record<string, unknown> | undefined
}

/**
 * Velger kilden, venter til kildeversjonsoppslaget har svart, og fyller ut
 * resten av de påkrevde feltene.
 *
 * Ventingen er ikke testrigging for sin egen skyld: skjemaet blokkerer
 * innsending mens oppslaget står på, fordi et funn registrert med
 * `source_version_id = null` før svaret er kommet, ville påstått noe ingen vet
 * — og evidensfunn er uforanderlige.
 */
async function fillRequiredFields() {
  selectSource()
  await waitFor(() => {
    expect(screen.getByLabelText('Kildeversjon (valgfritt)')).not.toBeDisabled()
  })
  fillFieldsBesidesSource()
}

function selectSource() {
  fireEvent.change(screen.getByLabelText('Kilde'), {
    target: { value: TEST_EDITOR_IDS.source },
  })
}

/** Alt utenom kilden. Brukes der kildeversjonsoppslaget med hensikt står uløst. */
function fillFieldsBesidesSource() {
  fireEvent.change(screen.getByLabelText('Hvor i kilden står funnet?'), {
    target: { value: 'Tabell 2, side 5' },
  })
  fireEvent.change(screen.getByLabelText('Populasjonen slik kilden beskriver den'), {
    target: { value: 'Voksne i poliklinisk behandling.' },
  })
  fireEvent.change(screen.getByLabelText('Virkestoff'), {
    target: { value: editorDrugRow().drug_id },
  })
  fireEvent.change(screen.getByLabelText('Endepunkt'), {
    target: { value: editorOutcomeRow().outcome_concept_id },
  })
  fireEvent.change(screen.getByLabelText('Hva ble faktisk målt?'), {
    target: { value: 'Gjennomsnittlig vektendring i kilogram.' },
  })
}

function submit() {
  fireEvent.click(screen.getByRole('button', { name: 'Registrer evidensfunn' }))
}

describe('Registrer evidensfunn — ikke innlogget', () => {
  it('viser en henvisning til Min tilgang, ikke skjemaet', async () => {
    const { rpcCalls } = renderRoute('/evidence/new', { api: LOOKUPS })
    expect(
      await screen.findByText('Du må logge inn for å registrere et evidensfunn.'),
    ).toBeInTheDocument()
    expect(screen.queryByLabelText('Kilde')).not.toBeInTheDocument()
    expect(rpcCalls).toEqual([])
  })
})

describe('Registrer evidensfunn — innlogget, ingen rollegate i klienten', () => {
  it('viser skjemaet uten å spørre om kallerens roller', async () => {
    // Samme doktrine som Opprett kilde: retten avgjøres av
    // knowledge.assert_editor_authorized(uuid) på serveren, og her avhenger den
    // dessuten av endepunktet — noe klienten uansett ikke kan regne ut.
    const { queries } = renderRoute('/evidence/new', {
      api: LOOKUPS,
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    expect(await screen.findByLabelText('Kilde')).toBeInTheDocument()
    expect(queries.some((query) => query.view === 'my_roles')).toBe(false)
  })

  it('sier fra når kalleren ikke ser noe å registrere mot, framfor å vise et tomt skjema', async () => {
    // RLS gir en kaller uten editor-rolle null kilder. Et skjema med tomme
    // nedtrekkslister ville sett ut som om kunnskapsbasen var tom.
    renderRoute('/evidence/new', {
      api: { ...LOOKUPS, editor_sources: [] },
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    expect(
      await screen.findByText(
        'Du har ingen kilder, virkestoff eller endepunkter å registrere et evidensfunn mot.',
      ),
    ).toBeInTheDocument()
    expect(screen.queryByLabelText('Kilde')).not.toBeInTheDocument()
  })

  it('en avvist spørring vises som feil, ikke som tomhet', async () => {
    renderRoute('/evidence/new', {
      api: { ...LOOKUPS, editor_drugs: { error: 'permission denied for view editor_drugs' } },
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    expect(
      await screen.findByText('Antidep fikk ikke hentet det du kan registrere mot.'),
    ).toBeInTheDocument()
    expect(screen.getByText(/permission denied for view editor_drugs/)).toBeInTheDocument()
  })
})

describe('null/ukjent-semantikken i skjemaet', () => {
  it('viser verdifeltet bare når statusen sier at kilden oppgir en verdi', async () => {
    renderRoute('/evidence/new', { api: LOOKUPS, auth: { initialUserId: TEST_USER_IDS.a } })
    await screen.findByLabelText('Kilde')

    expect(screen.queryByLabelText('Antall deltakere')).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Antall deltakere analysen omfatter'), {
      target: { value: 'reported_value' },
    })
    expect(screen.getByLabelText('Antall deltakere')).toBeInTheDocument()

    fireEvent.change(screen.getByLabelText('Antall deltakere analysen omfatter'), {
      target: { value: 'not_measured' },
    })
    expect(screen.queryByLabelText('Antall deltakere')).not.toBeInTheDocument()
  })

  it('sender hver status også når verdien er fraværende', async () => {
    const { rpcCalls } = renderRoute('/evidence/new', {
      api: LOOKUPS,
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')
    await fillRequiredFields()
    fireEvent.change(screen.getByLabelText('Antall deltakere analysen omfatter'), {
      target: { value: 'not_measured' },
    })
    submit()

    await screen.findByText('Evidensfunnet er registrert.')
    const args = lastCallArgs(rpcCalls)
    expect(args?.['p_sample_size']).toBeNull()
    expect(args?.['p_sample_size_availability']).toBe('not_measured')
    expect(args?.['p_estimate']).toBeNull()
    expect(args?.['p_estimate_availability']).toBe('not_reported')
    expect(args?.['p_ci_lower']).toBeNull()
    expect(args?.['p_confidence_interval_availability']).toBe('not_reported')
  })

  it('stopper et forsøk der statusen lover en verdi som ikke er fylt ut', async () => {
    // Ikke en duplisering av databasens constraint: uten en verdi finnes det
    // ingenting å sende, og et halvt utfylt felt skal ikke sendes som om det
    // var en verdi.
    const { rpcCalls } = renderRoute('/evidence/new', {
      api: LOOKUPS,
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')
    await fillRequiredFields()
    fireEvent.change(screen.getByLabelText('Tallverdi for effekten'), {
      target: { value: 'reported_value' },
    })
    submit()

    expect(
      await screen.findByText('Fyll inn estimatet, eller si hvorfor det mangler.'),
    ).toBeInTheDocument()
    expect(rpcCalls).toEqual([])
  })

  it('viser de seks statusene med norsk tekst, men sender de kanoniske verdiene', async () => {
    const { rpcCalls } = renderRoute('/evidence/new', {
      api: LOOKUPS,
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')

    const status = screen.getByLabelText('Kobling til en populasjon i katalogen')
    const labels = within(status)
      .getAllByRole('option')
      .map((option) => option.textContent)
    expect(labels).toContain('Ikke målt i studien')
    expect(labels).toContain('Ikke rapportert i kilden')
    expect(labels).not.toContain('not_measured')

    await fillRequiredFields()
    fireEvent.change(status, { target: { value: 'not_applicable' } })
    submit()

    await screen.findByText('Evidensfunnet er registrert.')
    expect(lastCallArgs(rpcCalls)?.['p_population_availability']).toBe('not_applicable')
    expect(lastCallArgs(rpcCalls)?.['p_population_id']).toBeNull()
  })
})

describe('oppfølgingstid og enhet', () => {
  it('setter tall og enhet sammen til ett intervall, med like grenser for ett tidspunkt', async () => {
    const { rpcCalls } = renderRoute('/evidence/new', {
      api: LOOKUPS,
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')
    await fillRequiredFields()
    fireEvent.change(screen.getByLabelText('Oppfølgingstid'), {
      target: { value: 'reported_value' },
    })
    fireEvent.change(screen.getByLabelText('Enhet for oppfølgingstiden'), {
      target: { value: 'weeks' },
    })
    fireEvent.change(screen.getByLabelText('Oppfølgingstid, fra'), { target: { value: '8' } })
    submit()

    await screen.findByText('Evidensfunnet er registrert.')
    expect(lastCallArgs(rpcCalls)?.['p_timepoint_min']).toBe('8 weeks')
    expect(lastCallArgs(rpcCalls)?.['p_timepoint_max']).toBe('8 weeks')
  })
})

describe('effektmål og enhet henger sammen', () => {
  it('viser enhetsfeltet bare for et dimensjonalt mål, og sender ingen enhet uten mål', async () => {
    // evidence_items_estimate_unit_check: dimensjonale mål krever enhet,
    // dimensjonsløse skal ikke ha en. Skjemaet viser feltet nøyaktig når målet
    // krever det, framfor å la redaktøren fylle ut noe databasen avviser.
    const { rpcCalls } = renderRoute('/evidence/new', {
      api: LOOKUPS,
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')

    expect(screen.queryByLabelText('Enhet')).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Effektmål'), { target: { value: 'odds_ratio' } })
    expect(screen.queryByLabelText('Enhet')).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Effektmål'), { target: { value: 'mean_difference' } })
    expect(screen.getByLabelText('Enhet')).toBeInTheDocument()

    await fillRequiredFields()
    fireEvent.change(screen.getByLabelText('Enhet'), { target: { value: 'kg' } })
    fireEvent.change(screen.getByLabelText('Tallverdi for effekten'), {
      target: { value: 'reported_value' },
    })
    fireEvent.change(screen.getByLabelText('Estimat'), { target: { value: '1,7' } })
    submit()

    await screen.findByText('Evidensfunnet er registrert.')
    expect(lastCallArgs(rpcCalls)?.['p_effect_measure']).toBe('mean_difference')
    expect(lastCallArgs(rpcCalls)?.['p_estimate']).toBe('1.7')
    expect(lastCallArgs(rpcCalls)?.['p_estimate_unit']).toBe('kg')
  })
})

describe('komparatoren', () => {
  it('spør om komparatorvirkestoff bare når kontrasten er et virkestoff', async () => {
    const { rpcCalls } = renderRoute('/evidence/new', {
      api: { ...LOOKUPS, editor_drugs: [editorDrugRow()] },
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')

    expect(screen.queryByLabelText('Komparatorvirkestoff')).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Sammenlignet med'), { target: { value: 'placebo' } })
    expect(screen.queryByLabelText('Komparatorvirkestoff')).not.toBeInTheDocument()

    await fillRequiredFields()
    submit()
    await screen.findByText('Evidensfunnet er registrert.')
    expect(lastCallArgs(rpcCalls)?.['p_comparator_kind']).toBe('placebo')
    expect(lastCallArgs(rpcCalls)?.['p_comparator_drug_id']).toBeNull()
  })
})

describe('kildeversjonene må ha svart før funnet kan registreres', () => {
  it('skiller «henter» fra «ingen registrert kildeversjon», og blokkerer innsending', async () => {
    // De to må ikke se like ut: er oppslaget ikke ferdig, er det ukjent om
    // kilden har et øyeblikksbilde — og et funn registrert med NULL kan ikke
    // rettes etterpå, fordi evidensfunn er uforanderlige.
    const { rpcCalls } = renderRoute('/evidence/new', {
      api: { ...LOOKUPS, editor_source_versions: { pending: true } },
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')
    selectSource()
    fillFieldsBesidesSource()

    const version = await screen.findByLabelText('Kildeversjon (valgfritt)')
    expect(version).toBeDisabled()
    expect(version).toHaveDisplayValue('Henter kildeversjoner …')

    submit()
    expect(await screen.findByText(/Vent til kildeversjonene er hentet/)).toBeInTheDocument()
    expect(rpcCalls).toEqual([])
  })

  it('viser en feil i oppslaget som en feil, og blokkerer innsending', async () => {
    const { rpcCalls } = renderRoute('/evidence/new', {
      api: {
        ...LOOKUPS,
        editor_source_versions: { error: 'permission denied for view editor_source_versions' },
      },
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')
    selectSource()
    fillFieldsBesidesSource()

    expect(
      await screen.findByText('Antidep fikk ikke hentet kildeversjonene for denne kilden.'),
    ).toBeInTheDocument()
    submit()
    expect(await screen.findByText(/Vent til kildeversjonene er hentet/)).toBeInTheDocument()
    expect(rpcCalls).toEqual([])
  })

  it('sier «ingen registrert kildeversjon» bare når kilden faktisk ikke har noen', async () => {
    renderRoute('/evidence/new', {
      api: { ...LOOKUPS, editor_source_versions: [] },
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')
    selectSource()
    const version = await screen.findByLabelText('Kildeversjon (valgfritt)')
    expect(version).toHaveDisplayValue('Ingen registrert kildeversjon')
    expect(version).not.toBeDisabled()
  })
})

describe('bekreftelsen', () => {
  it('viser funnet under riktig kilde etter en vellykket registrering', async () => {
    renderRoute('/evidence/new', {
      api: { ...LOOKUPS, editor_evidence_items: [editorEvidenceItemRow()] },
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')
    await fillRequiredFields()
    submit()

    expect(await screen.findByText('Evidensfunnet er registrert.')).toBeInTheDocument()
    expect(
      await screen.findByRole('heading', {
        level: 3,
        name: 'Registrerte evidensfunn på «Testkilde B: vektendring ved tolv uker»',
      }),
    ).toBeInTheDocument()
    expect(screen.getByText(/Tabell 3, side 118/)).toBeInTheDocument()
    expect(screen.getByText(/Registrert manuelt/)).toBeInTheDocument()
  })

  it('skiller placebo fra et armspesifikt funn i listen', async () => {
    // comparator_drug_name er NULL for begge. Uten kategorien ville en
    // placebokontrollert studie sett ut som et armspesifikt funn.
    renderRoute('/evidence/new', {
      api: {
        ...LOOKUPS,
        editor_evidence_items: [
          editorEvidenceItemRow({ comparator_kind: 'placebo' }),
          editorEvidenceItemRow({
            evidence_item_id: '66666666-6666-4666-8666-333333333333',
            comparator_kind: 'none',
            outcome_detail: 'Armspesifikt funn.',
          }),
        ],
      },
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')
    await fillRequiredFields()
    submit()

    // Avgrenset til listen: «én behandlingsarm» står også som etikett på
    // komparatorvalget i skjemaet under, og det er en annen påstand.
    const registered = within(await screen.findByRole('list'))
    expect(registered.getByText(/mot placebo/)).toBeInTheDocument()
    expect(registered.getByText(/én behandlingsarm/)).toBeInTheDocument()
  })

  it('navngir komparatorvirkestoffet når kontrasten er et virkestoff', async () => {
    renderRoute('/evidence/new', {
      api: {
        ...LOOKUPS,
        editor_evidence_items: [
          editorEvidenceItemRow({
            comparator_kind: 'drug',
            comparator_drug_id: '11111111-1111-4111-8111-222222222222',
            comparator_drug_name: 'virkestoff b',
          }),
        ],
      },
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')
    await fillRequiredFields()
    submit()

    const registered = within(await screen.findByRole('list'))
    expect(registered.getByText(/mot virkestoff b/)).toBeInTheDocument()
  })

  it('sier at funnet er registrert, ikke kontrollert eller publisert', async () => {
    renderRoute('/evidence/new', {
      api: { ...LOOKUPS, editor_evidence_items: [editorEvidenceItemRow()] },
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')
    await fillRequiredFields()
    submit()

    expect(
      await screen.findByText(/Funnene er registrert, ikke kontrollert eller publisert/),
    ).toBeInTheDocument()
  })

  it('lar kilden stå valgt, slik at neste funn fra samme publikasjon er ett klikk unna', async () => {
    renderRoute('/evidence/new', { api: LOOKUPS, auth: { initialUserId: TEST_USER_IDS.a } })
    await screen.findByLabelText('Kilde')
    await fillRequiredFields()
    submit()

    await screen.findByText('Evidensfunnet er registrert.')
    expect(screen.getByLabelText('Kilde')).toHaveValue(TEST_EDITOR_IDS.source)
    expect(screen.getByLabelText('Hvor i kilden står funnet?')).toHaveValue('')
  })

  it('en avvisning fra databasen vises med databasens egen tekst', async () => {
    renderRoute('/evidence/new', {
      api: {
        ...LOOKUPS,
        create_evidence_item: {
          error: 'Brukeren har ikke gyldig editor-rolle for dette innholdsområdet.',
        },
      },
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')
    await fillRequiredFields()
    submit()

    expect(await screen.findByText('Evidensfunnet ble ikke registrert.')).toBeInTheDocument()
    expect(
      screen.getByText(/Brukeren har ikke gyldig editor-rolle for dette innholdsområdet/),
    ).toBeInTheDocument()
    // Skjemaet blir stående utfylt: en avvisning skal ikke koste utfyllingen.
    expect(screen.getByLabelText('Hvor i kilden står funnet?')).toHaveValue('Tabell 2, side 5')
  })
})

describe('kildevalget', () => {
  it('merker en kilde som ikke lenger er i normal bruk', async () => {
    // En trukket kilde skal ikke kunne velges uten at det er synlig
    // (ANTIDEP_CONSTITUTION.md §14).
    renderRoute('/evidence/new', {
      api: {
        ...LOOKUPS,
        editor_sources: [
          editorSourceRow({ source_status: 'retracted', title: 'Trukket testkilde' }),
        ],
      },
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    const select = await screen.findByLabelText('Kilde')
    const labels = within(select)
      .getAllByRole('option')
      .map((option) => option.textContent)
    expect(
      labels.some((label) => label?.includes('Trukket tilbake av tidsskrift eller utgiver')),
    ).toBe(true)
  })

  it('tilbyr kildeversjonene som er registrert på den valgte kilden', async () => {
    const { queries } = renderRoute('/evidence/new', {
      api: { ...LOOKUPS, editor_source_versions: [editorSourceVersionRow()] },
      auth: { initialUserId: TEST_USER_IDS.a },
    })
    await screen.findByLabelText('Kilde')
    selectSource()

    const version = await screen.findByLabelText('Kildeversjon (valgfritt)')
    const labels = within(version)
      .getAllByRole('option')
      .map((option) => option.textContent)
    expect(labels[0]).toBe('Ingen registrert kildeversjon')
    expect(labels.some((label) => label?.includes('eksempel.invalid/testkilde-b'))).toBe(true)
    expect(
      queries.some(
        (query) =>
          query.view === 'editor_source_versions' &&
          query.filters.some(
            ([column, value]) => column === 'source_id' && value === TEST_EDITOR_IDS.source,
          ),
      ),
    ).toBe(true)
  })
})
