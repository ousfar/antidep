// ============================================================================
// Min tilgang — `/access`
//
// Steg 1 av «manuell adminflyt» (MVP_IMPLEMENTATION_PLAN.md §29, §74.21,
// §74.22): innlogging, og et svar på «hvem er jeg, og hva har jeg lov til?».
// Ikke mer. Steg 2 (skriveveien/RPC-laget) og Spor 2 (verifikasjon/godkjenning)
// hører til senere PR-er.
//
// Siden er bevisst den eneste veien inn til begge delene av spørsmålet: en
// uinnlogget kaller ser innloggingsskjemaet her, og en innlogget kaller ser
// svaret her. To sider ville latt de to drive fra hverandre.
//
// ----------------------------------------------------------------------------
// FELLE 1 — sesjonen er en inngang til spørringen, ikke en omgivelse rundt den
//
// Løsningen står i `use-auth-session.ts`, og brukes her: `AccessBody`
// forgrener på `AuthSessionState.status`, og `AccessOverview` — komponenten som
// faktisk kaller `fetchCallerActor()`/`fetchCallerRoles()` — finnes ikke i
// treet før kalleren er `signed_in`. En innlogging bytter dermed hele
// undertreet, ikke bare et felt i det, og `useReadModel()` sine spørringer
// monteres friskt. Se doc-kommentaren i `use-auth-session.ts` for hvorfor dette
// er valgt framfor en sesjonsnøkkel i en `useCallback`-avhengighet.
//
// ----------------------------------------------------------------------------
// FELLE 2 — fire tilstander, ikke tre
//
// `AccessSummary` holder disse fra hverandre, med hver sin ordlyd:
//
//   ikke innlogget            LoginForm (i AccessBody, før AccessOverview
//                              i det hele tatt monteres)
//   innlogget, ingen aktør    NoActorNotice
//   innlogget, ingen roller   «Du har ingen rettighet nå», i RolesSummary
//   feil                      AccessError — aldri lest som fravær
//
// En uinnlogget kaller mot `api.my_actor`/`api.my_roles` ville fått 42501 og
// blitt lest som «feil», som er galt svar. Det unngås strukturelt: spørringene
// kjører aldri før `useAuthSession()` har sagt `signed_in`.
//
// ----------------------------------------------------------------------------
// FELLE 3 — egen modul
//
// Fetch-funksjonene og deres resultattyper ligger i `caller-authorization.ts`,
// ikke i `published-read-model.ts`. Se doc-kommentaren der.
//
// ----------------------------------------------------------------------------
// FELLE 4 — ingen «du har lov»-boolean her heller
//
// Siden viser nøyaktig det `api.my_actor` og `api.my_roles` svarer: aktøren,
// med `retired_at`, og rollene som gjelder nå. Den regner ikke ut om kalleren
// «får lov» til noe — det avgjøres av skriveoperasjonen selv, på sitt eget
// tidspunkt (DATABASE_ARCHITECTURE.md §43, §48). En tilbaketrukket aktør har
// fortsatt sine rolletildelinger i `api.my_roles`, og de vises — sammen med et
// eksplisitt varsel om at en tilbaketrukket aktør ikke får brukt dem
// (`RetiredActorNotice`), aldri ved å skjule rollene.
// ============================================================================

import { useId, useState, type FormEvent } from 'react'
import { Detail, DetailList, DetailNote } from '../../components/DetailList'
import { fetchCallerActor, fetchCallerRoles } from '../../lib/caller-authorization'
import { formatTimestampAsDate, renderedText } from '../../lib/norwegian-format'
import { useAntidepClient } from '../antidep-client'
import { useAuthSession, type AuthSessionState } from '../use-auth-session'
import { useReadModel } from '../use-read-model'
import { usePageTitle } from '../use-page-title'
import type { CallerActorResult, CallerRolesResult } from '../../lib/caller-authorization'
import type { MyActorRow, MyRoleRow } from '../../types/api'

// ----------------------------------------------------------------------------
// Notiser med egen ordlyd
//
// `KnowledgeLoading`/`KnowledgeError`/`KnowledgeAbsence` i
// `components/KnowledgeNotice.tsx` sier eksplisitt «publisert kunnskap» — riktig
// ordlyd der, feil her: denne siden henter ikke publisert kunnskap, den henter
// kallerens egen tilgang. CSS-klassene gjenbrukes, som på kildesidens
// `UsageFaultNotice` (SourcePage.tsx), men teksten er egen.
// ----------------------------------------------------------------------------

function AccessLoading() {
  return (
    <p className="knowledge-notice knowledge-notice--loading" aria-busy="true" aria-live="polite">
      Henter tilgangen din …
    </p>
  )
}

function AccessError({ message }: { readonly message: string }) {
  return (
    <div className="knowledge-notice knowledge-notice--error" role="alert">
      <p className="knowledge-notice__lead">
        Antidep fikk ikke hentet informasjon om tilgangen din. Dette er en teknisk feil, ikke et
        svar om at du mangler rettigheter.
      </p>
      <p className="knowledge-notice__detail">Teknisk årsak: {message}</p>
    </div>
  )
}

