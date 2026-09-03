// ============================================================================
// Opprett kilde — `/sources/new`
//
// Steg 2 av «manuell adminflyt» (MVP_IMPLEMENTATION_PLAN.md §29, §74.24):
// «Editor oppretter Source» (§15), det aller første leddet i admin-workflowen.
// EvidenceItem, ClaimRevision, review og publisering hører til senere PR-er
// (§51).
//
// ----------------------------------------------------------------------------
// Ingen rollegate her — bare en innloggingsgate
//
// Siden viser skjemaet til enhver innlogget bruker, ikke bare til en med
// editor-rolle. `api.my_roles` (Steg 1, §74.21) svarer på hva kalleren HAR,
// ikke hva kalleren FÅR LOV TIL, og en klient som brukte innholdet der til å
// skjule skjemaet ville lovet en beslutning `knowledge.assert_editor_authorized()`
// uansett tar på nytt, på sitt eget tidspunkt (DATABASE_ARCHITECTURE.md §43,
// §48 — samme doktrine som `AccessPage.tsx` sin FELLE 4). En bruker uten
// editor-rolle får se skjemaet og et avvist forsøk med databasens egen
// forklaring, ikke en knapp som er deaktivert på et løfte klienten ikke kan
// stå for.
//
// Selve innloggingssjekken er strukturell, samme mønster som
// `AccessPage.tsx` sin FELLE 1: skjemaet finnes ikke i treet før kalleren er
// `signed_in`, og monteres friskt (med `userId` som `key`) ved hver innlogging
// eller brukerbytte.
// ============================================================================

import { useId, useState, type FormEvent } from 'react'
import { Link } from 'react-router'
import { createSource } from '../../lib/create-source'
import {
  canonicalPublicationDate,
  EMPTY_PUBLICATION_DATE,
  PUBLICATION_DATE_CHOICES,
} from '../../lib/publication-date'
import { SOURCE_TYPES } from '../../types/api'
import { useAntidepClient } from '../antidep-client'
import { useAuthSession, type AuthSessionState } from '../use-auth-session'
import { usePageTitle } from '../use-page-title'
import { accessPath, sourcePath } from '../routes'
import type { CreateSourceResult } from '../../lib/create-source'
import type { PublicationDateChoice, PublicationDateDraft } from '../../lib/publication-date'
import type { Uuid } from '../../types/api'

function CreateSourceLoading() {
  return (
    <p className="knowledge-notice knowledge-notice--loading" aria-busy="true" aria-live="polite">
      Sjekker innloggingen …
    </p>
  )
}

function CreateSourceError({ message }: { readonly message: string }) {
  return (
    <div className="knowledge-notice knowledge-notice--error" role="alert">
      <p className="knowledge-notice__lead">Antidep fikk ikke sjekket innloggingen din.</p>
      <p className="knowledge-notice__detail">Teknisk årsak: {message}</p>
    </div>
  )
}

function SignedOutNotice() {
  return (
    <div className="knowledge-notice knowledge-notice--absence" role="note">
      <p className="knowledge-notice__lead">Du må logge inn for å opprette en kilde.</p>
      <p className="knowledge-notice__caveat">
        <Link to={accessPath()}>Logg inn under «Min tilgang»</Link>, og kom tilbake hit.
      </p>
    </div>
  )
}

/** Tom streng fra et valgfritt tekstfelt betyr «ikke oppgitt», ikke en verdi å lagre. */
function blankToNull(value: string): string | null {
  return value.trim().length === 0 ? null : value
}

interface FormState {
  readonly sourceType: string
  readonly title: string
  readonly authorsOrIssuer: string
  readonly publisherOrJournal: string
  readonly volume: string
  readonly issue: string
  readonly pages: string
  readonly publicationDate: PublicationDateDraft
}

const EMPTY_FORM: FormState = {
  sourceType: SOURCE_TYPES[0],
  title: '',
  authorsOrIssuer: '',
  publisherOrJournal: '',
  volume: '',
  issue: '',
  pages: '',
  publicationDate: EMPTY_PUBLICATION_DATE,
}

// ----------------------------------------------------------------------------
// Publiseringsdato: presisjonen først, så nøyaktig så mye dato som den rommer
//
// Databasen lagrer en årfestet dato som `YYYY-01-01` og en månedsfestet som
// `YYYY-MM-01` (migrasjon 003). Det er riktig representasjon, men det er
// databasens representasjon: en redaktør som vet at kilden er fra «november
// 2000» skal ikke måtte vite at det skrives som 1. november for å slippe forbi
// en CHECK. Skjemaet spør derfor om presisjonen først og viser deretter det ene
// datofeltet den presisjonen faktisk rommer — et årsfelt, en månedsvelger eller
// en datovelger. Kanoniseringen skjer i `publication-date.ts`, som konstruerer
// den avkortede datoen framfor å kontrollere at brukeren traff den.
// ----------------------------------------------------------------------------

