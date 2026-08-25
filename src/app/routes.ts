// ============================================================================
// Adressene i klinikerflaten
//
// Ett sted, fordi URL-en er en kontrakt: §55 i
// PRODUCT_INFORMATION_ARCHITECTURE.md krever at en kliniker kan dele en lenke
// direkte til et virkestoff, en klinisk situasjon og en evidensvisning, og
// invariant 12 gjør dypelenker til standard. En adresse som konstrueres på
// stedet i hver komponent er ikke en kontrakt, den er en vane.
//
// Rutingen eier adressene. `ClaimCard` tar imot `evidenceHref` som en streng og
// kjenner ingen ruting; det er her strengen lages (§74.13 punkt 4).
//
// ----------------------------------------------------------------------------
// Hvorfor stisegmentene er engelske og innholdet norsk
//
// `/drugs/sertralin` står ordrett i MVP_IMPLEMENTATION_PLAN.md §30. Segmentene
// er dermed et teknisk navnerom på engelsk, mens verdiene i dem er de norske
// kanoniske navnene fra katalogen. Å oversette halvparten av stien ville gitt
// et vilkårlig skille; å oversette hele ville brutt med den adressen planen
// navngir.
// ============================================================================

import { toSlug } from '../lib/slug'
import type { Uuid } from '../types/api'

/**
 * Mønstrene ruteren matcher på. Parameternavnene er de `useParams()` gir, og
 * builderne under er de eneste stedene en faktisk adresse settes sammen.
 */
export const ROUTE_PATTERNS = {
  home: '/',
  drug: '/drugs/:drugSlug',
  topic: '/topics/:topicSlug',
  claimEvidence: '/claims/:claimId/evidence',
} as const

/** Forsiden: hvilke virkestoff Antidep har publisert kunnskap om. */
export function homePath(): string {
  return '/'
}

/** Legemiddelsiden for ett kanonisk virkestoffnavn (§30). */
export function drugPath(canonicalName: string): string {
  return `/drugs/${encodeURIComponent(toSlug(canonicalName))}`
}

/** Temasiden for ett klinisk begrep (§26). */
export function topicPath(topicLabel: string): string {
  return `/topics/${encodeURIComponent(toSlug(topicLabel))}`
}

/**
 * «Hvorfor sier Antidep dette?» (§15).
 *
 * Adressert med `claim_id` og ikke med revisjonen: identiteten er stabil på
 * tvers av revisjoner (ANTIDEP_CONSTITUTION.md §7), så en delt lenke fortsetter
 * å peke på påstanden også etter en ny publisering. Hvilken revisjon som står
 * publisert, er noe visningen leser, ikke noe adressen fryser.
 */
export function claimEvidencePath(claimId: Uuid): string {
  return `/claims/${encodeURIComponent(claimId)}/evidence`
}
