import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { KnowledgeAbsence, KnowledgeError, KnowledgeLoading } from './KnowledgeNotice'

const CAVEAT = /ikke dokumentasjon på fravær av effekt, bivirkning eller risiko/i

describe('tilstandene som ikke er en påstand', () => {
  it('ventetilstanden er merket som ventende, ikke som et svar', () => {
    const { container } = render(<KnowledgeLoading />)
    expect(screen.getByText(/Henter publisert kunnskap/i)).toHaveAttribute('aria-busy', 'true')
    // Uten en live-region er «laster» og «tomt» like for en skjermleser.
    expect(container.querySelector('[aria-live]')).not.toBeNull()
    expect(container).not.toHaveTextContent(CAVEAT)
  })

  it('fraværstilstanden bærer alltid forbeholdet', () => {
    // Setningen står ett sted nettopp for at den ikke skal kunne mangle på én
    // side (ANTIDEP_CONSTITUTION.md §17).
    render(<KnowledgeAbsence>Ingenting er publisert om dette.</KnowledgeAbsence>)
    const note = screen.getByRole('note')
    expect(note).toHaveTextContent('Ingenting er publisert om dette.')
    expect(note).toHaveTextContent(CAVEAT)
  })

  it('feiltilstanden sier at det ikke er et svar om kunnskapen', () => {
    render(<KnowledgeError message="tidsavbrudd mot databasen" />)
    const alert = screen.getByRole('alert')
    expect(alert).toHaveTextContent(/teknisk feil, ikke et svar om at kunnskap mangler/i)
    expect(alert).toHaveTextContent('tidsavbrudd mot databasen')
  })

  it('feil og fravær er forskjellige roller, ikke bare forskjellig tekst', () => {
    // En feil skal varsles; et fravær skal leses. De må ikke kunne forveksles
    // av et hjelpemiddel heller.
    const error = render(<KnowledgeError message="x" />)
    expect(error.container.querySelector('[role="note"]')).toBeNull()
    error.unmount()

    const absence = render(<KnowledgeAbsence>x</KnowledgeAbsence>)
    expect(absence.container.querySelector('[role="alert"]')).toBeNull()
  })
})
