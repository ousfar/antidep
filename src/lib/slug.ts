// ============================================================================
// Menneskelesbare adresser avledet fra kanoniske navn
//
// `api` eksponerer katalogobjekter med `uuid` og ingen slug-kolonne
// (MVP_IMPLEMENTATION_PLAN.md §74.5 punkt 2). Rutingen trenger likevel
// `/drugs/sertralin` og ikke `/drugs/3f2a…` — §30 navngir adressen eksplisitt,
// og §55 krever at den er delbar. Sluggen avledes derfor her, i klienten, fra
// det kanoniske navnet.
//
// ----------------------------------------------------------------------------
// Hva det koster, og hvorfor det likevel er riktig nå
//
// En slug avledet fra et visningsnavn er ikke en stabil identitet: endres
// navnet i katalogen, endres adressen, og en delt lenke slutter å virke. Det er
// registrert som gjeld i §74.7. Alternativet — å legge uuid-en i URL-en — ville
// oppfylt §55 rent teknisk, men gitt klinikeren en adresse som verken kan leses
// eller skrives, og §30 ber om det motsatte. Alternativet nummer to, en
// slug-kolonne i katalogen, er en migrasjon utenfor denne slicen.
//
// Påstandens identitet er ikke berørt: `claim_id` er og blir uuid-en i
// lenken til evidensvisningen (§7 i ANTIDEP_CONSTITUTION.md).
//
// ----------------------------------------------------------------------------
// Tvetydighet er en egen tilstand, ikke «ta den første»
//
// Avledningen er tapsgivende: to forskjellige navn kan gi samme slug. Å velge
// den første treffer riktig ni ganger av ti og viser feil virkestoff den tiende
// — en feil som ser ut som et gyldig svar. Oppslaget svarer derfor `ambiguous`,
// og visningen sier fra framfor å gjette (ANTIDEP_CONSTITUTION.md §17: en
// tilstand som ikke er kjent, skal ikke se ut som et svar).
// ============================================================================

/**
 * Norske bokstaver skrives om framfor å bli prosentkodet, slik at adressen
 * fortsatt kan leses og skrives for hånd. Omskrivingen er tapsgivende — «år» og
 * «ar» gir samme slug — og det er nettopp derfor oppslaget under kontrollerer
 * tvetydighet framfor å anta at avledningen er injektiv.
 */
const NORWEGIAN_LETTERS: Record<string, string> = {
  æ: 'ae',
  ø: 'o',
  å: 'a',
}

/**
 * Sluggen for ett kanonisk navn. Tom streng betyr at navnet ikke har noen
 * adresserbar form — et navn som bare består av tegn som ikke overlever
 * avledningen. Det er ikke en gyldig slug, og oppslaget under matcher den ikke.
 */
export function toSlug(value: string): string {
  return (
    value
      .toLowerCase()
      .replaceAll(/[æøå]/gu, (letter) => NORWEGIAN_LETTERS[letter] ?? letter)
      // Dekomponer og fjern diakritiske tegn (é → e). Norske bokstaver er
      // allerede tatt over, fordi NFD ville gjort «å» til «a» og «ø» til «ø».
      .normalize('NFD')
      .replaceAll(/\p{Diacritic}/gu, '')
      .replaceAll(/[^a-z0-9]+/gu, '-')
      .replaceAll(/^-+|-+$/gu, '')
  )
}

/** Resultatet av å slå opp én slug i et sett med navngitte objekter. */
export type SlugLookup<Item> =
  | { readonly kind: 'found'; readonly item: Item }
  /** Ingen i settet har denne sluggen. Sier ingenting om verden utenfor settet. */
  | { readonly kind: 'not_found' }
  /**
   * Flere navn gir samme slug. Adressen peker ikke entydig på ett objekt, og
   * det finnes ikke noe riktig valg å ta på leserens vegne.
   */
  | { readonly kind: 'ambiguous'; readonly items: readonly [Item, Item, ...Item[]] }

/**
 * Slår opp én slug blant navngitte objekter.
 *
 * Sluggen fra URL-en normaliseres på samme måte som navnene, slik at
 * `/drugs/Sertralin` og `/drugs/sertralin` treffer samme rad. En tom slug
 * treffer aldri — heller ikke et navn som selv ga tom slug, som ellers ville
 * blitt et objekt uten adresse som svarte på adressen «ingenting».
 */
export function findBySlug<Item>(
  items: readonly Item[],
  slug: string,
  nameOf: (item: Item) => string,
): SlugLookup<Item> {
  const wanted = toSlug(slug)
  if (wanted.length === 0) {
    return { kind: 'not_found' }
  }
  const matches = items.filter((item) => toSlug(nameOf(item)) === wanted)
  const [first, second, ...rest] = matches
  if (first === undefined) {
    return { kind: 'not_found' }
  }
  if (second === undefined) {
    return { kind: 'found', item: first }
  }
  return { kind: 'ambiguous', items: [first, second, ...rest] }
}