const DATE_CHOICE_LABELS: Record<PublicationDateChoice, string> = {
  none: 'Ingen dato er oppgitt i kilden',
  year: 'Bare året er kjent',
  month: 'Måned og år er kjent',
  day: 'Nøyaktig dato er kjent',
}

function PublicationDateFields({
  draft,
  onChange,
  problem,
}: {
  readonly draft: PublicationDateDraft
  readonly onChange: (draft: PublicationDateDraft) => void
  readonly problem: string | null
}) {
  const choiceId = useId()
  const valueId = useId()
  const problemId = useId()

  return (
    <>
      <div className="create-source-form__field">
        <label htmlFor={choiceId}>Publiseringsdato</label>
        <select
          id={choiceId}
          onChange={(event) =>
            onChange({ ...draft, choice: event.target.value as PublicationDateChoice })
          }
          value={draft.choice}
        >
          {PUBLICATION_DATE_CHOICES.map((choice) => (
            <option key={choice} value={choice}>
              {DATE_CHOICE_LABELS[choice]}
            </option>
          ))}
        </select>
      </div>

      {/* Ett felt om gangen, styrt av presisjonen. De tre verdiene lever side om
          side i draften, så et bytte fram og tilbake ikke sletter det brukeren
          allerede har skrevet. */}
      {draft.choice === 'year' ? (
        <div className="create-source-form__field">
          <label htmlFor={valueId}>År</label>
          <input
            aria-describedby={problem === null ? undefined : problemId}
            id={valueId}
            inputMode="numeric"
            max="9999"
            min="1000"
            onChange={(event) => onChange({ ...draft, year: event.target.value })}
            step="1"
            type="number"
            value={draft.year}
          />
        </div>
      ) : null}

      {draft.choice === 'month' ? (
        <div className="create-source-form__field">
          <label htmlFor={valueId}>Måned og år</label>
          <input
            aria-describedby={problem === null ? undefined : problemId}
            id={valueId}
            onChange={(event) => onChange({ ...draft, month: event.target.value })}
            type="month"
            value={draft.month}
          />
        </div>
      ) : null}

      {draft.choice === 'day' ? (
        <div className="create-source-form__field">
          <label htmlFor={valueId}>Dato</label>
          <input
            aria-describedby={problem === null ? undefined : problemId}
            id={valueId}
            onChange={(event) => onChange({ ...draft, day: event.target.value })}
            type="date"
            value={draft.day}
          />
        </div>
      ) : null}

      {problem === null ? null : (
        <p className="create-source-form__problem" id={problemId} role="alert">
          {problem}
        </p>
      )}
    </>
  )
}

type SubmitStatus = 'idle' | 'submitting'

/**
 * Bekreftelsen etter en vellykket opprettelse. Skjemaet nullstilles ved siden
 * av, slik at neste kilde kan registreres uten en ekstra handling — men
 * bekreftelsen for den forrige blir stående til en ny opprettelse erstatter
 * den, ikke bare til neste tastetrykk.
 */
function CreatedNotice({ sourceId }: { readonly sourceId: Uuid }) {
  return (
    <p className="knowledge-notice knowledge-notice--ok" role="status">
      Kilden er opprettet. <Link to={sourcePath(sourceId)}>Se kilden</Link>.
    </p>
  )
}

