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
  source: '/sources/:sourceId',
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

/**
 * Kildesiden: én publikasjon, og alt Antidep bruker den til
 * (PRODUCT_INFORMATION_ARCHITECTURE.md §42).
 *
 * Adressert med `source_id`, av samme grunn som evidensvisningen adresseres med
 * `claim_id`: uuid-en er kildens stabile identitet
 * (DATABASE_ARCHITECTURE.md §8), og den endrer seg ikke når raden redigeres.
 *
 * En slug avledet av tittelen ble vurdert og valgt bort. Kildetitler er inntil
 * 600 tegn og står på kildens eget språk, så sluggen ville blitt både lang og
 * fremmedspråklig — men det avgjørende er at avledningen har nøyaktig den
 * svakheten §74.7 allerede fører som gjeld for `/drugs/:drugSlug` og
 * `/topics/:topicSlug`: en adresse avledet av et visningsnavn er ikke en stabil
 * identitet, den er tapsgivende, og to titler kan kollidere. Å gjenta den på et
 * tredje objekt ville utvidet gjelden framfor å begrense den.
 */
export function sourcePath(sourceId: Uuid): string {
  return `/sources/${encodeURIComponent(sourceId)}`
}
