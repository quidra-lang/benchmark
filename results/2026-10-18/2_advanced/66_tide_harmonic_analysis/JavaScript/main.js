'use strict';

const records = require('./records');
const cleaning = require('./cleaning');
const harmonic = require('./harmonic_fit');
const predict = require('./predict');
const {real, plotLines, writeFiles} = require('./report');

function sum(items, value = item => item) {
  let total = 0;
  for (const item of items) total += value(item);
  return total;
}

function mean(items, value = item => item) {
  return sum(items, value) / items.length;
}

function choose(items, field, largest = true) {
  let best = null;
  for (const item of items) {
    if (best === null || (largest ? item[field] > best[field] : item[field] < best[field])) best = item;
  }
  return best;
}

function selectConstituents(constituents, length, rayleigh) {
  const selected = [];
  const statuses = new Map();
  for (const constituent of constituents) {
    if (constituent.speed * length < 360 * rayleigh) {
      statuses.set(constituent.name, 'short');
      continue;
    }
    const conflict = selected.find(other => Math.abs(constituent.speed - other.speed) * length < 360 * rayleigh);
    if (conflict) statuses.set(constituent.name, 'conflict:' + conflict.name);
    else {
      statuses.set(constituent.name, 'fitted');
      selected.push(constituent);
    }
  }
  return {selected, statuses};
}

function checkStation(station, rows, constituents, params) {
  const numeric = rows.filter(row => row.value !== null);
  const first = numeric[0].time;
  const last = numeric.at(-1).time;
  const length = last - first;
  const byTime = new Map(rows.map(row => [row.time, row]));
  const reasons = new Map();
  for (let time = first; time <= last; time++) {
    if (!byTime.has(time)) reasons.set(time, 'absent');
    else if (byTime.get(time).value === null) reasons.set(time, 'na');
  }
  const flats = cleaning.flatRuns(numeric, params.flatRun);
  for (const run of flats) {
    for (let time = run.start + 1; time <= run.end; time++) reasons.set(time, 'flat');
  }
  const candidates = numeric.filter(row => !reasons.has(row.time));
  const selection = selectConstituents(constituents, length, params.rayleigh);
  const preliminary = harmonic.fit(candidates, selection.selected);
  let squares = 0;
  for (const row of candidates) {
    row.preliminary = row.value - predict.level(preliminary, row.time);
    squares += row.preliminary * row.preliminary;
  }
  const prefitRms = Math.sqrt(squares / candidates.length);
  const {tested, spikes} = cleaning.spikeTests(candidates, params.spike);
  for (const spike of spikes) reasons.set(spike.time, 'spike');
  const usable = candidates.filter(row => !reasons.has(row.time));
  const counts = {rows: rows.length, numeric: numeric.length, na: 0, absent: 0, flat: 0,
    spikes: 0, usable: usable.length};
  for (const reason of reasons.values()) counts[reason === 'spike' ? 'spikes' : reason]++;
  return {...station, first, last, length, selection, candidates, usable, counts, flats,
    prefitRms, tested, spikes, gaps: cleaning.gaps(first, last, reasons)};
}

