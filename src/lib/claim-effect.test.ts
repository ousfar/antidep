import { describe, expect, it } from 'vitest'
import {
  describeClaimComparator,
  describeClaimDirection,
  describeClaimEffect,
  describeClaimMagnitude,
  isWithinArmMeasure,
  type ClaimComparatorState,
} from './claim-effect'
import { EFFECT_MEASURES, type EffectMeasure } from '../types/api'
import type { ClaimCertainty } from './claim-certainty'

const GRADED: ClaimCertainty = {
  kind: 'graded',
  level: 'moderate',
  framework: 'grade',
  rationale: null,
}
const NO_ASSESSABLE_EVIDENCE: ClaimCertainty = {
  kind: 'no_assessable_evidence',
  evidenceGap: 'Ingen studier med relevant oppfølgingstid.',
  rationale: null,
}

const SUBJECT_DRUG = '33333333-3333-4333-8333-333333333333'
const OTHER_DRUG = '44444444-4444-4444-8444-444444444444'

const NONE: ClaimComparatorState = { kind: 'none' }
const PLACEBO: ClaimComparatorState = { kind: 'placebo' }
const DRUG: ClaimComparatorState = { kind: 'drug', drugName: 'Virkestoff B' }

function comparatorInput(overrides: Partial<Parameters<typeof describeClaimComparator>[0]> = {}) {
  return {
    drug_id: SUBJECT_DRUG,
    comparator_kind: 'placebo',
    comparator_drug_id: null,
    comparator_drug_name: null,
    ...overrides,
  }
}

function magnitude(
  measure: string | null,
  value: number | null,
  unit: string | null,
  comparator: ClaimComparatorState,
) {
  return describeClaimMagnitude(
    { magnitude_measure: measure, magnitude_value: value, magnitude_unit: unit },
    comparator,
  )
}

describe('retning', () => {
  it.each([
    ['increase', 'increase'],
    ['decrease', 'decrease'],
    ['no_clear_difference', 'no_clear_difference'],
  ])('%s gir tilstanden %s', (value, kind) => {
    expect(describeClaimDirection(value)).toEqual({ kind })
  })

  it('NULL betyr at påstanden ikke uttrykker en retning', () => {
    expect(describeClaimDirection(null)).toEqual({ kind: 'not_expressed' })
  })

  it('holder «ingen klar forskjell» og «ingen retning angitt» fra hverandre', () => {
    // Det ene er et resultat, det andre er fravær av et strukturert felt. Slås
    // de sammen, blir fravær av data presentert som et nullfunn
    // (ANTIDEP_CONSTITUTION.md §17).
    expect(describeClaimDirection('no_clear_difference')).not.toEqual(describeClaimDirection(null))
  })

  it.each(['not_stated', 'neutral', 'INCREASE', '', 'økning'])(
    'en verdi utenfor vokabularet (%s) blir ukjent, ikke nøytral',
    (value) => {
      expect(describeClaimDirection(value)).toEqual({ kind: 'unknown', rawDirection: value })
    },
  )

  it('tar ikke imot evidensfunnets vokabular som om det var påstandens', () => {
    // knowledge.effect_direction har en fjerde verdi, not_stated, som beskriver
    // at kilden ikke oppgir en retning. Den betyr noe annet enn påstandens NULL
    // og skal ikke kunne komme inn her ubemerket.
    expect(describeClaimDirection('not_stated')).toEqual({
      kind: 'unknown',
      rawDirection: 'not_stated',
    })
  })
})

