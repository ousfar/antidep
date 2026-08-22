import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { describeClaimMagnitude } from '../src/lib/claim-effect'
import {
  CERTAINTY_LEVELS,
  CLAIM_DIRECTIONS,
  COMPARATOR_KINDS,
  EFFECT_MEASURES,
  ESTIMATE_UNITS,
  EVIDENCE_RELATIONSHIP_TYPES,
  KNOWLEDGE_TYPES,
  SOURCE_STATUSES,
  VALUE_AVAILABILITIES,
} from '../src/types/api'

// ============================================================================
// De lukkede vokabularene i src/types/api.ts er håndskrevne påstander om
// databasen. Ingenting har hittil kontrollert dem, og gjeldsposten står i
// MVP_IMPLEMENTATION_PLAN.md §74.7: en ny enum-verdi eller en omdøpt verdi
// gjør typen usann uten at noe feiler.
//
// Denne testen lukker vokabularhalvdelen av den gjelden. Den leser de
// versjonerte migrasjonene — samme framgangsmåte som
// tests/data-api-exposure.test.ts, og uten en kjørende database — og krever at
// hver union er nøyaktig enum-en den utgir seg for å være.
//
// Kilden vinner: slår kontrollen ut, er TypeScript-typen feil, ikke SQL-en.
//
// Kolonnenavn, nullbarhet og kolonnetyper er fortsatt ukontrollert. Den delen
// av gjeldsposten står.
// ============================================================================

const MIGRATIONS = 'supabase/migrations'

function migrationSql(): string {
  return readdirSync(MIGRATIONS)
    .filter((file) => file.endsWith('.sql'))
    .sort()
    .map((file) => readFileSync(join(MIGRATIONS, file), 'utf8'))
    .join('\n')
}

const SQL = migrationSql()

/** Verdiene i `create type <navn> as enum (…)`, i den rekkefølgen SQL-en gir dem. */
function enumValues(qualifiedName: string): string[] {
  const pattern = new RegExp(
    `create type ${qualifiedName.replace('.', '\\.')} as enum\\s*\\(([^)]*)\\)`,
    'i',
  )
  const match = pattern.exec(SQL)
  if (match?.[1] === undefined) {
    throw new Error(`fant ingen enum-definisjon for ${qualifiedName} i ${MIGRATIONS}`)
  }
  return match[1]
    .split(',')
    .map((entry) => entry.trim().replace(/^'|'$/g, ''))
    .filter((entry) => entry.length > 0)
}

describe('de lukkede vokabularene er nøyaktig enum-ene i migrasjonene', () => {
  it.each([
    ['knowledge.knowledge_type', KNOWLEDGE_TYPES],
    ['knowledge.certainty_level', CERTAINTY_LEVELS],
    ['knowledge.claim_direction', CLAIM_DIRECTIONS],
    ['knowledge.comparator_kind', COMPARATOR_KINDS],
    ['knowledge.effect_measure', EFFECT_MEASURES],
    ['knowledge.estimate_unit', ESTIMATE_UNITS],
    ['knowledge.claim_evidence_relationship', EVIDENCE_RELATIONSHIP_TYPES],
    ['knowledge.value_availability', VALUE_AVAILABILITIES],
    ['knowledge.source_status', SOURCE_STATUSES],
  ] as [string, readonly string[]][])('%s', (name, declared) => {
    // Som sett, ikke som liste: rekkefølgen i TypeScript er en presentasjons-
    // detalj, mens medlemskapet er påstanden om databasen.
    expect(new Set(declared)).toEqual(new Set(enumValues(name)))
  })

  it('finner faktisk enum-ene den leter etter', () => {
    // Uten denne ville en omskrevet migrasjon gjort hele testen stille sann:
    // enumValues() kaster, men bare hvis den kalles på et navn som finnes.
    expect(enumValues('knowledge.claim_direction')).toContain('no_clear_difference')
    expect(() => enumValues('knowledge.finnes_ikke')).toThrow(/fant ingen enum-definisjon/)
  })
})

describe('skillet mellom dimensjonale og dimensjonsløse effektmål følger migrasjon 004', () => {
  // claim_revisions_magnitude_unit_check krever enhet for målene den lister,
  // og forbyr enhet for resten. `claim-effect.ts` gjentar det skillet i en
  // egen liste, og de to kan drive fra hverandre uten at noe feiler.
  const constraint =
    /when magnitude_measure in \(([^)]*)\)\s*then magnitude_unit is not null/i.exec(SQL)

  const requiresUnit = (constraint?.[1] ?? '')
    .split(',')
    .map((entry) => entry.trim().replace(/^'|'$/g, ''))
    .filter((entry) => entry.length > 0)

  it('finner regelen i migrasjonen', () => {
    expect(requiresUnit.length).toBeGreaterThan(0)
    expect(requiresUnit.every((measure) => EFFECT_MEASURES.includes(measure as never))).toBe(true)
  })

  it.each(EFFECT_MEASURES)('%s behandles som migrasjonen sier', (measure) => {
    const dimensional = requiresUnit.includes(measure)
    expect(describeClaimMagnitude(measure, 1.2, 'kg')).toMatchObject(
      dimensional ? { kind: 'quantified' } : { reason: 'unit_on_dimensionless_measure' },
    )
    expect(describeClaimMagnitude(measure, 1.2, null)).toMatchObject(
      dimensional ? { reason: 'missing_unit' } : { kind: 'quantified' },
    )
  })
})
