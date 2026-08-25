// ============================================================================
// Klienten, gjort tilgjengelig for sidene
//
// `getAntidepClient()` leser miljøet og kaster hvis konfigurasjonen mangler
// eller er feil (`src/lib/supabase.ts`). Det er riktig oppførsel — en app som
// starter med halv konfigurasjon ender i et tomt resultat som ikke lar seg
// skille fra en tom projeksjon — men et kast under render ville tatt ned hele
// flaten. Her fanges det én gang, øverst, og blir til en tilstand sidene kan
// vise.
//
// Tilstanden er `unavailable`, ikke `empty`. Det er den samme regelen som i
// lesemodellen (§74.12 punkt 1): en feil skal aldri kunne leses som fravær av
// kunnskap (ANTIDEP_CONSTITUTION.md §17).
//
// Konteksten finnes for at sidene skal kunne testes med en injisert klient
// uten å røre modulsingletonen i `supabase.ts`.
// ============================================================================

import { createContext, useContext } from 'react'
import { getAntidepClient, type AntidepClient, type SupabaseEnv } from '../lib/supabase'

export type AntidepClientAvailability =
  | { readonly status: 'ready'; readonly client: AntidepClient }
  /** Klienten finnes ikke. Aldri det samme som at det ikke finnes kunnskap. */
  | { readonly status: 'unavailable'; readonly message: string }

/**
 * Oppretter klienten, eller beskriver hvorfor den ikke kan opprettes.
 *
 * Kalles én gang av `App`. Feilteksten er den `readSupabaseConfig()` selv
 * formulerer, fordi den navngir miljøvariabelen som mangler; visningen legger
 * den kliniske rammen rundt.
 */
export function resolveAntidepClient(env?: SupabaseEnv): AntidepClientAvailability {
  try {
    return {
      status: 'ready',
      client: env === undefined ? getAntidepClient() : getAntidepClient(env),
    }
  } catch (cause) {
    return {
      status: 'unavailable',
      message: cause instanceof Error ? cause.message : String(cause),
    }
  }
}

const AntidepClientContext = createContext<AntidepClientAvailability | undefined>(undefined)

export const AntidepClientProvider = AntidepClientContext.Provider

/**
 * Klienttilstanden for denne delen av treet.
 *
 * Kaster hvis den mangler. Et manglende oppsett er en programmeringsfeil, og en
 * stille fallback ville gjort en test som glemte provideren til en test som
 * påstår noe om en tom flate.
 */
export function useAntidepClient(): AntidepClientAvailability {
  const availability = useContext(AntidepClientContext)
  if (availability === undefined) {
    throw new Error(
      'AntidepClientProvider mangler over denne komponenten. Sider som leser publisert ' +
        'kunnskap må rendres innenfor provideren.',
    )
  }
  return availability
}
