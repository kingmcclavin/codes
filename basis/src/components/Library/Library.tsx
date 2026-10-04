import { useMemo, useState } from 'react'
import { exportNotebook, importNotebookFile } from '../../services/export'
import { pickFiles } from '../../services/files'
import { pluralize, relativeTime } from '../../services/time'
import { notebookPages, sortedSections, useLibrary } from '../../store/library'
import { useUI } from '../../store/ui'
import { Wordmark } from '../Brand/Logo'
import { Icon } from '../common/Icon'
import { PagePreview } from '../Notebook/PagePreview'
import { NotebookCard, NotebookCover } from './NotebookCard'
import './library.css'

type Sort = 'recent' | 'name' | 'created'

export function Library() {
  const notebooks = useLibrary((s) => s.notebooks)
  const sections = useLibrary((s) => s.sections)
  const pages = useLibrary((s) => s.pages)
  const theme = useUI((s) => s.resolvedTheme)
  const [sort, setSort] = useState<Sort>('recent')
  const ui = useUI.getState()

  const list = useMemo(() => {
    const arr = Object.values(notebooks)
    if (sort === 'name') return arr.sort((a, b) => a.name.localeCompare(b.name))
    if (sort === 'created') return arr.sort((a, b) => b.createdAt - a.createdAt)
    return arr.sort((a, b) => Math.max(b.updatedAt, b.lastOpenedAt) - Math.max(a.updatedAt, a.lastOpenedAt))
  }, [notebooks, sort])

  const favorites = list.filter((n) => n.favorite)
  const recentPages = useMemo(
    () =>
      Object.values(pages)
        .filter((p) => p.lastOpenedAt > 0 && notebooks[p.notebookId])
        .sort((a, b) => b.lastOpenedAt - a.lastOpenedAt)
        .slice(0, 8),
    [pages, notebooks],
  )
  const totalPages = Object.keys(pages).length

  const open = (notebookId: string, pageId?: string) => ui.navigate({ view: 'notebook', notebookId, pageId })

  const cardProps = (id: string, i: number) => {
    const nb = notebooks[id]
    return {
      nb,
      index: i,
      pageCount: notebookPages(pages, id).length,
      sectionCount: sortedSections(sections, id).length,
      onOpen: () => open(id),
      onToggleFavorite: () => useLibrary.getState().toggleFavorite(id),
      onEdit: () => ui.setNotebookDialog({ mode: 'edit', id }),
      onDuplicate: () => {
        useLibrary.getState().duplicateNotebook(id)
        ui.toast('Notebook duplicated')
      },
      onExport: () => {
        void exportNotebook(nb, sortedSections(sections, id), notebookPages(pages, id))
        ui.toast('Exporting notebook…')
      },
      onDelete: () => {
        if (confirm(`Delete “${nb.name}” and all of its pages? This cannot be undone.`)) {
          useLibrary.getState().deleteNotebook(id)
          ui.toast('Notebook deleted')
        }
      },
    }
  }

  const importNotebook = async () => {
    const [file] = await pickFiles('.basis,application/json')
    if (!file) return
    try {
      const snap = await importNotebookFile(file)
      useLibrary.getState().importSnapshot(snap)
      ui.toast(`Imported “${snap.notebooks[0].name}”`)
    } catch (e) {
      alert((e as Error).message)
    }
  }

  return (
    <div className="library ui">
      <header className="lib-header">
        <Wordmark size={24} />
        <button className="lib-search" onClick={() => ui.setSearchOpen(true)}>
          <Icon name="search" size={16} />
          <span>Search notebooks, pages, equations…</span>
          <span className="kbd">⌘K</span>
        </button>
        <div className="lib-header-actions">
          <button className="icon-btn" onClick={importNotebook} data-tip="Import notebook">
            <Icon name="upload" />
          </button>
          <button className="icon-btn" onClick={() => ui.setSettings({ theme: theme === 'dark' ? 'light' : 'dark' })} data-tip="Toggle theme">
            <Icon name={theme === 'dark' ? 'sun' : 'moon'} />
          </button>
          <button className="icon-btn" onClick={() => ui.setSettingsOpen(true)} data-tip="Settings">
            <Icon name="settings" />
          </button>
        </div>
      </header>

      <main className="lib-main">
        <div className="lib-hero">
          <div>
            <div className="label">Library</div>
            <h1>My Notebooks</h1>
            <div className="lib-stats mono">
              {pluralize(list.length, 'notebook')} · {pluralize(totalPages, 'page')}
            </div>
          </div>
          <button className="btn primary lg" onClick={() => ui.setNotebookDialog({ mode: 'create' })}>
            <Icon name="plus" size={16} stroke={2} />
            New Notebook
          </button>
        </div>

        {recentPages.length > 0 && (
          <section className="lib-section">
            <div className="lib-section-head">
              <span className="label">Recently opened</span>
            </div>
            <div className="recent-pages">
              {recentPages.map((p, i) => {
                const nb = notebooks[p.notebookId]
                return (
                  <button key={p.id} className="recent-page" style={{ animationDelay: `${i * 30}ms` }} onClick={() => open(p.notebookId, p.id)}>
                    <div className="recent-page-thumb">
                      <PagePreview page={p} />
                    </div>
                    <div className="recent-page-info">
                      <div className="recent-page-title">{p.title}</div>
                      <div className="recent-page-meta mono">
                        <span className="nb-dot" style={{ background: nb.color }} />
                        <span className="ellipsis">{nb.name}</span>
                        <span className="spacer" />
                        <span>{relativeTime(p.lastOpenedAt)}</span>
                      </div>
                    </div>
                  </button>
                )
              })}
            </div>
          </section>
        )}

        {favorites.length > 0 && (
          <section className="lib-section">
            <div className="lib-section-head">
              <span className="label">Favorites</span>
            </div>
            <div className="fav-row">
              {favorites.map((nb) => (
                <button key={nb.id} className="fav-chip" onClick={() => open(nb.id)}>
                  <NotebookCover nb={nb} size="sm" />
                  <div>
                    <div className="fav-name">{nb.name}</div>
                    <div className="fav-meta mono">{pluralize(notebookPages(pages, nb.id).length, 'page')}</div>
                  </div>
                </button>
              ))}
            </div>
          </section>
        )}

        <section className="lib-section">
          <div className="lib-section-head">
            <span className="label">All notebooks</span>
            <div className="segmented">
              {(['recent', 'name', 'created'] as Sort[]).map((s) => (
                <button key={s} className={sort === s ? 'on' : ''} onClick={() => setSort(s)}>
                  {s === 'recent' ? 'Recent' : s === 'name' ? 'A–Z' : 'Created'}
                </button>
              ))}
            </div>
          </div>
          <div className="nb-grid">
            {list.map((nb, i) => (
              <NotebookCard key={nb.id} {...cardProps(nb.id, i)} />
            ))}
            <button className="nb-card new" onClick={() => ui.setNotebookDialog({ mode: 'create' })}>
              <div className="nb-new-inner">
                <Icon name="plus" size={22} />
                <span>New Notebook</span>
              </div>
            </button>
          </div>
        </section>
      </main>
    </div>
  )
}
