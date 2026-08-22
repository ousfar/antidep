import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { ClaimCertainty } from './ClaimCertainty'
import type { ClaimCertainty as ClaimCertaintyState } from '../lib/claim-certainty'

function certaintyRegion(container: HTMLElement): HTMLElement {
  const region = container.querySelector<HTMLElement>('.claim-certainty')
  if (region === null) {
    throw new Error('sikkerhetsvisningen ble ikke rendret')
  }
  return region
}

const GRADED: ClaimCertaintyState[] = [
  { kind: 'graded', level: 'high', framework: 'grade', rationale: null },
  { kind: 'graded', level: 'moderate', framework: 'grade', rationale: null },
  { kind: 'graded', level: 'low', framework: 'grade', rationale: null },
  { kind: 'graded', level: 'very_low', framework: 'grade', rationale: null },
]

const NOT_GRADED: ClaimCertaintyState[] = [
  { kind: 'no_assessable_evidence', evidenceGap: 'Ingen studier på eldre.', rationale: null },
  { kind: 'no_assessable_evidence', evidenceGap: null, rationale: null },
  { kind: 'not_applicable_deterministic_fact' },
  {
    kind: 'unknown',
    reason: 'unrecognised_knowledge_type',
    rawCertaintyLevel: 'moderate',
    rawKnowledgeType: 'regulatory_status',
  },
  {
    kind: 'unknown',
    reason: 'missing_assessment',
    rawCertaintyLevel: null,
    rawKnowledgeType: 'evidence_synthesis',
  },
  {
    kind: 'unknown',
    reason: 'unrecognised_level',
    rawCertaintyLevel: 'ganske_sikker',
    rawKnowledgeType: 'evidence_synthesis',
  },
  {
    kind: 'unknown',
    reason: 'assessment_on_deterministic_fact',
    rawCertaintyLevel: 'high',
    rawKnowledgeType: 'deterministic_fact',
  },
]

describe('graderingene bruker ordlyden §16 foreskriver', () => {
  it.each([
    ['high', 'Høy sikkerhet'],
    ['moderate', 'Moderat sikkerhet'],
    ['low', 'Lav sikkerhet'],
    ['very_low', 'Svært lav sikkerhet'],
  ] as const)('%s blir «%s»', (level, expected) => {
    render(
      <ClaimCertainty certainty={{ kind: 'graded', level, framework: 'grade', rationale: null }} />,
    )
    expect(screen.getByText(expected)).toBeInTheDocument()
  })
})

describe('ingen vurderbar evidens er en vurdert tilstand, ikke en svak gradering', () => {
  it('bruker ordlyden fra §16', () => {
    render(
      <ClaimCertainty
        certainty={{
          kind: 'no_assessable_evidence',
          evidenceGap: 'Ingen studier på eldre.',
          rationale: null,
        }}
      />,
    )
    expect(screen.getByText('Ingen vurderbar evidens')).toBeInTheDocument()
  })

  it('viser hva som mangler i grunnlaget', () => {
    render(
      <ClaimCertainty
        certainty={{
          kind: 'no_assessable_evidence',
          evidenceGap: 'Ingen studier på eldre.',
          rationale: null,
        }}
      />,
    )
    expect(screen.getByText('Ingen studier på eldre.')).toBeInTheDocument()
  })

  it('står ikke uten forklaring når evidence_gap mangler', () => {
    // Kontrakten sier at feltet alltid er utfylt for denne tilstanden. Er det
    // likevel tomt, skal tilstanden fortsatt forklares — ikke stå naken og bli
    // lest som en svak gradering.
    const { container } = render(
      <ClaimCertainty
        certainty={{ kind: 'no_assessable_evidence', evidenceGap: null, rationale: null }}
      />,
    )
    expect(certaintyRegion(container)).toHaveTextContent(/lar seg ikke gradere/i)
  })
})

describe('deterministiske fakta graderes ikke, og det er ikke en mangel', () => {
  it('sier «Ikke aktuelt», ikke «ukjent» og ikke «lav»', () => {
    const { container } = render(
      <ClaimCertainty certainty={{ kind: 'not_applicable_deterministic_fact' }} />,
    )
    const region = certaintyRegion(container)
    expect(region).toHaveTextContent('Ikke aktuelt')
    expect(region).toHaveTextContent(/gjelder ikke for deterministiske fakta/i)
    expect(region).not.toHaveTextContent(/ukjent sikkerhet/i)
  })
})

