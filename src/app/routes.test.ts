import { describe, expect, it } from 'vitest'
import { claimEvidencePath, drugPath, homePath, topicPath, ROUTE_PATTERNS } from './routes'

describe('adressene', () => {
  it('bygger nøyaktig de adressene §30 navngir', () => {
    expect(drugPath('sertralin')).toBe('/drugs/sertralin')
    expect(drugPath('mirtazapin')).toBe('/drugs/mirtazapin')
  })

  it('bruker det kanoniske navnet, uavhengig av bokstavstørrelse', () => {
    expect(drugPath('Sertralin')).toBe('/drugs/sertralin')
  })

  it('adresserer et klinisk tema med etiketten', () => {
    expect(topicPath('vektendring')).toBe('/topics/vektendring')
  })

  it('adresserer evidensvisningen med påstandens stabile identitet', () => {
    // claim_id, ikke claim_revision_id: identiteten overlever en ny publisering,
    // så en delt lenke fortsetter å peke på påstanden (ANTIDEP_CONSTITUTION §7).
    expect(claimEvidencePath('11111111-1111-4111-8111-111111111111')).toBe(
      '/claims/11111111-1111-4111-8111-111111111111/evidence',
    )
  })

  it('forsiden er roten', () => {
    expect(homePath()).toBe('/')
  })

  it('mønstrene og byggerne beskriver samme adresser', () => {
    // Et mønster som drifter fra byggeren gir lenker ruteren ikke kjenner.
    expect(ROUTE_PATTERNS.drug).toBe('/drugs/:drugSlug')
    expect(ROUTE_PATTERNS.topic).toBe('/topics/:topicSlug')
    expect(ROUTE_PATTERNS.claimEvidence).toBe('/claims/:claimId/evidence')
    expect(ROUTE_PATTERNS.home).toBe(homePath())
  })
})
