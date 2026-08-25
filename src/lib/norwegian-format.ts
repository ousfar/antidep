// ============================================================================
// Norsk gjengivelse av databaseverdier
//
// Tre verdityper fra `api` må skrives om før en kliniker ser dem: intervaller,
// tidsstempler og tall. Alle tre har den samme fellen — en verdi som ikke lar
// seg tolke må ikke bli borte, og den må ikke bli gjettet på. Et felt som
// forsvinner fordi formateringen feilet, ser ut som fravær av data, og fravær
// av data skal aldri kunne leses som ingen risiko (ANTIDEP_CONSTITUTION.md §17).
//
// Derfor returnerer alle tre en `RenderedValue`, ikke en streng: den som ikke
// lot seg tolke, bærer databaseverdien uendret, og kalleren kan merke den.
//
// ----------------------------------------------------------------------------
// Hvorfor intervallformatet er som det er
//
// PostgREST serialiserer `interval` med PostgreSQLs egen tekstrepresentasjon,
// og Supabase kjører med standardinnstillingen `IntervalStyle = postgres`.
// Formen er kontrollert empirisk mot PostgreSQL 16, ikke antatt:
//
//   interval '8 weeks'              →  "56 days"
//   interval '3 months'             →  "3 mons"
//   interval '18 months'            →  "1 year 6 mons"
//   interval '1 year 2 mons 3 days' →  "1 year 2 mons 3 days"
//   interval '12 hours'             →  "12:00:00"
//   to_json(interval '8 weeks')     →  "56 days"   (samme form i JSON)
//
// Merk at uker ikke overlever: databasen normaliserer dem til dager. Vi regner
// dem ikke tilbake. «8 uker» leser bedre enn «56 dager», men enheten databasen
// faktisk bærer er den vi viser — en omregning ville vært en presentasjon av et
// tall som ikke står i kilden.
//
// Alt som ikke passer denne formen — ISO 8601 (`P56D`) fra en annen
// `IntervalStyle`, eller et negativt intervall, som migrasjon 004 uansett
// forbyr på et tidsrom — gjengis uendret framfor å tolkes på slump.
// ============================================================================

/** Resultatet av å gjengi én databaseverdi på norsk. */
export type RenderedValue =
  /** Verdien er gjenkjent og skrevet om. */
  | { readonly kind: 'formatted'; readonly text: string }
  /**
   * Verdien lot seg ikke tolke. `text` er databaseverdien uendret, slik at
   * visningen kan vise det som faktisk står framfor å utelate feltet.
   */
  | { readonly kind: 'unrecognised'; readonly text: string }

// ----------------------------------------------------------------------------
// Sortering
// ----------------------------------------------------------------------------

// Norsk kollasjon: æ, ø og å står sist og i den rekkefølgen, og «aa» sorteres
// som «å». En sortering på tegnverdi gir en annen rekkefølge — og en liste en
// norsk leser leser som usortert, ser ut som en liste sortert etter noe annet,
// for eksempel etter viktighet (PRODUCT_INFORMATION_ARCHITECTURE.md invariant 14).
//
// Sorteringen hører hjemme her og ikke i spørringen. `order by` i PostgreSQL
// bruker databasens kollasjon, som ikke er norsk i et Supabase-prosjekt, så en
// visning som *sier* at rekkefølgen er alfabetisk må selv gjøre den alfabetisk.
// Spørringene sorterer likevel: det gir en stabil rekkefølge mellom kall.
const COLLATOR = new Intl.Collator('nb')

/** Sammenligner to norske tekster for sortering. Egnet som `Array.sort`-komparator. */
export function compareNorwegian(a: string, b: string): number {
  return COLLATOR.compare(a, b)
}

// ----------------------------------------------------------------------------
// Tall
// ----------------------------------------------------------------------------

