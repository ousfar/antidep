// ============================================================================
// Fra en registrert identifikator til en lenke til originalen
//
// DOI og PMID har til nå stått som ren tekst. Å gjøre dem om til lenker er en
// egen beslutning, og den ble bevisst utsatt til kildesiden
// (MVP_IMPLEMENTATION_PLAN.md §74.15): å vise en streng fra databasen er noe
// annet enn å bygge en URL av den. En URL bygget på slump kan sende en kliniker
// til feil publikasjon, og en feil lenke ser ut som en riktig lenke.
//
// Beslutningen her er å lenke, fordi etterprøvbarhet mot originalkilden er hele
// poenget med kilde- og evidensvisningene (ANTIDEP_CONSTITUTION.md §4, §11;
// PRODUCT_INFORMATION_ARCHITECTURE.md §43). To ting gjør den forsvarlig:
//
// ----------------------------------------------------------------------------
// 1. Formen er håndhevet i databasen, og kontrolleres likevel her
//
// Migrasjon 003 legger to `CHECK`-betingelser på
// `knowledge.source_identifiers`:
//
//   doi   identifier_value ~ '^10\.[0-9]{4,9}/\S+$'   og små bokstaver
//   pmid  identifier_value ~ '^[1-9][0-9]{0,8}$'
//
// Det er laget som faktisk garanterer at verdien *er* en DOI eller en PMID, og
// ikke en URL, et `doi:`-prefiks eller en fritekst. Uten den garantien ville en
// lenke vært en gjetning.
//
// Mønstrene gjentas her likevel, av samme grunn som vokabularene har
// kjøretidskontroll: en betingelse i en migrasjon er ingen kontroll i klienten,
// og en verdi som ikke oppfyller formen skal bli en eksplisitt ukjent tilstand
// framfor en URL ingen har tatt stilling til. Bokstavstørrelsen er bevisst
// *ikke* del av kontrollen: DOI-er er ikke bokstavstørrelsesfølsomme, så en
// verdi med store bokstaver bryter databasens unikhetsregel uten å gjøre lenken
// feil, og å skjule en fungerende lenke for den forskjellen ville vært å
// straffe leseren for en registreringsfeil.
//
// ----------------------------------------------------------------------------
// 2. Suffikset prosentkodes, framfor å settes rått inn i en URL
//
// `\S+` tillater alt som ikke er blanktegn, og en DOI kan lovlig inneholde
// tegn som endrer betydningen av en URL: `#` ville kuttet adressen ved et
// fragment, `?` ville gjort resten til en spørrestreng, og eldre DOI-er
// inneholder `<` og `>`. Alle tre ville gitt en lenke som ser riktig ut og
// peker et annet sted.
//
// Tegnene under er DOI-håndbokens liste over hva som må kodes når en DOI settes
// inn i en URL. `/` står bevisst ikke i den: skilletegnet mellom prefiks og
// suffiks er en del av DOI-en, og resolveren forventer den ukodet.
// ============================================================================

/**
 * Én identifikator, med eller uten en adresse som kan følges.
 *
 * `value` er alltid verdien slik den står registrert. En identifikator som ikke
 * lar seg gjøre om til en adresse forsvinner ikke — den vises som tekst, og
 * visningen sier at formen ikke er den registrerte. Et felt som blir borte
 * fordi en avledning feilet, ser ut som fravær av data
 * (ANTIDEP_CONSTITUTION.md §17).
 */
export type SourceIdentifierLink =
  | { readonly kind: 'resolvable'; readonly value: string; readonly href: string }
  | { readonly kind: 'unresolvable'; readonly value: string }

/** Formen migrasjon 003 håndhever på en DOI. Forankret i begge ender. */
const DOI_PATTERN = /^10\.[0-9]{4,9}\/\S+$/

/** Formen migrasjon 003 håndhever på en PMID: positivt heltall uten ledende null. */
const PMID_PATTERN = /^[1-9][0-9]{0,8}$/

/**
 * Tegnene som må prosentkodes før en DOI settes inn i en URL-sti.
 *
 * Eksportert for testen, som kontrollerer at listen og mønsteret under beskriver
 * nøyaktig samme mengde. To skrivemåter av samme regel driver fra hverandre, og
 * et tegn som faller ut av mønsteret gir en lenke som peker feil uten å se feil
 * ut.
 */
export const DOI_UNSAFE_CHARACTERS = '"#%<>?[\\]^`{|}+'

const DOI_UNSAFE_PATTERN = /["#%<>?[\\\]^`{|}+]/g

/**
 * Ett tegn som prosentkode.
 *
 * Alle tegnene i mengden over er ASCII i området 0x22–0x7D, så koden er alltid
 * to heksadesimale sifre. Testen kontrollerer det for hvert enkelt tegn framfor
 * at koden antar det.
 */
function percentEncode(character: string): string {
  return `%${character.charCodeAt(0).toString(16).toUpperCase()}`
}

/**
 * DOI som adresse hos den offisielle resolveren.
 *
 * `%` kodes sammen med de øvrige tegnene og ikke i et eget steg: `replace`
 * leser den opprinnelige strengen fra venstre mot høyre, så en kode som settes
 * inn, kodes ikke på nytt.
 */
export function describeDoi(value: string): SourceIdentifierLink {
  if (!DOI_PATTERN.test(value)) {
    return { kind: 'unresolvable', value }
  }
  return {
    kind: 'resolvable',
    value,
    href: `https://doi.org/${value.replace(DOI_UNSAFE_PATTERN, percentEncode)}`,
  }
}

/**
 * PMID som adresse hos PubMed.
 *
 * Ingen koding: formen er bare siffer, og et siffer betyr det samme i en URL
 * som utenfor den.
 */
export function describePmid(value: string): SourceIdentifierLink {
  if (!PMID_PATTERN.test(value)) {
    return { kind: 'unresolvable', value }
  }
  return { kind: 'resolvable', value, href: `https://pubmed.ncbi.nlm.nih.gov/${value}/` }
}