function finalFit(station, params) {
  const model = harmonic.fit(station.usable, station.selection.selected);
  const residuals = new Map();
  let squares = 0;
  let maxAbs = 0;
  for (const row of station.usable) {
    row.fitted = predict.level(model, row.time);
    row.residual = row.value - row.fitted;
    residuals.set(row.time, row.residual);
    squares += row.residual * row.residual;
    maxAbs = Math.max(maxAbs, Math.abs(row.residual));
  }
  const dof = station.usable.length - model.unknowns;
  const variance = squares / dof;
  const observedMean = mean(station.usable, row => row.value);
  let centeredSquares = 0;
  let lagProduct = 0;
  let lagSquares = 0;
  for (const row of station.usable) {
    const difference = row.value - observedMean;
    centeredSquares += difference * difference;
    if (residuals.has(row.time + 1)) {
      lagProduct += row.residual * residuals.get(row.time + 1);
      lagSquares += row.residual * row.residual;
    }
  }
  for (let index = 0; index < model.constituents.length; index++) {
    const constituent = model.constituents[index];
    const {a, b, amplitude} = constituent;
    const ia = 2 * index + 1;
    const ib = 2 * index + 2;
    const va = variance * model.inverse[ia][ia];
    const vb = variance * model.inverse[ib][ib];
    const cab = variance * model.inverse[ia][ib];
    constituent.amplitudeError = Math.sqrt(a * a * va + b * b * vb + 2 * a * b * cab) / amplitude;
    constituent.phaseError = Math.sqrt(b * b * va + a * a * vb - 2 * a * b * cab)
      / (amplitude * amplitude) * 180 / harmonic.PI;
    const ratio = amplitude / constituent.amplitudeError;
    constituent.snr = ratio * ratio;
    constituent.significant = constituent.snr >= params.snrMin ? 'yes' : 'no';
  }
  station.model = model;
  station.fittedConstituents = new Map(model.constituents.map(item => [item.name, item]));
  station.residuals = residuals;
  station.statistics = {dof, rms: Math.sqrt(squares / station.usable.length), maxAbs,
    explained: 100 * (1 - squares / centeredSquares), lag1: lagProduct / lagSquares};
  station.top = station.usable.slice().sort((a, b) => Math.abs(b.residual) - Math.abs(a.residual) || a.time - b.time)
    .slice(0, params.topResiduals);
}

function predictions(station, params) {
  station.predictions = Array.from({length: params.hours + 1}, (_, index) => predict.level(station.model, params.start + index));
  const extrema = predict.gridExtrema(station.model, params.start, params.hours, params.grid);
  station.rawExtrema = extrema.length;
  while (extrema.length >= 2) {
    let pair = 0;
    let difference = Math.abs(extrema[0].height - extrema[1].height);
    for (let index = 1; index + 1 < extrema.length; index++) {
      const candidate = Math.abs(extrema[index].height - extrema[index + 1].height);
      if (candidate < difference) {
        pair = index;
        difference = candidate;
      }
    }
    if (difference >= params.minRange) break;
    extrema.splice(pair, 2);
  }
  const byDay = new Map();
  for (const extremum of extrema) {
    extremum.minute = Math.floor(extremum.refinedMinute + 0.5);
    extremum.day = Math.floor(extremum.minute / 1440);
    extremum.label = extremum.kind === 'high' ? 'LHW' : 'HLW';
    if (!byDay.has(extremum.day)) byDay.set(extremum.day, {highs: [], lows: []});
    byDay.get(extremum.day)[extremum.kind === 'high' ? 'highs' : 'lows'].push(extremum);
  }
  for (const group of byDay.values()) {
    const highest = choose(group.highs, 'height');
    const lowest = choose(group.lows, 'height', false);
    if (highest) highest.label = 'HHW';
    if (lowest) lowest.label = 'LLW';
  }
  const daily = [];
  for (let offset = 0; offset < params.hours / 24; offset++) {
    const day = params.start / 24 + offset;
    const group = byDay.get(day) || {highs: [], lows: []};
    const highest = choose(group.highs, 'height');
    const lowest = choose(group.lows, 'height', false);
    const hhw = highest === null ? null : highest.height;
    const llw = lowest === null ? null : lowest.height;
    daily.push({day, highCount: group.highs.length, lowCount: group.lows.length, hhw, llw,
      range: hhw === null || llw === null ? null : hhw - llw});
  }
  station.extrema = extrema;
  station.highs = extrema.filter(item => item.kind === 'high');
  station.lows = extrema.filter(item => item.kind === 'low');
  station.daily = daily;
}

