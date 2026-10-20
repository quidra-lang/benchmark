export function scale(values: number[], season: number) {
  let total = 0;
  for (let t = season; t < values.length; t++) total += Math.abs(values[t] - values[t - season]);
  return total / (values.length - season);
}
export function accuracy(actual: number[], forecast: number[], delta: number) {
  let errors = 0;
  let absolute = 0;
  let squares = 0;
  let percentage = 0;
  let symmetric = 0;
  for (let i = 0; i < actual.length; i++) {
    const e = actual[i] - forecast[i];
    const a = Math.abs(e);
    errors += e;
    absolute += a;
    squares += e * e;
    percentage += a / actual[i];
    symmetric += (2 * a) / (Math.abs(actual[i]) + Math.abs(forecast[i]));
  }
  const h = actual.length;
  const mae = absolute / h;
  return {
    me: errors / h,
    mae,
    rmse: Math.sqrt(squares / h),
    mape: (100 * percentage) / h,
    smape: (100 * symmetric) / h,
    mase: mae / delta,
  };
}
export function winkler(actual: number, low: number, high: number, kappa: number) {
  return actual < low
    ? high - low + kappa * (low - actual)
    : actual > high
      ? high - low + kappa * (actual - high)
      : high - low;
}
export const rank = (values: number[]) =>
  values.map((_, i) => i).sort((a, b) => values[a] - values[b] || a - b);
