import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { App } from './App'

describe('App-skallet', () => {
  it('viser produktnavnet i en toppbanner', () => {
    render(<App />)
    expect(screen.getByRole('banner')).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 1, name: 'Antidep' })).toBeInTheDocument()
  })

  it('har et hovedområde som sier tydelig at klinisk funksjonalitet ikke finnes ennå', () => {
    render(<App />)
    const main = screen.getByRole('main')
    expect(main).toHaveTextContent(/ingen klinisk funksjonalitet er implementert ennå/i)
  })
})
