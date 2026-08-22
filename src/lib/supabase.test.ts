import { afterEach, describe, expect, it } from 'vitest'
import {
  assertPublishableKey,
  createAntidepClient,
  getAntidepClient,
  readSupabaseConfig,
  resetAntidepClientForTests,
  type SupabaseEnv,
} from './supabase'

/** Bygger en legacy Supabase-nøkkel: en JWT der `role` er det som betyr noe. */
function jwtWithRole(role: string): string {
  const segment = (value: object) =>
    btoa(JSON.stringify(value)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '')
  return [segment({ alg: 'HS256', typ: 'JWT' }), segment({ role }), 'signatur'].join('.')
}

const ANON_KEY = jwtWithRole('anon')

const VALID: SupabaseEnv = {
  VITE_SUPABASE_URL: 'https://prosjekt.supabase.co',
  VITE_SUPABASE_PUBLISHABLE_KEY: ANON_KEY,
}

afterEach(() => {
  resetAntidepClientForTests()
})

describe('nøkkelvakt', () => {
  it('avviser en secret key', () => {
    expect(() => assertPublishableKey('sb_secret_abc123')).toThrow(/secret key/i)
  })

  it('avviser en service_role-nøkkel', () => {
    expect(() => assertPublishableKey(jwtWithRole('service_role'))).toThrow(/service_role/)
  })

  it('avviser en ukjent privilegert rolle, ikke bare service_role', () => {
    // Vakten er positiv: alt utenfor anon/authenticated stoppes, slik at en
    // framtidig privilegert rolle ikke slipper gjennom fordi den ikke var
    // navngitt her.
    expect(() => assertPublishableKey(jwtWithRole('postgres'))).toThrow(/postgres/)
  })

  it('godtar anon og authenticated', () => {
    expect(() => assertPublishableKey(jwtWithRole('anon'))).not.toThrow()
    expect(() => assertPublishableKey(jwtWithRole('authenticated'))).not.toThrow()
  })

  it('godtar en publishable key i det nye formatet', () => {
    expect(() => assertPublishableKey('sb_publishable_abc123')).not.toThrow()
  })

  it('blokkerer ikke et nøkkelformat den ikke kjenner', () => {
    // Et ukjent format er ikke bevis på at nøkkelen er hemmelig. Vakten er et
    // supplement til at hemmeligheter aldri legges i repoet, ikke en lås.
    expect(() => assertPublishableKey('en-ugjenkjennelig-nokkel')).not.toThrow()
    expect(() => assertPublishableKey('a.b.c')).not.toThrow()
  })
})

describe('konfigurasjonslesing', () => {
  it('leser en gyldig konfigurasjon', () => {
    expect(readSupabaseConfig(VALID)).toEqual({
      url: 'https://prosjekt.supabase.co',
      publishableKey: ANON_KEY,
    })
  })

  it('feiler når URL-en mangler', () => {
    expect(() => readSupabaseConfig({ VITE_SUPABASE_PUBLISHABLE_KEY: ANON_KEY })).toThrow(
      /VITE_SUPABASE_URL mangler/,
    )
  })

  it('feiler når nøkkelen mangler', () => {
    expect(() => readSupabaseConfig({ VITE_SUPABASE_URL: VALID.VITE_SUPABASE_URL })).toThrow(
      /VITE_SUPABASE_PUBLISHABLE_KEY mangler/,
    )
  })

  it('behandler en blank verdi som manglende', () => {
    expect(() => readSupabaseConfig({ ...VALID, VITE_SUPABASE_URL: '   ' })).toThrow(
      /VITE_SUPABASE_URL mangler/,
    )
  })

  it('feiler på en URL som ikke lar seg tolke', () => {
    expect(() =>
      readSupabaseConfig({ ...VALID, VITE_SUPABASE_URL: 'prosjekt.supabase.co' }),
    ).toThrow(/ikke en gyldig URL/)
  })

  it('feiler på et annet protokollskjema enn http og https', () => {
    expect(() =>
      readSupabaseConfig({ ...VALID, VITE_SUPABASE_URL: 'postgres://localhost:5432' }),
    ).toThrow(/http eller https/)
  })

  it('slipper ikke en hemmelig nøkkel gjennom konfigurasjonslesingen', () => {
    expect(() =>
      readSupabaseConfig({ ...VALID, VITE_SUPABASE_PUBLISHABLE_KEY: jwtWithRole('service_role') }),
    ).toThrow(/service_role/)
  })
})

describe('klienten', () => {
  it('er bundet til kontraktslaget api', () => {
    // Ikke en sikkerhetsgrense — den ligger i RLS og i at de kanoniske
    // schemaene ikke er eksponert — men klienten skal ikke kunne peke et annet
    // sted uten at noen endrer denne linjen.
    // `rest` er protected i supabase-js, så kontrollen må gå utenom typen.
    // Alternativet er å ikke kontrollere at db.schema-valget faktisk traff.
    const client = createAntidepClient(readSupabaseConfig(VALID)) as unknown as {
      rest: { schemaName: string }
    }
    expect(client.rest.schemaName).toBe('api')
  })

  it('gjenbruker den delte klienten', () => {
    expect(getAntidepClient(VALID)).toBe(getAntidepClient(VALID))
  })

  it('opprettes først ved kall, slik at import ikke kaster uten konfigurasjon', () => {
    // Modulen er allerede importert på dette tidspunktet uten å kaste.
    expect(() => getAntidepClient({})).toThrow(/VITE_SUPABASE_URL mangler/)
  })
})