describe('komparator', () => {
  it('et navngitt virkestoff', () => {
    expect(
      describeClaimComparator(
        comparatorInput({
          comparator_kind: 'drug',
          comparator_drug_id: OTHER_DRUG,
          comparator_drug_name: 'Virkestoff B',
        }),
      ),
    ).toEqual({ kind: 'drug', drugName: 'Virkestoff B' })
  })

  it.each([
    ['placebo', 'placebo'],
    ['none', 'none'],
  ])('%s uten virkestoff', (value, kind) => {
    expect(describeClaimComparator(comparatorInput({ comparator_kind: value }))).toEqual({ kind })
  })

  it('«ingen komparator» er ikke «ukjent komparator»', () => {
    expect(describeClaimComparator(comparatorInput({ comparator_kind: 'none' }))).toEqual({
      kind: 'none',
    })
  })

  it('kategorien drug uten navn er et brudd, ikke en anonym sammenligning', () => {
    expect(
      describeClaimComparator(
        comparatorInput({ comparator_kind: 'drug', comparator_drug_id: OTHER_DRUG }),
      ),
    ).toMatchObject({ kind: 'unknown', reason: 'unnamed_comparator_drug' })
  })

  it('et virkestoff på en kategori som ikke er drug er et brudd', () => {
    // Databasen binder de to sammen. Kommer de fra hverandre, sier raden to
    // forskjellige ting om hva påstanden sammenlignes mot.
    expect(
      describeClaimComparator(
        comparatorInput({ comparator_kind: 'placebo', comparator_drug_name: 'Virkestoff B' }),
      ),
    ).toMatchObject({ kind: 'unknown', reason: 'named_drug_without_drug_kind' })
  })

  it('en komparator-id på en kategori som ikke er drug er også et brudd', () => {
    expect(
      describeClaimComparator(
        comparatorInput({ comparator_kind: 'none', comparator_drug_id: OTHER_DRUG }),
      ),
    ).toMatchObject({ kind: 'unknown', reason: 'named_drug_without_drug_kind' })
  })

  it('en påstand kan ikke sammenlignes med virkestoffet den selv handler om', () => {
    // «Sammenlignet med sertralin» på en påstand om sertralin er ingen
    // sammenligning, og et tall festet til den er ikke tolkbart.
    expect(
      describeClaimComparator(
        comparatorInput({
          comparator_kind: 'drug',
          comparator_drug_id: SUBJECT_DRUG,
          comparator_drug_name: 'Virkestoff A',
        }),
      ),
    ).toMatchObject({ kind: 'unknown', reason: 'comparator_is_subject_drug' })
  })

  it('avgjør identitet på id, ikke på navn', () => {
    // To katalogoppføringer kan bære samme visningsnavn; det er id-en som sier
    // om det faktisk er samme virkestoff.
    expect(
      describeClaimComparator(
        comparatorInput({
          comparator_kind: 'drug',
          comparator_drug_id: OTHER_DRUG,
          comparator_drug_name: 'Virkestoff A',
        }),
      ),
    ).toEqual({ kind: 'drug', drugName: 'Virkestoff A' })
  })

  it.each(['usual_care', 'DRUG', ''])(
    'en kategori utenfor vokabularet (%s) blir ukjent',
    (value) => {
      expect(describeClaimComparator(comparatorInput({ comparator_kind: value }))).toMatchObject({
        kind: 'unknown',
        reason: 'unrecognised_kind',
      })
    },
  )
})

