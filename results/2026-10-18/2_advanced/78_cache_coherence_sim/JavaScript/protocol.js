'use strict';

const DIRTY = new Set(['M', 'O']);
const TYPES = ['BusRd', 'BusRdX', 'BusUpgr', 'BusWr', 'WB'];

function request(protocol, state, operation) {
  if (protocol === 'VI') {
    if (operation === 'W') return { type: 'BusWr', state: state === 'I' ? 'I' : 'V' };
    return { type: state === 'I' ? 'BusRd' : null, state: 'V' };
  }
  if (operation === 'R') return state === 'I'
    ? { type: 'BusRd', state: protocol === 'MSI' ? 'S' : 'ES' } : { type: null, state };
  if (state === 'I') return { type: 'BusRdX', state: 'M' };
  return { type: state === 'S' || state === 'O' ? 'BusUpgr' : null, state: 'M' };
}

function snoop(protocol, state, type) {
  if (type === 'BusRd') {
    if (state === 'M') return { state: protocol === 'MOESI' ? 'O' : 'S', supply: true, flush: protocol !== 'MOESI' };
    if (state === 'O') return { state: 'O', supply: true, flush: false };
    return { state: state === 'E' ? 'S' : state, supply: false, flush: false };
  }
  return { state: 'I', supply: type === 'BusRdX' && DIRTY.has(state), flush: false };
}

module.exports = { DIRTY, TYPES, request, snoop };
