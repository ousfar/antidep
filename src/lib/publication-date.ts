// ============================================================================
// Publiseringsdato: fra det brukeren faktisk vet, til det databasen lagrer
//
// `knowledge.sources` lagrer en publiseringsdato avkortet til den presisjonen
// den er belagt for (migrasjon 003), og håndhever avkortingen deklarativt:
//
//   year   datoen må være YYYY-01-01
//   month  datoen må være YYYY-MM-01
//   day    datoen er den faktiske dagen
//
// Kolonnen og presisjonen er dessuten parkoblet: begge satt, eller begge NULL.
//
// Konvensjonen er riktig i databasen — den hindrer falsk presisjon
// (ANTIDEP_CONSTITUTION.md §6) — men den er databasens representasjon, ikke noe
// en redaktør skal måtte kjenne til. En kilde som bare er årfestet til 2000 er
// ikke «1. januar 2000», og et skjema som krever at brukeren skriver
// 1. januar for å uttrykke «2000» ber brukeren om å kjenne et internt format.
//
// Denne modulen er oversettelsen mellom de to. Brukeren oppgir presisjonen
// først og deretter nøyaktig så mye dato som den presisjonen rommer; herfra
// utledes den kanoniske verdien deterministisk.
//
// ----------------------------------------------------------------------------
// Hva dette IKKE er
//
// Dette er ikke feltvalidering som dupliserer databasens CHECK-constraints — de
// er fortsatt fasiten (§43, §48), og en dato som er umulig (13. måned, 31.
// februar) avvises av databasen, ikke her. Kontrollen under svarer på et annet
// og snevrere spørsmål: *har skjemaet i det hele tatt fått nok input til å
// danne en verdi?* Er svaret nei, finnes det ingen dato å sende, og et halvt
// utfylt felt skal ikke sendes som om det var en dato.
// ============================================================================

import { DATE_PRECISIONS } from '../types/api'

/**
 * Presisjonsvalgene skjemaet tilbyr: databasens vokabular, pluss «ingen dato».
 *
 * `none` er ikke en databaseverdi. Den er skjemaets måte å uttrykke det
 * tilfellet der både dato og presisjon skal være NULL — en udatert kilde er en
 * reell tilstand, ikke en manglende utfylling.
 *
 * Avledet av `DATE_PRECISIONS` framfor skrevet ut på nytt, slik at en ny
 * presisjonsverdi i databasen ikke kan bli stående uten et valg her.
 */
export const PUBLICATION_DATE_CHOICES = ['none', ...DATE_PRECISIONS] as const
export type PublicationDateChoice = (typeof PUBLICATION_DATE_CHOICES)[number]

/**
 * Det skjemaet holder på mens brukeren fyller ut.
 *
 * De tre datofeltene finnes side om side framfor som en union på `choice`, slik
 * at et bytte fram og tilbake mellom presisjonene ikke sletter det brukeren
 * allerede har skrevet. Bare feltet som hører til den valgte presisjonen leses.
 */
export interface PublicationDateDraft {
  readonly choice: PublicationDateChoice
  /** `YYYY`, fra årsfeltet. */
  readonly year: string
  /** `YYYY-MM`, slik `<input type="month">` gir den. */
  readonly month: string
  /** `YYYY-MM-DD`, slik `<input type="date">` gir den. */
  readonly day: string
}

export const EMPTY_PUBLICATION_DATE: PublicationDateDraft = {
  choice: 'none',
  year: '',
  month: '',
  day: '',
}

/**
 * Den kanoniske verdien, klar for `api.create_source(...)`.
 *
 * `incomplete` betyr at brukeren har valgt en presisjon uten å fylle ut datoen
 * den krever. Da finnes det ingen verdi å kanonisere, og skjemaet skal si fra
 * framfor å sende en halv dato databasen uansett ville avvist med sitt eget
 * constraint-navn.
 */
export type CanonicalPublicationDate =
  | { readonly status: 'ok'; readonly date: string | null; readonly precision: string | null }
  | { readonly status: 'incomplete'; readonly message: string }

// Formene de tre inputtypene faktisk leverer. Kontrollen er en formkontroll,
// ikke en gyldighetskontroll: at «2000-02-31» er en umulig dato, er databasens
// svar å gi, ikke dette lagets.
const YEAR_SHAPE = /^\d{4}$/
const MONTH_SHAPE = /^\d{4}-\d{2}$/
const DAY_SHAPE = /^\d{4}-\d{2}-\d{2}$/

/**
 * Oversetter det brukeren oppga til den avkortede datoen databasen krever.
 *
 * Avkortingen er databasens regel, gjentatt her som en konstruksjon framfor som
 * en kontroll: `year` bygger `YYYY-01-01` og `month` bygger `YYYY-MM-01`, så en
 * dato som ikke er avkortet kan ikke oppstå i det hele tatt. Det er derfor
 * skjemaet ikke trenger å kjenne — eller kunne bryte — konvensjonen.
 */
export function canonicalPublicationDate(draft: PublicationDateDraft): CanonicalPublicationDate {
  switch (draft.choice) {
    case 'none':
      // Begge NULL sammen: sources_publication_date_precision_pairing_check.
      return { status: 'ok', date: null, precision: null }

    case 'year':
      if (!YEAR_SHAPE.test(draft.year)) {
        return { status: 'incomplete', message: 'Fyll inn året kilden ble publisert.' }
      }
      return { status: 'ok', date: `${draft.year}-01-01`, precision: 'year' }

    case 'month':
      if (!MONTH_SHAPE.test(draft.month)) {
        return { status: 'incomplete', message: 'Fyll inn måneden og året kilden ble publisert.' }
      }
      return { status: 'ok', date: `${draft.month}-01`, precision: 'month' }

    case 'day':
      if (!DAY_SHAPE.test(draft.day)) {
        return { status: 'incomplete', message: 'Fyll inn datoen kilden ble publisert.' }
      }
      return { status: 'ok', date: draft.day, precision: 'day' }
  }
}
