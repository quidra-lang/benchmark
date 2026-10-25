let state = 42, arrival = 0;
const freeTimes = [0, 0], waits: number[] = [];
for (let customer = 1; customer <= 20; customer++) {
  state = state * 48271 % 2147483647;
  arrival += state % 5 + 1;
  state = state * 48271 % 2147483647;
  const service = state % 7 + 2;
  const teller = freeTimes[0] <= freeTimes[1] ? 0 : 1;
  const start = Math.max(arrival, freeTimes[teller]), end = start + service;
  freeTimes[teller] = end;
  const wait = start - arrival;
  waits.push(wait);
  console.log(
    `customer ${customer}: arrive=${arrival} start=${start} end=${end} ` +
    `teller=${teller + 1} wait=${wait}`
  );
}
const average = waits.reduce((sum, wait) => sum + wait, 0) / 20;
console.log(`average wait: ${average.toFixed(2)}`);
console.log(`max wait: ${Math.max(...waits)}`);
console.log(`last departure: ${Math.max(...freeTimes)}`);
