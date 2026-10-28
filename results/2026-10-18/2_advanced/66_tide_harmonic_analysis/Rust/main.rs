mod records;
mod cleaning;
mod harmonic_fit;
mod predict;
mod report;

use std::collections::BTreeMap;
use records::{Params, Station, Constituent};
use harmonic_fit::{Fit, PI};
use predict::Extremum;
use report::real;

fn selection(constituents: &[Constituent], length: i64, rayleigh: f64) -> (Vec<String>, Vec<usize>) {
    let mut status = Vec::new();
    let mut selected: Vec<usize> = Vec::new();
    for (i, c) in constituents.iter().enumerate() {
        if c.speed*length as f64 < 360.0*rayleigh { status.push("short".to_owned()); }
        else if let Some(&j) = selected.iter().find(|&&j| (c.speed-constituents[j].speed).abs()*length as f64 < 360.0*rayleigh) {
            status.push(format!("conflict:{}", constituents[j].name));
        } else { status.push("fitted".to_owned()); selected.push(i); }
    }
    (status, selected)
}

fn fit(times: &[i64], levels: &BTreeMap<i64, f64>, indices: &[usize], constituents: &[Constituent]) -> Fit {
    let speeds: Vec<_> = indices.iter().map(|&i| constituents[i].speed).collect();
    harmonic_fit::fit(times, levels, &speeds)
}
fn mean(values: &[f64]) -> f64 { values.iter().sum::<f64>()/values.len() as f64 }
fn optional(value: Option<f64>) -> String { value.map_or_else(|| "none".to_owned(), |v| real(v, 3)) }
fn best(values: &[f64], maximum: bool) -> usize {
    let mut selected = 0;
    for i in 1..values.len() { if if maximum { values[i] > values[selected] } else { values[i] < values[selected] } { selected = i; } }
    selected
}

struct ResultStation {
    fit: Fit,
    selected: Vec<usize>,
    amplitudes: Vec<f64>,
    phases: Vec<f64>,
    residuals: BTreeMap<i64, f64>,
    predictions: Vec<f64>,
    extremes: Vec<Extremum>,
    datums: [f64; 6],
}

