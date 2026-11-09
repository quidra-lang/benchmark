'use strict';

function attributeModel(chart, points, lots) {
  let defectives = 0;
  let defects = 0;
  let inspected = 0;
  for (const number of points) {
    const lot = lots[number - 1];
    defectives += lot.defectives;
    defects += lot.defects;
    inspected += lot.inspected;
  }
  let center;
  if (chart === 'p') center = defectives / inspected;
  else if (chart === 'np') center = defectives / points.length;
  else if (chart === 'c') center = defects / points.length;
  else center = defects / inspected;
  return {center, defectiveRate: defectives / inspected};
}

function attributeLot(chart, model, lot) {
  const center = model.center;
  let value;
  let sigma;
  if (chart === 'p') {
    value = lot.defectives / lot.inspected;
    sigma = Math.sqrt(center * (1 - center) / lot.inspected);
  } else if (chart === 'np') {
    value = lot.defectives;
    sigma = Math.sqrt(center * (1 - model.defectiveRate));
  } else if (chart === 'c') {
    value = lot.defects;
    sigma = Math.sqrt(center);
  } else {
    value = lot.defects / lot.inspected;
    sigma = Math.sqrt(center / lot.inspected);
  }
  const lcl = Math.max(0, center - 3 * sigma);
  const ucl = center + 3 * sigma;
  const z = (value - center) / sigma;
  const status = value > ucl ? 'high' : value < lcl ? 'low' : 'ok';
  return {number: lot.number, inspected: lot.inspected, value, lcl, ucl, z, status};
}

module.exports = {attributeModel, attributeLot};
