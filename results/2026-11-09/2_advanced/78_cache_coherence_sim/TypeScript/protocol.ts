export const DIRTY = new Set(['M', 'O']);
export const TYPES = ['BusRd', 'BusRdX', 'BusUpgr', 'BusWr', 'WB'];

export function request(protocol: string, state: string, operation: string): {type: string | null; state: string} {
  if (protocol === 'VI') {
    if (operation === 'W') return { type: 'BusWr', state: state === 'I' ? 'I' : 'V' };
    return { type: state === 'I' ? 'BusRd' : null, state: 'V' };
  }
  if (operation === 'R') return state === 'I'
    ? { type: 'BusRd', state: protocol === 'MSI' ? 'S' : 'ES' } : { type: null, state };
  if (state === 'I') return { type: 'BusRdX', state: 'M' };
  return { type: state === 'S' || state === 'O' ? 'BusUpgr' : null, state: 'M' };
}

export function snoop(protocol: string, state: string, type: string): {state: string; supply: boolean; flush: boolean} {
  if (type === 'BusRd') {
    if (state === 'M') return { state: protocol === 'MOESI' ? 'O' : 'S', supply: true, flush: protocol !== 'MOESI' };
    if (state === 'O') return { state: 'O', supply: true, flush: false };
    return { state: state === 'E' ? 'S' : state, supply: false, flush: false };
  }
  return { state: 'I', supply: type === 'BusRdX' && DIRTY.has(state), flush: false };
}

