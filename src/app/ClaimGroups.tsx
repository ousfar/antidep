// ============================================================================
// Publiserte påstander, gruppert
//
// Legemiddelsiden grupperer på tema, temasiden grupperer på virkestoff. Det er
// samme visning med to akser, og den ligger ett sted fordi den bærer to
// forbehold som ikke må stå i bare den ene av dem.
//
// ----------------------------------------------------------------------------
// Forbehold 1: rekkefølge er ikke rangering
//
// «UI-derived recommendations» er et eksplisitt antimønster
// (PRODUCT_INFORMATION_ARCHITECTURE.md §65), og invariant 14 sier at visuell
// orden ikke skal bli en anbefaling ved en tilfeldighet. En liste med to
// virkestoff under et tema *er* en ordnet liste, og leseren fyller inn en
// mening hvis vi ikke oppgir den. Rekkefølgen er derfor alfabetisk, sorteringen
// gjøres her framfor å arves fra spørringen — `order by` i PostgreSQL bruker
// databasens kollasjon, som ikke er norsk, så en visning som *sier* at
// rekkefølgen er alfabetisk må selv gjøre den alfabetisk — og den skrives ut.
//
// ----------------------------------------------------------------------------
// Forbehold 2: to påstander ved siden av hverandre er ikke en sammenligning
//
// Dette gjelder bare aksen «flere virkestoff under ett tema». To påstander kan
// ha ulik populasjon, ulik komparator og ulik tidsramme, og da er de ikke
// sammenlignbare selv om de står under samme overskrift. Sammenligning er en
// egen visning med egen semantikk (§21-§24, slice 3), og §29 krever definert
// semantikk før noe rangeres. Kortene bærer scope hver for seg (§14); her sies
// det som gjelder paret.
// ============================================================================

import { useId } from 'react'
import { Link } from 'react-router'
import { ClaimCard } from '../components/ClaimCard'
import { compareNorwegian } from '../lib/norwegian-format'
import { claimEvidencePath, drugPath, topicPath } from './routes'
import type { PublishedClaimRow } from '../types/api'

/** Hvilken akse settet grupperes på. Aksen avgjør både overskrift og forbehold. */
export type ClaimGroupAxis = 'topic' | 'drug'

interface Group {
  readonly id: string
  readonly label: string
  readonly href: string
  readonly claims: readonly PublishedClaimRow[]
}

function groupKey(axis: ClaimGroupAxis, claim: PublishedClaimRow) {
  return axis === 'topic'
    ? { id: claim.topic_concept_id, label: claim.topic_label, href: topicPath(claim.topic_label) }
    : { id: claim.drug_id, label: claim.drug_name, href: drugPath(claim.drug_name) }
}

/**
 * Grupperer på identiteten, ikke på etiketten.
 *
 * To katalogobjekter kan i prinsippet bære samme etikett; å gruppere på tekst
 * ville slått dem sammen til én overskrift og gjort to virkestoff til ett.
 * Etiketten er det leseren ser, `uuid`-en er det som avgjør hva som hører
 * sammen (DATABASE_ARCHITECTURE.md §8).
 */
function toGroups(claims: readonly PublishedClaimRow[], axis: ClaimGroupAxis): Group[] {
  const groups = new Map<string, { label: string; href: string; claims: PublishedClaimRow[] }>()
  for (const claim of claims) {
    const key = groupKey(axis, claim)
    const existing = groups.get(key.id)
    if (existing === undefined) {
      groups.set(key.id, { label: key.label, href: key.href, claims: [claim] })
    } else {
      existing.claims.push(claim)
    }
  }
  return [...groups]
    .map(([id, group]) => ({
      id,
      label: group.label,
      href: group.href,
      claims: [...group.claims].sort((a, b) => compareNorwegian(a.statement, b.statement)),
    }))
    .sort((a, b) => compareNorwegian(a.label, b.label))
}

/**
 * Rekkefølgen *og* hva listen er.
 *
 * En liste er to påstander på én gang: rekkefølgen, og at dette er settet. Den
 * andre er den farligste her — en temaside som viser to virkestoff, leses lett
 * som at de øvrige ikke har temaet, og en legemiddelside som viser to temaer,
 * som at virkestoffet ikke har andre. Begge er «No-data-as-zero» (§65) med en
 * liste som bærer.
 */
const ORDER_NOTE: Record<ClaimGroupAxis, string> = {
  topic:
    'Temaene er de Antidep har publisert påstander om for dette virkestoffet, i alfabetisk ' +
    'rekkefølge. Rekkefølgen er ikke en prioritering av klinisk viktighet, og listen er ingen ' +
    'fullstendig oversikt over kliniske forhold ved virkestoffet.',
  drug:
    'Virkestoffene er de Antidep har publisert påstander om for dette temaet, i alfabetisk ' +
    'rekkefølge. Rekkefølgen er ingen rangering, og at et virkestoff ikke står her, betyr ikke ' +
    'at temaet ikke gjelder for det.',
}

const COMPARISON_CAVEAT =
  'Påstandene under er ikke en sammenligning. De kan gjelde ulike populasjoner, ulike ' +
  'komparatorer og ulike tidsrammer, og lar seg da ikke stille opp mot hverandre. Hver påstand ' +
  'oppgir sitt eget anvendelsesområde.'

export interface ClaimGroupsProps {
  readonly claims: readonly PublishedClaimRow[]
  readonly axis: ClaimGroupAxis
}

export function ClaimGroups({ claims, axis }: ClaimGroupsProps) {
  const groups = toGroups(claims, axis)

  return (
    <>
      <div className="claim-groups__notes">
        <p className="claim-groups__note">{ORDER_NOTE[axis]}</p>
        {axis === 'drug' ? <p className="claim-groups__note">{COMPARISON_CAVEAT}</p> : null}
      </div>
      {groups.map((group) => (
        <ClaimGroup key={group.id} group={group} />
      ))}
    </>
  )
}

function ClaimGroup({ group }: { readonly group: Group }) {
  const headingId = useId()

  return (
    <section className="claim-group" aria-labelledby={headingId}>
      <h3 className="claim-group__heading" id={headingId}>
        {/* Gruppeoverskriften er inngangen til den andre aksen: fra en påstand
            om vekt hos ett virkestoff til alle virkestoff Antidep har publisert
            om vekt (§3, §26). */}
        <Link to={group.href}>{group.label}</Link>
      </h3>
      {group.claims.map((claim) => (
        <ClaimCard
          key={claim.claim_id}
          claim={claim}
          evidenceHref={claimEvidencePath(claim.claim_id)}
          // Siden eier hierarkiet: h1 er produktet, h2 er siden, h3 er gruppen,
          // og påstanden ligger under gruppen sin.
          headingLevel={4}
        />
      ))}
    </section>
  )
}
