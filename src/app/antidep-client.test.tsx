import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { AntidepClientProvider, resolveAntidepClient, useAntidepClient } from './antidep-client'
import { resetAntidepClientForTests } from '../lib/supabase'

function Probe() {
  const availability = useAntidepClient()
  return <output>{availability.status}</output>
}

describe('klienttilstanden', () => {
  it('en manglende konfigurasjon blir en tilstand, ikke et kast under render', () => {
    resetAntidepClientForTests()
    const availability = resolveAntidepClient({})
    expect(availability.status).toBe('unavailable')
    if (availability.status !== 'unavailable') {
      throw new Error('forventet unavailable')
    }
    // Meldingen navngir miljøvariabelen, slik at feilen er handlingsbar.
    expect(availability.message).toMatch(/VITE_SUPABASE_URL/)
  })

  it('en gyldig konfigurasjon gir en klient', () => {
    resetAntidepClientForTests()
    const availability = resolveAntidepClient({
      VITE_SUPABASE_URL: 'https://eksempel.supabase.co',
      VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_testverdi',
    })
    expect(availability.status).toBe('ready')
    resetAntidepClientForTests()
  })

  it('en manglende provider er en programmeringsfeil, ikke en tom flate', () => {
    // En stille fallback ville gjort en test som glemte provideren til en test
    // som påstår noe om en tom klinikerflate.
    expect(() => render(<Probe />)).toThrow(/AntidepClientProvider mangler/)
  })

  it('provideren gir tilstanden videre', () => {
    render(
      <AntidepClientProvider value={{ status: 'unavailable', message: 'ingen konfigurasjon' }}>
        <Probe />
      </AntidepClientProvider>,
    )
    expect(screen.getByRole('status')).toHaveTextContent('unavailable')
  })
})
