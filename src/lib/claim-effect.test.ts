import { describe, expect, it } from 'vitest'
import {
  describeClaimComparator,
  describeClaimDirection,
  describeClaimEffect,
  describeClaimMagnitude,
} from './claim-effect'

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
    expect(describeClaimComparator('drug', 'mirtazapin')).toEqual({
      kind: 'drug',
      drugName: 'mirtazapin',
    })
  })

  it.each([
    ['placebo', 'placebo'],
    ['none', 'none'],
  ])('%s uten virkestoff', (value, kind) => {
    expect(describeClaimComparator(value, null)).toEqual({ kind })
  })

  it('«ingen komparator» er ikke «ukjent komparator»', () => {
    expect(describeClaimComparator('none', null)).toEqual({ kind: 'none' })
  })

  it('kategorien drug uten navn er et brudd, ikke en anonym sammenligning', () => {
    expect(describeClaimComparator('drug', null)).toEqual({
      kind: 'unknown',
      reason: 'unnamed_comparator_drug',
      rawComparatorKind: 'drug',
      rawComparatorDrugName: null,
    })
  })

  it('et virkestoff på en kategori som ikke er drug er et brudd', () => {
    // Databasen binder de to sammen. Kommer de fra hverandre, sier raden to
    // forskjellige ting om hva påstanden sammenlignes mot.
    expect(describeClaimComparator('placebo', 'sertralin')).toEqual({
      kind: 'unknown',
      reason: 'named_drug_without_drug_kind',
      rawComparatorKind: 'placebo',
      rawComparatorDrugName: 'sertralin',
    })
  })

  it.each(['usual_care', 'DRUG', ''])(
    'en kategori utenfor vokabularet (%s) blir ukjent',
    (value) => {
      expect(describeClaimComparator(value, null)).toEqual({
        kind: 'unknown',
        reason: 'unrecognised_kind',
        rawComparatorKind: value,
        rawComparatorDrugName: null,
      })
    },
  )
})

describe('størrelse', () => {
  it('et dimensjonalt mål med enhet', () => {
    expect(describeClaimMagnitude('mean_difference', 1.7, 'kg')).toEqual({
      kind: 'quantified',
      measure: 'mean_difference',
      value: 1.7,
      unit: 'kg',
    })
  })

  it('et dimensjonsløst mål uten enhet', () => {
    expect(describeClaimMagnitude('odds_ratio', 2.1, null)).toEqual({
      kind: 'quantified',
      measure: 'odds_ratio',
      value: 2.1,
      unit: null,
    })
  })

  it('ingen tallfesting er ikke en effekt på null', () => {
    expect(describeClaimMagnitude(null, null, null)).toEqual({ kind: 'not_quantified' })
  })

  it('en tallfestet effekt på null er en målt verdi, ikke fravær', () => {
    expect(describeClaimMagnitude('mean_difference', 0, 'kg')).toEqual({
      kind: 'quantified',
      measure: 'mean_difference',
      value: 0,
      unit: 'kg',
    })
  })

  it.each([
    ['et tall uten mål', [null, 1.7, null], 'value_without_measure'],
    ['et mål uten tall', ['mean_difference', null, 'kg'], 'measure_without_value'],
    ['et mål utenfor vokabularet', ['hazard_ratio', 1.7, null], 'unrecognised_measure'],
    ['en enhet utenfor vokabularet', ['mean_difference', 1.7, 'lbs'], 'unrecognised_unit'],
    ['et dimensjonalt mål uten enhet', ['mean_change', 1.7, null], 'missing_unit'],
    [
      'en enhet på et dimensjonsløst mål',
      ['risk_ratio', 1.7, 'kg'],
      'unit_on_dimensionless_measure',
    ],
    ['en enhet helt uten mål', [null, null, 'kg'], 'unit_on_dimensionless_measure'],
    ['et tall som ikke er et tall', ['mean_difference', Number.NaN, 'kg'], 'value_without_measure'],
  ])('%s er et brudd (%#)', (_label, args, reason) => {
    const [measure, value, unit] = args as [string | null, number | null, string | null]
    expect(describeClaimMagnitude(measure, value, unit)).toMatchObject({
      kind: 'unknown',
      reason,
    })
  })

  it('bærer råverdiene videre, slik at bruddet kan vises framfor å forsvinne', () => {
    expect(describeClaimMagnitude('hazard_ratio', 1.7, 'lbs')).toEqual({
      kind: 'unknown',
      reason: 'unrecognised_measure',
      rawMeasure: 'hazard_ratio',
      rawValue: 1.7,
      rawUnit: 'lbs',
    })
  })

  it('skiller de tre dimensjonsløse målene fra de to dimensjonale', () => {
    // Regelen er migrasjon 004 sin: enhet er påkrevd for mean_change og
    // mean_difference, forbudt for de tre andre. Testen holder listen ærlig.
    const dimensionless = ['standardised_mean_difference', 'risk_ratio', 'odds_ratio']
    const dimensional = ['mean_change', 'mean_difference']

    for (const measure of dimensionless) {
      expect(describeClaimMagnitude(measure, 1.2, null)).toMatchObject({ kind: 'quantified' })
      expect(describeClaimMagnitude(measure, 1.2, 'kg')).toMatchObject({
        reason: 'unit_on_dimensionless_measure',
      })
    }
    for (const measure of dimensional) {
      expect(describeClaimMagnitude(measure, 1.2, 'kg')).toMatchObject({ kind: 'quantified' })
      expect(describeClaimMagnitude(measure, 1.2, null)).toMatchObject({ reason: 'missing_unit' })
    }
  })
})

describe('de tre aksene avledes sammen', () => {
  it('gir retning, størrelse og komparator fra én rad', () => {
    expect(
      describeClaimEffect({
        direction: 'increase',
        comparator_kind: 'placebo',
        comparator_drug_name: null,
        magnitude_measure: 'mean_difference',
        magnitude_value: 1.7,
        magnitude_unit: 'kg',
      }),
    ).toEqual({
      direction: { kind: 'increase' },
      magnitude: { kind: 'quantified', measure: 'mean_difference', value: 1.7, unit: 'kg' },
      comparator: { kind: 'placebo' },
    })
  })

  it('lar én brutt akse stå alene uten å ta de to andre med seg', () => {
    // En ukjent komparator gjør ikke retningen ukjent. Å slå dem sammen ville
    // skjult informasjon som er gyldig.
    const effect = describeClaimEffect({
      direction: 'decrease',
      comparator_kind: 'usual_care',
      comparator_drug_name: null,
      magnitude_measure: null,
      magnitude_value: null,
      magnitude_unit: null,
    })
    expect(effect.direction).toEqual({ kind: 'decrease' })
    expect(effect.magnitude).toEqual({ kind: 'not_quantified' })
    expect(effect.comparator).toMatchObject({ kind: 'unknown', reason: 'unrecognised_kind' })
  })
})
