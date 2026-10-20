'use strict';

function associate(picks, window, minimumStations) {
  const candidates = [];
  for (let i = 0; i < picks.length; i++) {
    const first = picks[i];
    if (first.candidate !== null) continue;
    const stations = new Set();
    const selected = [];
    for (let j = i; j < picks.length && picks[j].sample <= first.sample + window; j++) {
      const pick = picks[j];
      if (pick.candidate !== null || stations.has(pick.station.index)) continue;
      stations.add(pick.station.index);
      selected.push(pick);
    }
    if (selected.length < minimumStations) continue;
    const number = candidates.length + 1;
    for (const pick of selected) pick.candidate = number;
    candidates.push({ number, first, picks: selected });
  }
  return candidates;
}

module.exports = { associate };