fn analyze(station: &Station, params: &Params, constituents: &[Constituent], cleaning_lines: &mut Vec<String>,
           constants: &mut Vec<String>, extremes_lines: &mut Vec<String>, summary: &mut Vec<String>) -> ResultStation {
    let first = station.observations.iter().find(|(_, v)| v.is_some()).unwrap().0.to_owned();
    let last = station.observations.iter().rev().find(|(_, v)| v.is_some()).unwrap().0.to_owned();
    let length = last-first;
    let values: Vec<_> = (first..=last).map(|t| station.observations.get(&t).copied().flatten()).collect();
    let levels: BTreeMap<_, _> = station.observations.iter().filter_map(|(&t, v)| v.map(|v| (t, v as f64/1000.0))).collect();
    let mut reasons: Vec<_> = (first..=last).map(|t| match station.observations.get(&t) {
        None => "absent".to_owned(), Some(None) => "na".to_owned(), _ => String::new(),
    }).collect();
    let runs = cleaning::flat_runs(&values, params.flat);
    for &(u, v, _) in &runs { for t in u+1..=v { reasons[t] = "flat".to_owned(); } }
    let candidates: Vec<_> = (first..=last).filter(|&t| reasons[(t-first) as usize].is_empty()).collect();
    let (status, selected) = selection(constituents, length, params.rayleigh);
    let preliminary = fit(&candidates, &levels, &selected, constituents);
    let residuals: BTreeMap<_, _> = candidates.iter().map(|&t| (t, levels[&t]-predict::level(&preliminary, t as f64))).collect();
    let prefit_rms = (residuals.values().map(|e| e*e).sum::<f64>()/candidates.len() as f64).sqrt();
    let (tested, spikes) = cleaning::spikes(&residuals, params.window, params.count, params.factor, params.lower);
    for spike in &spikes { reasons[(spike.time-first) as usize] = "spike".to_owned(); }
    let usable: Vec<_> = candidates.iter().copied().filter(|&t| reasons[(t-first) as usize].is_empty()).collect();
    let fitted = fit(&usable, &levels, &selected, constituents);
    let residuals: BTreeMap<_, _> = usable.iter().map(|&t| (t, levels[&t]-predict::level(&fitted, t as f64))).collect();
    let dt = |time: i64| records::datetime(params.epoch, 60*time);
    cleaning_lines.push(format!("station={} name={}", station.code, station.name));
    cleaning_lines.push(format!("span start={} end={} hours={} record_length={}", dt(first), dt(last), length+1, length));
    let reason_count = |reason: &str| reasons.iter().filter(|r| r.as_str() == reason).count();
    cleaning_lines.push(format!("counts rows={} numeric={} na={} absent={} flat={} spikes={} usable={}", station.observations.len(), levels.len(),
        reason_count("na"), reason_count("absent"), reason_count("flat"), reason_count("spike"), usable.len()));
    for &(u, v, value) in &runs {
        cleaning_lines.push(format!("flat start={} end={} value={} removed={}", dt(first+u as i64), dt(first+v as i64), real(value as f64/1000.0, 3), v-u));
    }
    cleaning_lines.push(format!("spike_test window={} candidates={} tested={} prefit_rms={}", params.window, candidates.len(), tested, real(prefit_rms, 4)));
    for spike in &spikes {
        cleaning_lines.push(format!("spike time={} value={} residual={} median={} mad={} limit={}", dt(spike.time), real(levels[&spike.time], 3),
            real(spike.residual, 4), real(spike.median, 4), real(spike.mad, 4), real(spike.limit, 4)));
    }
    for (u, v, cause) in cleaning::gaps(&reasons) { cleaning_lines.push(format!("gap start={} end={} hours={} cause={}", dt(first+u as i64), dt(first+v as i64), v-u+1, cause)); }
    let ss: f64 = residuals.values().map(|r| r*r).sum();
    let unknowns = fitted.coefficients.len();
    let dof = usable.len()-unknowns;
    let variance = ss/dof as f64;
    let mut amplitudes = Vec::new();
    let mut phases = Vec::new();
    let mut uncertainties = Vec::new();
    for k in 0..selected.len() {
        let (ia, ib) = (2*k+1, 2*k+2);
        let (a, b) = (fitted.coefficients[ia], fitted.coefficients[ib]);
        let (amplitude, phase) = harmonic_fit::amplitude_phase(a, b);
        let (va, vb, cab) = (variance*fitted.inverse[ia][ia], variance*fitted.inverse[ib][ib], variance*fitted.inverse[ia][ib]);
        let amplitude_error = (a*a*va+b*b*vb+2.0*a*b*cab).sqrt()/amplitude;
        let phase_error = (b*b*va+a*a*vb-2.0*a*b*cab).sqrt()/(amplitude*amplitude)*180.0/PI;
        let snr = (amplitude/amplitude_error)*(amplitude/amplitude_error);
        amplitudes.push(amplitude); phases.push(phase); uncertainties.push((amplitude_error, phase_error, snr));
    }
    for (i, c) in constituents.iter().enumerate() {
        if let Some(k) = selected.iter().position(|&j| j == i) {
            let (amplitude_error, phase_error, snr) = uncertainties[k];
            constants.push(format!("{},{},{},fitted,{},{},{},{},{},{}", station.code, c.name, real(c.speed, 7), real(amplitudes[k], 4), real(phases[k], 2),
                real(amplitude_error, 4), real(phase_error, 2), real(snr, 1), if snr >= params.snr { "yes" } else { "no" }));
        } else { constants.push(format!("{},{},{},{},,,,,,", station.code, c.name, real(c.speed, 7), status[i])); }
    }
    let predictions: Vec<_> = (0..=params.duration).map(|i| predict::level(&fitted, (params.start+i) as f64)).collect();
    let mut extremes = predict::extrema(&fitted, params.start, params.duration, params.grid);
    let raw = extremes.len();
    while extremes.len() >= 2 {
        let pair = (0..extremes.len()-1).min_by(|&a, &b| (extremes[a].height-extremes[a+1].height).abs().total_cmp(&(extremes[b].height-extremes[b+1].height).abs()).then(a.cmp(&b))).unwrap();
        if (extremes[pair].height-extremes[pair+1].height).abs() >= params.min_range { break; }
        extremes.drain(pair..pair+2);
    }
    let mut daily_best = BTreeMap::<i64, (Option<usize>, Option<usize>)>::new();
    for (i, extremum) in extremes.iter().enumerate() {
        let entry = daily_best.entry(extremum.rounded.div_euclid(1440)).or_default();
        if extremum.high {
            if entry.0.map_or(true, |j| extremum.height > extremes[j].height) { entry.0 = Some(i); }
        } else if entry.1.map_or(true, |j| extremum.height < extremes[j].height) { entry.1 = Some(i); }
    }
    for (i, extremum) in extremes.iter_mut().enumerate() {
        let (high, low) = daily_best[&extremum.rounded.div_euclid(1440)];
        let label = if extremum.high { if high == Some(i) { "HHW" } else { "LHW" } }
            else if low == Some(i) { "LLW" } else { "HLW" };
        extremum.label = label.to_owned();
    }
    extremes_lines.push(format!("station={} extremes={} raw={} removed={}", station.code, extremes.len(), raw, raw-extremes.len()));
    for (i, e) in extremes.iter().enumerate() {
        extremes_lines.push(format!("{} {} {} change={}", records::datetime(params.epoch, e.rounded), e.label, real(e.height, 3),
            if i == 0 { "none".to_owned() } else { real(e.height-extremes[i-1].height, 3) }));
    }
    let mut daily = Vec::new();
    for day in 0..params.duration/24 {
        let date = params.start/24+day;
        let high: Vec<_> = extremes.iter().filter(|e| e.high && e.rounded.div_euclid(1440) == date).map(|e| e.height).collect();
        let low: Vec<_> = extremes.iter().filter(|e| !e.high && e.rounded.div_euclid(1440) == date).map(|e| e.height).collect();
        let hhw = if high.is_empty() { None } else { Some(high[best(&high, true)]) };
        let llw = if low.is_empty() { None } else { Some(low[best(&low, false)]) };
        let range = hhw.zip(llw).map(|(a, b)| a-b);
        extremes_lines.push(format!("day date={} high_waters={} low_waters={} hhw={} llw={} range={}", records::date(params.epoch, date*1440), high.len(), low.len(), optional(hhw), optional(llw), optional(range)));
        daily.push((date, hhw, llw, range));
    }
    let high: Vec<_> = extremes.iter().enumerate().filter(|(_, e)| e.high).map(|(i, _)| i).collect();
    let low: Vec<_> = extremes.iter().enumerate().filter(|(_, e)| !e.high).map(|(i, _)| i).collect();
    let mhhw = mean(&daily.iter().filter_map(|d| d.1).collect::<Vec<_>>());
    let mllw = mean(&daily.iter().filter_map(|d| d.2).collect::<Vec<_>>());
    let mhw = mean(&high.iter().map(|&i| extremes[i].height).collect::<Vec<_>>());
    let mlw = mean(&low.iter().map(|&i| extremes[i].height).collect::<Vec<_>>());
    let mtl = (mhw+mlw)/2.0;
    let dtl = (mhhw+mllw)/2.0;
    let constituent = |name: &str| selected.iter().position(|&i| constituents[i].name == name).unwrap();
    let (m2, s2, k1, o1, m4) = (constituent("M2"), constituent("S2"), constituent("K1"), constituent("O1"), constituent("M4"));
    let form = (amplitudes[k1]+amplitudes[o1])/(amplitudes[m2]+amplitudes[s2]);
    let tide_type = if form < 0.25 { "semidiurnal" } else if form < 1.5 { "mixed_semidiurnal" } else if form < 3.0 { "mixed_diurnal" } else { "diurnal" };
    let observed: Vec<_> = usable.iter().map(|t| levels[t]).collect();
    let observed_mean = mean(&observed);
    let sst: f64 = observed.iter().map(|h| { let e = h-observed_mean; e*e }).sum();
    let adjacent: Vec<_> = residuals.iter().filter_map(|(&t, &r)| residuals.get(&(t+1)).map(|&next| (r, next))).collect();
    let lag1 = adjacent.iter().map(|(a, b)| a*b).sum::<f64>()/adjacent.iter().map(|(a, _)| a*a).sum::<f64>();
    summary.push(format!("[station {}] {}", station.code, station.name));
    summary.push(format!("record first={} last={} length={} usable={}", dt(first), dt(last), length, usable.len()));
    summary.push(format!("fit constituents={} unknowns={} dof={} mean_level={}", selected.len(), unknowns, dof, real(fitted.coefficients[0], 4)));
    summary.push(format!("residual rms={} max_abs={} explained_percent={} lag1_autocorrelation={}", real((ss/usable.len() as f64).sqrt(), 4),
        real(residuals.values().map(|r| r.abs()).fold(0.0, f64::max), 4), real(100.0*(1.0-ss/sst), 4), real(lag1, 4)));
    let mut top = usable.clone();
    top.sort_by(|a, b| residuals[b].abs().total_cmp(&residuals[a].abs()).then(a.cmp(b)));
    for (rank, &t) in top.iter().take(params.top).enumerate() {
        summary.push(format!("top_residual rank={} time={} observed={} fitted={} residual={}", rank+1, dt(t), real(levels[&t], 3), real(predict::level(&fitted, t as f64), 4), real(residuals[&t], 4)));
    }
    let mid = first+length/2;
    let training: Vec<_> = usable.iter().copied().filter(|&t| t <= mid).collect();
    let testing: Vec<_> = usable.iter().copied().filter(|&t| t > mid).collect();
    let (_, validation_indices) = selection(constituents, training.last().unwrap()-training[0], params.rayleigh);
    let validation = fit(&training, &levels, &validation_indices, constituents);
    let val_error: f64 = testing.iter().map(|&t| { let e = levels[&t]-predict::level(&validation, t as f64); e*e }).sum();
    let in_sample: f64 = testing.iter().map(|t| residuals[t]*residuals[t]).sum();
    let test_mean = mean(&testing.iter().map(|t| levels[t]).collect::<Vec<_>>());
    let test_sst: f64 = testing.iter().map(|t| { let e = levels[t]-test_mean; e*e }).sum();
    summary.push(format!("validation split={} train={} test={} constituents={} rms={} in_sample_rms={} skill={}", dt(mid), training.len(), testing.len(), validation_indices.len(),
        real((val_error/testing.len() as f64).sqrt(), 4), real((in_sample/testing.len() as f64).sqrt(), 4), real(1.0-val_error/test_sst, 4)));
    summary.push(format!("form_number={} type={}", real(form, 4), tide_type));
    summary.push(format!("ranges spring={} neap={} mn={} gt={}", real(2.0*(amplitudes[m2]+amplitudes[s2]), 3), real(2.0*(amplitudes[m2]-amplitudes[s2]), 3), real(mhw-mlw, 3), real(mhhw-mllw, 3)));
    let rise: Vec<_> = extremes.windows(2).filter(|pair| !pair[0].high && pair[1].high).map(|pair| (pair[1].rounded-pair[0].rounded) as f64).collect();
    let fall: Vec<_> = extremes.windows(2).filter(|pair| pair[0].high && !pair[1].high).map(|pair| (pair[1].rounded-pair[0].rounded) as f64).collect();
    let phase = (2.0*phases[m2]-phases[m4]).rem_euclid(360.0);
    summary.push(format!("asymmetry rise_minutes={} fall_minutes={} m4_m2_ratio={} relative_phase={} dominance={}", real(mean(&rise), 1), real(mean(&fall), 1),
        real(amplitudes[m4]/amplitudes[m2], 4), real(phase, 2), if phase < 180.0 { "flood" } else { "ebb" }));
    summary.push(format!("datums mhhw={} mhw={} mtl={} dtl={} mlw={} mllw={}", real(mhhw, 3), real(mhw, 3), real(mtl, 3), real(dtl, 3), real(mlw, 3), real(mllw, 3)));
    let amplitude_sum: f64 = amplitudes.iter().sum();
    summary.push(format!("bounds hat={} lat={}", real(fitted.coefficients[0]+amplitude_sum, 3), real(fitted.coefficients[0]-amplitude_sum, 3)));
    let highest = high[best(&high.iter().map(|&i| extremes[i].height).collect::<Vec<_>>(), true)];
    let lowest = low[best(&low.iter().map(|&i| extremes[i].height).collect::<Vec<_>>(), false)];
    summary.push(format!("window high_waters={} low_waters={} highest={} highest_time={} lowest={} lowest_time={}", high.len(), low.len(), real(extremes[highest].height, 3),
        records::datetime(params.epoch, extremes[highest].rounded), real(extremes[lowest].height, 3), records::datetime(params.epoch, extremes[lowest].rounded)));
    let ranges: Vec<_> = daily.iter().filter(|d| d.3.is_some()).collect();
    let range_values: Vec<_> = ranges.iter().map(|d| d.3.unwrap()).collect();
    let widest = ranges[best(&range_values, true)];
    let narrowest = ranges[best(&range_values, false)];
    summary.push(format!("daily_range widest={} widest_date={} narrowest={} narrowest_date={}", real(widest.3.unwrap(), 3), records::date(params.epoch, widest.0*1440),
        real(narrowest.3.unwrap(), 3), records::date(params.epoch, narrowest.0*1440)));
    summary.push(format!("exceedance above_mhhw={} below_mllw={}", real(100.0*predictions.iter().filter(|&&v| v > mhhw).count() as f64/predictions.len() as f64, 2),
        real(100.0*predictions.iter().filter(|&&v| v < mllw).count() as f64/predictions.len() as f64, 2)));
    let dw = constituents[selected[s2]].speed-constituents[selected[m2]].speed;
    let dg = phases[s2]-phases[m2];
    let qa = (dw*params.start as f64-dg)/180.0;
    let qb = (dw*(params.start+params.duration) as f64-dg)/180.0;
    for q in qa.min(qb).ceil() as i64..=qa.max(qb).floor() as i64 {
        let t = (dg+180.0*q as f64)/dw;
        if t >= params.start as f64 && t <= (params.start+params.duration) as f64 {
            summary.push(format!("{} time={}", if q.rem_euclid(2) == 0 { "spring" } else { "neap" }, records::datetime(params.epoch, (t*60.0+0.5).floor() as i64)));
        }
    }
    let mut events = Vec::new();
    let mut i = 0;
    while i < usable.len() {
        let t = usable[i];
        let r = residuals[&t];
        let sign = if r > params.surge { 1 } else if r < -params.surge { -1 } else { i += 1; continue; };
        let first_event = i; i += 1;
        while i < usable.len() && usable[i] == usable[i-1]+1 && if sign == 1 { residuals[&usable[i]] > params.surge } else { residuals[&usable[i]] < -params.surge } { i += 1; }
        if i-first_event >= params.surge_hours {
            let times = &usable[first_event..i];
            let values: Vec<_> = times.iter().map(|t| residuals[t]).collect();
            let peak = times[best(&values, sign == 1)];
            events.push((sign, usable[first_event], usable[i-1], peak));
        }
    }
    summary.push(format!("surges count={} threshold={} min_hours={}", events.len(), real(params.surge, 3), params.surge_hours));
    for (sign, u, v, peak) in events { summary.push(format!("surge type={} start={} end={} hours={} peak={} peak_time={}", if sign == 1 { "positive" } else { "negative" }, dt(u), dt(v), v-u+1, real(residuals[&peak], 4), dt(peak))); }
    let weights = [0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1];
    let mut daily_means = Vec::new();
    for day in first.div_euclid(24)..=last.div_euclid(24) {
        let noon = 24*day+12;
        if noon-19 < first || noon+19 > last { continue; }
        let mut sum = 0.0;
        let mut filled = 0;
        for j in -19i64..=19 {
            let t = noon+j;
            let value = if residuals.contains_key(&t) { levels[&t] } else { filled += 1; predict::level(&fitted, t as f64) };
            sum += weights[j.unsigned_abs() as usize] as f64*value;
        }
        daily_means.push((day, sum/30.0, filled));
    }
    let means: Vec<_> = daily_means.iter().map(|d| d.1).collect();
    let xs: Vec<_> = daily_means.iter().map(|d| (d.0-daily_means[0].0) as f64).collect();
    let (xm, vm) = (mean(&xs), mean(&means));
    let slope = xs.iter().zip(&means).map(|(&x, &v)| (x-xm)*(v-vm)).sum::<f64>()/xs.iter().map(|x| (x-xm)*(x-xm)).sum::<f64>();
    let maximum = best(&means, true);
    let minimum = best(&means, false);
    summary.push(format!("daily_mean days={} average={} slope_mm_per_day={} max={} max_date={} min={} min_date={}", means.len(), real(vm, 4), real(1000.0*slope, 3),
        real(means[maximum], 4), records::date(params.epoch, daily_means[maximum].0*1440), real(means[minimum], 4), records::date(params.epoch, daily_means[minimum].0*1440)));
    for (day, level, filled) in daily_means { summary.push(format!("daily_mean date={} level={} filled={}", records::date(params.epoch, day*1440), real(level, 4), filled)); }
    ResultStation { fit: fitted, selected, amplitudes, phases, residuals, predictions, extremes, datums: [mhhw, mhw, mtl, dtl, mlw, mllw] }
}