describe('de fire kontraktsbruddene navngir hva som er galt', () => {
  it.each([
    ['unrecognised_knowledge_type', /kjenner ikke kunnskapstypen «regulatory_status»/i],
    ['missing_assessment', /mangler den sikkerhetsvurderingen/i],
    ['unrecognised_level', /«ganske_sikker» er utenfor vokabularet/i],
    ['assessment_on_deterministic_fact', /GRADE gjelder ikke for kunnskapstypen/i],
  ] as const)('%s', (reason, expected) => {
    const certainty = NOT_GRADED.find(
      (state) => state.kind === 'unknown' && state.reason === reason,
    )
    if (certainty === undefined) {
      throw new Error(`mangler tilstand for ${reason}`)
    }
    const { container } = render(<ClaimCertainty certainty={certainty} />)
    const region = certaintyRegion(container)
    expect(region).toHaveTextContent('Ukjent sikkerhet')
    expect(region).toHaveTextContent(expected)
  })
})

describe('ikke-gradert skiller seg i art, ikke i grad', () => {
  it.each(GRADED)('en gradering bærer data-certainty-level ($level)', (certainty) => {
    const { container } = render(<ClaimCertainty certainty={certainty} />)
    expect(certaintyRegion(container).dataset['certaintyLevel']).toBeDefined()
  })

  it.each(NOT_GRADED)('en ikke-gradert tilstand bærer den ikke ($kind, $reason)', (certainty) => {
    // Stilsettet henger den graderte drakten på nettopp dette attributtet. Uten
    // denne regelen kan en ikke-gradert tilstand arve utseendet til en
    // gradering, og «ingen vurderbar evidens» bli et trinn under «svært lav»
    // (ANTIDEP_CONSTITUTION.md §17).
    const { container } = render(<ClaimCertainty certainty={certainty} />)
    expect(certaintyRegion(container).dataset['certaintyLevel']).toBeUndefined()
  })

  it.each(NOT_GRADED)(
    'en ikke-gradert tilstand beskrives aldri som en gradering ($kind, $reason)',
    (certainty) => {
      const { container } = render(<ClaimCertainty certainty={certainty} />)
      const text = certaintyRegion(container).textContent ?? ''
      for (const graded of [
        'Høy sikkerhet',
        'Moderat sikkerhet',
        'Lav sikkerhet',
        'Svært lav sikkerhet',
      ]) {
        expect(text).not.toContain(graded)
      }
    },
  )

  it.each(NOT_GRADED)(
    'en ikke-gradert tilstand sier at den ikke betyr lav risiko ($kind, $reason)',
    (certainty) => {
      const { container } = render(<ClaimCertainty certainty={certainty} />)
      expect(certaintyRegion(container)).toHaveTextContent(
        /betyr ikke lav risiko, ingen effekt eller ingen bivirkning/i,
      )
    },
  )

  it.each(GRADED)('en gradering bærer ikke forbeholdet ($level)', (certainty) => {
    const { container } = render(<ClaimCertainty certainty={certainty} />)
    expect(certaintyRegion(container)).not.toHaveTextContent(/betyr ikke lav risiko/i)
  })
})

describe('sikkerheten er alltid synlig', () => {
  it.each([...GRADED, ...NOT_GRADED])(
    '$kind$level$reason har både etikett og verdi',
    (certainty) => {
      // En sikkerhetsvisning som kan bli tom er verre enn ingen: et tomt felt
      // leses som fravær av risiko (ANTIDEP_CONSTITUTION.md §17).
      const { container } = render(<ClaimCertainty certainty={certainty} />)
      const region = certaintyRegion(container)
      expect(region.querySelector('.claim-certainty__label')?.textContent).toBe(
        'Sikkerhet i evidensen',
      )
      const value = region.querySelector('.claim-certainty__value')?.textContent ?? ''
      expect(value.trim().length).toBeGreaterThan(0)
    },
  )
})
