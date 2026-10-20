import { readFileSync } from 'node:fs';

export type Family = 'XBAR_R' | 'XBAR_S' | 'I_MR';
export type Shewhart = 'XBAR_R' | 'R' | 'XBAR_S' | 'S' | 'I' | 'MR';
export type Chart = Shewhart | 'CUSUM' | 'EWMA' | 'MA';
export type AttributeChart = 'p' | 'np' | 'c' | 'u';
export interface Spec {
  characteristic: string; lsl: number; usl: number; target: number;
  subgroup_size: number; phase1_subgroups: number; max_passes: number;
  rules: Record<Shewhart | 'STD', number[]>;
  cusum_k: number; cusum_h: number; ewma_lambda: number; ewma_l: number;
  ma_span: number; event_gap: number; ci_z: number; histogram_bin: number;
  rolling_window: number; rolling_step: number;
}
export interface Sample { number: number; subgroup: number; value: number }
export interface Lot { number: number; inspected: number; defectives: number; defects: number }
export interface Constants { A2: number; A3: number; B3: number; B4: number; D3: number; D4: number; d2: number; c4: number }
export const CONSTANTS: Record<number, Constants> = {
  2: { A2:1.880,A3:2.659,B3:0,B4:3.267,D3:0,D4:3.267,d2:1.128,c4:0.7979 },
  3: { A2:1.023,A3:1.954,B3:0,B4:2.568,D3:0,D4:2.574,d2:1.693,c4:0.8862 },
  4: { A2:0.729,A3:1.628,B3:0,B4:2.266,D3:0,D4:2.282,d2:2.059,c4:0.9213 },
  5: { A2:0.577,A3:1.427,B3:0,B4:2.089,D3:0,D4:2.114,d2:2.326,c4:0.9400 },
  6: { A2:0.483,A3:1.287,B3:0.030,B4:1.970,D3:0,D4:2.004,d2:2.534,c4:0.9515 },
  7: { A2:0.419,A3:1.182,B3:0.118,B4:1.882,D3:0.076,D4:1.924,d2:2.704,c4:0.9594 },
  8: { A2:0.373,A3:1.099,B3:0.185,B4:1.815,D3:0.136,D4:1.864,d2:2.847,c4:0.9650 },
  9: { A2:0.337,A3:1.032,B3:0.239,B4:1.761,D3:0.184,D4:1.816,d2:2.970,c4:0.9693 },
  10:{ A2:0.308,A3:0.975,B3:0.284,B4:1.716,D3:0.223,D4:1.777,d2:3.078,c4:0.9727 },
};
function lines(path: string): string[] { return readFileSync(path, 'ascii').trimEnd().split('\n'); }
export function readDataset() {
  const settings = lines('input/spec.txt').map(line => line.split(' '));
  const number = (name: string) => Number(settings.find(row => row[0] === name)![1]);
  const rules = (name: string) => settings.find(row => row[0] === 'rules' && row[1] === name)!.slice(2).map(Number);
  const spec: Spec = {
    characteristic: settings[0][1], lsl:number('lsl'), usl:number('usl'), target:number('target'),
    subgroup_size:number('subgroup_size'), phase1_subgroups:number('phase1_subgroups'), max_passes:number('max_passes'),
    rules:{ XBAR_R:rules('XBAR_R'), R:rules('R'), XBAR_S:rules('XBAR_S'), S:rules('S'), I:rules('I'), MR:rules('MR'), STD:rules('STD') },
    cusum_k:number('cusum_k'), cusum_h:number('cusum_h'), ewma_lambda:number('ewma_lambda'), ewma_l:number('ewma_l'),
    ma_span:number('ma_span'), event_gap:number('event_gap'), ci_z:number('ci_z'), histogram_bin:number('histogram_bin'),
    rolling_window:number('rolling_window'), rolling_step:number('rolling_step'),
  };
  const samples: Sample[] = lines('input/measurements.csv').slice(1).map(line => {
    const [number, subgroup, value] = line.split(',').map(Number); return {number,subgroup,value};
  });
  const lots: Lot[] = lines('input/attributes.csv').slice(1).map(line => {
    const [number, inspected, defectives, defects] = line.split(',').map(Number); return {number,inspected,defectives,defects};
  });
  return {spec,samples,lots,constants:CONSTANTS[spec.subgroup_size]};
}