fn main() {
    let (params, constituents) = records::read();
    let mut cleaning = Vec::new();
    let mut constants = vec!["station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant".to_owned()];
    let mut extremes = Vec::new();
    let mut summary = Vec::new();
    let results: Vec<_> = params.stations.iter().map(|station| analyze(station, &params, &constituents, &mut cleaning, &mut constants, &mut extremes, &mut summary)).collect();
    let mut predictions = vec![format!("time,{}", params.stations.iter().map(|s| s.code.as_str()).collect::<Vec<_>>().join(","))];
    for i in 0..=params.duration as usize { predictions.push(format!("{},{}", records::datetime(params.epoch, 60*(params.start+i as i64)), results.iter().map(|r| real(r.predictions[i], 3)).collect::<Vec<_>>().join(","))); }
    let reference = params.stations.iter().position(|s| s.code == params.reference).unwrap();
    let r = &results[reference];
    summary.push(format!("[comparison] reference={}", params.reference));
    for (i, station) in params.stations.iter().enumerate() {
        if i == reference { continue; }
        let result = &results[i];
        let lag = |high| {
            let extrema: Vec<_> = r.extremes.iter().filter(|e| e.high == high).collect();
            let lags: Vec<_> = result.extremes.iter().filter(|e| e.high == high).map(|e| {
                let nearest = extrema.iter().min_by_key(|candidate| ((candidate.rounded-e.rounded).abs(), candidate.rounded)).unwrap();
                (e.rounded-nearest.rounded) as f64
            }).collect();
            mean(&lags)
        };
        summary.push(format!("{} tide hw_lag_min={} lw_lag_min={} range_ratio={} mtl_diff={}", station.code, real(lag(true), 1), real(lag(false), 1),
            real((result.datums[0]-result.datums[5])/(r.datums[0]-r.datums[5]), 4), real(result.datums[2]-r.datums[2], 3)));
        for name in ["M2", "S2", "K1", "O1"] {
            let k = result.selected.iter().position(|&k| constituents[k].name == name).unwrap();
            let rk = r.selected.iter().position(|&k| constituents[k].name == name).unwrap();
            let mut phase = result.phases[k]-r.phases[rk];
            if phase > 180.0 { phase -= 360.0; } else if phase <= -180.0 { phase += 360.0; }
            summary.push(format!("{} {} amplitude_ratio={} phase_diff={} time_lag_min={}", station.code, name, real(result.amplitudes[k]/r.amplitudes[rk], 4),
                real(phase, 2), real(phase/constituents[result.selected[k]].speed*60.0, 1)));
        }
    }
    summary.push(format!("[correlation] max_lag={}", params.lag));
    for a in 0..results.len() { for b in a+1..results.len() {
        let mut correlations = Vec::new();
        for lag in -params.lag..=params.lag {
            let pairs: Vec<_> = results[a].residuals.iter().filter_map(|(&t, &x)| results[b].residuals.get(&(t+lag)).map(|&y| (x, y))).collect();
            let mx = pairs.iter().map(|p| p.0).sum::<f64>()/pairs.len() as f64;
            let my = pairs.iter().map(|p| p.1).sum::<f64>()/pairs.len() as f64;
            let sxy: f64 = pairs.iter().map(|&(x, y)| (x-mx)*(y-my)).sum();
            let sxx: f64 = pairs.iter().map(|&(x, _)| (x-mx)*(x-mx)).sum();
            let syy: f64 = pairs.iter().map(|&(_, y)| (y-my)*(y-my)).sum();
            correlations.push((lag, sxy/(sxx*syy).sqrt(), pairs.len()));
        }
        let best = correlations.iter().min_by(|a, b| b.1.total_cmp(&a.1).then(a.0.abs().cmp(&b.0.abs())).then(a.0.cmp(&b.0))).unwrap();
        let zero = correlations.iter().find(|c| c.0 == 0).unwrap();
        summary.push(format!("{}-{} lag0={} best_lag={} best={} pairs={}", params.stations[a].code, params.stations[b].code, real(zero.1, 4), best.0, real(best.1, 4), best.2));
    } }
    let i = params.stations.iter().position(|s| s.code == params.plot).unwrap();
    let result = &results[i];
    let rows = ((params.plot_top-params.plot_bottom)/params.plot_step+1) as usize;
    let mut cells = vec![vec![b' '; params.plot_hours]; rows];
    let zero = ((params.plot_top as f64-100.0*result.fit.coefficients[0])/params.plot_step as f64+0.5).floor() as i64;
    if zero >= 0 && zero < rows as i64 { cells[zero as usize].fill(b'-'); }
    let mut marks = vec![None; params.plot_hours];
    for e in &result.extremes {
        let column = (e.rounded-60*params.start+30).div_euclid(60);
        if column >= 0 && column < params.plot_hours as i64 { marks[column as usize] = Some(if e.high { b'H' } else { b'L' }); }
    }
    for c in 0..params.plot_hours {
        let row = ((params.plot_top as f64-100.0*result.predictions[c])/params.plot_step as f64+0.5).floor() as i64;
        if row < 0 { cells[0][c] = b'^'; } else if row >= rows as i64 { cells[rows-1][c] = b'v'; }
        else { cells[row as usize][c] = marks[c].unwrap_or(b'*'); }
    }
    summary.push(format!("[plot] station={} start={} hours={} step_cm={}", params.plot, records::datetime(params.epoch, 60*params.start), params.plot_hours, params.plot_step));
    summary.extend(report::plot(&cells, params.plot_top, params.plot_step));
    for (file, lines) in [("cleaning.txt", cleaning), ("constituents.csv", constants), ("predictions.csv", predictions), ("extremes.txt", extremes), ("summary.txt", summary)] { report::write(file, &lines); }
}
