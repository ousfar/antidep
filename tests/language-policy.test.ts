import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

// ANTIDEP_CONSTITUTION.md §3: Antidep skal alltid bruke «antidepressiver»,
// aldri den forbudte formen. Denne testen håndhever regelen deterministisk
// for all app-kode. («antidepressiver» inneholder ikke den forbudte formen
// som delstreng, så korrekt språk passerer.)
const FORBIDDEN_FORM = /antidepressiva/i

function collectFiles(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name)
    return entry.isDirectory() ? collectFiles(path) : [path]
  })
}

describe('språkregel fra konstitusjonen', () => {
  it('app-kode og index.html bruker aldri den forbudte ordformen', () => {
    const files = [...collectFiles('src'), 'index.html']
    const violations = files.filter((file) => FORBIDDEN_FORM.test(readFileSync(file, 'utf8')))
    expect(violations).toEqual([])
  })
})
