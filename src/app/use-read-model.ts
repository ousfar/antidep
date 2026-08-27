// ============================================================================
// Henting av lesemodelldata i en komponent
//
// Ingen server-state-avhengighet. §7 i MVP_IMPLEMENTATION_PLAN.md lister
// server-state som en aktuell kategori, men ber om at et bibliotek ikke innføres
// før behovet er demonstrert. Flaten har i dag åtte lesespørringer — seks fra
// `published-read-model.ts` og to fra `caller-authorization.ts` (§74.22) —
// ingen mutasjoner, ingen invalidering og ingen bakgrunnsoppfriskning; det
// behovet er ikke demonstrert. Se §74.14.
//
// ----------------------------------------------------------------------------
// Generisk over resultattypen, ikke bundet til `published-read-model.ts`
//
// Hooken kjente opprinnelig bare `ReadModelResult<Row>`. Kallerens egen
// autorisasjon (§74.22) har en annen tomhetssemantikk — `no_actor` og
// `no_roles` betyr noe annet enn `empty`, og de to skal ikke slås sammen bare
// fordi henteplumbingen er felles (§74.21 «FELLE 3»). Hooken er derfor generisk
// over `Result`: den kjenner ingenting om hva feltene i et konkret resultat
// betyr, bare at et resultat er det en spørring løser med. `Row` finnes ikke
// lenger i denne signaturen — `ReadModelQuery<Row>` og `ReadModelState<Row>` er
// beholdt som typealias for de eksisterende kallstedene, men `useReadModel()`
// selv trenger den ikke: `Result` utledes direkte av spørringens returtype.
//
// ----------------------------------------------------------------------------
// Fire tilstander, og «laster» er en av dem
//
// Lesemodellen har tre (`ok | empty | error`), og `ok` har per konstruksjon
// aldri null rader (§74.12 punkt 1). Henting legger til én til: fram til svaret
// er der, vet vi ingenting. «Laster» må derfor ikke kunne rendres som «tomt» —
// det ville vist «Antidep har ingen publisert kunnskap» i det halvsekundet før
// svaret kom, og fravær av data skal aldri se ut som ingen risiko
// (ANTIDEP_CONSTITUTION.md §17). Samme regel gjelder `caller-authorization.ts`
// sine egne tomme tilstander.
//
// ----------------------------------------------------------------------------
// Tre feilkilder som ellers ville blitt til tomhet
//
// 1. En manglende klient. Konfigurasjonsfeil blir `error`, aldri `empty`.
// 2. En avvist promise. Kastet feil fanges og blir `error`, aldri `empty`.
// 3. Et foreldet svar. Skifter spørringen mens den forrige er underveis, kan
//    det første svaret komme sist. Uten en vakt ville da forrige virkestoffs
//    påstander stått under dette virkestoffets overskrift — et gyldig utseende
//    svar om feil legemiddel.
//
// Den tredje er løst strukturelt framfor med et flagg: svaret lagres sammen med
// spørringen det hører til, og vises bare når det fortsatt er den spørringen som
// gjelder. Et foreldet svar er dermed ikke noe som må fanges i tide — det er
// noe som ikke kan vises.
// ============================================================================

import { useEffect, useState } from 'react'
import { useAntidepClient } from './antidep-client'
import type { ReadModelResult } from '../lib/published-read-model'
import type { AntidepClient } from '../lib/supabase'

export type ReadModelState<Row> =
  /** Svaret er ikke kommet ennå. Sier ingenting om hva som finnes. */
  { readonly status: 'loading' } | ReadModelResult<Row>

/** En lesefunksjon fra `published-read-model.ts`, bundet til sine parametere. */
export type ReadModelQuery<Row> = (client: AntidepClient) => Promise<ReadModelResult<Row>>

/** Den ene feilformen enhver spørring kan ende i, uansett hva resultattypen ellers er. */
interface ErrorResult {
  readonly status: 'error'
  readonly message: string
}

/** Ett svar, med spørringen det er svar på. */
interface Snapshot<Result> {
  readonly query: (client: AntidepClient) => Promise<Result>
  readonly result: Result | ErrorResult
}

/**
 * Kjører én lesespørring og gir tilstanden dens.
 *
 * `query` må være referansestabil mellom rendere som skal gi samme resultat —
 * bruk modulfunksjonen direkte når den ikke har parametere, og `useCallback`
 * når den har. En ny referanse betyr «hent på nytt», og det er med hensikt den
 * eneste utløseren: en spørring som kjøres på nytt uten at noe er endret, er en
 * spørring ingen ba om.
 *
 * `Result` utledes av `query`s returtype, så et kall som
 * `useReadModel(fetchCallerActor)` gir `CallerActorResult`, ikke
 * `ReadModelResult<Row>`. Feilgrenen fra klientoppslaget (`availability.status
 * !== 'ready'`) og fra en avvist spørring er alltid `ErrorResult`, som er
 * strukturelt identisk med `error`-varianten enhver resultattype i denne
 * kodebasen har — det er derfor ingen `as`-cast her.
 */
export function useReadModel<Result>(
  query: (client: AntidepClient) => Promise<Result>,
): { readonly status: 'loading' } | ErrorResult | Result {
  const availability = useAntidepClient()
  const [snapshot, setSnapshot] = useState<Snapshot<Result> | null>(null)
  const client = availability.status === 'ready' ? availability.client : null

  useEffect(() => {
    if (client === null) {
      return
    }
    void (async () => {
      try {
        setSnapshot({ query, result: await query(client) })
      } catch (cause) {
        // En kastet feil er en feil. Den skal ikke bli til «ingen kunnskap».
        setSnapshot({
          query,
          result: {
            status: 'error',
            message: cause instanceof Error ? cause.message : String(cause),
          },
        })
      }
    })()
  }, [client, query])

  if (availability.status !== 'ready') {
    return { status: 'error', message: availability.message }
  }
  return snapshot !== null && snapshot.query === query ? snapshot.result : { status: 'loading' }
}
