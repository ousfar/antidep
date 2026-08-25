import { describe, expect, it } from 'vitest'
import { findBySlug, toSlug } from './slug'

describe('toSlug', () => {
  it('gir adressene §30 navngir', () => {
    // De to pilotvirkestoffene lagres med liten forbokstav i katalogen
    // (migrasjon 002), og planen navngir /drugs/sertralin og /drugs/mirtazapin.
    expect(toSlug('sertralin')).toBe('sertralin')
    expect(toSlug('mirtazapin')).toBe('mirtazapin')
  })

  it('skriver om norske bokstaver framfor å prosentkode dem', () => {
    expect(toSlug('vektøkning')).toBe('vektokning')
    expect(toSlug('Måltid')).toBe('maltid')
    expect(toSlug('Ærlig')).toBe('aerlig')
  })

  it('fjerner diakritiske tegn uten å fjerne bokstaven', () => {
    expect(toSlug('café')).toBe('cafe')
    // Midt i ordet, der et tegn som ikke fjernes ville blitt til en bindestrek
    // framfor å forsvinne. En trailende bindestrek trimmes uansett bort, så
    // «café» alene ville ikke skilt de to.
    expect(toSlug('précis')).toBe('precis')
  })

  it('slår sammen skilletegn og mellomrom til én bindestrek', () => {
    expect(toSlug('seksuell  dysfunksjon')).toBe('seksuell-dysfunksjon')
    expect(toSlug('QT-forlengelse (EKG)')).toBe('qt-forlengelse-ekg')
  })

  it('lar tall stå', () => {
    expect(toSlug('CYP2D6-hemming')).toBe('cyp2d6-hemming')
  })

  it('trimmer bindestreker i begge ender', () => {
    expect(toSlug('  – vekt –  ')).toBe('vekt')
  })

  it('gir tom streng når ingenting overlever', () => {
    // Ikke en gyldig adresse. Oppslaget under matcher den ikke.
    expect(toSlug('———')).toBe('')
    expect(toSlug('')).toBe('')
  })
})

interface Named {
  readonly name: string
}

const named = (name: string): Named => ({ name })
const nameOf = (item: Named) => item.name

describe('findBySlug', () => {
  it('finner objektet sluggen peker på', () => {
    const result = findBySlug([named('mirtazapin'), named('sertralin')], 'sertralin', nameOf)
    expect(result).toEqual({ kind: 'found', item: named('sertralin') })
  })

  it('normaliserer sluggen fra URL-en på samme måte som navnet', () => {
    // /drugs/Sertralin og /drugs/sertralin er samme side.
    expect(findBySlug([named('sertralin')], 'Sertralin', nameOf).kind).toBe('found')
  })

  it('sier ikke funnet framfor å velge noe i nærheten', () => {
    expect(findBySlug([named('sertralin')], 'mirtazapin', nameOf)).toEqual({ kind: 'not_found' })
  })

  it('sier fra når to navn gir samme slug, framfor å ta det første', () => {
    // Avledningen er tapsgivende. Å vise det første ville vært et gyldig
    // utseende svar om feil objekt.
    // Omskrivingen ø → o er tapsgivende, og det er nettopp den som kan kollidere.
    const items = [named('vektøkning'), named('vektokning')]
    const result = findBySlug(items, 'vektokning', nameOf)
    expect(result.kind).toBe('ambiguous')
    if (result.kind !== 'ambiguous') {
      throw new Error('forventet ambiguous')
    }
    expect(result.items).toHaveLength(2)
  })

  it('en tom slug treffer ingenting, heller ikke et navn uten slug', () => {
    // Ellers ville et objekt uten adresse svart på adressen «ingenting».
    expect(findBySlug([named('———')], '', nameOf)).toEqual({ kind: 'not_found' })
    expect(findBySlug([named('———')], '———', nameOf)).toEqual({ kind: 'not_found' })
  })

  it('et tomt sett gir ikke funnet, ikke tvetydig', () => {
    expect(findBySlug([], 'sertralin', nameOf)).toEqual({ kind: 'not_found' })
  })
})