describe('størrelse, uavhengig av komparatoren', () => {
  it('et dimensjonalt kontrastivt mål med enhet og komparator', () => {
    expect(magnitude('mean_difference', 1.7, 'kg', PLACEBO)).toEqual({
      kind: 'quantified',
      measure: 'mean_difference',
      value: 1.7,
      unit: 'kg',
    })
  })

  it('et dimensjonsløst mål uten enhet', () => {
    expect(magnitude('odds_ratio', 2.1, null, PLACEBO)).toEqual({
      kind: 'quantified',
      measure: 'odds_ratio',
      value: 2.1,
      unit: null,
    })
  })

  it('ingen tallfesting er ikke en effekt på null', () => {
    expect(magnitude(null, null, null, NONE)).toEqual({ kind: 'not_quantified' })
  })

  it('en tallfestet effekt på null er en målt verdi, ikke fravær', () => {
    expect(magnitude('mean_difference', 0, 'kg', PLACEBO)).toMatchObject({ kind: 'quantified' })
  })

  it.each([
    ['et tall uten mål', [null, 1.7, null], 'value_without_measure'],
    ['et mål uten tall', ['mean_difference', null, 'kg'], 'measure_without_value'],
    ['et mål utenfor vokabularet', ['hazard_ratio', 1.7, null], 'unrecognised_measure'],
    ['en enhet utenfor vokabularet', ['mean_difference', 1.7, 'lbs'], 'unrecognised_unit'],
    ['et dimensjonalt mål uten enhet', ['mean_difference', 1.7, null], 'missing_unit'],
    [
      'en enhet på et dimensjonsløst mål',
      ['risk_ratio', 1.7, 'kg'],
      'unit_on_dimensionless_measure',
    ],
    ['en enhet helt uten mål', [null, null, 'kg'], 'unit_on_dimensionless_measure'],
    ['et tall som ikke er et tall', ['mean_difference', Number.NaN, 'kg'], 'value_without_measure'],
  ])('%s er et brudd', (_label, args, reason) => {
    const [measure, value, unit] = args as [string | null, number | null, string | null]
    expect(magnitude(measure, value, unit, PLACEBO)).toMatchObject({ kind: 'unknown', reason })
  })

  it('bærer råverdiene videre, slik at bruddet kan vises framfor å forsvinne', () => {
    expect(magnitude('hazard_ratio', 1.7, 'lbs', PLACEBO)).toEqual({
      kind: 'unknown',
      reason: 'unrecognised_measure',
      rawMeasure: 'hazard_ratio',
      rawValue: 1.7,
      rawUnit: 'lbs',
    })
  })
})

// ----------------------------------------------------------------------------
// Effektmål og komparator som ett hele
// ----------------------------------------------------------------------------

