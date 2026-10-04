import { useCanvas } from '../../store/canvas'
import { Icon } from '../common/Icon'

export function ZoomControls({ zoom }: { zoom: number }) {
  const z = (a: 'in' | 'out' | 'reset' | 'fit') => useCanvas.getState().zoomProvider?.(a)
  return (
    <div className="zoom-controls canvas-ui ui">
      <button className="icon-btn sm" onClick={() => z('out')} aria-label="Zoom out" data-tip="Zoom out (⌘−)" data-tip-pos="top">
        <Icon name="minus" size={15} />
      </button>
      <button className="zoom-pct mono" onClick={() => z('reset')} data-tip="Reset to 100% (⌘0)" data-tip-pos="top">
        {Math.round(zoom * 100)}%
      </button>
      <button className="icon-btn sm" onClick={() => z('in')} aria-label="Zoom in" data-tip="Zoom in (⌘+)" data-tip-pos="top">
        <Icon name="plus" size={15} />
      </button>
      <span className="vsep" />
      <button className="icon-btn sm" onClick={() => z('fit')} aria-label="Fit" data-tip="Fit content (⌘1)" data-tip-pos="top">
        <Icon name="fit" size={15} />
      </button>
    </div>
  )
}