function validation(station, constituents, params) {
  const split = station.first + Math.floor(station.length / 2);
  const training = station.usable.filter(row => row.time <= split);
  const test = station.usable.filter(row => row.time > split);
  const selection = selectConstituents(constituents, training.at(-1).time - training[0].time, params.rayleigh);
  const model = harmonic.fit(training, selection.selected);
  const observedMean = mean(test, row => row.value);
  let squares = 0;
  let inSampleSquares = 0;
  let centeredSquares = 0;
  for (const row of test) {
    const error = row.value - predict.level(model, row.time);
    const centered = row.value - observedMean;
    squares += error * error;
    inSampleSquares += row.residual * row.residual;
    centeredSquares += centered * centered;
  }
  return {split, train: training.length, test: test.length, constituents: selection.selected.length,
    rms: Math.sqrt(squares / test.length), inSampleRms: Math.sqrt(inSampleSquares / test.length),
    skill: 1 - squares / centeredSquares};
}

function residualEvents(station, settings) {
  const events = [];
  let current = null;
  const finish = () => {
    if (current !== null && current.end - current.start + 1 >= settings.hours) events.push(current);
    current = null;
  };
  for (const row of station.usable) {
    const type = row.residual > settings.threshold ? 'positive' : row.residual < -settings.threshold ? 'negative' : null;
    if (current !== null && (type !== current.type || row.time !== current.end + 1)) finish();
    if (type === null) continue;
    if (current === null) {
      current = {type, start: row.time, end: row.time, peak: row.residual, peakTime: row.time};
    } else {
      current.end = row.time;
      if (type === 'positive' ? row.residual > current.peak : row.residual < current.peak) {
        current.peak = row.residual;
        current.peakTime = row.time;
      }
    }
  }
  finish();
  return events;
}

function dailyMeans(station) {
  const weights = [0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1];
  const usable = new Map(station.usable.map(row => [row.time, row.value]));
  const filledLevels = [];
  for (let time = station.first; time <= station.last; time++) {
    filledLevels.push(usable.has(time) ? usable.get(time) : predict.level(station.model, time));
  }
  const days = [];
  for (let day = Math.floor(station.first / 24); day <= Math.floor(station.last / 24); day++) {
    const noon = day * 24 + 12;
    if (noon - 19 < station.first || noon + 19 > station.last) continue;
    let total = 0;
    let filled = 0;
    for (let offset = -19; offset <= 19; offset++) {
      const time = noon + offset;
      total += weights[Math.abs(offset)] * filledLevels[time - station.first];
      if (!usable.has(time)) filled++;
    }
    days.push({day, level: total / 30, filled});
  }
  const average = mean(days, entry => entry.level);
  const firstDay = days[0].day;
  const meanDay = mean(days, entry => entry.day - firstDay);
  let numerator = 0;
  let denominator = 0;
  for (const entry of days) {
    const x = entry.day - firstDay - meanDay;
    numerator += x * (entry.level - average);
    denominator += x * x;
  }
  return {days, average, slope: 1000 * (numerator / denominator),
    maximum: choose(days, 'level'), minimum: choose(days, 'level', false)};
}

