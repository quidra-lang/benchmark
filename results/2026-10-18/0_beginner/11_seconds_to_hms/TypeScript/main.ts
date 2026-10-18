for (const total of [0, 59, 3725, 45296, 86400, 312047]) {
  const parts = [Math.floor(total / 3600), Math.floor(total % 3600 / 60), total % 60];
  console.log(`${total} seconds = ${parts.map(n => String(n).padStart(2, "0")).join(":")}`);
}
