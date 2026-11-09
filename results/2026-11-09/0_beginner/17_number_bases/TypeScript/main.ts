for (const n of [0, 10, 255, 1000, 43981, 65535]) {
  console.log(`${n}: bin=${n.toString(2)} oct=${n.toString(8)} hex=${n.toString(16).toUpperCase()}`);
}
