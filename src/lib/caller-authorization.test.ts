import { describe, expect, it } from 'vitest'
import { fetchCallerActor, fetchCallerRoles } from './caller-authorization'
import type { AntidepClient } from './supabase'
import type { MyActorRow, MyRoleRow } from '../types/api'

// ----------------------------------------------------------------------------
// Samme falske klient som published-read-model.test.ts, av samme grunn: den
// svarer på nivået lesefunksjonene faktisk spør på.
// ----------------------------------------------------------------------------

interface RecordedQuery {
  view: string
  columns: string
  filters: [string, unknown][]
  orders: [string, { ascending: boolean }][]
}

function fakeClient(outcome: { data: unknown[] | null; error: { message: string } | null }) {
  const queries: RecordedQuery[] = []
  const client = {
    from(view: string) {
      const recorded: RecordedQuery = { view, columns: '', filters: [], orders: [] }
      const builder = {
        select(columns: string) {
          recorded.columns = columns
          queries.push(recorded)
          return builder
        },
        order(column: string, options: { ascending: boolean }) {
          recorded.orders.push([column, options])
          return builder
        },
        then<Result>(resolve: (value: typeof outcome) => Result) {
          return Promise.resolve(outcome).then(resolve)
        },
      }
      return builder
    },
  }
  return { client: client as unknown as AntidepClient, queries }
}

const ACTOR: MyActorRow = {
  actor_id: '00000000-0000-4000-8000-111111111111',
  actor_key: 'human:testredaktor',
  display_name: 'Test Redaktør',
  retired_at: null,
}

const ROLE: MyRoleRow = {
  role_code: 'reviewer',
  scope_id: null,
  scope_type: null,
  valid_from: '2026-08-20T10:00:00Z',
  valid_to: null,
}

describe('fetchCallerActor', () => {
  it('leser api.my_actor', async () => {
    const { client, queries } = fakeClient({ data: [ACTOR], error: null })
    const result = await fetchCallerActor(client)

    expect(result).toEqual({ status: 'ok', actor: ACTOR })
    expect(queries).toEqual([{ view: 'my_actor', columns: '*', filters: [], orders: [] }])
  })

  it('ingen rad er no_actor, ikke empty og ikke feil', async () => {
    // «Ingen aktør knyttet til kontoen» er noe annet enn «ingen publisert
    // kunnskap» — se doc-kommentaren i caller-authorization.ts (FELLE 3).
    const { client } = fakeClient({ data: [], error: null })
    expect(await fetchCallerActor(client)).toEqual({ status: 'no_actor' })
  })

  it('data null uten feil er også no_actor', async () => {
    const { client } = fakeClient({ data: null, error: null })
    expect(await fetchCallerActor(client)).toEqual({ status: 'no_actor' })
  })

  it('en feil er en feil, aldri no_actor', async () => {
    const { client } = fakeClient({ data: null, error: { message: 'avvist' } })
    expect(await fetchCallerActor(client)).toEqual({ status: 'error', message: 'avvist' })
  })

  it('en feil vinner over en rad som måtte følge med', async () => {
    const { client } = fakeClient({ data: [ACTOR], error: { message: 'avvist' } })
    expect(await fetchCallerActor(client)).toEqual({ status: 'error', message: 'avvist' })
  })
})

describe('fetchCallerRoles', () => {
  it('leser api.my_roles, sortert stabilt på role_code', async () => {
    const { client, queries } = fakeClient({ data: [ROLE], error: null })
    const result = await fetchCallerRoles(client)

    expect(result).toEqual({ status: 'ok', roles: [ROLE] })
    expect(queries).toEqual([
      {
        view: 'my_roles',
        columns: '*',
        filters: [],
        orders: [['role_code', { ascending: true }]],
      },
    ])
  })

  it('ingen rad er no_roles, ikke empty og ikke feil', async () => {
    // «Ingen rettighet nå» — verken en feil, og heller ikke det generiske
    // «Antidep har ikke publisert dette» empty betyr på lesemodellen.
    const { client } = fakeClient({ data: [], error: null })
    expect(await fetchCallerRoles(client)).toEqual({ status: 'no_roles' })
  })

  it('data null uten feil er også no_roles', async () => {
    const { client } = fakeClient({ data: null, error: null })
    expect(await fetchCallerRoles(client)).toEqual({ status: 'no_roles' })
  })

  it('en feil er en feil, aldri no_roles', async () => {
    const { client } = fakeClient({ data: null, error: { message: 'avvist' } })
    expect(await fetchCallerRoles(client)).toEqual({ status: 'error', message: 'avvist' })
  })

  it('gir hele settet videre, med flere tildelinger', async () => {
    const second: MyRoleRow = { ...ROLE, role_code: 'publisher' }
    const { client } = fakeClient({ data: [ROLE, second], error: null })
    const result = await fetchCallerRoles(client)
    expect(result.status === 'ok' ? result.roles : []).toHaveLength(2)
  })
})

// ----------------------------------------------------------------------------
// Kompileringsvakt, som i published-read-model.test.ts: at radtypene fra
// api.my_actor/api.my_roles faktisk når fram til klienten, og ikke kollapser
// stille til `never` (se den filens kommentar for feilmodusen).
// ----------------------------------------------------------------------------

type MutuallyAssignable<A, B> = [A] extends [B] ? ([B] extends [A] ? true : false) : false

function actorQuery(client: AntidepClient) {
  return client.from('my_actor').select('*')
}
function rolesQuery(client: AntidepClient) {
  return client.from('my_roles').select('*')
}

const actorRowReachesTheClient: MutuallyAssignable<
  Awaited<ReturnType<typeof actorQuery>>['data'],
  MyActorRow[] | null
> = true

const roleRowReachesTheClient: MutuallyAssignable<
  Awaited<ReturnType<typeof rolesQuery>>['data'],
  MyRoleRow[] | null
> = true

describe('kontrakttypene når fram til klienten', () => {
  it('gir radtypene fra api.my_actor og api.my_roles, ikke never', async () => {
    const { client, queries } = fakeClient({ data: [], error: null })
    await actorQuery(client)
    await rolesQuery(client)

    expect(queries.map((query) => query.view)).toEqual(['my_actor', 'my_roles'])
    expect([actorRowReachesTheClient, roleRowReachesTheClient]).toEqual([true, true])
  })
})
