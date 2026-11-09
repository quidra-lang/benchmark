import type { Attribute, Route } from './types.ts';

import * as fs from 'node:fs';
import { communitiesText } from './policy.ts';
export const pathText = (path: number[]): string => path.join(',');

export function attributeText(attribute: Attribute): string {
  return `path ${pathText(attribute.path)} origin ${attribute.origin} med ${attribute.med} comm ${communitiesText(attribute.communities)}`;
}

export function routeText(route: Route | null | undefined): string {
  if (route == null) return 'NONE';
  if (route.local) return `LOCAL origin ${route.origin} comm ${communitiesText(route.communities)}`;
  return `next ${route.path[0]} path ${pathText(route.path)} link ${route.link!.name} lp ${route.localPref} med ${route.med} origin ${route.origin} comm ${communitiesText(route.communities)}`;
}

export function writeReports(reports: [string, string[]][]): void {
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of reports) fs.writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

