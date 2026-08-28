import { fireEvent, screen, waitFor } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { TEST_USER_IDS, myActorRow, myRoleRow, renderRoute } from '../test-support'

// `useAuthSession()` leser sesjonen asynkront selv når svaret er kjent
// (`getSession()` løser først etter monteringen), så skjemaet er ikke i DOM-en
// før den første avventingen er unnagjort — se `use-auth-session.test.tsx`
// sin «starter i laster»-test for samme poeng, isolert på hooken alene.
async function submitLogin(email: string, password: string) {
  fireEvent.change(await screen.findByLabelText('E-post'), { target: { value: email } })
  fireEvent.change(screen.getByLabelText('Passord'), { target: { value: password } })
  fireEvent.click(screen.getByRole('button', { name: 'Logg inn' }))
}

describe('Min tilgang — ikke innlogget', () => {
  it('viser innloggingsskjemaet, og spør ikke om aktør/roller ennå', async () => {
    // FELLE 2: en uinnlogget kaller mot api.my_actor/api.my_roles ville fått
    // 42501 og blitt lest som «feil». Spørringene skal derfor aldri kjøre før
    // kalleren faktisk er innlogget.
    const { queries } = renderRoute('/access')
    expect(await screen.findByLabelText('E-post')).toBeInTheDocument()
    expect(screen.getByLabelText('Passord')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Logg inn' })).toBeInTheDocument()
    expect(queries.some((query) => query.view === 'my_actor')).toBe(false)
    expect(queries.some((query) => query.view === 'my_roles')).toBe(false)
  })

  it('et avvist innloggingsforsøk viser feilen og blir stående på skjemaet', async () => {
    renderRoute('/access', { auth: { signInError: 'Feil e-post eller passord' } })
    await submitLogin('redaktor@antidep.no', 'feil-passord')

    expect(await screen.findByRole('alert')).toHaveTextContent('Feil e-post eller passord')
    expect(screen.getByRole('button', { name: 'Logg inn' })).toBeInTheDocument()
  })
})

describe('Min tilgang — FELLE 1: innlogging utløser en frisk spørring', () => {
  it('spør ikke før innlogging, og gjør det rett etter — uten en sesjonsnøkkel i kallstedet', async () => {
    const { queries } = renderRoute('/access', {
      auth: { signInUserId: TEST_USER_IDS.a },
      api: { my_actor: [myActorRow()], my_roles: [myRoleRow()] },
    })
    await screen.findByLabelText('E-post')
    expect(queries.some((query) => query.view === 'my_actor')).toBe(false)

    await submitLogin('redaktor@antidep.no', 'hemmelig')

    await waitFor(() => {
      expect(queries.some((query) => query.view === 'my_actor')).toBe(true)
      expect(queries.some((query) => query.view === 'my_roles')).toBe(true)
    })
    expect(await screen.findByText('Test Redaktør')).toBeInTheDocument()
  })
})

describe('Min tilgang — innlogget, fire tilstander (FELLE 2)', () => {
  it('ingen aktør: sier at kontoen ikke er knyttet til en person, og viser ingen roller', async () => {
    renderRoute('/access', {
      auth: { initialUserId: TEST_USER_IDS.a },
      api: { my_actor: [], my_roles: [myRoleRow()] },
    })
    expect(
      await screen.findByText('Kontoen din er ikke knyttet til en person i Antidep.'),
    ).toBeInTheDocument()
    // En rolle uten en aktør å attribuere den til vises ikke som om den var i bruk.
    expect(screen.queryByText('reviewer')).not.toBeInTheDocument()
  })

  it('aktør uten roller: sier at det ikke er noen rettighet nå', async () => {
    renderRoute('/access', {
      auth: { initialUserId: TEST_USER_IDS.a },
      api: { my_actor: [myActorRow()], my_roles: [] },
    })
    expect(await screen.findByText('Du har ingen rettighet nå.')).toBeInTheDocument()
  })

  it('aktør med roller: viser rollene', async () => {
    renderRoute('/access', {
      auth: { initialUserId: TEST_USER_IDS.a },
      api: {
        my_actor: [myActorRow()],
        my_roles: [myRoleRow({ role_code: 'reviewer' }), myRoleRow({ role_code: 'publisher' })],
      },
    })
    expect(await screen.findByText('reviewer')).toBeInTheDocument()
    expect(screen.getByText('publisher')).toBeInTheDocument()
  })

  it('en teknisk feil vises som en feil, aldri som fravær', async () => {
    renderRoute('/access', {
      auth: { initialUserId: TEST_USER_IDS.a },
      api: { my_actor: { error: 'nettverksfeil' }, my_roles: [myRoleRow()] },
    })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent('nettverksfeil')
    expect(screen.queryByText(/Kontoen din er ikke knyttet/)).not.toBeInTheDocument()
    expect(screen.queryByText('Du har ingen rettighet nå.')).not.toBeInTheDocument()
  })
})

describe('Min tilgang — FELLE 4: tilbaketrukket aktør', () => {
  it('viser rollene og varsler samtidig, uten å late som de kan brukes', async () => {
    renderRoute('/access', {
      auth: { initialUserId: TEST_USER_IDS.a },
      api: {
        my_actor: [myActorRow({ retired_at: '2026-08-25T10:00:00Z' })],
        my_roles: [myRoleRow({ role_code: 'publisher' })],
      },
    })
    // Rollen vises fortsatt — den er en ekte rad, ikke skjult av tilbaketrekkingen.
    expect(await screen.findByText('publisher')).toBeInTheDocument()
    // ...men varselet om at den likevel ikke kan brukes, står ved siden av.
    expect(screen.getByText(/tatt ut av bruk/)).toBeInTheDocument()
    expect(screen.getByText(/blir avvist/)).toBeInTheDocument()
  })

  it('en aktør som ikke er tilbaketrukket, får ikke varselet', async () => {
    renderRoute('/access', {
      auth: { initialUserId: TEST_USER_IDS.a },
      api: { my_actor: [myActorRow({ retired_at: null })], my_roles: [myRoleRow()] },
    })
    await screen.findByText('reviewer')
    expect(screen.queryByText(/tatt ut av bruk/)).not.toBeInTheDocument()
  })
})

describe('Min tilgang — utlogging', () => {
  it('logg ut fører tilbake til innloggingsskjemaet', async () => {
    renderRoute('/access', {
      auth: { initialUserId: TEST_USER_IDS.a },
      api: { my_actor: [myActorRow()], my_roles: [myRoleRow()] },
    })
    fireEvent.click(await screen.findByRole('button', { name: 'Logg ut' }))
    expect(await screen.findByLabelText('E-post')).toBeInTheDocument()
  })

  it('logger bare ut denne økten, ikke kalleren fra alle enheter', async () => {
    // supabase-js sin standard scope er 'global': logger kalleren ut av
    // *alle* enheter og nettlesere kontoen er innlogget på. En knapp merket
    // «Logg ut» skal ikke ha den sideeffekten uten et eksplisitt produktkrav
    // — se ChatGPT-tilbakemeldingen på PR #34.
    const { signOutCalls } = renderRoute('/access', {
      auth: { initialUserId: TEST_USER_IDS.a },
      api: { my_actor: [myActorRow()], my_roles: [myRoleRow()] },
    })
    fireEvent.click(await screen.findByRole('button', { name: 'Logg ut' }))
    await screen.findByLabelText('E-post')
    expect(signOutCalls).toEqual([{ scope: 'local' }])
  })
})