function NoActorNotice() {
  return (
    <div className="knowledge-notice knowledge-notice--absence" role="note">
      <p className="knowledge-notice__lead">Kontoen din er ikke knyttet til en person i Antidep.</p>
      <p className="knowledge-notice__caveat">
        Rolletildelinger forutsetter en registrert aktør (ANTIDEP_CONSTITUTION.md §14). Ta kontakt
        med en administrator for å få kontoen din knyttet til en aktør.
      </p>
    </div>
  )
}

// ----------------------------------------------------------------------------
// Innlogget: aktøren og rollene
// ----------------------------------------------------------------------------

const SCOPE_LABEL_NOTE =
  'Antidep har registrert hvilket kliniske begrep tildelingen er avgrenset til, men ' +
  'lesemodellen eksponerer ikke etiketten ennå, så den kan ikke navngis her ' +
  '(MVP_IMPLEMENTATION_PLAN.md §74.7).'

const PLANNED_END_NOTE = 'Dette er en planlagt sluttdato som ennå ikke har inntruffet.'

function RoleEntry({ role }: { readonly role: MyRoleRow }) {
  const validFrom = renderedText(formatTimestampAsDate(role.valid_from), 'dato')

  return (
    <li className="access-role">
      {/* role_code er bevisst ikke oversatt: den er `string`, ikke en lukket
          union ennå (types/api.ts), og en oversettelse ville late som om
          vokabularet er lukket uten at noe håndhever det. */}
      <p className="access-role__code">{role.role_code}</p>
      <DetailList>
        <Detail label="Avgrensning">
          {role.scope_id === null ? 'Uavgrenset' : 'Avgrenset til et bestemt klinisk begrep'}
          {role.scope_id === null ? null : <DetailNote>{SCOPE_LABEL_NOTE}</DetailNote>}
        </Detail>
        <Detail label="Gjelder fra">{validFrom}</Detail>
        <Detail label="Gjelder til">
          {role.valid_to === null ? (
            'Ingen sluttdato er satt'
          ) : (
            <>
              {renderedText(formatTimestampAsDate(role.valid_to), 'dato')}
              <DetailNote>{PLANNED_END_NOTE}</DetailNote>
            </>
          )}
        </Detail>
      </DetailList>
    </li>
  )
}

function RolesSummary({ roles }: { readonly roles: readonly MyRoleRow[] }) {
  return (
    <section aria-labelledby="mine-roller">
      <h3 id="mine-roller">Mine roller</h3>
      {roles.length === 0 ? (
        <div className="knowledge-notice knowledge-notice--absence" role="note">
          <p className="knowledge-notice__lead">Du har ingen rettighet nå.</p>
          <p className="knowledge-notice__caveat">
            Dette skiller ikke en tildeling som nylig utløp fra én som aldri fantes
            (MVP_IMPLEMENTATION_PLAN.md §74.7). Ta kontakt med en administrator hvis du mener dette
            er feil.
          </p>
        </div>
      ) : (
        <ul className="access-roles">
          {roles.map((role) => (
            <RoleEntry key={`${role.role_code}:${role.scope_id ?? 'uavgrenset'}`} role={role} />
          ))}
        </ul>
      )}
    </section>
  )
}

/**
 * FELLE 4: `retired_at` vises alltid ved siden av rollene, aldri i stedet for
 * dem. Rollene under er ekte rader fra `api.my_roles` — de er ikke gjort
 * usanne av at aktøren er tilbaketrukket — men en tilbaketrukket aktør får dem
 * ikke brukt: `knowledge.assert_publisher_authorized(uuid, uuid)` avviser den
 * uansett. En skjerm som viste rollene uten dette varselet, ville lovet noe
 * systemet ikke innfrir.
 */
function RetiredActorNotice({ retiredAt }: { readonly retiredAt: string }) {
  const retired = renderedText(formatTimestampAsDate(retiredAt), 'dato')
  return (
    <p className="access-actor__retired" role="note">
      Denne aktøren ble tatt ut av bruk {retired}. Rollene under er fortsatt registrert, men
      handlinger som krever en aktiv aktør — for eksempel publisering — blir avvist, uansett hvilke
      roller som står her.
    </p>
  )
}

function ActorSummary({ actor }: { readonly actor: MyActorRow }) {
  return (
    <section aria-labelledby="min-aktor">
      <h3 id="min-aktor">Min aktør</h3>
      <DetailList>
        <Detail label="Navn">{actor.display_name}</Detail>
        <Detail label="Aktørnøkkel">{actor.actor_key}</Detail>
      </DetailList>
      {actor.retired_at === null ? null : <RetiredActorNotice retiredAt={actor.retired_at} />}
    </section>
  )
}

/** Det `useReadModel(fetchCallerActor)` faktisk kan returnere. Se `use-read-model.ts`. */
type ActorQueryState = { readonly status: 'loading' } | CallerActorResult
/** Det `useReadModel(fetchCallerRoles)` faktisk kan returnere. */
type RolesQueryState = { readonly status: 'loading' } | CallerRolesResult

