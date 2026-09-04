import { describe, expect, it } from 'vitest'
import {
  EMPTY_CONFIDENCE_INTERVAL_DRAFT,
  EMPTY_NUMBER_DRAFT,
  EMPTY_POPULATION_DRAFT,
  EMPTY_TIMEPOINT_DRAFT,
  availabilityHasValue,
  canonicalConfidenceInterval,
  canonicalNumber,
  canonicalPopulation,
  canonicalTimepoint,
} from './evidence-registration'
import { AVAILABILITY_PARTITION } from './evidence-item'
import { VALUE_AVAILABILITIES } from '../types/api'

// ============================================================================
// Kanoniseringen fra skjemautfylling til det databasen krever.
//
// Testene her handler om null/ukjent-semantikken, ikke om databasens
// constraints: at et estimat utenfor sitt eget konfidensintervall avvises,
// prøves i 390_evidence_item_registration_test.sql mot en ekte database.
// ============================================================================

const MISSING = { missingMessage: 'Fyll inn verdien.' }

describe('availabilityHasValue', () => {
  it('er sann for nøyaktig de to statusene der en verdi står i kolonnen', () => {
    // Delingen er den samme evidence-item.ts bygger visningen på. Kontrollert
    // mot den framfor mot en liste skrevet på nytt her.
    const present = VALUE_AVAILABILITIES.filter(availabilityHasValue)
    expect(new Set(present)).toEqual(new Set(AVAILABILITY_PARTITION.present))
  })

  it('er usann for hver av de fire fraværsgrunnene', () => {
    for (const availability of AVAILABILITY_PARTITION.absent) {
      expect(availabilityHasValue(availability)).toBe(false)
    }
  })
})

describe('canonicalNumber', () => {
  it('gir null når statusen sier at verdien ikke finnes, uansett hva som står i feltet', () => {
    // Feltet kan bære en verdi fra et tidligere valg. Statusen, ikke inputen,
    // avgjør hva som sendes — ellers ville paret databasen håndhever kunne
    // brytes fra skjemaet.
    expect(canonicalNumber({ availability: 'not_measured', value: '240' }, MISSING)).toEqual({
      status: 'ok',
      value: null,
    })
  })

  it('leser et tall når statusen sier at kilden oppgir det', () => {
    expect(canonicalNumber({ availability: 'reported_value', value: '1.7' }, MISSING)).toEqual({
      status: 'ok',
      value: 1.7,
    })
  })

  it('leser komma som desimalskilletegn', () => {
    // En norsk kliniker skriver 1,7. Se hodekommentaren i modulen.
    expect(canonicalNumber({ availability: 'reported_value', value: '1,7' }, MISSING)).toEqual({
      status: 'ok',
      value: 1.7,
    })
  })

  it('godtar et negativt estimat: en reduksjon er en gyldig verdi', () => {
    expect(canonicalNumber({ availability: 'reported_value', value: '-0,8' }, MISSING)).toEqual({
      status: 'ok',
      value: -0.8,
    })
  })

  it('sier fra når statusen lover en verdi som ikke er fylt ut', () => {
    expect(canonicalNumber({ availability: 'reported_value', value: '' }, MISSING)).toEqual({
      status: 'incomplete',
      message: 'Fyll inn verdien.',
    })
  })

  it('avviser tekst som ikke er et tall, framfor å sende NaN', () => {
    expect(
      canonicalNumber({ availability: 'uncertain_extraction', value: 'ca. 2' }, MISSING),
    ).toEqual({ status: 'incomplete', message: 'Fyll inn verdien.' })
  })

  it('krever et helt tall når feltet er et antall', () => {
    const draft = { availability: 'reported_value', value: '240,5' } as const
    expect(canonicalNumber(draft, { ...MISSING, whole: true })).toEqual({
      status: 'incomplete',
      message: 'Fyll inn verdien.',
    })
    expect(canonicalNumber({ ...draft, value: '240' }, { ...MISSING, whole: true })).toEqual({
      status: 'ok',
      value: 240,
    })
  })

  it('starter som «ikke rapportert»: skjemaet antar ikke at kilden oppgir noe', () => {
    expect(availabilityHasValue(EMPTY_NUMBER_DRAFT.availability)).toBe(false)
  })
})

