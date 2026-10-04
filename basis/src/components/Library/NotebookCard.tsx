import { useRef, useState } from 'react'
import type { Notebook } from '../../models'
import { pluralize, relativeTime } from '../../services/time'
import { Icon } from '../common/Icon'
import { Menu, anchorOf } from '../common/Popover'

export function NotebookCover({ nb, size = 'md' }: { nb: Pick<Notebook, 'icon' | 'color'>; size?: 'sm' | 'md' }) {
  return (
    <div className={`nb-cover ${size}`} style={{ ['--nb' as string]: nb.color }}>
      <div className="nb-cover-grid" />
      <div className="nb-cover-spine" />
      <Icon name={nb.icon} size={size === 'sm' ? 18 : 30} stroke={1.25} className="nb-cover-icon" />
    </div>
  )
}

export function NotebookCard({
  nb,
  pageCount,
  sectionCount,
  onOpen,
  onToggleFavorite,
  onEdit,
  onDuplicate,
  onExport,
  onDelete,
  index = 0,
}: {
  nb: Notebook
  pageCount: number
  sectionCount: number
  onOpen: () => void
  onToggleFavorite: () => void
  onEdit: () => void
  onDuplicate: () => void
  onExport: () => void
  onDelete: () => void
  index?: number
}) {
  const moreRef = useRef<HTMLButtonElement>(null)
  const [menu, setMenu] = useState(false)
  return (
    <div className="nb-card" style={{ animationDelay: `${index * 35}ms` }} onClick={onOpen} role="button" tabIndex={0} onKeyDown={(e) => e.key === 'Enter' && onOpen()}>
      <NotebookCover nb={nb} />
      <div className="nb-card-body">
        <div className="nb-card-title">
          <span>{nb.name}</span>
          <div className="nb-card-actions" onClick={(e) => e.stopPropagation()}>
            <button className={`icon-btn sm fav ${nb.favorite ? 'on' : ''}`} onClick={onToggleFavorite} aria-label="Favorite" data-tip={nb.favorite ? 'Unfavorite' : 'Favorite'}>
              <Icon name="star" size={15} />
            </button>
            <button ref={moreRef} className="icon-btn sm" onClick={() => setMenu(true)} aria-label="More">
              <Icon name="more" size={16} stroke={2.4} />
            </button>
          </div>
        </div>
        {nb.description && <div className="nb-card-desc">{nb.description}</div>}
        <div className="nb-card-meta mono">
          <span>{pluralize(pageCount, 'page')}</span>
          <span className="dot">·</span>
          <span>{pluralize(sectionCount, 'section')}</span>
          <span className="spacer" />
          <span>Edited {relativeTime(nb.updatedAt)}</span>
        </div>
      </div>
      {menu && (
        <Menu
          anchor={anchorOf(moreRef.current)}
          align="end"
          onClose={() => setMenu(false)}
          items={[
            { label: 'Open', icon: 'open', onSelect: onOpen },
            { label: 'Edit details', icon: 'edit', onSelect: onEdit },
            { label: nb.favorite ? 'Remove from favorites' : 'Add to favorites', icon: 'star', onSelect: onToggleFavorite },
            { label: 'Duplicate', icon: 'copy', onSelect: onDuplicate },
            { label: 'Export notebook', icon: 'download', onSelect: onExport },
            { separator: true },
            { label: 'Delete notebook', icon: 'trash', danger: true, onSelect: onDelete },
          ]}
        />
      )}
    </div>
  )
}
