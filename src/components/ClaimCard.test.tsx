import { render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { ClaimCard } from './ClaimCard'
import type { ClaimDirection, EffectMeasure, EstimateUnit, PublishedClaimRow } from '../types/api'

// ----------------------------------------------------------------------------
// Syntetiske testdata
//
// Ingenting her er hentet fra en kilde, og ingenting her er innhold. Virkelige
// påstander kommer fra databasen gjennom review- og publiseringsgatene
// (ANTIDEP_CONSTITUTION.md §12), aldri fra en fikstur. Virkestoffnavnene er
// derfor oppdiktede, og tallene er valgt for å teste formatering.
// ----------------------------------------------------------------------------

const BASE: PublishedClaimRow = {
  claim_id: '11111111-1111-4111-8111-111111111111',
  claim_revision_id: '22222222-2222-4222-8222-222222222222',
  revision_number: 3,
  knowledge_type: 'evidence_synthesis',

  drug_id: '33333333-3333-4333-8333-333333333333',
  drug_name: 'Virkestoff A',
  topic_concept_id: '44444444-4444-4444-8444-444444444444',
  topic_label: 'Vekt',

  statement: 'Testpåstand: Virkestoff A er assosiert med større vektøkning enn placebo.',
  scope: 'Voksne, korttidsbehandling ved depresjon',

  population_id: '55555555-5555-4555-8555-555555555555',
  population_label: 'Voksne 18–64 år',
  timeframe_min: '56 days',
  timeframe_max: '84 days',
  comparator_kind: 'placebo',
  comparator_drug_id: null,
  comparator_drug_name: null,

  direction: 'increase',
  magnitude_measure: 'mean_difference',
  magnitude_value: 1.7,
  magnitude_unit: 'kg',

  qualifiers: 'Grunnlaget tillater ikke sammenligning med andre virkestoffer.',
  uncertainty_summary: 'Få studier, og kort oppfølgingstid.',

  certainty_framework: 'grade',
  certainty_level: 'moderate',
  certainty_rationale: 'Nedgradert for upresishet.',
  evidence_gap: null,
  last_assessed_at: '2026-08-20T10:00:00Z',

  withdrawn_evidence_count: 0,

  content_hash: 'sha256-v1:0000',
  revision_created_at: '2026-08-19T10:00:00Z',
  published_at: '2026-08-20T12:00:00Z',
  last_reviewed_at: '2026-08-21T09:15:00Z',
}

function claim(overrides: Partial<PublishedClaimRow> = {}): PublishedClaimRow {
  return { ...BASE, ...overrides }
}

const HREF = '/claims/11111111-1111-4111-8111-111111111111/evidens'

function renderCard(overrides: Partial<PublishedClaimRow> = {}) {
  return render(<ClaimCard claim={claim(overrides)} evidenceHref={HREF} />)
}

function card(): HTMLElement {
  return screen.getByRole('article')
}

/** Verdien under en gitt etikett i detaljlisten. */
function detail(label: string): string {
  const term = screen.getByText(label, { selector: 'dt' })
  const value = term.parentElement?.querySelector('dd')
  if (value == null) {
    throw new Error(`fant ingen verdi for detaljen «${label}»`)
  }
  return value.textContent ?? ''
}

function hasDetail(label: string): boolean {
  return screen.queryByText(label, { selector: 'dt' }) !== null
}

// ----------------------------------------------------------------------------

describe('kortets struktur følger §13', () => {
  it('viser kunnskapstype, konklusjon, retning, sikkerhet og veien til evidensen', () => {
    renderCard()
    expect(screen.getByText('Evidensbasert syntese')).toBeInTheDocument()
    expect(
      screen.getByRole('heading', { level: 3, name: /større vektøkning enn placebo/ }),
    ).toBeInTheDocument()
    expect(card()).toHaveTextContent('Økning')
    expect(screen.getByText('Moderat sikkerhet')).toBeInTheDocument()
    expect(screen.getByRole('link')).toHaveAttribute('href', HREF)
  })

  it('gir kortet et tilgjengelig navn fra konklusjonen', () => {
    renderCard()
    expect(card()).toHaveAccessibleName(BASE.statement)
  })
})

describe('kunnskapstypen står øverst', () => {
  it.each([
    ['deterministic_fact', 'Deterministisk faktum'],
    ['evidence_synthesis', 'Evidensbasert syntese'],
    ['clinical_recommendation', 'Klinisk anbefaling'],
  ] as const)('%s merkes «%s»', (knowledge_type, label) => {
    // Produktinvariant 8: en klinisk anbefaling skal være merket som en
    // anbefaling, ikke kunne leses som et faktum.
    renderCard({
      knowledge_type,
      certainty_level: knowledge_type === 'deterministic_fact' ? null : 'moderate',
    })
    expect(screen.getByText(label)).toBeInTheDocument()
  })

  it('en ukjent kunnskapstype sies høyt', () => {
    renderCard({ knowledge_type: 'regulatory_status' as PublishedClaimRow['knowledge_type'] })
    expect(card()).toHaveTextContent(/Ukjent kunnskapstype \(«regulatory_status»\)/)
  })
})

describe('konklusjonen og anvendelsesområdet kan ikke bli tomme', () => {
  it('en tom formulering blir en synlig mangel, ikke en tom overskrift', () => {
    renderCard({ statement: '   ' })
    expect(
      screen.getByRole('heading', { level: 3, name: 'Påstanden mangler formulering.' }),
    ).toBeInTheDocument()
  })

  it('et tomt anvendelsesområde blir en synlig mangel', () => {
    renderCard({ scope: '' })
    expect(detail('Gjelder')).toBe('Anvendelsesområdet mangler.')
  })

  it('anvendelsesområdet står alltid', () => {
    renderCard()
    expect(detail('Gjelder')).toBe(BASE.scope)
  })
})

describe('retningen', () => {
  it.each([
    ['increase', 'Økning'],
    ['decrease', 'Reduksjon'],
    ['no_clear_difference', 'Ingen klar forskjell'],
  ] as const)('%s vises som «%s»', (direction, expected) => {
    renderCard({ direction })
    expect(card()).toHaveTextContent(expected)
  })

  it('NULL sier at påstanden ikke angir en retning', () => {
    renderCard({ direction: null })
    expect(card()).toHaveTextContent('Påstanden angir ingen retning')
  })

  it('holder «ingen klar forskjell» og «ingen retning angitt» fra hverandre', () => {
    // Det ene er et resultat, det andre er fravær av et felt
    // (ANTIDEP_CONSTITUTION.md §17).
    const noDifference = render(
      <ClaimCard claim={claim({ direction: 'no_clear_difference' })} evidenceHref={HREF} />,
    )
    const notExpressed = render(
      <ClaimCard claim={claim({ direction: null })} evidenceHref={HREF} />,
    )
    const first = noDifference.container.querySelector('.claim-card__direction')?.textContent
    const second = notExpressed.container.querySelector('.claim-card__direction')?.textContent
    expect(first).not.toBe(second)
  })

  it('en retning utenfor vokabularet blir ukjent, ikke nøytral', () => {
    // knowledge.effect_direction har verdien not_stated; påstandens vokabular
    // har den ikke. Den skal ikke falle inn i en godartet gren.
    renderCard({ direction: 'not_stated' as ClaimDirection })
    expect(card()).toHaveTextContent(/Ukjent retning \(«not_stated»\)/)
  })

  it('pilen er et supplement og er skjult for hjelpemidler', () => {
    const { container } = renderCard({ direction: 'increase' })
    const symbol = container.querySelector('.claim-card__direction-symbol')
    expect(symbol).toHaveAttribute('aria-hidden', 'true')
    // Teksten alene bærer betydningen (§20).
    expect(container.querySelector('.claim-card__direction')).toHaveTextContent('Økning')
  })

  it.each(['no_clear_difference', null] as const)(
    'de tvetydige retningene får ingen pil (%s)',
    (direction) => {
      const { container } = renderCard({ direction })
      expect(container.querySelector('.claim-card__direction-symbol')).toBeNull()
    },
  )
})

describe('et tall står aldri uten sin komparator', () => {
  it('viser mål, verdi, enhet og komparator sammen', () => {
    renderCard()
    expect(detail('Størrelse og sammenligning')).toContain('Gjennomsnittsforskjell 1,7 kg.')
    expect(detail('Størrelse og sammenligning')).toContain('Sammenlignet med placebo.')
  })

  it.each([
    ['quantified', {}, 'Sammenlignet med placebo.'],
    [
      'not_quantified',
      { magnitude_measure: null, magnitude_value: null, magnitude_unit: null },
      'Sammenlignet med placebo.',
    ],
    [
      'unknown',
      { magnitude_measure: null, magnitude_value: 1.7, magnitude_unit: null },
      'Sammenlignet med placebo.',
    ],
  ] as const)(
    'komparatoren står i feltet også når størrelsen er %s',
    (_kind, overrides, expected) => {
      // Databasen håndhever ikke at et kontrastivt effektmål har en komparator
      // (se claim-effect.ts). Visningen svarer på det ved å gjøre de to
      // uatskillelige — også når det ikke finnes et tall å vise.
      renderCard(overrides)
      expect(detail('Størrelse og sammenligning')).toContain(expected)
    },
  )

  it.each([
    [
      'drug',
      { comparator_kind: 'drug', comparator_drug_name: 'Virkestoff B' },
      'Sammenlignet med Virkestoff B.',
    ],
    ['placebo', { comparator_kind: 'placebo' }, 'Sammenlignet med placebo.'],
    [
      'none',
      { comparator_kind: 'none', magnitude_measure: 'mean_change' as EffectMeasure },
      'Ingen komparator: endring fra behandlingsstart.',
    ],
  ] as const)('komparatorkategorien %s skrives ut', (_kind, overrides, expected) => {
    renderCard(overrides)
    expect(detail('Størrelse og sammenligning')).toContain(expected)
  })

  it('«ingen komparator» er ikke «ukjent komparator»', () => {
    renderCard({ comparator_kind: 'none', magnitude_measure: 'mean_change' })
    expect(detail('Størrelse og sammenligning')).not.toContain('ikke tolkbar')
  })

  it('en ikke-tallfestet størrelse sier at effekten ikke er null', () => {
    renderCard({ magnitude_measure: null, magnitude_value: null, magnitude_unit: null })
    const text = detail('Størrelse og sammenligning')
    expect(text).toContain('Størrelsen er ikke tallfestet.')
    expect(text).toMatch(/betyr ikke at effekten er null/i)
  })
})

describe('et tall som ikke er tolkbart, vises ikke som et tall', () => {
  it.each([
    [
      'et tall uten mål',
      { magnitude_measure: null, magnitude_value: 1.7, magnitude_unit: null },
      /uten effektmålet som gir det betydning/i,
    ],
    [
      'et mål uten tall',
      { magnitude_measure: 'mean_difference' as EffectMeasure, magnitude_value: null },
      /uten tallverdi/i,
    ],
    [
      'et mål utenfor vokabularet',
      { magnitude_measure: 'hazard_ratio' as EffectMeasure, magnitude_unit: null },
      /utenfor vokabularet/i,
    ],
    [
      'en enhet utenfor vokabularet',
      { magnitude_unit: 'lbs' as EstimateUnit },
      /Enheten er utenfor vokabularet/i,
    ],
    [
      'et dimensjonalt mål uten enhet',
      { magnitude_measure: 'mean_change' as EffectMeasure, magnitude_unit: null },
      /krever en enhet, og enheten mangler/i,
    ],
    [
      'en enhet på et dimensjonsløst mål',
      { magnitude_measure: 'risk_ratio' as EffectMeasure, magnitude_unit: 'kg' as EstimateUnit },
      /dimensjonsløst og skal ikke bære en enhet/i,
    ],
  ] as const)('%s forklares framfor å vises', (_label, overrides, expected) => {
    renderCard(overrides)
    const text = detail('Størrelse og sammenligning')
    expect(text).toContain('Størrelsen er ikke tolkbar.')
    expect(text).toMatch(expected)
    expect(text).not.toContain('1,7')
  })
})

describe('scope skjules aldri', () => {
  it('en uavgrenset populasjon skrives ut, og er ikke det samme som ukjent', () => {
    // NULL betyr at påstanden ikke er avgrenset til en registrert populasjon,
    // ikke at populasjonen er ukjent.
    renderCard({ population_id: null, population_label: null })
    expect(detail('Populasjon')).toBe('Ikke avgrenset til en registrert populasjon')
  })

  it('en tidsuavgrenset påstand sier det framfor å utelate raden', () => {
    // En rad som forsvinner får påstanden til å se tidløs ut (§14).
    renderCard({ timeframe_min: null, timeframe_max: null })
    expect(detail('Tidsramme')).toBe('Ikke tidsavgrenset')
  })

  it('viser tidsrammen som norsk varighet', () => {
    renderCard()
    expect(detail('Tidsramme')).toBe('56 dager til 84 dager')
  })

  it('slår sammen en tidsramme der min og maks er like', () => {
    renderCard({ timeframe_min: '56 days', timeframe_max: '56 days' })
    expect(detail('Tidsramme')).toBe('56 dager')
  })

  it('sier fra når bare den ene grensen er registrert', () => {
    // Databasen parer de to. Et enslig ledd er et brudd, ikke halve sannheten.
    renderCard({ timeframe_max: null })
    expect(detail('Tidsramme')).toBe('Ufullstendig registrert tidsramme: 56 dager')
  })

  it('viser en utolkbar intervalltekst uendret framfor å utelate den', () => {
    renderCard({ timeframe_min: 'P56D', timeframe_max: 'P84D' })
    expect(detail('Tidsramme')).toBe('P56D til P84D')
  })

  it('viser forbehold når de finnes, og utelater raden ellers', () => {
    renderCard()
    expect(detail('Forbehold')).toBe(BASE.qualifiers)
    renderCard({ qualifiers: null })
    expect(screen.queryAllByText('Forbehold', { selector: 'dt' })).toHaveLength(1)
  })
})

describe('usikkerhetsteksten', () => {
  it('vises når den finnes', () => {
    renderCard()
    expect(detail('Usikkerhet')).toBe(BASE.uncertainty_summary)
  })

  it.each(['evidence_synthesis', 'clinical_recommendation'] as const)(
    'sier fra når den mangler på en %s',
    (knowledge_type) => {
      // Migrasjon 004 krever den for begge typene. Mangler den, er raden brutt,
      // og stillhet ville skjult det (ANTIDEP_CONSTITUTION.md §6).
      renderCard({ knowledge_type, uncertainty_summary: null })
      expect(detail('Usikkerhet')).toMatch(/mangler, og skulle vært utfylt/i)
    },
  )

  it('utelates for et deterministisk faktum, som ikke krever den', () => {
    renderCard({
      knowledge_type: 'deterministic_fact',
      uncertainty_summary: null,
      certainty_level: null,
      certainty_framework: null,
    })
    expect(hasDetail('Usikkerhet')).toBe(false)
  })

  it('antar ikke at en ukjent kunnskapstype er unntatt', () => {
    renderCard({
      knowledge_type: 'regulatory_status' as PublishedClaimRow['knowledge_type'],
      uncertainty_summary: null,
    })
    expect(detail('Usikkerhet')).toMatch(/mangler, og skulle vært utfylt/i)
  })
})

describe('tilbaketrukket evidens merkes', () => {
  it('sier ingenting når ingenting er trukket tilbake', () => {
    const { container } = renderCard({ withdrawn_evidence_count: 0 })
    expect(container.querySelector('.claim-card__withdrawal')).toBeNull()
  })

  it('bruker entall for én lenke', () => {
    renderCard({ withdrawn_evidence_count: 1 })
    expect(screen.getByRole('note')).toHaveTextContent(
      'Én av evidenslenkene bak denne påstanden er trukket tilbake etter publisering.',
    )
  })

  it('sier at påstanden ikke er uberørt', () => {
    renderCard({ withdrawn_evidence_count: 3 })
    const note = screen.getByRole('note')
    expect(note).toHaveTextContent('3 av evidenslenkene')
    expect(note).toHaveTextContent(/deler av grunnlaget er underkjent/i)
  })

  it.each([-1, 1.5])('et utolkbart antall (%s) blir sagt, ikke stilltiende godtatt', (count) => {
    // Den benigne grenen her ville vært å vise ingenting, som ser ut som
    // «ingenting er trukket tilbake».
    renderCard({ withdrawn_evidence_count: count })
    expect(screen.getByRole('note')).toHaveTextContent(/ikke tolkbart/i)
  })
})

describe('sist faglig vurdert', () => {
  it('vises som norsk dato', () => {
    renderCard()
    expect(card()).toHaveTextContent('Sist faglig vurdert: 21. august 2026')
  })

  it('er «Ukjent» når datoen mangler, ikke «ikke vurdert» og ikke en fersk dato', () => {
    renderCard({ last_reviewed_at: null })
    expect(card()).toHaveTextContent('Sist faglig vurdert: Ukjent')
  })
})

describe('«Hvorfor sier Antidep dette?» er alltid nåbar', () => {
  it('lenker til evidensvisningen', () => {
    renderCard()
    const link = screen.getByRole('link')
    expect(link).toHaveTextContent('Hvorfor sier Antidep dette?')
    expect(link).toHaveAttribute('href', HREF)
  })

  it('får et tilgjengelig navn som skiller kortene fra hverandre', () => {
    // Uten dette heter hver lenke på en side med flere kort det samme.
    render(
      <>
        <ClaimCard claim={claim()} evidenceHref="/a" />
        <ClaimCard
          claim={claim({ statement: 'Testpåstand: en annen påstand.' })}
          evidenceHref="/b"
        />
      </>,
    )
    const names = screen.getAllByRole('link').map((link) => link.getAttribute('aria-labelledby'))
    expect(new Set(names).size).toBe(2)
    expect(
      within(screen.getAllByRole('article')[1] as HTMLElement).getByRole('link', {
        name: /Hvorfor sier Antidep dette\? Testpåstand: en annen påstand\./,
      }),
    ).toBeInTheDocument()
  })
})

describe('for et deterministisk faktum er retning og størrelse ikke aktuelle', () => {
  const FACT = {
    knowledge_type: 'deterministic_fact',
    statement: 'Testpåstand: Virkestoff A finnes som tablett 50 mg.',
    certainty_level: null,
    certainty_framework: null,
    uncertainty_summary: null,
    direction: null,
    magnitude_measure: null,
    magnitude_value: null,
    magnitude_unit: null,
    comparator_kind: 'none',
  } as const satisfies Partial<PublishedClaimRow>

  it('utelater retningslinjen framfor å si at retningen mangler', () => {
    // «Påstanden angir ingen retning» på «finnes som tablett 50 mg» er en
    // kategorifeil: faktumet har ingen retning å angi
    // (ANTIDEP_CONSTITUTION.md §5).
    const { container } = renderCard(FACT)
    expect(container.querySelector('.claim-card__direction')).toBeNull()
  })

  it('utelater størrelsesfeltet framfor å si at effekten ikke er null', () => {
    renderCard(FACT)
    expect(hasDetail('Størrelse og sammenligning')).toBe(false)
  })

  it('viser likevel en retning som faktisk er registrert', () => {
    // Utelatelsen gjelder tomme felter, ikke felter med innhold.
    renderCard({ ...FACT, direction: 'increase' })
    expect(card()).toHaveTextContent('Økning')
  })

  it('viser likevel en størrelse som faktisk er registrert', () => {
    renderCard({
      ...FACT,
      magnitude_measure: 'mean_change',
      magnitude_value: 50,
      magnitude_unit: 'kg',
    })
    expect(detail('Størrelse og sammenligning')).toContain('Gjennomsnittlig endring 50 kg.')
  })

  it('viser likevel en komparator som faktisk er registrert', () => {
    renderCard({ ...FACT, comparator_kind: 'placebo' })
    expect(detail('Størrelse og sammenligning')).toContain('Sammenlignet med placebo.')
  })
})

describe('unntaket gjelder bare deterministiske fakta', () => {
  const EMPTY_EFFECT = {
    direction: null,
    magnitude_measure: null,
    magnitude_value: null,
    magnitude_unit: null,
    comparator_kind: 'none',
  } as const satisfies Partial<PublishedClaimRow>

  it.each(['evidence_synthesis', 'clinical_recommendation'] as const)(
    'en %s sier fortsatt at retningen ikke er angitt',
    (knowledge_type) => {
      // Her er tomheten informasjon, og stillhet ville vært §17-feilen.
      renderCard({ ...EMPTY_EFFECT, knowledge_type })
      expect(card()).toHaveTextContent('Påstanden angir ingen retning')
    },
  )

  it.each(['evidence_synthesis', 'clinical_recommendation'] as const)(
    'en %s sier fortsatt at størrelsen ikke er tallfestet',
    (knowledge_type) => {
      renderCard({ ...EMPTY_EFFECT, knowledge_type })
      expect(detail('Størrelse og sammenligning')).toContain('Størrelsen er ikke tallfestet.')
    },
  )

  it('en ukjent kunnskapstype antas ikke å være unntatt', () => {
    renderCard({
      ...EMPTY_EFFECT,
      knowledge_type: 'regulatory_status' as PublishedClaimRow['knowledge_type'],
    })
    expect(card()).toHaveTextContent('Påstanden angir ingen retning')
    expect(hasDetail('Størrelse og sammenligning')).toBe(true)
  })
})

describe('kortet rendres uten advarsler fra React', () => {
  it.each([
    ['gradert', {}],
    [
      'ingen vurderbar evidens',
      { certainty_level: 'no_assessable_evidence', evidence_gap: 'Mangler.' },
    ],
    [
      'deterministisk faktum',
      {
        knowledge_type: 'deterministic_fact',
        certainty_level: null,
        uncertainty_summary: null,
        direction: null,
        magnitude_measure: null,
        magnitude_value: null,
        magnitude_unit: null,
        comparator_kind: 'none',
      },
    ],
    ['tilbaketrukket evidens', { withdrawn_evidence_count: 2 }],
    ['kontraktsbrudd', { magnitude_measure: null, magnitude_value: 1.7, magnitude_unit: null }],
  ] as [string, Partial<PublishedClaimRow>][])(
    'ingen console.error for %s',
    (_label, overrides) => {
      // React rapporterer ugyldig DOM-nøsting, manglende nøkler og ugyldige
      // attributter gjennom console.error. En stille advarsel her ville vært en
      // konsollfeil i nettleseren.
      const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
      try {
        renderCard(overrides)
        expect(spy).not.toHaveBeenCalled()
      } finally {
        spy.mockRestore()
      }
    },
  )
})