function tidalCharacteristics(station, params) {
  const m2 = station.fittedConstituents.get('M2');
  const s2 = station.fittedConstituents.get('S2');
  const k1 = station.fittedConstituents.get('K1');
  const o1 = station.fittedConstituents.get('O1');
  const m4 = station.fittedConstituents.get('M4');
  const form = (k1.amplitude + o1.amplitude) / (m2.amplitude + s2.amplitude);
  const type = form < 0.25 ? 'semidiurnal' : form < 1.5 ? 'mixed_semidiurnal' : form < 3 ? 'mixed_diurnal' : 'diurnal';
  const mhhw = mean(station.daily.filter(day => day.hhw !== null), day => day.hhw);
  const mllw = mean(station.daily.filter(day => day.llw !== null), day => day.llw);
  const mhw = mean(station.highs, item => item.height);
  const mlw = mean(station.lows, item => item.height);
  const amplitudeSum = sum(station.model.constituents, item => item.amplitude);
  const completeDays = station.daily.filter(day => day.range !== null);
  const rises = [];
  const falls = [];
  for (let index = 1; index < station.extrema.length; index++) {
    const previous = station.extrema[index - 1];
    const current = station.extrema[index];
    if (previous.kind === 'low' && current.kind === 'high') rises.push(current.minute - previous.minute);
    if (previous.kind === 'high' && current.kind === 'low') falls.push(current.minute - previous.minute);
  }
  let relativePhase = 2 * m2.phase - m4.phase;
  while (relativePhase < 0) relativePhase += 360;
  while (relativePhase >= 360) relativePhase -= 360;
  let above = 0;
  let below = 0;
  for (const value of station.predictions) {
    if (value > mhhw) above++;
    if (value < mllw) below++;
  }
  return {form, type, spring: 2 * (m2.amplitude + s2.amplitude), neap: 2 * (m2.amplitude - s2.amplitude),
    mhhw, mllw, mhw, mlw, mtl: (mhw + mlw) / 2, dtl: (mhhw + mllw) / 2,
    mn: mhw - mlw, gt: mhhw - mllw, hat: station.model.mean + amplitudeSum, lat: station.model.mean - amplitudeSum,
    highest: choose(station.highs, 'height'), lowest: choose(station.lows, 'height', false),
    widest: choose(completeDays, 'range'), narrowest: choose(completeDays, 'range', false),
    above: 100 * above / (params.hours + 1), below: 100 * below / (params.hours + 1),
    rise: mean(rises), fall: mean(falls), m4Ratio: m4.amplitude / m2.amplitude,
    relativePhase, dominance: relativePhase < 180 ? 'flood' : 'ebb'};
}

function springNeap(station, params) {
  const m2 = station.fittedConstituents.get('M2');
  const s2 = station.fittedConstituents.get('S2');
  const differenceSpeed = s2.speed - m2.speed;
  const differencePhase = s2.phase - m2.phase;
  const startQ = (differenceSpeed * params.start - differencePhase) / 180;
  const endQ = (differenceSpeed * (params.start + params.hours) - differencePhase) / 180;
  const events = [];
  // Padded candidate bounds keep the prescribed t_q range test authoritative.
  const first = Math.floor(Math.min(startQ, endQ)) - 1;
  const last = Math.ceil(Math.max(startQ, endQ)) + 1;
  for (let q = first; q <= last; q++) {
    const time = (differencePhase + 180 * q) / differenceSpeed;
    if (time >= params.start && time <= params.start + params.hours) {
      events.push({type: q % 2 === 0 ? 'spring' : 'neap', minute: Math.floor(time * 60 + 0.5)});
    }
  }
  return events;
}

function cleaningLines(station, params) {
  const dt = time => records.hourDatetime(params.epoch, time);
  const count = station.counts;
  const lines = [`station=${station.code} name=${station.name}`,
    `span start=${dt(station.first)} end=${dt(station.last)} hours=${station.length + 1} record_length=${station.length}`,
    `counts rows=${count.rows} numeric=${count.numeric} na=${count.na} absent=${count.absent} flat=${count.flat} spikes=${count.spikes} usable=${count.usable}`];
  for (const run of station.flats) {
    lines.push(`flat start=${dt(run.start)} end=${dt(run.end)} value=${real(run.value, 3)} removed=${run.end - run.start}`);
  }
  lines.push(`spike_test window=${params.spike.window} candidates=${station.candidates.length} tested=${station.tested} prefit_rms=${real(station.prefitRms, 4)}`);
  for (const spike of station.spikes) {
    lines.push(`spike time=${dt(spike.time)} value=${real(spike.value, 3)} residual=${real(spike.residual, 4)}`
      + ` median=${real(spike.median, 4)} mad=${real(spike.mad, 4)} limit=${real(spike.limit, 4)}`);
  }
  for (const gap of station.gaps) {
    lines.push(`gap start=${dt(gap.start)} end=${dt(gap.end)} hours=${gap.end - gap.start + 1} cause=${gap.cause}`);
  }
  return lines;
}

