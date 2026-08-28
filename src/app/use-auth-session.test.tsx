import { act, render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { AntidepClientProvider, type AntidepClientAvailability } from './antidep-client'
import { fakeClient, TEST_USER_IDS } from './test-support'
import { useAuthSession, type AuthSessionState } from './use-auth-session'

function Probe() {
  const state = useAuthSession()
  return <output>{describeState(state)}</output>
}

function describeState(state: AuthSessionState): string {
  switch (state.status) {
    case 'loading':
      return 'laster'
    case 'signed_out':
      return 'utlogget'
    case 'signed_in':
      return `innlogget: ${state.userId}`
    case 'unavailable':
      return `utilgjengelig: ${state.message}`
  }
}

function renderProbe(availability: AntidepClientAvailability) {
  return render(
    <AntidepClientProvider value={availability}>
      <Probe />
    </AntidepClientProvider>,
  )
}

function state(): string {
  return screen.getByRole('status').textContent ?? ''
}

describe('useAuthSession', () => {
  it('starter i laster, ikke i utlogget', () => {
    // «Laster» og «utlogget» må aldri se like ut: det ene vet vi ingenting om
    // ennå, det andre er et svar om at kontoen faktisk ikke er innlogget.
    // getSession() svarer asynkront selv når svaret er kjent, så rett etter
    // montering er ingen av auth-hendelsene rukket å skje.
    const { client } = fakeClient({}, { initialUserId: null })
    renderProbe({ status: 'ready', client })
    expect(state()).toBe('laster')
  })

  it('leser en allerede innlogget sesjon ved montering', async () => {
    const { client } = fakeClient({}, { initialUserId: TEST_USER_IDS.a })
    renderProbe({ status: 'ready', client })
    await waitFor(() => {
      expect(state()).toBe(`innlogget: ${TEST_USER_IDS.a}`)
    })
  })

  it('ingen sesjon er utlogget', async () => {
    const { client } = fakeClient({}, { initialUserId: null })
    renderProbe({ status: 'ready', client })
    await waitFor(() => {
      expect(state()).toBe('utlogget')
    })
  })

  it('en klient som ikke lot seg opprette er utilgjengelig, aldri utlogget', () => {
    // Konfigurasjonsfeil og «ikke innlogget» må ikke kunne forveksles — samme
    // regel som `useReadModel()` håndhever for `unavailable` mot `empty`.
    renderProbe({ status: 'unavailable', message: 'VITE_SUPABASE_URL mangler' })
    expect(state()).toBe('utilgjengelig: VITE_SUPABASE_URL mangler')
  })

  it('oppdager en innlogging via abonnementet, uten at noe annet endres', async () => {
    // Selve grunnlaget FELLE 1 (MVP_IMPLEMENTATION_PLAN.md §74.22) løses med:
    // en komponent kan se innloggingstilstanden endre seg uten selv å pollet
    // eller å bli forsynt med en ny prop.
    const { client } = fakeClient({}, { initialUserId: null, signInUserId: TEST_USER_IDS.b })
    renderProbe({ status: 'ready', client })
    await waitFor(() => expect(state()).toBe('utlogget'))

    await act(async () => {
      await client.auth.signInWithPassword({ email: 'x@example.test', password: 'hemmelig' })
    })

    await waitFor(() => {
      expect(state()).toBe(`innlogget: ${TEST_USER_IDS.b}`)
    })
  })

  it('oppdager en utlogging via abonnementet', async () => {
    const { client } = fakeClient({}, { initialUserId: TEST_USER_IDS.a })
    renderProbe({ status: 'ready', client })
    await waitFor(() => expect(state()).toBe(`innlogget: ${TEST_USER_IDS.a}`))

    await act(async () => {
      await client.auth.signOut()
    })

    await waitFor(() => {
      expect(state()).toBe('utlogget')
    })
  })
})
