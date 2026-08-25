// ============================================================================
// Fra adresse til objekt, med tilstandene i behold
//
// Både legemiddelsiden og temasiden må gjøre det samme: vente på en spørring,
// og deretter slå opp én slug i svaret. De to trinnene har til sammen seks
// utfall, og fem av dem ville vært en tom skjerm om ingen skrev dem ut.
// Rekkefølgen mellom dem er den samme på begge sider, og ligger derfor her.
//
// Ordlyden ligger *ikke* her. «Antidep har ikke publisert om dette virkestoffet»
// og «Antidep har ikke publisert om dette temaet» er forskjellige utsagn, og en
// felles, parameterisert setning ville før eller siden blitt formulert slik at
// den passer begge og treffer ingen.
// ============================================================================

import { findBySlug, type SlugLookup } from '../lib/slug'
import type { ReadModelState } from './use-read-model'

/** Tilstandene der det ennå ikke finnes noe sett å slå opp i. */
export type UnresolvedReadModelState<Row> = Exclude<ReadModelState<Row>, { status: 'ok' }>

export type SlugResolution<Row, Item> =
  /** Spørringen ga ikke noe sett: den laster, den er tom, eller den feilet. */
  | { readonly kind: 'unresolved'; readonly state: UnresolvedReadModelState<Row> }
  /** Settet finnes, og sluggen er slått opp i det — med eller uten treff. */
  | {
      readonly kind: 'resolved'
      readonly lookup: SlugLookup<Item>
      readonly rows: readonly [Row, ...Row[]]
    }

/**
 * Slår opp sluggen i svaret, når svaret finnes.
 *
 * `candidatesOf` finnes fordi kandidatene ikke alltid er radene. Temasiden slår
 * opp i de kliniske begrepene påstandene nevner, og der er flere rader det samme
 * begrepet — et oppslag direkte i radene ville meldt tvetydighet hver gang et
 * tema hadde mer enn én påstand.
 */
export function resolveSlug<Row, Item>(
  state: ReadModelState<Row>,
  slug: string,
  candidatesOf: (rows: readonly [Row, ...Row[]]) => readonly Item[],
  nameOf: (item: Item) => string,
): SlugResolution<Row, Item> {
  if (state.status !== 'ok') {
    return { kind: 'unresolved', state }
  }
  return {
    kind: 'resolved',
    lookup: findBySlug(candidatesOf(state.rows), slug, nameOf),
    rows: state.rows,
  }
}
