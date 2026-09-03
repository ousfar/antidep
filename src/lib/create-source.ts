// ============================================================================
// Den kontrollerte skriveveien for å opprette en Source
//
// Steg 2 av «manuell adminflyt» (MVP_IMPLEMENTATION_PLAN.md §29, §74.24):
// «Editor oppretter Source» (§15). Ett kall til `api.create_source(...)`
// (migrasjon 007c) — ingen egen validering her utover det formen selv samler
// inn, fordi databasens CHECK-constraints på `knowledge.sources` er fasiten
// (§43, §48), ikke en kopi av dem i klienten.
//
// ----------------------------------------------------------------------------
// Ingen «du har lov»-boolean her heller
//
// Samme doktrine som `caller-authorization.ts`: denne modulen avgjør ikke om
// kalleren FÅR opprette en kilde. Den sender forsøket og returnerer det
// databasen svarer, inkludert en avvisning fra
// `knowledge.assert_editor_authorized()`. `CreateSourcePage.tsx` viser forsøket
// til enhver innlogget bruker og lar funksjonen kontrollere retten på sitt eget
// tidspunkt (DATABASE_ARCHITECTURE.md §43, §48) — ikke fordi klienten ikke
// kunne lest `api.my_roles` på forhånd, men fordi det svaret uansett ikke ville
// vært det som gjelder.
// ============================================================================

import type { AntidepClient } from './supabase'
import type { Uuid } from '../types/api'

/** Feltene skjemaet samler inn. Tomme valgfrie felter sendes som `null`, ikke som tomstreng. */
export interface CreateSourceInput {
  readonly sourceType: string
  readonly title: string
  readonly authorsOrIssuer: string
  readonly publisherOrJournal: string | null
  readonly volume: string | null
  readonly issue: string | null
  readonly pages: string | null
  readonly publicationDate: string | null
  readonly publicationDatePrecision: string | null
}

export type CreateSourceResult =
  | { readonly status: 'ok'; readonly sourceId: Uuid }
  | { readonly status: 'error'; readonly message: string }

/**
 * Kaller `api.create_source(...)`. Returnerer aldri en avvisning som et kastet
 * unntak: `CreateSourcePage.tsx` skal kunne vise enhver avvisning — manglende
 * aktør, manglende editor-rolle, en tom tittel, en ukjent kildetype — med
 * databasens egen tekst, uten å måtte skille feiltyper fra hverandre her.
 */
export async function createSource(
  client: AntidepClient,
  input: CreateSourceInput,
): Promise<CreateSourceResult> {
  const { data, error } = await client.rpc('create_source', {
    p_source_type: input.sourceType,
    p_title: input.title,
    p_authors_or_issuer: input.authorsOrIssuer,
    p_publisher_or_journal: input.publisherOrJournal,
    p_volume: input.volume,
    p_issue: input.issue,
    p_pages: input.pages,
    p_publication_date: input.publicationDate,
    p_publication_date_precision: input.publicationDatePrecision,
  })
  if (error !== null) {
    return { status: 'error', message: error.message }
  }
  return { status: 'ok', sourceId: data }
}
