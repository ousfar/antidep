import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

// DATABASE_ARCHITECTURE.md §5, §44 og §47: eksponering i Data API skal være
// opt-in, og bare kontraktslaget `api` skal være eksponert. Testen leser den
// versjonerte Supabase-konfigurasjonen slik at en utilsiktet eksponering fanges
// uten at en database må kjøre.
const CANONICAL_SCHEMAS = ['catalog', 'knowledge', 'workflow', 'provenance', 'audit', 'ingest']

const config = readFileSync('supabase/config.toml', 'utf8')

function apiSection(): string {
  const start = config.indexOf('\n[api]\n')
  if (start === -1) {
    throw new Error('fant ingen [api]-seksjon i supabase/config.toml')
  }
  const rest = config.slice(start + 1)
  const nextSection = rest.indexOf('\n[', 1)
  return nextSection === -1 ? rest : rest.slice(0, nextSection)
}

function exposedSchemas(): string[] {
  const match = /^schemas\s*=\s*\[(?<list>[^\]]*)\]/m.exec(apiSection())
  const list = match?.groups?.list
  if (list === undefined) {
    throw new Error('fant ingen schemas-nøkkel i [api]-seksjonen av supabase/config.toml')
  }
  return list
    .split(',')
    .map((entry) => entry.trim().replace(/^"|"$/g, ''))
    .filter((entry) => entry.length > 0)
}

describe('Data API-eksponering', () => {
  it('eksponerer kontraktslaget api', () => {
    expect(exposedSchemas()).toContain('api')
  })

  it('eksponerer ingen kanoniske schemaer', () => {
    const exposed = exposedSchemas().filter((schema) => CANONICAL_SCHEMAS.includes(schema))
    expect(exposed).toEqual([])
  })

  it('slår ikke på automatisk eksponering av nye tabeller', () => {
    const enabling = config
      .split('\n')
      .filter((line) => /^\s*auto_expose_new_tables\s*=\s*true/.test(line))
    expect(enabling).toEqual([])
  })
})
