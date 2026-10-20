'use strict';

function findPeaks(signals) {
    const { integrated, bandpass, derivative } = signals;
    const peaks = [];
    for (let n = 0; n < integrated.length; n++) {
        if (integrated[n] <= 0) continue;
        let peak = true;
        for (let j = Math.max(0, n - 20); j < n; j++) if (integrated[j] >= integrated[n]) { peak = false; break; }
        if (!peak) continue;
        for (let j = n + 1; j <= Math.min(integrated.length - 1, n + 20); j++) if (integrated[j] > integrated[n]) { peak = false; break; }
        if (!peak) continue;
        let position = Math.max(0, n - 30);
        for (let j = position + 1; j <= n; j++) if (Math.abs(bandpass[j]) > Math.abs(bandpass[position])) position = j;
        let slope = 0;
        for (let j = Math.max(0, n - 29); j <= n; j++) slope = Math.max(slope, Math.abs(derivative[j]));
        peaks.push({ number: peaks.length + 1, time: n, position, peakI: integrated[n], peakF: Math.abs(bandpass[position]),
            slope, thresholdI: null, thresholdF: null, kind: null });
    }
    return peaks;
}

function qrsWidth(bandpass, position) {
    const amplitude = Math.abs(bandpass[position]);
    let first = position;
    let last = position;
    for (let j = Math.max(0, position - 25); j <= Math.min(bandpass.length - 1, position + 25); j++) {
        if (4 * Math.abs(bandpass[j]) >= amplitude) { first = Math.min(first, j); last = Math.max(last, j); }
    }
    return 5 * (last - first + 1);
}

function initialLevels(signals) {
    let maxI = 0;
    let maxF = 0;
    let sumI = 0;
    let sumF = 0;
    for (let n = 0; n < 400; n++) {
        maxI = Math.max(maxI, signals.integrated[n]);
        maxF = Math.max(maxF, Math.abs(signals.bandpass[n]));
        sumI += signals.integrated[n];
        sumF += Math.abs(signals.bandpass[n]);
    }
    return { spki: Math.floor(maxI / 3), npki: Math.floor(sumI / 800), spkf: Math.floor(maxF / 3), npkf: Math.floor(sumF / 800) };
}

module.exports = { findPeaks, qrsWidth, initialLevels };