function constituentLines(station, constituents) {
  return constituents.map(constituent => {
    const status = station.selection.statuses.get(constituent.name);
    const prefix = `${station.code},${constituent.name},${real(constituent.speed, 7)},${status}`;
    if (status !== 'fitted') return prefix + ',,,,,,';
    const fitted = station.fittedConstituents.get(constituent.name);
    return prefix + `,${real(fitted.amplitude, 4)},${real(fitted.phase, 2)},${real(fitted.amplitudeError, 4)}`
      + `,${real(fitted.phaseError, 2)},${real(fitted.snr, 1)},${fitted.significant}`;
  });
}

function extremeLines(station, params) {
  const lines = [`station=${station.code} extremes=${station.extrema.length} raw=${station.rawExtrema} removed=${station.rawExtrema - station.extrema.length}`];
  for (let index = 0; index < station.extrema.length; index++) {
    const item = station.extrema[index];
    const change = index === 0 ? 'none' : real(item.height - station.extrema[index - 1].height, 3);
    lines.push(`${records.datetime(params.epoch, item.minute)} ${item.label} ${real(item.height, 3)} change=${change}`);
  }
  for (const day of station.daily) {
    lines.push(`day date=${records.date(params.epoch, day.day)} high_waters=${day.highCount} low_waters=${day.lowCount}`
      + ` hhw=${real(day.hhw, 3)} llw=${real(day.llw, 3)} range=${real(day.range, 3)}`);
  }
  return lines;
}

function summaryLines(station, params) {
  const dt = time => records.hourDatetime(params.epoch, time);
  const minute = time => records.datetime(params.epoch, time);
  const date = day => records.date(params.epoch, day);
  const stats = station.statistics;
  const validation = station.validation;
  const tide = station.characteristics;
  const daily = station.dailyMeans;
  const lines = [`[station ${station.code}] ${station.name}`,
    `record first=${dt(station.first)} last=${dt(station.last)} length=${station.length} usable=${station.usable.length}`,
    `fit constituents=${station.model.constituents.length} unknowns=${station.model.unknowns} dof=${stats.dof} mean_level=${real(station.model.mean, 4)}`,
    `residual rms=${real(stats.rms, 4)} max_abs=${real(stats.maxAbs, 4)} explained_percent=${real(stats.explained, 4)} lag1_autocorrelation=${real(stats.lag1, 4)}`];
  station.top.forEach((row, index) => {
    lines.push(`top_residual rank=${index + 1} time=${dt(row.time)} observed=${real(row.value, 3)}`
      + ` fitted=${real(row.fitted, 4)} residual=${real(row.residual, 4)}`);
  });
  lines.push(`validation split=${dt(validation.split)} train=${validation.train} test=${validation.test} constituents=${validation.constituents}`
    + ` rms=${real(validation.rms, 4)} in_sample_rms=${real(validation.inSampleRms, 4)} skill=${real(validation.skill, 4)}`);
  lines.push(`form_number=${real(tide.form, 4)} type=${tide.type}`);
  lines.push(`ranges spring=${real(tide.spring, 3)} neap=${real(tide.neap, 3)} mn=${real(tide.mn, 3)} gt=${real(tide.gt, 3)}`);
  lines.push(`asymmetry rise_minutes=${real(tide.rise, 1)} fall_minutes=${real(tide.fall, 1)} m4_m2_ratio=${real(tide.m4Ratio, 4)}`
    + ` relative_phase=${real(tide.relativePhase, 2)} dominance=${tide.dominance}`);
  lines.push(`datums mhhw=${real(tide.mhhw, 3)} mhw=${real(tide.mhw, 3)} mtl=${real(tide.mtl, 3)} dtl=${real(tide.dtl, 3)}`
    + ` mlw=${real(tide.mlw, 3)} mllw=${real(tide.mllw, 3)}`);
  lines.push(`bounds hat=${real(tide.hat, 3)} lat=${real(tide.lat, 3)}`);
  lines.push(`window high_waters=${station.highs.length} low_waters=${station.lows.length} highest=${real(tide.highest.height, 3)}`
    + ` highest_time=${minute(tide.highest.minute)} lowest=${real(tide.lowest.height, 3)} lowest_time=${minute(tide.lowest.minute)}`);
  lines.push(`daily_range widest=${real(tide.widest.range, 3)} widest_date=${date(tide.widest.day)}`
    + ` narrowest=${real(tide.narrowest.range, 3)} narrowest_date=${date(tide.narrowest.day)}`);
  lines.push(`exceedance above_mhhw=${real(tide.above, 2)} below_mllw=${real(tide.below, 2)}`);
  for (const event of station.springNeap) lines.push(`${event.type} time=${minute(event.minute)}`);
  lines.push(`surges count=${station.events.length} threshold=${real(params.surge.threshold, 3)} min_hours=${params.surge.hours}`);
  for (const event of station.events) {
    lines.push(`surge type=${event.type} start=${dt(event.start)} end=${dt(event.end)} hours=${event.end - event.start + 1}`
      + ` peak=${real(event.peak, 4)} peak_time=${dt(event.peakTime)}`);
  }
  lines.push(`daily_mean days=${daily.days.length} average=${real(daily.average, 4)} slope_mm_per_day=${real(daily.slope, 3)}`
    + ` max=${real(daily.maximum.level, 4)} max_date=${date(daily.maximum.day)} min=${real(daily.minimum.level, 4)} min_date=${date(daily.minimum.day)}`);
  for (const day of daily.days) {
    lines.push(`daily_mean date=${date(day.day)} level=${real(day.level, 4)} filled=${day.filled}`);
  }
  return lines;
}

