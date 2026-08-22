// ============================================================================
// Supabase-klienten for nettleseren
//
// Klienten er bundet til kontraktslaget `api`. Det er ikke en sikkerhetsgrense
// — den ligger i RLS, i grants og i at de kanoniske schemaene ikke er
// eksponert (migrasjon 007, punkt «Trusselvurdering») — men det holder
// klientkoden på den ene leseveien som faktisk er sanksjonert, og gjør et
// forsøk på å lese et kanonisk schema til en typefeil framfor et 404 i
// produksjon.
//
// Nøkkelvakten under er av samme grunn et supplement, ikke en lås:
// service_role omgår RLS og hører ikke hjemme i en nettleser
// (DATABASE_ARCHITECTURE.md §49, CLAUDE.md). Den virkelige beskyttelsen er at
// nøkkelen aldri legges i repoet; vakten fanger den dagen noen likevel
// kopierer feil verdi inn i `.env.local`.
// ============================================================================

import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '../types/database'

/** Supabase-klienten slik resten av appen ser den: bundet til `api`. */
export type AntidepClient = SupabaseClient<Database, 'api'>

export interface SupabaseConfig {
  readonly url: string
  readonly publishableKey: string
}

/** Den delen av miljøet klienten leser. Injiseres for å kunne testes. */
export interface SupabaseEnv {
  readonly VITE_SUPABASE_URL?: string | undefined
  readonly VITE_SUPABASE_PUBLISHABLE_KEY?: string | undefined
}

const SECRET_KEY_PREFIX = 'sb_secret_'

/** Rollene en nettleserklient har lov til å opptre som (migrasjon 001). */
const CLIENT_ROLES = ['anon', 'authenticated']

/**
 * Leser `role`-claimet fra en legacy Supabase-nøkkel (en JWT).
 *
 * Returnerer `null` når nøkkelen ikke er en JWT vi kan lese. Et ukjent format
 * er ikke bevis på at nøkkelen er hemmelig, og vakten skal ikke blokkere et
 * gyldig nøkkelformat den ikke kjenner.
 */
function jwtRoleClaim(key: string): string | null {
  const segments = key.split('.')
  if (segments.length !== 3) {
    return null
  }
  const payload = segments[1]
  if (payload === undefined || payload.length === 0) {
    return null
  }
  try {
    const base64 = payload.replaceAll('-', '+').replaceAll('_', '/')
    const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), '=')
    const claims: unknown = JSON.parse(atob(padded))
    if (typeof claims !== 'object' || claims === null) {
      return null
    }
    const role = (claims as Record<string, unknown>)['role']
    return typeof role === 'string' ? role : null
  } catch {
    return null
  }
}

/**
 * Avviser nøkler som gir mer enn en nettleser skal ha.
 *
 * Kontrollen er bevisst positiv for JWT-nøkler: alt annet enn `anon` og
 * `authenticated` avvises, ikke bare `service_role`. En framtidig privilegert
 * rolle skal ikke slippe gjennom fordi vakten bare kjente den ene ved navn.
 */
export function assertPublishableKey(key: string): void {
  if (key.startsWith(SECRET_KEY_PREFIX)) {
    throw new Error(
      'VITE_SUPABASE_PUBLISHABLE_KEY ser ut til å være en secret key ' +
        `(${SECRET_KEY_PREFIX}…). Hemmelige nøkler skal aldri i klientkode eller i repoet. ` +
        'Bruk prosjektets publishable key.',
    )
  }
  const role = jwtRoleClaim(key)
  if (role !== null && !CLIENT_ROLES.includes(role)) {
    throw new Error(
      `VITE_SUPABASE_PUBLISHABLE_KEY har rollen «${role}». En nettleserklient skal bare ` +
        `opptre som ${CLIENT_ROLES.join(' eller ')}. En service_role-nøkkel omgår RLS og ` +
        'skal aldri i klientkode eller i repoet.',
    )
  }
}

function required(env: SupabaseEnv, name: keyof SupabaseEnv): string {
  const value = env[name]?.trim()
  if (value === undefined || value.length === 0) {
    throw new Error(
      `Miljøvariabelen ${name} mangler. Kopier .env.example til .env.local og fyll inn ` +
        'verdiene fra `npm run db:status` (lokal stack) eller Supabase-prosjektet.',
    )
  }
  return value
}

/**
 * Leser og validerer konfigurasjonen. Feiler høyt og tidlig: en app som
 * starter med halv konfigurasjon ender i et tomt resultat som ikke lar seg
 * skille fra en tom projeksjon, og de to skal aldri se like ut.
 */
export function readSupabaseConfig(env: SupabaseEnv): SupabaseConfig {
  const url = required(env, 'VITE_SUPABASE_URL')
  let parsed: URL
  try {
    parsed = new URL(url)
  } catch {
    throw new Error(`VITE_SUPABASE_URL er ikke en gyldig URL: «${url}».`)
  }
  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    throw new Error(`VITE_SUPABASE_URL må bruke http eller https, ikke «${parsed.protocol}».`)
  }

  const publishableKey = required(env, 'VITE_SUPABASE_PUBLISHABLE_KEY')
  assertPublishableKey(publishableKey)

  return { url, publishableKey }
}

export function createAntidepClient(config: SupabaseConfig): AntidepClient {
  return createClient<Database, 'api'>(config.url, config.publishableKey, {
    db: { schema: 'api' },
  })
}

let client: AntidepClient | undefined

/**
 * Klienten appen deler. Opprettes ved første kall slik at en modulimport ikke
 * kaster i tester og verktøy som ikke har miljøvariablene satt.
 */
export function getAntidepClient(env: SupabaseEnv = import.meta.env): AntidepClient {
  client ??= createAntidepClient(readSupabaseConfig(env))
  return client
}

/** Bare for tester: glem den delte klienten. */
export function resetAntidepClientForTests(): void {
  client = undefined
}