// Ingen avkorting. Standardverdien for maximumFractionDigits er 3, og den ville
// stilltiende gjort 1,7143 til 1,714 — en klinisk verdi endret av en
// formateringsdetalj. Her lokaliseres desimaltegnet, ingenting annet.
const NUMBER_FORMAT = new Intl.NumberFormat('nb-NO', { maximumFractionDigits: 20 })

/** Tall med norsk desimalkomma. NaN og uendelig er kontraktsbrudd og gjengis rått. */
export function formatNumber(value: number): RenderedValue {
  if (!Number.isFinite(value)) {
    return { kind: 'unrecognised', text: String(value) }
  }
  return { kind: 'formatted', text: NUMBER_FORMAT.format(value) }
}

// ----------------------------------------------------------------------------
// Tidsstempler
// ----------------------------------------------------------------------------

// Sonen er bundet til Europe/Oslo, ikke til leserens maskin. Antidep er et
// verktøy for klinikere i Norge, og «sist faglig vurdert» skal være den samme
// datoen for alle som leser påstanden. En sonefri formatering ville dessuten
// gjort testene avhengige av maskinen de kjører på.
const DATE_FORMAT = new Intl.DateTimeFormat('nb-NO', {
  dateStyle: 'long',
  timeZone: 'Europe/Oslo',
})

/**
 * `timestamptz` som norsk dato. Klokkeslettet utelates med hensikt: feltene
 * dette brukes på — publisert, sist faglig vurdert — er datoer i klinisk bruk,
 * og et klokkeslett ville antydet en presisjon beslutningen ikke har.
 */
export function formatTimestampAsDate(raw: string): RenderedValue {
  const parsed = new Date(raw)
  if (Number.isNaN(parsed.getTime())) {
    return { kind: 'unrecognised', text: raw }
  }
  return { kind: 'formatted', text: DATE_FORMAT.format(parsed) }
}

// ----------------------------------------------------------------------------
// Intervaller
// ----------------------------------------------------------------------------

/** Entall og flertall for enhetene PostgreSQL faktisk skriver ut. */
const INTERVAL_UNITS: ReadonlyMap<string, readonly [string, string]> = new Map([
  ['year', ['år', 'år']],
  ['years', ['år', 'år']],
  ['mon', ['måned', 'måneder']],
  ['mons', ['måned', 'måneder']],
  ['day', ['dag', 'dager']],
  ['days', ['dag', 'dager']],
])

const WHOLE_NUMBER = /^\d+$/
const CLOCK_PART = /^(\d+):([0-5]\d):([0-5]\d(?:\.\d+)?)$/

function pluralise(amount: number, forms: readonly [string, string]): string {
  const [singular, plural] = forms
  const word = amount === 1 ? singular : plural
  const rendered = formatNumber(amount)
  return `${rendered.text} ${word}`
}

/**
 * Intervalltekst fra PostgreSQL som norsk varighet.
 *
 * Gjenkjenner den fulle formen `[N år] [N mons] [N days] [HH:MM:SS]` og
 * gjengir bare leddene som faktisk står der. Alt annet — inkludert negative
 * intervaller, som et tidsrom ikke kan ha — returneres uendret.
 */
