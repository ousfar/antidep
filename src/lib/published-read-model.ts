// ============================================================================
// Lesefunksjonene mot kontraktslaget `api`
//
// Fem lesefunksjoner over de tre viewene. Ingen skriveveier: `api` er
// lesemodell, og skriving går gjennom kontrollerte SECURITY DEFINER-funksjoner
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

/**
 * Alle publiserte påstander.
 *
 * Finnes fordi temasiden må slå opp et klinisk begrep fra en slug, og `api`
 * ikke eksponerer noen temaprojeksjon: `published_claims` er det eneste stedet
 * `topic_label` finnes, og en slug kan ikke inverteres til en etikett
 * (`src/lib/slug.ts`). Settet lastes derfor i sin helhet og filtreres i
 * klienten.
 *
 * Det holder så lenge det publiserte settet er lite, og det er registrert som
 * gjeld i MVP_IMPLEMENTATION_PLAN.md §74.7: triggeren er et `api.published_-
 * topics`-view eller en slug-kolonne i katalogen, som lar temasiden filtrere
 * på serversiden slik legemiddelsiden allerede gjør.
 *
 * Sorteringen er alfabetisk på virkestoff og deretter på tema. Det er en
 * stabil rekkefølge uten klinisk mening; hvilken rekkefølge en visning
 * presenterer settet i, er en designbeslutning som hører til visningen
 * (ANTIDEP_CONSTITUTION.md §9, PRODUCT_INFORMATION_ARCHITECTURE.md §29).
 */
export async function fetchPublishedClaims(
  client: AntidepClient,
): Promise<ReadModelResult<PublishedClaimRow>> {
  return toResult(
    await client
      .from('published_claims')
      .select('*')
      .order('drug_name', { ascending: true })
      .order('topic_label', { ascending: true })
      .order('statement', { ascending: true }),
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
 * Én publisert påstand, slått opp på sin stabile identitet.
 *
 * Finnes fordi evidensvisningen skal ha påstanden øverst
 * (PRODUCT_INFORMATION_ARCHITECTURE.md §41), og evidensradene ikke bærer den:
 * `statement`, `certainty_level`, `uncertainty_summary` og `topic_label` står
 * bare i `published_claims`. Uten oppslaget måtte evidensvisningen enten
 * gjengitt påstanden fra evidensfunnene — altså gjettet — eller latt være å
 * vise den, og et evidensgrunnlag uten påstanden over seg er ikke etterprøvbart
 * (ANTIDEP_CONSTITUTION.md §4).
 *
 * Filteret er `claim_id` og ikke revisjonen: identiteten er stabil på tvers av
 * revisjoner (§7), så en delt lenke fortsetter å peke på påstanden også etter en
 * ny publisering. Hvilken revisjon som står publisert, er noe viewet avgjør.
 *
 * Ingen sortering: `published_claims` har én rad per publisert påstand, så et
 * svar med mer enn én rad er et kontraktsbrudd og ikke en rekkefølge. Kalleren
 * ser det, fordi `ok` bærer hele settet.
 */
export async function fetchPublishedClaimById(
  client: AntidepClient,
  claimId: Uuid,
): Promise<ReadModelResult<PublishedClaimRow>> {
  return toResult(await client.from('published_claims').select('*').eq('claim_id', claimId))
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
