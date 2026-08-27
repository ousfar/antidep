// ============================================================================
// Innloggingstilstanden
//
// Supabase-js henger sesjonen på klienten automatisk ved innlogging — det
// trengs ingen egen klient for det (`src/lib/supabase.ts`). Det som mangler, er
// en måte for React-treet å *vite* når den tilstanden endrer seg, og til å
// holde «vet ikke ennå», «ikke innlogget», «innlogget» og «klienten finnes
// ikke» fra hverandre. De fire betyr forskjellige ting, og ingen av dem skal
// kunne se ut som en av de andre — samme regel som `useReadModel()` håndhever
// for lesemodelldata.
//
// ----------------------------------------------------------------------------
// FELLE 1 — sesjonen er en inngang til spørringen, ikke en omgivelse rundt den
//
// `useReadModel()` kjører bare på nytt når spørringens referanse endres
// (`use-read-model.ts`). Innlogging endrer ingen parameter på en spørring som
// `fetchCallerActor` — samme funksjon, samme referanse — så uten et eksplisitt
// grep ville en side fortsatt vist svaret fra før innlogging.
//
// Løsningen her er ikke å la denne hooken smugle en sesjonsnøkkel inn i en
// `useCallback`-avhengighet et annet sted. Den er strukturell: `AccessPage.tsx`
// forgrener på `AuthSessionState.status` og rendrer et *annet* komponenttre for
// `signed_out` enn for `signed_in`. Komponenten som kaller `fetchCallerActor`/
// `fetchCallerRoles` finnes ikke i det hele tatt før kalleren er innlogget, og
// monteres først da — en førstegangsmontering er per konstruksjon en frisk
// spørring, uten at noen nøkkel må holdes i sync med sesjonen. Bytter kalleren
// konto, går veien alltid via `signOut()` først (det finnes ingen innloggingsvei
// mens en sesjon allerede står), så komponenten avmonteres og monteres på nytt
// for den nye sesjonen. Denne hooken er stedet som *oppdager* endringen; hvor
// den brukes til å skille komponenttrærne, er `AccessPage.tsx`.
// ============================================================================

import { useEffect, useState } from 'react'
import { useAntidepClient } from './antidep-client'
import type { Session } from '@supabase/supabase-js'

export type AuthSessionState =
  /** Vi har ikke spurt sesjonslagret ennå. Sier ingenting om innloggingsstatus. */
  | { readonly status: 'loading' }
  | { readonly status: 'signed_out' }
  | { readonly status: 'signed_in'; readonly userId: string }
  /** Klienten finnes ikke. Aldri det samme som «ikke innlogget». */
  | { readonly status: 'unavailable'; readonly message: string }

function toSessionState(session: Session | null): AuthSessionState {
  return session === null
    ? { status: 'signed_out' }
    : { status: 'signed_in', userId: session.user.id }
}

/**
 * Den nåværende innloggingstilstanden, oppdatert når den endrer seg.
 *
 * Leser sesjonen én gang ved montering (`getSession()`) og abonnerer deretter
 * på `onAuthStateChange()` for innlogging, utlogging og tokenfornyelse. Et
 * kall skal aldri kunne miste en endring som skjer i vinduet mellom de to: uten
 * `getSession()` først ville en allerede innlogget bruker sett «ikke
 * innlogget» helt til neste auth-hendelse.
 */
export function useAuthSession(): AuthSessionState {
  const availability = useAntidepClient()
  const client = availability.status === 'ready' ? availability.client : null
  const [session, setSession] = useState<AuthSessionState>({ status: 'loading' })

  useEffect(() => {
    if (client === null) {
      return
    }
    let cancelled = false

    void client.auth.getSession().then(({ data }) => {
      if (!cancelled) {
        setSession(toSessionState(data.session))
      }
    })

    const {
      data: { subscription },
    } = client.auth.onAuthStateChange((_event, authSession) => {
      if (!cancelled) {
        setSession(toSessionState(authSession))
      }
    })

    return () => {
      cancelled = true
      subscription.unsubscribe()
    }
  }, [client])

  if (availability.status !== 'ready') {
    return { status: 'unavailable', message: availability.message }
  }
  return session
}
