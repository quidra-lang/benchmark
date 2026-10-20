'use strict';

const fs = require('node:fs');
const { communitiesText } = require('./policy');
const pathText = path => path.join(',');

function attributeText(attribute) {
  return `path ${pathText(attribute.path)} origin ${attribute.origin} med ${attribute.med} comm ${communitiesText(attribute.communities)}`;
}

function routeText(route) {
  if (route == null) return 'NONE';
  if (route.local) return `LOCAL origin ${route.origin} comm ${communitiesText(route.communities)}`;
  return `next ${route.path[0]} path ${pathText(route.path)} link ${route.link.name} lp ${route.localPref} med ${route.med} origin ${route.origin} comm ${communitiesText(route.communities)}`;
}

function writeReports(reports) {
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of reports) fs.writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

module.exports = { pathText, attributeText, routeText, writeReports };