function waterLag(waters, reference) {
  let total = 0;
  for (const water of waters) {
    let nearest = reference[0];
    for (let index = 1; index < reference.length; index++) {
      if (Math.abs(reference[index].minute - water.minute) < Math.abs(nearest.minute - water.minute)) nearest = reference[index];
    }
    total += water.minute - nearest.minute;
  }
  return total / waters.length;
}

function comparisonLines(stations, params) {
  const reference = stations.find(station => station.code === params.reference);
  const lines = [`[comparison] reference=${params.reference}`];
  for (const station of stations) {
    if (station === reference) continue;
    const tide = station.characteristics;
    lines.push(`${station.code} tide hw_lag_min=${real(waterLag(station.highs, reference.highs), 1)}`
      + ` lw_lag_min=${real(waterLag(station.lows, reference.lows), 1)} range_ratio=${real(tide.gt / reference.characteristics.gt, 4)}`
      + ` mtl_diff=${real(tide.mtl - reference.characteristics.mtl, 3)}`);
    for (const name of ['M2', 'S2', 'K1', 'O1']) {
      const own = station.fittedConstituents.get(name);
      const other = reference.fittedConstituents.get(name);
      let phase = own.phase - other.phase;
      if (phase > 180) phase -= 360;
      if (phase <= -180) phase += 360;
      lines.push(`${station.code} ${name} amplitude_ratio=${real(own.amplitude / other.amplitude, 4)}`
        + ` phase_diff=${real(phase, 2)} time_lag_min=${real(phase / own.speed * 60, 1)}`);
    }
  }
  return lines;
}

function correlation(first, second, lag) {
  const pairs = [];
  for (const row of first.usable) {
    if (second.residuals.has(row.time + lag)) pairs.push([row.residual, second.residuals.get(row.time + lag)]);
  }
  const mx = mean(pairs, pair => pair[0]);
  const my = mean(pairs, pair => pair[1]);
  let sxy = 0;
  let sxx = 0;
  let syy = 0;
  for (const pair of pairs) {
    const x = pair[0] - mx;
    const y = pair[1] - my;
    sxy += x * y;
    sxx += x * x;
    syy += y * y;
  }
  return {lag, rho: sxy / Math.sqrt(sxx * syy), pairs: pairs.length};
}