describe('effektmålet og komparatoren må si det samme', () => {
  it('mean_change med «ingen komparator» er gyldig', () => {
    // Den kanoniske kombinasjonen: en endring fra behandlingsstart, målt
    // innenfor én arm. Dette er hva `none` betyr (migrasjon 004).
    expect(magnitude('mean_change', 1.7, 'kg', NONE)).toEqual({
      kind: 'quantified',
      measure: 'mean_change',
      value: 1.7,
      unit: 'kg',
    })
  })

  it('mean_difference med «ingen komparator» er ikke tolkbart', () => {
    // En gjennomsnittsforskjell uten noe å være forskjellig fra. Skal ikke
    // kunne bli `quantified`, for da kan en visning rendre tallet.
    expect(magnitude('mean_difference', 1.7, 'kg', NONE)).toMatchObject({
      kind: 'unknown',
      reason: 'contrastive_measure_without_comparator',
    })
  })

  it.each(['placebo', 'drug'] as const)(
    'et kontrastivt mål med komparator %s er gyldig',
    (kind) => {
      expect(magnitude('mean_difference', 1.7, 'kg', kind === 'placebo' ? PLACEBO : DRUG)).toEqual({
        kind: 'quantified',
        measure: 'mean_difference',
        value: 1.7,
        unit: 'kg',
      })
    },
  )

  it.each(EFFECT_MEASURES)('%s klassifiseres, ingen faller mellom stolene', (measure) => {
    // Uttømmende over vokabularet: hvert mål er enten innenfor-arm eller
    // kontrastivt, og reglene gjelder i begge retninger. Kommer et sjette mål
    // til, dukker det opp her uten at noen må huske det.
    const unit: string | null = ['mean_change', 'mean_difference'].includes(measure) ? 'kg' : null
    const withinArm = isWithinArmMeasure(measure)

    expect(magnitude(measure, 1.7, unit, NONE)).toMatchObject(
      withinArm ? { kind: 'quantified' } : { reason: 'contrastive_measure_without_comparator' },
    )
    expect(magnitude(measure, 1.7, unit, PLACEBO)).toMatchObject(
      withinArm ? { reason: 'within_arm_measure_with_comparator' } : { kind: 'quantified' },
    )
  })

  it('bare mean_change måler innenfor én arm', () => {
    // Kontrastiv er komplementet, så listen over innenfor-arm-mål er den som må
    // holdes ærlig. Et nytt mål havner blant de kontrastive til noen tar
    // stilling til det — den trygge retningen.
    const withinArm = EFFECT_MEASURES.filter((measure: EffectMeasure) =>
      isWithinArmMeasure(measure),
    )
    expect(withinArm).toEqual(['mean_change'])
  })

  it('mean_change med en komparator er ikke tolkbart', () => {
    // Motsatt vei: en endring innenfor én arm, presentert som om den var en
    // sammenligning mot placebo.
    expect(magnitude('mean_change', 1.7, 'kg', PLACEBO)).toMatchObject({
      kind: 'unknown',
      reason: 'within_arm_measure_with_comparator',
    })
  })

  it('et tall festes ikke til en komparator som selv er brutt', () => {
    const broken: ClaimComparatorState = {
      kind: 'unknown',
      reason: 'unrecognised_kind',
      rawComparatorKind: 'usual_care',
      rawComparatorDrugName: null,
    }
    expect(magnitude('mean_difference', 1.7, 'kg', broken)).toMatchObject({
      kind: 'unknown',
      reason: 'comparator_not_interpretable',
    })
  })

  it('en påstand uten tallfesting rammes ikke av regelen', () => {
    // Uten et tall finnes det ingen feillesning å hindre, og en `none`-kategori
    // uten størrelse er bare det påstanden faktisk sier.
    expect(magnitude(null, null, null, NONE)).toEqual({ kind: 'not_quantified' })
    expect(magnitude(null, null, null, PLACEBO)).toEqual({ kind: 'not_quantified' })
  })

  it('holder de tre tilstandene fra hverandre', () => {
    // Gyldig none, brutt komparator og uforenlig par krever hver sin retting og
    // skal ikke kunne forveksles.
    const valid = magnitude('mean_change', 1.7, 'kg', NONE)
    const brokenComparator = magnitude('mean_difference', 1.7, 'kg', {
      kind: 'unknown',
      reason: 'unrecognised_kind',
      rawComparatorKind: 'usual_care',
      rawComparatorDrugName: null,
    })
    const incoherentPair = magnitude('mean_difference', 1.7, 'kg', NONE)

    expect(valid.kind).toBe('quantified')
    expect(brokenComparator).toMatchObject({ reason: 'comparator_not_interpretable' })
    expect(incoherentPair).toMatchObject({ reason: 'contrastive_measure_without_comparator' })
  })
})

describe('de tre aksene avledes sammen', () => {
  it('gir retning, størrelse og komparator fra én rad', () => {
    expect(
      describeClaimEffect(
        {
          direction: 'increase',
          drug_id: SUBJECT_DRUG,
          comparator_kind: 'placebo',
          comparator_drug_id: null,
          comparator_drug_name: null,
          magnitude_measure: 'mean_difference',
          magnitude_value: 1.7,
          magnitude_unit: 'kg',
        },
        GRADED,
      ),
    ).toEqual({
      direction: { kind: 'increase' },
      magnitude: { kind: 'quantified', measure: 'mean_difference', value: 1.7, unit: 'kg' },
      comparator: { kind: 'placebo' },
    })
  })

  it('lar en brutt komparator slå ut på størrelsen, men ikke på retningen', () => {
    // Retningen er påstandens egen konklusjon og står uavhengig av tallet.
    const effect = describeClaimEffect(
      {
        direction: 'decrease',
        drug_id: SUBJECT_DRUG,
        comparator_kind: 'usual_care',
        comparator_drug_id: null,
        comparator_drug_name: null,
        magnitude_measure: 'mean_difference',
        magnitude_value: 1.7,
        magnitude_unit: 'kg',
      },
      GRADED,
    )
    expect(effect.direction).toEqual({ kind: 'decrease' })
    expect(effect.comparator).toMatchObject({ kind: 'unknown', reason: 'unrecognised_kind' })
    expect(effect.magnitude).toMatchObject({ reason: 'comparator_not_interpretable' })
  })

  it('fanger det uforenlige paret gjennom hele avledningen', () => {
    const effect = describeClaimEffect(
      {
        direction: 'increase',
        drug_id: SUBJECT_DRUG,
        comparator_kind: 'none',
        comparator_drug_id: null,
        comparator_drug_name: null,
        magnitude_measure: 'mean_difference',
        magnitude_value: 1.7,
        magnitude_unit: 'kg',
      },
      GRADED,
    )
    expect(effect.comparator).toEqual({ kind: 'none' })
    expect(effect.magnitude).toMatchObject({
      reason: 'contrastive_measure_without_comparator',
      rawValue: 1.7,
    })
  })
})

