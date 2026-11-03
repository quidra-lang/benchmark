const { ceilRatio } = require('./report');

function lotSize(item, net, available, week, gross, receipts, horizon) {
  if (item.rule === 'LFL') return net;
  if (item.rule === 'FOQ') return ceilRatio(net, item.fixed) * item.fixed;
  if (item.rule === 'MIN') {
    return ceilRatio(Math.max(net, item.minimum), item.multiple) * item.multiple;
  }
  let balance = available;
  let quantity = net;
  const lastWeek = Math.min(week + item.periods - 1, horizon);
  for (let future = week + 1; future <= lastWeek; future += 1) {
    balance += receipts[future] - gross[future];
    quantity = Math.max(quantity, item.safety - balance);
  }
  return quantity;
}

module.exports = { lotSize };
