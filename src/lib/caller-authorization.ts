// ============================================================================
// Kallerens egen autorisasjon
//
// To lesefunksjoner over `api.my_actor` og `api.my_roles` (migrasjon 007b,
// MVP_IMPLEMENTATION_PLAN.md §74.21). Første steg i «manuell adminflyt» (§29):
// før noen skjerm i den kan vise noe, må den kunne svare på «hvem er jeg, og
// hva har jeg lov til?».
//
// ----------------------------------------------------------------------------
// Hvorfor dette ikke står i published-read-model.ts («FELLE 3»)
//
// Kallerens egen aktør og egne roller er ikke publisert kunnskap: en tom
// `api.my_actor` betyr «ingen aktør er knyttet til denne kontoen», og en tom
// `api.my_roles` betyr «ingen rettighet nå» — to forskjellige, navngitte
// tomhetsformer, ikke den ene generiske `empty`-tilstanden lesemodellen bruker
// for «Antidep har ikke publisert dette». Å gjenbruke `ReadModelResult<Row>`
// her ville flatet ut nettopp det skillet en klient trenger for å vise riktig
// melding (se `AccessPage.tsx`). Sorteringsdoktrinen i `published-read-model.ts`
// gjelder heller ikke: rekkefølgen på en persons roller er ikke en vekting av
// noe, bare en stabil rekkefølge mellom kall — se `fetchCallerRoles()`.
//
// ----------------------------------------------------------------------------
// Ingen «du har lov»-boolean her («FELLE 4»)
//
// Funksjonene under svarer på hva kalleren HAR — en aktørrad, og de
// rolletildelingene som gjelder nå — aldri på hva kalleren KAN. En
// tilbaketrukket aktør (`retired_at` satt) beholder sine rolletildelinger i
// `api.my_roles`, men skriveoperasjonene avviser den likevel
// (`knowledge.assert_publisher_authorized(uuid, uuid)`). Å beregne en
// «tilgang: ja/nei»-verdi her ville flyttet en autorisasjonsbeslutning inn i
// denne modulen, og den ville uansett ikke vært den som gjelder. Klienten viser
// begge fakta — aktøren, med `retired_at`, og rollene — og lar leseren se
// sammenhengen selv; se `AccessPage.tsx`.
// ============================================================================

import type { AntidepClient } from './supabase'
import type { MyActorRow, MyRoleRow } from '../types/api'

/**
 * Kallerens egen aktørrad.
 *
 * `no_actor` er ikke en feil og ikke det samme som ikke innlogget: en
 * brukerkonto kan finnes før noen har registrert en aktør for den. Kalleren må
 * være innlogget for at dette kallet i det hele tatt skal gi mening — `api`
 * avviser en uinnlogget kaller med en tilgangsfeil, og den avgjørelsen tas ikke
 * her (se `AccessPage.tsx` og «FELLE 2» i §74.22).
 */
export type CallerActorResult =
  | { readonly status: 'ok'; readonly actor: MyActorRow }
  | { readonly status: 'no_actor' }
  | { readonly status: 'error'; readonly message: string }

/**
 * Kallerens egne rolletildelinger som gjelder nå.
 *
 * `no_roles` betyr «ingen rettighet nå», og skiller ikke en utløpt tildeling
 * fra en som aldri fantes — det er `api.my_roles` sin dokumenterte grense
 * (migrasjon 007b), ført som gjeld i MVP_IMPLEMENTATION_PLAN.md §74.7.
 */
export type CallerRolesResult =
  | { readonly status: 'ok'; readonly roles: readonly [MyRoleRow, ...MyRoleRow[]] }
  | { readonly status: 'no_roles' }
  | { readonly status: 'error'; readonly message: string }

interface PostgrestOutcome<Row> {
  data: Row[] | null
  error: { message: string } | null
}

/** Kallerens egen aktørrad, eller ingen rad. Aldri mer enn én (unik `auth_user_id`). */
export async function fetchCallerActor(client: AntidepClient): Promise<CallerActorResult> {
  const { data, error }: PostgrestOutcome<MyActorRow> = await client.from('my_actor').select('*')
  if (error !== null) {
    return { status: 'error', message: error.message }
  }
  const [actor] = data ?? []
  return actor === undefined ? { status: 'no_actor' } : { status: 'ok', actor }
}

/**
 * Kallerens egne rolletildelinger som gjelder nå.
 *
 * Sortert på `role_code` for en stabil rekkefølge mellom kall, ikke som en
 * rangering: innenfor settet viewet viser er `(role_code, scope_id)` allerede
 * entydig (migrasjon 007b), og rekkefølgen har ingen klinisk eller
 * governance-mening slik den kan ha på en evidensliste.
 */
export async function fetchCallerRoles(client: AntidepClient): Promise<CallerRolesResult> {
  const { data, error }: PostgrestOutcome<MyRoleRow> = await client
    .from('my_roles')
    .select('*')
    .order('role_code', { ascending: true })
  if (error !== null) {
    return { status: 'error', message: error.message }
  }
  const [first, ...rest] = data ?? []
  return first === undefined ? { status: 'no_roles' } : { status: 'ok', roles: [first, ...rest] }
}