export function formatIntervalText(raw: string): RenderedValue {
  const unrecognised = { kind: 'unrecognised', text: raw } as const

  const trimmed = raw.trim()
  if (trimmed.length === 0) {
    return unrecognised
  }

  const tokens = trimmed.split(/\s+/)
  const parts: string[] = []
  let index = 0

  // Tallenhetsleddene, i den rekkefølgen PostgreSQL skriver dem.
  while (index + 1 < tokens.length) {
    const amountToken = tokens[index]
    const unitToken = tokens[index + 1]
    if (amountToken === undefined || unitToken === undefined) {
      return unrecognised
    }
    const forms = INTERVAL_UNITS.get(unitToken)
    if (forms === undefined) {
      break
    }
    // Bevisst ikke `-?\d+`: et negativt ledd gjengis rått framfor å bli til en
    // varighet med minustegn, som er lett å lese feil.
    if (!WHOLE_NUMBER.test(amountToken)) {
      return unrecognised
    }
    parts.push(pluralise(Number(amountToken), forms))
    index += 2
  }

  // Et eventuelt klokkeslettledd, som alltid står sist.
  if (index < tokens.length) {
    const clockToken = tokens[index]
    const clock = clockToken === undefined ? null : CLOCK_PART.exec(clockToken)
    if (clock === null || index + 1 !== tokens.length) {
      return unrecognised
    }
    const [hours, minutes, seconds] = [Number(clock[1]), Number(clock[2]), Number(clock[3])]
    if (hours > 0) parts.push(pluralise(hours, ['time', 'timer']))
    if (minutes > 0) parts.push(pluralise(minutes, ['minutt', 'minutter']))
    if (seconds > 0) parts.push(pluralise(seconds, ['sekund', 'sekunder']))
  }

  // Et intervall der hvert ledd er null er fortsatt et intervall, og det skal
  // ikke bli en tom streng som ser ut som en manglende verdi.
  if (parts.length === 0) {
    return { kind: 'formatted', text: '0 sekunder' }
  }

  return { kind: 'formatted', text: parts.join(' ') }
}

// ----------------------------------------------------------------------------
// Datoer med oppgitt presisjon
// ----------------------------------------------------------------------------

// En publiseringsdato lagres avkortet til presisjonsnivået den faktisk er kjent
// på (migrasjon 003), og bibliografiske kilder oppgir ofte bare år. «1. januar
// 2019» for en dato som bare er kjent til året, er falsk presisjon
// (ANTIDEP_CONSTITUTION.md §6) — og den er ikke synlig som feil, fordi den ser
// ut som en helt vanlig dato. Presisjonen må derfor følge datoen helt fram til
// teksten.
//
// Datoen tolkes med et mønster framfor med `Date`. PostgREST serialiserer
// `date` som `YYYY-MM-DD` uten sone, og en `Date` ville lagt en sone på den; en
// omregning til Europe/Oslo kunne da flyttet dagen. Her er det ingen sone å
// regne feil.
const DATE_TEXT = /^(\d{4})-(\d{2})-(\d{2})$/

const MONTH_FORMAT = new Intl.DateTimeFormat('nb-NO', { month: 'long', timeZone: 'UTC' })

/** Presisjonsnivåene `knowledge.date_precision` uttrykker. */
export type FormattedDatePrecision = 'year' | 'month' | 'day'

/**
 * En `date` fra `api`, skrevet ut med nøyaktig den presisjonen den har.
 *
 * Vokabularkontrollen på presisjonen ligger ikke her, men i `evidence-item.ts`:
 * en ukjent presisjonsverdi skal bli en eksplisitt ukjent tilstand hos kalleren,
 * ikke et valg mellom tre formater her.
 */
export function formatDateAtPrecision(
  raw: string,
  precision: FormattedDatePrecision,
): RenderedValue {
  const parts = DATE_TEXT.exec(raw.trim())
  const [year, month, day] = [parts?.[1], parts?.[2], parts?.[3]]
  if (year === undefined || month === undefined || day === undefined) {
    return { kind: 'unrecognised', text: raw }
  }

  const monthNumber = Number(month)
  const dayNumber = Number(day)
  // Et ugyldig ledd gjengis rått framfor å bli til «måned 13»: en dato som ikke
  // lar seg tolke skal ikke se ut som en tolket dato.
  if (monthNumber < 1 || monthNumber > 12 || dayNumber < 1 || dayNumber > 31) {
    return { kind: 'unrecognised', text: raw }
  }

  if (precision === 'year') {
    return { kind: 'formatted', text: year }
  }
  const monthName = MONTH_FORMAT.format(Date.UTC(2000, monthNumber - 1, 1))
  if (precision === 'month') {
    return { kind: 'formatted', text: `${monthName} ${year}` }
  }
  return { kind: 'formatted', text: `${String(dayNumber)}. ${monthName} ${year}` }
}
