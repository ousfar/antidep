import { describe, expect, it } from 'vitest'
import { describeClaimCertainty, type ClaimCertaintyInput } from './claim-certainty'

function claim(overrides: Partial<ClaimCertaintyInput> = {}): ClaimCertaintyInput {
  return {
    knowledge_type: 'evidence_synthesis',
    certainty_level: 'moderate',
    certainty_framework: 'grade',
    certainty_rationale: 'To randomiserte studier med moderat presisjon.',
    evidence_gap: null,
    ...overrides,
  }
}

describe('gradert sikkerhet', () => {
  it('gir graden og metoden bak den', () => {
    expect(describeClaimCertainty(claim({ certainty_level: 'high' }))).toEqual({
      kind: 'graded',
      level: 'high',
      framework: 'grade',
      rationale: 'To randomiserte studier med moderat presisjon.',
    })
  })

  it('dekker hele GRADE-skalaen', () => {
    for (const level of ['high', 'moderate', 'low', 'very_low'] as const) {
      const certainty = describeClaimCertainty(claim({ certainty_level: level }))
      expect(certainty).toMatchObject({ kind: 'graded', level })
    }
  })
})

describe('de to NULL-lignende tilstandene holdes fra hverandre', () => {
  it('no_assessable_evidence er vurdert og ikke graderbar, med hullet utfylt', () => {
    const certainty = describeClaimCertainty(
      claim({
        certainty_level: 'no_assessable_evidence',
        evidence_gap: 'Ingen studier på denne populasjonen.',
      }),
    )
    expect(certainty).toEqual({
      kind: 'no_assessable_evidence',
      evidenceGap: 'Ingen studier på denne populasjonen.',
      rationale: 'To randomiserte studier med moderat presisjon.',
    })
  })

  it('NULL på et deterministisk faktum betyr at GRADE ikke gjelder', () => {
    expect(
      describeClaimCertainty(
        claim({ knowledge_type: 'deterministic_fact', certainty_level: null }),
      ),
    ).toEqual({ kind: 'not_applicable_deterministic_fact' })
  })

  it('gir de to tilstandene forskjellig kind, slik at de ikke kan renderes likt', () => {
    const ikkeGraderbar = describeClaimCertainty(
      claim({ certainty_level: 'no_assessable_evidence', evidence_gap: 'Ingen studier.' }),
    )
    const ikkeAktuelt = describeClaimCertainty(
      claim({ knowledge_type: 'deterministic_fact', certainty_level: null }),
    )
    expect(ikkeGraderbar.kind).not.toBe(ikkeAktuelt.kind)
  })
})

describe('kontraktsbrudd blir ukjent, aldri godartet', () => {
  it('en evidenssyntese uten vurdering er ukjent, ikke lav', () => {
    expect(describeClaimCertainty(claim({ certainty_level: null }))).toEqual({
      kind: 'unknown',
      reason: 'missing_assessment',
      rawCertaintyLevel: null,
      rawKnowledgeType: 'evidence_synthesis',
    })
  })

  it('en klinisk anbefaling uten vurdering er ukjent', () => {
    expect(
      describeClaimCertainty(
        claim({ knowledge_type: 'clinical_recommendation', certainty_level: null }),
      ),
    ).toMatchObject({ kind: 'unknown', reason: 'missing_assessment' })
  })

  it('en verdi utenfor vokabularet havner ikke i en godartet gren', () => {
    // Radtypen er en påstand om databasen, ikke en garanti: en ny enum-verdi
    // eller en klient mot en nyere database skal gi ukjent sikkerhet.
    expect(describeClaimCertainty(claim({ certainty_level: 'ganske_sikker' }))).toEqual({
      kind: 'unknown',
      reason: 'unrecognised_level',
      rawCertaintyLevel: 'ganske_sikker',
      rawKnowledgeType: 'evidence_synthesis',
    })
  })

  it('en ukjent kunnskapstype uten vurdering skilles fra en manglende vurdering', () => {
    // Uten dette skillet ville en ny kunnskapstype uten GRADE sett ut som en
    // evidenssyntese publiseringsgaten hadde sluppet gjennom uvurdert.
    expect(
      describeClaimCertainty(claim({ knowledge_type: 'kommende_type', certainty_level: null })),
    ).toMatchObject({ kind: 'unknown', reason: 'unrecognised_knowledge_type' })
  })
})

describe('ingen tilstand kan forveksles med en lav gradering', () => {
  it('bare faktisk graderte påstander får kind graded', () => {
    const ikkeGraderte: ClaimCertaintyInput[] = [
      claim({ certainty_level: 'no_assessable_evidence', evidence_gap: 'Ingen studier.' }),
      claim({ knowledge_type: 'deterministic_fact', certainty_level: null }),
      claim({ certainty_level: null }),
      claim({ certainty_level: 'ganske_sikker' }),
      claim({ certainty_level: '' }),
    ]
    for (const input of ikkeGraderte) {
      expect(describeClaimCertainty(input).kind).not.toBe('graded')
    }
  })
})
