'use strict';

function filterSignal(ecg) {
    const lowpass = [];
    const bandpass = [];
    const derivative = [];
    const squared = [];
    const integrated = [];
    let previous = 0;
    let beforePrevious = 0;
    let highpassSum = 0;
    let windowSum = 0;
    for (let n = 0; n < ecg.length; n++) {
        const current = 2 * previous - beforePrevious + ecg[n] - 2 * (ecg[n - 6] ?? 0) + (ecg[n - 12] ?? 0);
        beforePrevious = previous;
        previous = current;
        lowpass.push(Math.floor(current / 32));
        highpassSum += lowpass[n] - (lowpass[n - 32] ?? 0);
        bandpass.push((lowpass[n - 16] ?? 0) - Math.floor(highpassSum / 32));
        derivative.push(Math.floor((2 * bandpass[n] + (bandpass[n - 1] ?? 0) - (bandpass[n - 3] ?? 0) - 2 * (bandpass[n - 4] ?? 0)) / 8));
        squared.push(derivative[n] * derivative[n]);
        windowSum += squared[n] - (squared[n - 30] ?? 0);
        integrated.push(Math.floor(windowSum / 30));
    }
    return { ecg, lowpass, bandpass, derivative, squared, integrated };
}

module.exports = { filterSignal };