describe('en påstand kan ikke være mer presis enn evidensen under den', () => {
  const QUANTIFIED = {
    direction: 'increase',
    drug_id: SUBJECT_DRUG,
    comparator_kind: 'placebo',
    comparator_drug_id: null,
    comparator_drug_name: null,
    magnitude_measure: 'mean_difference',
    magnitude_value: 1.7,
    magnitude_unit: 'kg',
  }

  it('en gradert påstand beholder tallet', () => {
    expect(describeClaimEffect(QUANTIFIED, GRADED).magnitude).toMatchObject({
      kind: 'quantified',
      value: 1.7,
    })
  })

  it('«ingen vurderbar evidens» gjør en tallfestet effekt utolkbar', () => {
    // Migrasjon 004: no_assessable_evidence betyr at det ikke finnes
    // tilstrekkelig grunnlag til å gjøre en vurdering i det hele tatt. Et
    // punktestimat ved siden av den tilstanden er falsk presisjon
    // (ANTIDEP_CONSTITUTION.md §6).
    expect(describeClaimEffect(QUANTIFIED, NO_ASSESSABLE_EVIDENCE).magnitude).toMatchObject({
      kind: 'unknown',
      reason: 'precision_exceeds_assessable_evidence',
      rawValue: 1.7,
    })
  })

  it('rører ikke en påstand som ikke tallfester noe', () => {
    const unquantified = {
      ...QUANTIFIED,
      magnitude_measure: null,
      magnitude_value: null,
      magnitude_unit: null,
    }
    expect(describeClaimEffect(unquantified, NO_ASSESSABLE_EVIDENCE).magnitude).toEqual({
      kind: 'not_quantified',
    })
  })

  it('overstyrer ikke et brudd som allerede er funnet', () => {
    // Rekkefølgen skal ikke skjule den mer spesifikke feilen.
    const noComparator = { ...QUANTIFIED, comparator_kind: 'none' }
    expect(describeClaimEffect(noComparator, NO_ASSESSABLE_EVIDENCE).magnitude).toMatchObject({
      reason: 'contrastive_measure_without_comparator',
    })
  })

  it('avgrenses til den vurderte tilstanden, ikke til ukjent sikkerhet', () => {
    // `unknown` dekker blant annet en kunnskapstype Antidep ikke kjenner, og da
    // vet vi ikke hvilken presisjon som er forsvarlig. Der sier
    // sikkerhetsvisningen fra i stedet.
    const unknownCertainty: ClaimCertainty = {
      kind: 'unknown',
      reason: 'unrecognised_knowledge_type',
      rawCertaintyLevel: 'moderate',
      rawKnowledgeType: 'regulatory_status',
    }
    expect(describeClaimEffect(QUANTIFIED, unknownCertainty).magnitude).toMatchObject({
      kind: 'quantified',
    })
  })
})
