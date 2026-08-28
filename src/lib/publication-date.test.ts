import { describe, expect, it } from 'vitest'
import {
  canonicalPublicationDate,
  EMPTY_PUBLICATION_DATE,
  PUBLICATION_DATE_CHOICES,
} from './publication-date'
import { DATE_PRECISIONS } from '../types/api'
import type { PublicationDateDraft } from './publication-date'

function draft(overrides: Partial<PublicationDateDraft> = {}): PublicationDateDraft {
  return { ...EMPTY_PUBLICATION_DATE, ...overrides }
}

describe('presisjonsvalgene', () => {
  it('er databasens vokabular pluss «ingen dato», i den rekkefølgen', () => {
    // Avledet framfor skrevet ut på nytt: en ny presisjonsverdi i databasen skal
    // ikke kunne bli stående uten et valg i skjemaet.
    expect(PUBLICATION_DATE_CHOICES).toEqual(['none', ...DATE_PRECISIONS])
  })
})

describe('canonicalPublicationDate', () => {
  it('ingen dato gir begge feltene NULL, som constrainten krever', () => {
    // sources_publication_date_precision_pairing_check: dato og presisjon er
    // begge satt eller begge NULL. En udatert kilde er en reell tilstand.
    expect(canonicalPublicationDate(draft({ choice: 'none' }))).toEqual({
      status: 'ok',
      date: null,
      precision: null,
    })
  })

  it('bare år avkortes til 1. januar, uten at brukeren oppgir det', () => {
    // Dette er hele poenget: brukeren skriver «2000», databasen får
    // «2000-01-01» med presisjonen year, og de to kan ikke komme i utakt.
    expect(canonicalPublicationDate(draft({ choice: 'year', year: '2000' }))).toEqual({
      status: 'ok',
      date: '2000-01-01',
      precision: 'year',
    })
  })

  it('år og måned avkortes til den 1. i måneden', () => {
    // «november 2000» → 2000-11-01. Brukeren skal aldri måtte vite det.
    expect(canonicalPublicationDate(draft({ choice: 'month', month: '2000-11' }))).toEqual({
      status: 'ok',
      date: '2000-11-01',
      precision: 'month',
    })
  })

  it('nøyaktig dato sendes uendret', () => {
    expect(canonicalPublicationDate(draft({ choice: 'day', day: '2005-04-07' }))).toEqual({
      status: 'ok',
      date: '2005-04-07',
      precision: 'day',
    })
  })

  it('en valgt presisjon uten dato er incomplete, ikke en halv dato', () => {
    // Uten dette ville skjemaet sendt precision uten date, og databasen ville
    // avvist det med et constraint-navn brukeren ikke kan gjøre noe med.
    for (const choice of ['year', 'month', 'day'] as const) {
      const result = canonicalPublicationDate(draft({ choice }))
      expect(result.status).toBe('incomplete')
    }
  })

  it('hver presisjon leser bare sitt eget felt', () => {
    // De tre feltene lever side om side, slik at et bytte fram og tilbake ikke
    // sletter det brukeren har skrevet. Da må hver gren lese riktig felt — en
    // forveksling ville gitt en dato fra en annen presisjon enn den valgte.
    const filled = draft({ year: '1999', month: '2000-11', day: '2005-04-07' })

    expect(canonicalPublicationDate({ ...filled, choice: 'year' })).toEqual({
      status: 'ok',
      date: '1999-01-01',
      precision: 'year',
    })
    expect(canonicalPublicationDate({ ...filled, choice: 'month' })).toEqual({
      status: 'ok',
      date: '2000-11-01',
      precision: 'month',
    })
    expect(canonicalPublicationDate({ ...filled, choice: 'day' })).toEqual({
      status: 'ok',
      date: '2005-04-07',
      precision: 'day',
    })
    // ...og «ingen dato» ignorerer alle tre framfor å sende den sist utfylte.
    expect(canonicalPublicationDate({ ...filled, choice: 'none' })).toEqual({
      status: 'ok',
      date: null,
      precision: null,
    })
  })

  it('en ufullstendig verdi av riktig type er også incomplete', () => {
    // `<input type="number">` kan stå med «20» mens brukeren skriver, og
    // `<input type="month">`/`type="date"` gir tom streng for en ugyldig verdi.
    expect(canonicalPublicationDate(draft({ choice: 'year', year: '20' })).status).toBe(
      'incomplete',
    )
    expect(canonicalPublicationDate(draft({ choice: 'month', month: '2000' })).status).toBe(
      'incomplete',
    )
    expect(canonicalPublicationDate(draft({ choice: 'day', day: '2000-11' })).status).toBe(
      'incomplete',
    )
  })

  it('lar databasen dømme om datoen er mulig, framfor å dublere regelen', () => {
    // 31. februar har riktig form og slipper gjennom her; databasen avviser den.
    // Kontrollen i denne modulen er en formkontroll, ikke en gyldighetskontroll
    // — CHECK-constraintene er fortsatt fasiten (§43, §48).
    expect(canonicalPublicationDate(draft({ choice: 'day', day: '2000-02-31' }))).toEqual({
      status: 'ok',
      date: '2000-02-31',
      precision: 'day',
    })
  })
})