function correlationLines(stations, maximumLag) {
  const lines = [`[correlation] max_lag=${maximumLag}`];
  for (let i = 0; i < stations.length; i++) {
    for (let j = i + 1; j < stations.length; j++) {
      let best = null;
      let zero;
      for (let lag = -maximumLag; lag <= maximumLag; lag++) {
        const candidate = correlation(stations[i], stations[j], lag);
        if (lag === 0) zero = candidate.rho;
        if (best === null || candidate.rho > best.rho || (candidate.rho === best.rho &&
          (Math.abs(lag) < Math.abs(best.lag) || (Math.abs(lag) === Math.abs(best.lag) && lag < best.lag)))) best = candidate;
      }
      lines.push(`${stations[i].code}-${stations[j].code} lag0=${real(zero, 4)} best_lag=${best.lag} best=${real(best.rho, 4)} pairs=${best.pairs}`);
    }
  }
  return lines;
}

function plot(stations, params) {
  const station = stations.find(item => item.code === params.plot.code);
  const {hours, top, bottom, step} = params.plot;
  const rowCount = (top - bottom) / step + 1;
  const cells = Array.from({length: rowCount}, () => Array(hours).fill(' '));
  const heights = Array.from({length: rowCount}, (_, row) => top - row * step);
  const baseline = Math.floor((top - 100 * station.model.mean) / step + 0.5);
  if (baseline >= 0 && baseline < rowCount) cells[baseline].fill('-');
  const marks = new Map();
  for (const extremum of station.extrema) {
    const column = Math.floor((extremum.minute - 60 * params.start + 30) / 60);
    if (column >= 0 && column < hours) marks.set(column, extremum.kind === 'high' ? 'H' : 'L');
  }
  for (let column = 0; column < hours; column++) {
    const row = Math.floor((top - 100 * station.predictions[column]) / step + 0.5);
    if (row < 0) cells[0][column] = '^';
    else if (row >= rowCount) cells[rowCount - 1][column] = 'v';
    else cells[row][column] = marks.get(column) || '*';
  }
  return [`[plot] station=${station.code} start=${records.hourDatetime(params.epoch, params.start)} hours=${hours} step_cm=${step}`,
    ...plotLines(cells, heights)];
}

function main() {
  const {params, constituents, observations} = records.readAll();
  const stations = [];
  const files = {'cleaning.txt': [],
    'constituents.csv': ['station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant'],
    'predictions.csv': ['time,' + params.stations.map(station => station.code).join(',')],
    'extremes.txt': [], 'summary.txt': []};
  const append = (name, lines) => {
    for (const line of lines) files[name].push(line);
  };
  for (const source of params.stations) {
    const station = checkStation(source, observations.get(source.code), constituents, params);
    finalFit(station, params);
    predictions(station, params);
    station.validation = validation(station, constituents, params);
    station.events = residualEvents(station, params.surge);
    station.dailyMeans = dailyMeans(station);
    station.characteristics = tidalCharacteristics(station, params);
    station.springNeap = springNeap(station, params);
    stations.push(station);
    append('cleaning.txt', cleaningLines(station, params));
    append('constituents.csv', constituentLines(station, constituents));
    append('extremes.txt', extremeLines(station, params));
    append('summary.txt', summaryLines(station, params));
  }
  for (let index = 0; index <= params.hours; index++) {
    files['predictions.csv'].push(records.hourDatetime(params.epoch, params.start + index)
      + ',' + stations.map(station => real(station.predictions[index], 3)).join(','));
  }
  append('summary.txt', comparisonLines(stations, params));
  append('summary.txt', correlationLines(stations, params.correlationLag));
  append('summary.txt', plot(stations, params));
  writeFiles(files);
}

main();
