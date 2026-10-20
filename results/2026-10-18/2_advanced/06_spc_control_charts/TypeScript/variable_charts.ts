import { CONSTANTS, type Constants, type Family, type Sample } from './dataset.ts';
export interface Point { number: number; value: number }
export interface Control { lcl: number; cl: number; ucl: number }
export interface Group { number: number; samples: Sample[]; total: number; squares: number; mean: number; range: number; sd: number }
export interface Model { limits: [Control, Control]; sequences: [Point[], Point[]] }
export function subgroupStatistics(samples: Sample[], n: number): Group[] {
  const groups: Group[] = [];
  for (let start = 0; start < samples.length; start += n) {
    const members = samples.slice(start,start+n);
    let total = 0, squares = 0, low = members[0].value, high = low;
    for (const {value} of members) { total += value; squares += value*value; low=Math.min(low,value); high=Math.max(high,value); }
    groups.push({number:members[0].subgroup,samples:members,total,squares,mean:total/n,range:high-low,
      sd:Math.sqrt((n*squares-total*total)/(n*(n-1)))});
  }
  return groups;
}
export function movingRanges(points: Point[]): Point[] {
  return points.slice(1).map((point,i) => ({number:point.number,value:Math.abs(point.value-points[i].value)}));
}
export const outside = (value: number, control: Control) => value < control.lcl || value > control.ucl;
export function familyLimits(family: Family, points: number[], groups: Group[], samples: Sample[], n: number, c: Constants): Model {
  if (family === 'I_MR') {
    const individual = points.map(number => ({number,value:samples[number-1].value}));
    const ranges = movingRanges(individual);
    let total=0, spreadTotal=0;
    for (const point of individual) total+=point.value;
    for (const point of ranges) spreadTotal+=point.value;
    const center=total/individual.length, spread=spreadTotal/ranges.length, two=CONSTANTS[2];
    const width=3*spread/two.d2;
    return {limits:[{lcl:center-width,cl:center,ucl:center+width},{lcl:two.D3*spread,cl:spread,ucl:two.D4*spread}],sequences:[individual,ranges]};
  }
  const selected=points.map(number=>groups[number-1]);
  let total=0, spreadTotal=0;
  for (const group of selected) { total+=group.total; spreadTotal+=family==='XBAR_R'?group.range:group.sd; }
  const center=total/(selected.length*n), spread=spreadTotal/selected.length;
  const width=(family==='XBAR_R'?c.A2:c.A3)*spread;
  return {limits:[{lcl:center-width,cl:center,ucl:center+width},
    {lcl:(family==='XBAR_R'?c.D3:c.B3)*spread,cl:spread,ucl:(family==='XBAR_R'?c.D4:c.B4)*spread}],
    sequences:[selected.map(g=>({number:g.number,value:g.mean})),selected.map(g=>({number:g.number,value:family==='XBAR_R'?g.range:g.sd}))]};
}