describe('canonicalPopulation', () => {
  it('gir null når koblingen ikke er gjort', () => {
    expect(canonicalPopulation(EMPTY_POPULATION_DRAFT)).toEqual({
      status: 'ok',
      populationId: null,
    })
  })

  it('sier fra når statusen lover en kobling som ikke er valgt', () => {
    const result = canonicalPopulation({ availability: 'reported_value', populationId: '' })
    expect(result.status).toBe('incomplete')
  })

  it('sender populasjonen når den er valgt', () => {
    expect(
      canonicalPopulation({ availability: 'uncertain_extraction', populationId: 'p1' }),
    ).toEqual({ status: 'ok', populationId: 'p1' })
  })
})

describe('canonicalTimepoint', () => {
  it('gir begge grensene som null når tidsrommet ikke er rapportert', () => {
    // Paret er alltid begge satt eller begge NULL.
    expect(canonicalTimepoint(EMPTY_TIMEPOINT_DRAFT)).toEqual({
      status: 'ok',
      min: null,
      max: null,
    })
  })

  it('gjør ett oppgitt tidspunkt til like grenser', () => {
    expect(
      canonicalTimepoint({
        availability: 'reported_value',
        unit: 'weeks',
        from: '8',
        to: '',
      }),
    ).toEqual({ status: 'ok', min: '8 weeks', max: '8 weeks' })
  })

  it('beholder et spenn som et spenn, framfor å avrunde til falsk presisjon', () => {
    expect(
      canonicalTimepoint({
        availability: 'reported_value',
        unit: 'weeks',
        from: '26',
        to: '32',
      }),
    ).toEqual({ status: 'ok', min: '26 weeks', max: '32 weeks' })
  })

  it('setter enheten sammen med tallet, slik at de to ikke kan komme fra hverandre', () => {
    expect(
      canonicalTimepoint({
        availability: 'reported_value',
        unit: 'months',
        from: '6',
        to: '',
      }),
    ).toEqual({ status: 'ok', min: '6 months', max: '6 months' })
  })

  it('sier fra når tidsrommet er lovet, men ikke fylt ut', () => {
    const result = canonicalTimepoint({
      availability: 'reported_value',
      unit: 'weeks',
      from: '',
      to: '',
    })
    expect(result.status).toBe('incomplete')
  })

  it('sier fra når øvre grense er skrevet, men ikke er et tall', () => {
    const result = canonicalTimepoint({
      availability: 'reported_value',
      unit: 'weeks',
      from: '8',
      to: 'tolv',
    })
    expect(result.status).toBe('incomplete')
  })
})

describe('canonicalConfidenceInterval', () => {
  it('gir alle tre som null når intervallet ikke er rapportert', () => {
    expect(canonicalConfidenceInterval(EMPTY_CONFIDENCE_INTERVAL_DRAFT)).toEqual({
      status: 'ok',
      lower: null,
      upper: null,
      level: null,
    })
  })

  it('leser alle tre verdiene når intervallet er rapportert', () => {
    expect(
      canonicalConfidenceInterval({
        availability: 'reported_value',
        lower: '0,9',
        upper: '2,5',
        level: '95',
      }),
    ).toEqual({ status: 'ok', lower: 0.9, upper: 2.5, level: 95 })
  })

  it('sier fra når bare den ene grensen er fylt ut: en halv grense er ingen grense', () => {
    const result = canonicalConfidenceInterval({
      availability: 'reported_value',
      lower: '0,9',
      upper: '',
      level: '95',
    })
    expect(result.status).toBe('incomplete')
  })

  it('sier fra når nivået er tomt, framfor å anta 95 på kildens vegne', () => {
    const result = canonicalConfidenceInterval({
      availability: 'reported_value',
      lower: '0,9',
      upper: '2,5',
      level: '',
    })
    expect(result.status).toBe('incomplete')
  })
})
