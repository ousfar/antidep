import { render, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { describe, expect, it } from 'vitest'
import { EvidenceFinding } from './EvidenceFinding'
import { evidenceRow } from '../app/test-support'
import type { PublishedClaimEvidenceRow } from '../types/api'

// ============================================================================
// Presentasjonen av ett evidensfunn.
//
// Testene rendrer med `render()` og leser i det returnerte `container`-et
// framfor i `screen`, slik at to rendere i samme test ikke gir to treff på
// samme rolle. `getBy*` ville da feilet, og `getAllBy*[0]` ville stille målt
// forrige render.
// ============================================================================

function renderFinding(overrides: Partial<PublishedClaimEvidenceRow> = {}) {
  // Ruteren må være til stede: lenken til kildesiden er en rute og rendres med
  // `Link`, slik at den ikke gir en full dokumentnavigering (se komponenten).
  const { container } = render(
    <MemoryRouter>
      <EvidenceFinding
        finding={evidenceRow(overrides)}
        sourceHref="/sources/test"
        headingLevel={4}
      />
    </MemoryRouter>,
  )
  const article = within(container).getByRole('article')
  return { container, article }
}

/** Teksten i `<dd>`-en som hører til én `<dt>`. */
function detail(article: HTMLElement, label: string): string {
  const terms = [...article.querySelectorAll('dt')]
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

describe('forutsetningene testene hviler på', () => {
  it('grunnfiksturen er et velformet, støttende funn', () => {
    // Uten denne kunne testene under passert fordi *alt* ble et kontraktsbrudd.
    const { article } = renderFinding()
    expect(article).toHaveTextContent('Støtter påstanden')
    expect(detail(article, 'Resultat')).toContain('Gjennomsnittsforskjell 1,7 kg')
  })
})

describe('relasjonen til påstanden', () => {
  it('skriver ut Antideps vurdering av funnet', () => {
    const { article } = renderFinding({ relationship_type: 'contradicts' })
    expect(article).toHaveTextContent('Motsier påstanden')
  })

  it('gir funnet et tilgjengelig navn som bærer både relasjonen og kilden', () => {
    // Uten relasjonen i navnet ville et motstridende funn hett nøyaktig som et
    // støttende for en skjermleser, og to funn fra samme kilde hett det samme.
    const { article } = renderFinding({ relationship_type: 'contradicts' })
    expect(article).toHaveAccessibleName('Motsier påstanden Testkilde A: vektendring ved åtte uker')
  })

  it('en ukjent relasjonstype leses ikke som støtte', () => {
    const { article } = renderFinding({
      relationship_type: 'refutes' as PublishedClaimEvidenceRow['relationship_type'],
    })
    expect(article).not.toHaveTextContent('Støtter påstanden')
    expect(article).toHaveTextContent(/ikke tolkbar/i)
    expect(article).toHaveTextContent(/skal ikke leses som støtte/i)
  })

  it('skriver ut direktheten som egen akse', () => {
    const { article } = renderFinding({ relationship_type: 'contradicts', directness: 'indirect' })
    expect(article).toHaveTextContent('Motsier påstanden')
    expect(detail(article, 'Direkthet')).toContain('indirekte')
  })
})

describe('kildens egen retning holdes fra Antideps vurdering', () => {
  it('skriver ut at kilden ikke oppgir noen retning', () => {
    // `not_stated` er den fjerde verdien påstandens retningsvokabular ikke har.
    // «Kilden oppgir ingen retning» er ikke det samme som «ingen klar forskjell».
    const { article } = renderFinding({ reported_direction: 'not_stated' })
    expect(detail(article, 'Rapportert retning')).toBe('Kilden oppgir ingen retning')
  })

  it('skiller nullfunnet fra manglende retning', () => {
    const { article } = renderFinding({ reported_direction: 'no_clear_difference' })
    expect(detail(article, 'Rapportert retning')).toBe('Kilden fant ingen klar forskjell')
  })

  it('sier at retningen er ukjent framfor å utelate den', () => {
    const { article } = renderFinding({
      reported_direction: 'mixed' as PublishedClaimEvidenceRow['reported_direction'],
    })
    expect(detail(article, 'Rapportert retning')).toContain('mixed')
  })

  it('lar kilden rapportere en annen retning enn Antideps vurdering', () => {
    // Nettopp da er forskjellen klinisk interessant, og de to må ikke slås sammen.
    const { article } = renderFinding({
      relationship_type: 'contradicts',
      reported_direction: 'decrease',
    })
    expect(article).toHaveTextContent('Motsier påstanden')
    expect(detail(article, 'Rapportert retning')).toBe('Kilden rapporterer en reduksjon')
  })
})

describe('et fravær sier alltid hvorfor', () => {
  it('utvalgsstørrelse som ikke er rapportert, er ikke et utvalg på null', () => {
    const { article } = renderFinding({
      sample_size: null,
      sample_size_availability: 'not_reported',
    })
    expect(detail(article, 'Utvalgsstørrelse')).toBe('Ikke rapportert i kilden')
  })

  it('skiller «ikke målt» fra «ikke rapportert»', () => {
    const { article } = renderFinding({
      timepoint_min: null,
      timepoint_max: null,
      timepoint_availability: 'not_measured',
    })
    expect(detail(article, 'Måletidspunkt')).toBe('Ikke målt i studien')
  })

  it('sier at en verdi står i kilden uten å la seg lese entydig ut', () => {
    const { article } = renderFinding({
      population_label: null,
      population_id: null,
      population_availability: 'not_extractable',
    })
    expect(detail(article, 'Populasjon')).toContain('lar seg ikke lese entydig ut')
  })

  it('en utvalgsstørrelse på null vises ikke som et tall', () => {
    // Den ville sett ut som et resultat — «ingen deltakere» — framfor som den
    // ødelagte raden den er. Migrasjon 003 forbyr verdien; visningen nekter å
    // gjengi den (ANTIDEP_CONSTITUTION.md §17).
    const { article } = renderFinding({ sample_size: 0 })
    expect(detail(article, 'Utvalgsstørrelse')).not.toContain('0')
    expect(detail(article, 'Utvalgsstørrelse')).toContain('kan ikke være det den er registrert som')
  })

  it('merker en usikker ekstraksjon framfor å vise verdien som sikker', () => {
    const { article } = renderFinding({ sample_size_availability: 'uncertain_extraction' })
    expect(detail(article, 'Utvalgsstørrelse')).toContain('240')
    expect(detail(article, 'Utvalgsstørrelse')).toContain('ekstraksjonen er registrert som usikker')
  })
})

describe('presisjonen', () => {
  it('viser intervallet med nivået sitt', () => {
    const { article } = renderFinding()
    expect(detail(article, 'Presisjon')).toBe('95 % KI: 0,9 til 2,5')
  })

  it('feltet står også når intervallet mangler', () => {
    // Et manglende intervall betyr upresist grunnlag, ikke et presist estimat.
    // Et felt som forsvinner, ville latt estimatet stå som om det var presist.
    const { article } = renderFinding({
      ci_lower: null,
      ci_upper: null,
      ci_level_percent: null,
      confidence_interval_availability: 'not_reported',
    })
    expect(detail(article, 'Presisjon')).toBe('Ikke rapportert i kilden')
  })

  it('et intervall uten nivå vises ikke som et intervall', () => {
    const { article } = renderFinding({ ci_level_percent: null })
    expect(detail(article, 'Presisjon')).not.toContain('0,9 til 2,5')
    expect(detail(article, 'Presisjon')).toContain('delvis registrert')
  })
})

describe('resultatet', () => {
  it('viser tallet med målet og enheten sin', () => {
    const { article } = renderFinding()
    expect(detail(article, 'Resultat')).toBe('Gjennomsnittsforskjell 1,7 kg')
  })

  it('viser ikke tallet når målet krever en komparator som ikke finnes', () => {
    const { article } = renderFinding({ comparator_kind: 'none', comparator_drug_id: null })
    expect(detail(article, 'Resultat')).not.toContain('1,7')
    expect(detail(article, 'Resultat')).toContain('ikke tolkbar')
  })

  it('sier at en manglende effektstørrelse ikke betyr at effekten er null', () => {
    const { article } = renderFinding({
      estimate: null,
      estimate_unit: null,
      effect_measure: null,
      estimate_availability: 'not_measured',
      ci_lower: null,
      ci_upper: null,
      ci_level_percent: null,
      confidence_interval_availability: 'not_applicable',
    })
    expect(detail(article, 'Resultat')).toContain('betyr ikke at effekten er null')
  })

  it('beholder målet kilden brukte når tallet mangler', () => {
    const { article } = renderFinding({
      estimate: null,
      estimate_availability: 'not_reported',
      ci_lower: null,
      ci_upper: null,
      ci_level_percent: null,
      confidence_interval_availability: 'not_reported',
    })
    expect(detail(article, 'Resultat')).toContain('Gjennomsnittsforskjell')
    expect(detail(article, 'Resultat')).toContain('ikke rapportert i kilden')
  })
})

describe('kilden', () => {
  it('skriver ut datoen med den presisjonen den har', () => {
    // Fiksturen er månedspresis. «1. mars 2019» ville vært falsk presisjon.
    const { article } = renderFinding()
    expect(detail(article, 'Publisert')).toBe('mars 2019')
  })

  it('skriver bare året når bare året er kjent', () => {
    const { article } = renderFinding({
      source_publication_date: '2019-01-01',
      source_publication_date_precision: 'year',
    })
    expect(detail(article, 'Publisert')).toBe('2019')
  })

  it('en dato uten presisjon vises ikke som en dato', () => {
    const { article } = renderFinding({ source_publication_date_precision: null })
    expect(detail(article, 'Publisert')).not.toContain('mars')
    expect(detail(article, 'Publisert')).toContain('ikke tolkbar')
  })

  it('viser en tilbaketrukket kilde som tilbaketrukket', () => {
    const { article } = renderFinding({
      source_status: 'retracted',
      source_status_note: 'Trukket tilbake i 2021 etter datafeil.',
    })
    expect(detail(article, 'Kildestatus')).toContain('Trukket tilbake')
    expect(detail(article, 'Kildestatus')).toContain('etter datafeil')
  })

  it('skriver ut kildestatusen også når den er normal', () => {
    // En status som bare vises når den er avvikende, gjør fravær av merking til
    // en påstand ingen har tatt stilling til.
    const { article } = renderFinding()
    expect(detail(article, 'Kildestatus')).toBe('I bruk')
  })

  it('en ukjent kildestatus faller ikke sammen med «i bruk»', () => {
    const { article } = renderFinding({
      source_status: 'embargoed' as PublishedClaimEvidenceRow['source_status'],
    })
    expect(detail(article, 'Kildestatus')).not.toBe('I bruk')
    expect(detail(article, 'Kildestatus')).toContain('embargoed')
  })

  it('viser stedet i kilden, som er det som gjør funnet kontrollerbart', () => {
    const { article } = renderFinding()
    expect(detail(article, 'Sted i kilden')).toBe('Tabell 2, side 114')
  })

  it('sier at en manglende kildeversjon ikke betyr at kilden er uendret', () => {
    const { article } = renderFinding()
    expect(detail(article, 'Kildeversjon')).toContain('betyr ikke at kilden er uendret')
  })

  it('viser alle registrerte identifikatorer, ikke bare den første', () => {
    const { article } = renderFinding({ source_dois: ['10.0000/a', '10.0000/b'] })
    expect(within(article).getByRole('link', { name: '10.0000/a' })).toHaveAttribute(
      'href',
      'https://doi.org/10.0000/a',
    )
    expect(within(article).getByRole('link', { name: '10.0000/b' })).toHaveAttribute(
      'href',
      'https://doi.org/10.0000/b',
    )
  })

  it('sier at ingen identifikator er registrert i Antidep', () => {
    // Ikke det samme som at kilden mangler en.
    const { article } = renderFinding({ source_dois: null })
    expect(detail(article, 'DOI')).toContain('registrert i Antidep')
  })

  it('lenker til kildesiden, som er den andre halvdelen av §42', () => {
    const { article } = renderFinding()
    const link = within(article).getByRole('link', {
      name: 'Alt Antidep bruker denne kilden til Testkilde A: vektendring ved åtte uker',
    })
    expect(link).toHaveAttribute('href', '/sources/test')
  })
})

describe('en tilbaketrukket ekstraksjon', () => {
  const withdrawn = {
    extraction_withdrawn: true,
    extraction_withdrawn_at: '2026-08-22T08:00:00Z',
    extraction_withdrawal_rationale: 'Feil kolonne lest ut av tabellen.',
  } as const

  it('merkes framfor å skjules', () => {
    const { article } = renderFinding(withdrawn)
    expect(article).toHaveTextContent(/trukket tilbake denne ekstraksjonen/i)
    // Funnet står fortsatt: påstanden over det er fortsatt publisert.
    expect(article).toHaveTextContent('Testkilde A: vektendring ved åtte uker')
  })

  it('sier når og hvorfor', () => {
    const { article } = renderFinding(withdrawn)
    expect(article).toHaveTextContent('22. august 2026')
    expect(article).toHaveTextContent('Feil kolonne lest ut av tabellen.')
  })

  it('et funn som ikke er trukket tilbake sier ingenting om tilbaketrekking', () => {
    const { article } = renderFinding()
    expect(article).not.toHaveTextContent(/trukket tilbake/i)
  })
})