function CreateSourceForm() {
  const availability = useAntidepClient()
  const [form, setForm] = useState<FormState>(EMPTY_FORM)
  const [status, setStatus] = useState<SubmitStatus>('idle')
  const [result, setResult] = useState<CreateSourceResult | null>(null)
  const [dateProblem, setDateProblem] = useState<string | null>(null)
  const sourceTypeId = useId()
  const titleId = useId()
  const authorsId = useId()
  const publisherId = useId()
  const volumeId = useId()
  const issueId = useId()
  const pagesId = useId()

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (availability.status !== 'ready') {
      return
    }

    // Datoen kanoniseres før kallet, ikke validert mot databasens regler:
    // `canonicalPublicationDate()` *bygger* den avkortede datoen presisjonen
    // krever. Er den `incomplete`, har brukeren valgt en presisjon uten å fylle
    // ut datoen — da finnes det ingen verdi å sende, og skjemaet sier fra
    // framfor å la databasen avvise en halv dato med sitt eget constraint-navn.
    // Alt annet er fortsatt databasens dom (§43, §48).
    const publicationDate = canonicalPublicationDate(form.publicationDate)
    if (publicationDate.status === 'incomplete') {
      setDateProblem(publicationDate.message)
      return
    }
    setDateProblem(null)

    setStatus('submitting')
    // Databasens CHECK-constraints på knowledge.sources er fasiten (migrasjon
    // 003); skjemaet gjetter ikke på dem selv (oppgaveteksten, felle 4). Det
    // eneste som gjøres her er å oversette et tomt tekstfelt til fravær, ikke å
    // validere innholdet i et utfylt felt.
    const outcome = await createSource(availability.client, {
      sourceType: form.sourceType,
      title: form.title,
      authorsOrIssuer: form.authorsOrIssuer,
      publisherOrJournal: blankToNull(form.publisherOrJournal),
      volume: blankToNull(form.volume),
      issue: blankToNull(form.issue),
      pages: blankToNull(form.pages),
      publicationDate: publicationDate.date,
      publicationDatePrecision: publicationDate.precision,
    })
    setStatus('idle')
    setResult(outcome)
    if (outcome.status === 'ok') {
      setForm(EMPTY_FORM)
    }
  }

  return (
    <>
      {result?.status === 'ok' ? <CreatedNotice sourceId={result.sourceId} /> : null}
      {result?.status === 'error' ? (
        <div className="knowledge-notice knowledge-notice--error" role="alert">
          <p className="knowledge-notice__lead">Kilden ble ikke opprettet.</p>
          <p className="knowledge-notice__detail">Teknisk årsak: {result.message}</p>
        </div>
      ) : null}

      <form className="create-source-form" onSubmit={(event) => void handleSubmit(event)}>
        <div className="create-source-form__field">
          <label htmlFor={sourceTypeId}>Kildetype</label>
          <select
            id={sourceTypeId}
            onChange={(event) => setForm({ ...form, sourceType: event.target.value })}
            required
            value={form.sourceType}
          >
            {SOURCE_TYPES.map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </select>
        </div>

        <div className="create-source-form__field">
          <label htmlFor={titleId}>Tittel</label>
          <input
            id={titleId}
            onChange={(event) => setForm({ ...form, title: event.target.value })}
            required
            type="text"
            value={form.title}
          />
        </div>

        <div className="create-source-form__field">
          <label htmlFor={authorsId}>Forfattere eller utgiver</label>
          <input
            id={authorsId}
            onChange={(event) => setForm({ ...form, authorsOrIssuer: event.target.value })}
            required
            type="text"
            value={form.authorsOrIssuer}
          />
        </div>

        <div className="create-source-form__field">
          <label htmlFor={publisherId}>Tidsskrift eller utgiver (valgfritt)</label>
          <input
            id={publisherId}
            onChange={(event) => setForm({ ...form, publisherOrJournal: event.target.value })}
            type="text"
            value={form.publisherOrJournal}
          />
        </div>

        <div className="create-source-form__field">
          <label htmlFor={volumeId}>Volum (valgfritt)</label>
          <input
            id={volumeId}
            onChange={(event) => setForm({ ...form, volume: event.target.value })}
            type="text"
            value={form.volume}
          />
        </div>

        <div className="create-source-form__field">
          <label htmlFor={issueId}>Hefte (valgfritt)</label>
          <input
            id={issueId}
            onChange={(event) => setForm({ ...form, issue: event.target.value })}
            type="text"
            value={form.issue}
          />
        </div>

        <div className="create-source-form__field">
          <label htmlFor={pagesId}>Sider (valgfritt)</label>
          <input
            id={pagesId}
            onChange={(event) => setForm({ ...form, pages: event.target.value })}
            type="text"
            value={form.pages}
          />
        </div>

        <PublicationDateFields
          draft={form.publicationDate}
          onChange={(publicationDate) => setForm({ ...form, publicationDate })}
          problem={dateProblem}
        />

        <button disabled={status === 'submitting'} type="submit">
          {status === 'submitting' ? 'Oppretter …' : 'Opprett kilde'}
        </button>
      </form>
    </>
  )
}

function CreateSourceBody({ authState }: { readonly authState: AuthSessionState }) {
  switch (authState.status) {
    case 'loading':
      return <CreateSourceLoading />
    case 'unavailable':
      return <CreateSourceError message={authState.message} />
    case 'signed_out':
      return <SignedOutNotice />
    case 'signed_in':
      return <CreateSourceForm key={authState.userId} />
  }
}

export function CreateSourcePage() {
  usePageTitle('Opprett kilde')
  const authState = useAuthSession()

  return (
    <>
      <p className="page-kicker">Admin</p>
      <h2>Opprett kilde</h2>
      <p className="create-source-form__intro">
        Det første steget i redaksjonsarbeidet: en kilde må være registrert før evidens kan knyttes
        til den. Resten av kjeden — evidensfunn, påstander, faglig godkjenning og publisering — er
        ikke bygget ennå.
      </p>
      <CreateSourceBody authState={authState} />
    </>
  )
}
