for (const n of [0, 7, 999, 1000, -456789, 3141592, 9876543210]) {
  console.log(String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ","));
}
