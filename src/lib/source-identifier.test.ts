import { describe, expect, it } from 'vitest'
import { DOI_UNSAFE_CHARACTERS, describeDoi, describePmid } from './source-identifier'

// ============================================================================
// Avledningen fra en registrert identifikator til en adresse.
//
// Mønstrene speiler `CHECK`-betingelsene i migrasjon 003, og testene prøver
// ytterpunktene framfor midten: en form som er ett siffer for kort eller ett for
// lang, uten skilletegn, med et prefiks foran eller et ledd bak. En lenke som
// bygges av en verdi utenfor formen, peker et annet sted uten å se feil ut.
// ============================================================================

describe('DOI', () => {
  it('en registrert DOI blir en adresse hos den offisielle resolveren', () => {
    expect(describeDoi('10.1000/abc123')).toEqual({
      kind: 'resolvable',
      value: '10.1000/abc123',
      href: 'https://doi.org/10.1000/abc123',
    })
  })

  it('skilletegnet mellom prefiks og suffiks kodes ikke', () => {
    // «/» er en del av DOI-en, og resolveren forventer den ukodet. Kodet ville
    // adressen pekt på en annen DOI enn den registrerte.
    const link = describeDoi('10.1000/a/b/c')
    expect(link).toMatchObject({ href: 'https://doi.org/10.1000/a/b/c' })
  })

  it('tegn som endrer betydningen av en URL prosentkodes', () => {
    // Formen på gamle Wiley-DOI-er. Ukodet ville «<» og «>» gitt en adresse
    // nettleseren tolker annerledes enn DOI-en sier.
    const link = describeDoi('10.1002/(sici)1097-0258(19970615)16:11<1223::aid-sim550>3.0.co;2-2')
    expect(link).toMatchObject({
      href: 'https://doi.org/10.1002/(sici)1097-0258(19970615)16:11%3C1223::aid-sim550%3E3.0.co;2-2',
    })
  })

  it('et fragmenttegn kutter ikke adressen', () => {
    // Ukodet ville alt etter «#» blitt et fragment, og resolveren ville fått en
    // annen DOI enn den registrerte.
    expect(describeDoi('10.1000/abc#def')).toMatchObject({
      href: 'https://doi.org/10.1000/abc%23def',
    })
  })

  it('et spørsmålstegn blir ikke til en spørrestreng', () => {
    expect(describeDoi('10.1000/abc?def')).toMatchObject({
      href: 'https://doi.org/10.1000/abc%3Fdef',
    })
  })

  it('en prosent i verdien kodes én gang, ikke to', () => {
    // Kodes «%» i et eget steg før de øvrige tegnene, blir «%23» til «%2523».
    expect(describeDoi('10.1000/abc%23def')).toMatchObject({
      href: 'https://doi.org/10.1000/abc%2523def',
    })
  })

  it('hvert tegn i den utrygge mengden kodes, og bare de', () => {
    // Listen og mønsteret er to skrivemåter av samme regel. Uten denne kunne et
    // tegn falt ut av mønsteret uten at noe feilet.
    for (const character of DOI_UNSAFE_CHARACTERS) {
      const link = describeDoi(`10.1000/x${character}y`)
      expect(link).toMatchObject({
        href: `https://doi.org/10.1000/x%${character.charCodeAt(0).toString(16).toUpperCase()}y`,
      })
    }

    // Alt annet som kan stå i en DOI, står uendret. 0x21 til 0x7e er de
    // synlige ASCII-tegnene; blanktegn kan ikke forekomme, fordi formen krever
    // `\S`.
    const unsafe = new Set([...DOI_UNSAFE_CHARACTERS])
    for (let code = 0x21; code <= 0x7e; code += 1) {
      const character = String.fromCharCode(code)
      if (unsafe.has(character)) {
        continue
      }
      expect(describeDoi(`10.1000/x${character}y`)).toMatchObject({
        href: `https://doi.org/10.1000/x${character}y`,
      })
    }
  })

  it('bokstavstørrelse gjør ikke en DOI ulenkbar', () => {
    // Databasen krever små bokstaver for at unikhetsregelen skal holde, men en
    // DOI er ikke bokstavstørrelsesfølsom: lenken er riktig uansett, og å skjule
    // den ville straffet leseren for en registreringsfeil.
    expect(describeDoi('10.1000/ABC')).toMatchObject({ kind: 'resolvable' })
  })

  it('en verdi utenfor den registrerte formen blir ingen adresse', () => {
    const outside = [
      '', // tom
      '10.1000', // uten skilletegn
      '10.1000/', // uten suffiks
      '10.100/abc', // ett siffer for kort i registrantkoden
      '10.1234567890/abc', // ett siffer for langt
      '11.1000/abc', // feil prefiks
      'doi:10.1000/abc', // prefikset skrivemåte
      'https://doi.org/10.1000/abc', // allerede en adresse
      'x10.1000/abc', // et ledd foran
      '10.1000/abc def', // blanktegn i suffikset
      '10.1000/abc\n', // avsluttende linjeskift
      '10.1000/abc\nx', // et ledd bak, etter linjeskift
    ]
    for (const value of outside) {
      expect(describeDoi(value)).toEqual({ kind: 'unresolvable', value })
    }
  })
})

describe('PMID', () => {
  it('en registrert PMID blir en adresse hos PubMed', () => {
    expect(describePmid('12345678')).toEqual({
      kind: 'resolvable',
      value: '12345678',
      href: 'https://pubmed.ncbi.nlm.nih.gov/12345678/',
    })
  })

  it('ytterpunktene i lengden', () => {
    expect(describePmid('1')).toMatchObject({ kind: 'resolvable' })
    expect(describePmid('999999999')).toMatchObject({ kind: 'resolvable' })
    expect(describePmid('1000000000')).toMatchObject({ kind: 'unresolvable' })
  })

  it('en verdi utenfor den registrerte formen blir ingen adresse', () => {
    const outside = [
      '',
      '0', // null er ikke en PMID
      '0123', // ledende null
      '12a34',
      ' 1234',
      '1234 ',
      '1234\n',
      'PMID12345',
    ]
    for (const value of outside) {
      expect(describePmid(value)).toEqual({ kind: 'unresolvable', value })
    }
  })
})