/**
 * De fire tilstandene fra FELLE 2, for den innloggede kalleren.
 *
 * Venter bevisst på at *begge* spørringene er ferdige før noe annet enn
 * «laster» vises: aktøren og rollene er uavhengige spørringer, og et svar som
 * viser «ingen aktør» mens rollene fortsatt laster, ville vært en forhastet
 * konklusjon presentert som endelig.
 */
function AccessSummary({
  actorState,
  rolesState,
}: {
  readonly actorState: ActorQueryState
  readonly rolesState: RolesQueryState
}) {
  if (actorState.status === 'loading' || rolesState.status === 'loading') {
    return <AccessLoading />
  }
  if (actorState.status === 'error') {
    return <AccessError message={actorState.message} />
  }
  if (actorState.status === 'no_actor') {
    return <NoActorNotice />
  }
  if (rolesState.status === 'error') {
    return <AccessError message={rolesState.message} />
  }

  const roles = rolesState.status === 'ok' ? rolesState.roles : []
  return (
    <>
      <ActorSummary actor={actorState.actor} />
      <RolesSummary roles={roles} />
    </>
  )
}

function SignOutButton() {
  const availability = useAntidepClient()
  const [signingOut, setSigningOut] = useState(false)

  async function handleClick() {
    if (availability.status !== 'ready') {
      return
    }
    setSigningOut(true)
    await availability.client.auth.signOut()
    // Ingen `setSigningOut(false)` her med hensikt: en vellykket utlogging
    // fanges av `useAuthSession()`s abonnement, og AccessOverview avmonteres —
    // en tilstandsoppdatering på et avmontert tre er unødvendig og kan logge en
    // React-advarsel i utvikling.
  }

  return (
    <button
      className="access-sign-out"
      disabled={signingOut}
      onClick={() => void handleClick()}
      type="button"
    >
      {signingOut ? 'Logger ut …' : 'Logg ut'}
    </button>
  )
}

function AccessOverview() {
  const actorState = useReadModel(fetchCallerActor)
  const rolesState = useReadModel(fetchCallerRoles)

  return (
    <>
      <AccessSummary actorState={actorState} rolesState={rolesState} />
      <SignOutButton />
    </>
  )
}

// ----------------------------------------------------------------------------
// Ikke innlogget: innloggingsskjemaet
// ----------------------------------------------------------------------------

type LoginStatus = 'idle' | 'submitting' | { readonly error: string }

function LoginForm() {
  const availability = useAntidepClient()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [status, setStatus] = useState<LoginStatus>('idle')
  const emailId = useId()
  const passwordId = useId()

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (availability.status !== 'ready') {
      return
    }
    setStatus('submitting')
    const { error } = await availability.client.auth.signInWithPassword({ email, password })
    if (error !== null) {
      setStatus({ error: error.message })
      return
    }
    // Ingen navigering herfra: en vellykket innlogging fanges av
    // `useAuthSession()`s abonnement, og AccessBody bytter selv til
    // AccessOverview. Skjemaet trenger ikke vite at det skjedde.
    setStatus('idle')
  }

  return (
    <form className="login-form" onSubmit={(event) => void handleSubmit(event)}>
      <p className="login-form__lead">Logg inn for å se din tilgang i Antidep.</p>

      <div className="login-form__field">
        <label htmlFor={emailId}>E-post</label>
        <input
          autoComplete="email"
          id={emailId}
          onChange={(event) => setEmail(event.target.value)}
          required
          type="email"
          value={email}
        />
      </div>

      <div className="login-form__field">
        <label htmlFor={passwordId}>Passord</label>
        <input
          autoComplete="current-password"
          id={passwordId}
          onChange={(event) => setPassword(event.target.value)}
          required
          type="password"
          value={password}
        />
      </div>

      {typeof status === 'object' ? (
        <p className="login-form__error" role="alert">
          Innloggingen ble avvist. Teknisk årsak: {status.error}
        </p>
      ) : null}

      <button disabled={status === 'submitting'} type="submit">
        {status === 'submitting' ? 'Logger inn …' : 'Logg inn'}
      </button>
    </form>
  )
}

// ----------------------------------------------------------------------------
// Siden
// ----------------------------------------------------------------------------

function AccessBody({ authState }: { readonly authState: AuthSessionState }) {
  switch (authState.status) {
    case 'loading':
      return <AccessLoading />
    case 'unavailable':
      return <AccessError message={authState.message} />
    case 'signed_out':
      return <LoginForm />
    case 'signed_in':
      // Frisk montering ved hver innlogging — se FELLE 1 i doc-kommentaren
      // øverst. `key` sikrer det samme også ved et brukerbytte: skulle en ny
      // sesjon få samme React-posisjon uten at komponenten noen gang
      // avmonteres, ville `userId` som `key` uansett tvunget en ny montering.
      return <AccessOverview key={authState.userId} />
  }
}

export function AccessPage() {
  usePageTitle('Min tilgang')
  const authState = useAuthSession()

  return (
    <>
      <p className="page-kicker">Konto</p>
      <h2>Min tilgang</h2>
      <AccessBody authState={authState} />
    </>
  )
}
