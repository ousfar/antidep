// ============================================================================
// Database-typen supabase-js parametriseres med
//
// Bare kontraktslaget `api` finnes her, og det er hele poenget: de kanoniske
// schemaene er ikke eksponert i Data API-et (`supabase/config.toml`), og
// klientrollene mangler uansett usage på dem. En Database-type som listet
// `knowledge` eller `workflow` ville beskrevet en tilgang som ikke finnes.
//
// Typen er håndskrevet framfor generert. Generering krever en kjørende stack,
// og et generert artefakt ville dessuten flatet ut nettopp de skillene
// `./api.ts` bevarer — hvilke vokabularer som er lukkede, og hva NULL betyr i
// hver enkelt kolonne. Radtypene her er derfor de samme objektene UI-koden
// leser.
//
// Formen er bestemt av supabase-js, ikke av oss: `Tables`, `Views` og
// `Functions` må alle finnes, og hver må være et oppslag. Mangler én, eller
// oppfyller en Row ikke `Record<string, unknown>`, forkastes schemaet stille og
// spørringene gir `never` framfor en typefeil. Se merknaden i `./api.ts`.
//
// De tomme oppslagene er `{ [_ in never]: never }` og ikke
// `Record<string, never>`, av samme grunn. supabase-js slår opp en relasjon i
// `Tables & Views`, og `Record<string, never>` gir *hver* nøkkel typen `never`
// — også viewenes. Snittet blir da `never`, hvert view mister radtypen sin, og
// `never` er tilordnbart til alt, så ingenting feiler. Begge feilformene er
// prøvd ut mot kompilatoren, ikke antatt.
//
// Viewene er lesemodell, så de har `Row` og ingen `Insert`/`Update`: forsøk på
// å skrive gjennom dem blir en typefeil. Skriveveien er og blir en kontrollert
// SECURITY DEFINER-funksjon (DATABASE_ARCHITECTURE.md §43), og `Tables` og
// `Functions` står tomme til den første faktisk eksponeres i `api`.
// ============================================================================

import type { PublishedClaimEvidenceRow, PublishedClaimRow, PublishedDrugRow } from './api'

export type Database = {
  api: {
    Tables: { [_ in never]: never }
    Views: {
      published_drugs: {
        Row: PublishedDrugRow
        Relationships: []
      }
      published_claims: {
        Row: PublishedClaimRow
        Relationships: []
      }
      published_claim_evidence: {
        Row: PublishedClaimEvidenceRow
        Relationships: []
      }
    }
    Functions: { [_ in never]: never }
  }
}
