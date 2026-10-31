'use strict';

function fitScaling(rows, method) {
  const centers = [], scales = [];
  for (let feature = 0; feature < rows[0].features.length; feature++) {
    let center, scale;
    if (method === 'standard') {
      let total = 0;
      for (const row of rows) total += row.features[feature];
      center = total / rows.length;
      let squared = 0;
      for (const row of rows) {
        const difference = row.features[feature] - center;
        squared += difference * difference;
      }
      scale = rows.length === 1 ? 0 : Math.sqrt(squared / (rows.length - 1));
    } else {
      let minimum = rows[0].features[feature], maximum = minimum;
      for (const row of rows) {
        minimum = Math.min(minimum, row.features[feature]);
        maximum = Math.max(maximum, row.features[feature]);
      }
      center = minimum;
      scale = maximum - minimum;
    }
    centers.push(center);
    scales.push(scale);
  }
  return { centers, scales };
}

function transform(row, scaling, features) {
  return features.map(feature => scaling.scales[feature] > 0
    ? (row.features[feature] - scaling.centers[feature]) / scaling.scales[feature] : 0);
}

module.exports = { fitScaling, transform };
