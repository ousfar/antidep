// ============================================================================
// Lesefunksjonene mot kontraktslaget `api`
//
// Tre spørringer, én per view. Ingen skriveveier: `api` er lesemodell, og
// skriving går gjennom kontrollerte SECURITY DEFINER-funksjoner
// (DATABASE_ARCHITECTURE.md §43).
//
// ----------------------------------------------------------------------------
// Hvorfor tomt er en egen tilstand
//
// Viewene svarer `[]` til noe faktisk er publisert, og det er korrekt oppførsel
// (MVP_IMPLEMENTATION_PLAN.md §74.4). Et tomt svar er også det RLS gir en
// kaller som ikke har lov til å se noe, og det en feilkonfigurert klient
// nærmer seg. Skal «ingen data» aldri kunne se ut som «ingen risiko»
// (ANTIDEP_CONSTITUTION.md §17), må tomheten være umulig å overse.
//
// Derfor returnerer funksjonene en lukket union der `ok` per konstruksjon
// aldri har null rader. En kaller kan ikke rendre et tomt sett som en liste
// uten først å ha tatt stilling til `empty`, og en feil kan ikke bli borte i
// den samme tomme listen.
// ----------------------------------------------------------------------------
// Sortering
//
// Alfabetisk der det finnes et navn å sortere på. Evidensen sorteres bevisst
// på lenkens id: en rekkefølge etter relationship_type ville satt støttende
// funn først og gjort presentasjonsrekkefølgen til en vekting av evidensen,
// og motstridende funn skal stå side om side med støttende
// (ANTIDEP_CONSTITUTION.md §9, PRODUCT_INFORMATION_ARCHITECTURE.md §20). Her
// trengs bare en stabil rekkefølge mellom kall; hva som skal stå øverst i
// klinikerflaten er en designbeslutning som hører til visningen.
// ============================================================================

import type { AntidepClient } from './supabase'
import type {
  PublishedClaimEvidenceRow,
  PublishedClaimRow,
  PublishedDrugRow,
  Uuid,
} from '../types/api'

export type ReadModelResult<Row> =
  /** Minst én rad. Aldri tom — se `empty`. */
  | { readonly status: 'ok'; readonly rows: readonly [Row, ...Row[]] }
  /**
   * Projeksjonen er tom. Ikke en feil, og ikke «ingenting å bekymre seg for»:
   * Antidep har ingen publisert kunnskap å vise for denne forespørselen.
   */
  | { readonly status: 'empty' }
  /**
   * Spørringen nådde ikke fram, eller ble avvist. Skal aldri presenteres som
   * fravær av kunnskap.
   */
  | { readonly status: 'error'; readonly message: string }

interface PostgrestOutcome<Row> {
  data: Row[] | null
  error: { message: string } | null
}

function toResult<Row>({ data, error }: PostgrestOutcome<Row>): ReadModelResult<Row> {
  if (error !== null) {
    return { status: 'error', message: error.message }
  }
  const [first, ...rest] = data ?? []
  if (first === undefined) {
    return { status: 'empty' }
  }
  return { status: 'ok', rows: [first, ...rest] }
}

/** Virkestoffene Antidep har publisert minst én påstand om. */
export async function fetchPublishedDrugs(
  client: AntidepClient,
): Promise<ReadModelResult<PublishedDrugRow>> {
  return toResult(
    await client.from('published_drugs').select('*').order('canonical_name', { ascending: true }),
  )
}

/** De publiserte påstandene der virkestoffet er subjekt. */
export async function fetchPublishedClaimsForDrug(
  client: AntidepClient,
  drugId: Uuid,
): Promise<ReadModelResult<PublishedClaimRow>> {
  return toResult(
    await client
      .from('published_claims')
      .select('*')
      .eq('drug_id', drugId)
      .order('topic_label', { ascending: true })
      .order('statement', { ascending: true }),
  )
}

/**
 * Evidensgrunnlaget bak «Hvorfor sier Antidep dette?»
 * (PRODUCT_INFORMATION_ARCHITECTURE.md §15). Settet er komplett: støttende,
 * motstridende, nøytrale og indirekte lenker. En klient skal ikke filtrere
 * bort de motstridende (ANTIDEP_CONSTITUTION.md §9).
 */
export async function fetchPublishedClaimEvidence(
  client: AntidepClient,
  claimId: Uuid,
): Promise<ReadModelResult<PublishedClaimEvidenceRow>> {
  return toResult(
    await client
      .from('published_claim_evidence')
      .select('*')
      .eq('claim_id', claimId)
      .order('claim_evidence_link_id', { ascending: true }),
  )
}
