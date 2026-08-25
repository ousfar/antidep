import { render, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { DetailList } from './DetailList'
import {
  ExtractionWithdrawalNote,
  SourceExtractionDetails,
  SourcePublicationDetails,
} from './SourceDetails'
import { evidenceRow } from '../app/test-support'
import type { PublishedClaimEvidenceRow } from '../types/api'

// ============================================================================
// De delte kildefeltene, prøvd for seg.
//
// Evidensvisningen og kildesiden rendrer de samme komponentene, så en test som
// bare går gjennom én av sidene ville latt en gren stå uprøvd i den andre. Her
// prøves kombinasjonene som ingen av sidene stiller opp av seg selv — særlig
// kildeversjonen, der leddene er valgfrie hver for seg.
// ============================================================================

function renderExtraction(overrides: Partial<PublishedClaimEvidenceRow> = {}) {
  const { container } = render(
    <DetailList>
      <SourceExtractionDetails extraction={evidenceRow(overrides)} />
    </DetailList>,
  )
  return container
}

/** Teksten i `<dd>`-en som hører til én `<dt>`. */
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

const VERSION = {
  source_version_id: '99999999-9999-4999-8999-111111111111',
  source_version_retrieved_at: '2026-03-04T09:00:00Z',
  source_version_external_version: '3. utgave',
  source_version_retrieved_from: 'https://eksempel.test/kilde',
} as const

describe('kildeversjonen funnet ble lest ut av', () => {
  it('viser hentetidspunkt, versjonsbetegnelse og hentested', () => {
    const container = renderExtraction(VERSION)
    expect(detail(container, 'Kildeversjon')).toBe(
      'Hentet 4. mars 2026. Versjon 3. utgave. Fra https://eksempel.test/kilde',
    )
  })

  it('utelater leddene som ikke er registrert, framfor å skrive dem som tomme', () => {
    const container = renderExtraction({
      ...VERSION,
      source_version_external_version: null,
      source_version_retrieved_from: null,
    })
    expect(detail(container, 'Kildeversjon')).toBe('Hentet 4. mars 2026')
  })

  it('bare versjonsbetegnelsen, uten hentetidspunkt', () => {
    const container = renderExtraction({
      ...VERSION,
      source_version_retrieved_at: null,
      source_version_retrieved_from: null,
    })
    expect(detail(container, 'Kildeversjon')).toBe('Versjon 3. utgave')
  })

  it('bare hentestedet, som er det siste leddet', () => {
    // Ytterpunktet i den andre enden: uten denne stod det siste leddet uprøvd.
    const container = renderExtraction({
      ...VERSION,
      source_version_retrieved_at: null,
      source_version_external_version: null,
    })
    expect(detail(container, 'Kildeversjon')).toBe('Fra https://eksempel.test/kilde')
  })

  it('en registrert versjon uten opplysninger sier at den er registrert', () => {
    // Ikke det samme som ingen versjon: raden finnes, men bærer ingenting.
    const container = renderExtraction({
      source_version_id: VERSION.source_version_id,
      source_version_retrieved_at: null,
      source_version_external_version: null,
      source_version_retrieved_from: null,
    })
    expect(detail(container, 'Kildeversjon')).toBe('Registrert, uten nærmere opplysninger.')
  })

  it('ingen registrert versjon betyr ikke at kilden er uendret', () => {
    const container = renderExtraction()
    expect(detail(container, 'Kildeversjon')).toBe(
      'Ingen kildeversjon er registrert. Det betyr ikke at kilden er uendret siden ekstraksjonen.',
    )
  })

  it('et hentetidspunkt som ikke er en dato, vises som det står', () => {
    const container = renderExtraction({ ...VERSION, source_version_retrieved_at: 'i fjor' })
    expect(detail(container, 'Kildeversjon')).toContain('i fjor (ikke tolkbar som dato)')
  })
})

describe('merket på en tilbaketrukket ekstraksjon', () => {
  it('står ikke når ingen tilbaketrekking er registrert', () => {
    const { container } = render(<ExtractionWithdrawalNote extraction={evidenceRow()} />)
    expect(container).toBeEmptyDOMElement()
  })

  it('sier når og hvorfor', () => {
    const { container } = render(
      <ExtractionWithdrawalNote
        extraction={evidenceRow({
          extraction_withdrawn: true,
          extraction_withdrawn_at: '2026-08-22T08:00:00Z',
          extraction_withdrawal_rationale: 'Feil kolonne lest ut av tabellen.',
        })}
      />,
    )
    const note = within(container).getByRole('note')
    expect(note).toHaveTextContent('22. august 2026')
    expect(note).toHaveTextContent('Begrunnelse: Feil kolonne lest ut av tabellen.')
  })

  it('merkes også uten tidspunkt og uten begrunnelse', () => {
    // Merkingen er det viktige: uten den ville et underkjent funn sett gyldig ut.
    const { container } = render(
      <ExtractionWithdrawalNote extraction={evidenceRow({ extraction_withdrawn: true })} />,
    )
    const note = within(container).getByRole('note')
    expect(note).toHaveTextContent(/Antidep har trukket tilbake denne ekstraksjonen\./)
    expect(note).not.toHaveTextContent('Begrunnelse')
  })
})

describe('publikasjonen', () => {
  it('en dato som bare er kjent til året, vises som året', () => {
    // Vist som hel dato ville «2019» blitt «1. januar 2019» — falsk presisjon.
    const { container } = render(
      <DetailList>
        <SourcePublicationDetails
          source={evidenceRow({
            source_publication_date: '2019-01-01',
            source_publication_date_precision: 'year',
          })}
        />
      </DetailList>,
    )
    expect(detail(container, 'Publisert')).toBe('2019')
  })

  it('en dato uten presisjonsnivå vises ikke som en dato', () => {
    const { container } = render(
      <DetailList>
        <SourcePublicationDetails
          source={evidenceRow({ source_publication_date_precision: null })}
        />
      </DetailList>,
    )
    expect(detail(container, 'Publisert')).toContain('ikke tolkbar uten et kjent presisjonsnivå')
  })

  it('en udatert kilde sier at ingen dato er registrert i Antidep', () => {
    const { container } = render(
      <DetailList>
        <SourcePublicationDetails
          source={evidenceRow({
            source_publication_date: null,
            source_publication_date_precision: null,
          })}
        />
      </DetailList>,
    )
    expect(detail(container, 'Publisert')).toBe('Ingen publiseringsdato er registrert i Antidep')
  })

  it('en ukjent dokumenttype gjettes ikke', () => {
    const { container } = render(
      <DetailList>
        <SourcePublicationDetails source={evidenceRow({ source_type: 'preprint' as never })} />
      </DetailList>,
    )
    expect(detail(container, 'Dokumenttype')).toBe('Ukjent dokumenttype («preprint»)')
  })
})
