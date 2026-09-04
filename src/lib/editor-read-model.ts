// ============================================================================
// Lesefunksjonene mot den redaksjonelle lesemodellen i `api`
//
// Seks spørringer over de seks viewene migrasjon 007d eksponerer. De svarer på
// hva en editor kan velge mellom når et evidensfunn skal registreres — og på
// hva som allerede er registrert på en kilde.
//
// ----------------------------------------------------------------------------
// Hvorfor dette ikke står i published-read-model.ts
//
// Samme grunn som for `caller-authorization.ts`: tomhetssemantikken er en annen.
// Et tomt svar fra `published_drugs` betyr «Antidep har ikke publisert dette».
// Et tomt svar herfra betyr «du ser ingenting her» — og de to grunnene til at
// det kan skje er forskjellige: kalleren mangler editor-rollen, eller katalogen
// er faktisk tom. Ingen av dem er «ingen publisert kunnskap», og å gjenbruke
// `ReadModelResult` ville flatet ut nettopp det skillet skjemaet trenger for å
// si noe sant til brukeren.
//
// Tilstanden heter derfor `none` og ikke `empty`, slik at den ikke leses som
// lesemodellens `empty` ved et uhell.
//
// ----------------------------------------------------------------------------
// Sortering
//
// Alfabetisk der det finnes et navn, og på tid der det ikke gjør det.
// Rekkefølgen her er ingen vekting: dette er redaksjonelle oppslag, ikke
// presentasjon av evidens, så doktrinen i `published-read-model.ts` om at
// rekkefølgen ikke skal antyde en rangering av funn, er ikke i spill. Det som
// trengs er en stabil rekkefølge mellom kall, og for de registrerte funnene at
// det nyeste står øverst — det er nettopp det en bekreftelse skal vise.
// ============================================================================

import type { AntidepClient } from './supabase'
import type {
  EditorDrugRow,
  EditorEvidenceItemRow,
  EditorOutcomeRow,
  EditorPopulationRow,
  EditorSourceRow,
  EditorSourceVersionRow,
  Uuid,
} from '../types/api'

export type EditorReadResult<Row> =
  /** Minst én rad. Aldri tom — se `none`. */
  | { readonly status: 'ok'; readonly rows: readonly [Row, ...Row[]] }
  /**
   * Ingen rader er synlige for kalleren. Det kan bety at kalleren ikke har
   * editor-rollen, eller at registeret faktisk er tomt; viewene skiller ikke de
   * to, og en klient som påstår å vite hvilken av dem det er, hevder mer enn
   * svaret sier.
   */
  | { readonly status: 'none' }
  /** Spørringen nådde ikke fram, eller ble avvist. Aldri det samme som `none`. */
  | { readonly status: 'error'; readonly message: string }

interface PostgrestOutcome<Row> {
  data: Row[] | null
  error: { message: string } | null
}

function toResult<Row>({ data, error }: PostgrestOutcome<Row>): EditorReadResult<Row> {
  if (error !== null) {
    return { status: 'error', message: error.message }
  }
  const [first, ...rest] = data ?? []
  if (first === undefined) {
    return { status: 'none' }
  }
  return { status: 'ok', rows: [first, ...rest] }
}

/** Kildene et evidensfunn kan knyttes til. */
export async function fetchEditorSources(
  client: AntidepClient,
): Promise<EditorReadResult<EditorSourceRow>> {
  return toResult(
    await client.from('editor_sources').select('*').order('title', { ascending: true }),
  )
}

/**
 * Øyeblikksbildene som er registrert for én kilde.
 *
 * Nyeste først: er det flere, er den sist hentede representasjonen den en
 * fersk ekstraksjon normalt er lest av.
 */
export async function fetchEditorSourceVersions(
  client: AntidepClient,
  sourceId: Uuid,
): Promise<EditorReadResult<EditorSourceVersionRow>> {
  return toResult(
    await client
      .from('editor_source_versions')
      .select('*')
      .eq('source_id', sourceId)
      .order('retrieved_at', { ascending: false }),
  )
}

/** Virkestoffene i katalogen, som intervensjon eller komparator. */
export async function fetchEditorDrugs(
  client: AntidepClient,
): Promise<EditorReadResult<EditorDrugRow>> {
  return toResult(
    await client.from('editor_drugs').select('*').order('canonical_name', { ascending: true }),
  )
}

/** De kliniske begrepene som er endepunkter. Andre begrepstyper står ikke der. */
export async function fetchEditorOutcomes(
  client: AntidepClient,
): Promise<EditorReadResult<EditorOutcomeRow>> {
  return toResult(
    await client.from('editor_outcomes').select('*').order('canonical_label', { ascending: true }),
  )
}

/** Populasjonene et funn kan indekseres under. */
export async function fetchEditorPopulations(
  client: AntidepClient,
): Promise<EditorReadResult<EditorPopulationRow>> {
  return toResult(
    await client
      .from('editor_populations')
      .select('*')
      .order('canonical_label', { ascending: true }),
  )
}

/**
 * Evidensfunnene som er registrert på én kilde.
 *
 * Nyeste først, slik at funnet som nettopp ble registrert står øverst i
 * bekreftelsen. Rekkefølgen er registreringstid og ikke en vurdering: ingenting
 * her sier hvilket funn som veier tyngst.
 */
export async function fetchEditorEvidenceItems(
  client: AntidepClient,
  sourceId: Uuid,
): Promise<EditorReadResult<EditorEvidenceItemRow>> {
  return toResult(
    await client
      .from('editor_evidence_items')
      .select('*')
      .eq('source_id', sourceId)
      .order('created_at', { ascending: false }),
  )
}
