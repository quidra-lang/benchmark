import type {AttributeChart,Lot} from './dataset.ts';
export interface AttributeModel { center: number; defectiveRate: number }
export interface AttributeRow { number: number; inspected: number; value: number; lcl: number; ucl: number; z: number; status: 'high'|'low'|'ok' }
export function attributeModel(chart: AttributeChart, points: number[], lots: Lot[]): AttributeModel {
  let d=0,c=0,n=0;
  for(const number of points) { const lot=lots[number-1]; d+=lot.defectives;c+=lot.defects;n+=lot.inspected; }
  return {center:chart==='p'?d/n:chart==='np'?d/points.length:chart==='c'?c/points.length:c/n,defectiveRate:d/n};
}
export function attributeLot(chart: AttributeChart, model: AttributeModel, lot: Lot): AttributeRow {
  const center=model.center;
  const value=chart==='p'?lot.defectives/lot.inspected:chart==='np'?lot.defectives:chart==='c'?lot.defects:lot.defects/lot.inspected;
  const sigma=Math.sqrt(chart==='p'?center*(1-center)/lot.inspected:chart==='np'?center*(1-model.defectiveRate):chart==='c'?center:center/lot.inspected);
  const lcl=Math.max(0,center-3*sigma),ucl=center+3*sigma;
  return {number:lot.number,inspected:lot.inspected,value,lcl,ucl,z:(value-center)/sigma,status:value>ucl?'high':value<lcl?'low':'ok'};
}
