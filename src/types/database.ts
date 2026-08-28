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
// SECURITY DEFINER-funksjon (DATABASE_ARCHITECTURE.md §43). `Tables` står tom:
// ingen tabell er eller skal bli direkte eksponert. `Functions` fikk sitt
// første medlem i migrasjon 007c: `create_source`, den kontrollerte skriveveien
// for å opprette en Source (MVP_IMPLEMENTATION_PLAN.md §29, §74.23). Args-typen
// speiler parametrene til api.create_source(...) i migrasjonen; to av dem er
// `text` der den underliggende kolonnen er en enum, av samme grunn som
// migrasjonens hodekommentar gir: PostgREST caster JSON-verdien til parameterens
// deklarerte type i kallerens egen sesjon, og authenticated har ikke usage på
// knowledge — en enum-typet parameter ville derfor gjort funksjonen ukjørbar
// for klientrollen, uansett at selve funksjonen er SECURITY DEFINER.
// ============================================================================

import type {
  DateText,
  MyActorRow,
  MyRoleRow,
  PublishedClaimEvidenceRow,
  PublishedClaimRow,
  PublishedDrugRow,
  Uuid,
} from './api'

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
      // Kallerens eget (migrasjon 007b). Ingen av de to er lesbare for `anon`,
      // så en spørring uten sesjon gir avslag og ikke et tomt resultat.
      my_actor: {
        Row: MyActorRow
        Relationships: []
      }
      my_roles: {
        Row: MyRoleRow
        Relationships: []
      }
    }
    Functions: {
      create_source: {
        Args: {
          p_source_type: string
          p_title: string
          p_authors_or_issuer: string
          p_publisher_or_journal?: string | null
          p_volume?: string | null
          p_issue?: string | null
          p_pages?: string | null
          p_publication_date?: DateText | null
          p_publication_date_precision?: string | null
        }
        Returns: Uuid
      }
    }
  }
}
