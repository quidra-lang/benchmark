import { readFileSync } from 'node:fs';

export type Variable = 'sex' | 'stage';
export interface Subject {
  id: number;
  group: string;
  time: number;
  event: number;
  age: number;
  sex: string;
  stage: number;
}
export interface Parameters {
  groups: string[];
  reportTimes: number[];
  tau: number;
  lifeWidth: number;
  lifeCount: number;
  strata: Variable;
  subgroups: Variable[];
  landmark: number;
  covariates: string[];
  residuals: number;
  width: number;
  height: number;
  plotTime: number;
  divisions: number;
}
export function readDataset(): { subjects: Subject[]; params: Parameters } {
  const subjects = readFileSync('input/subjects.csv', 'ascii')
    .trimEnd()
    .split('\n')
    .slice(1)
    .map((line) => {
      const [id, group, time, event, age, sex, stage] = line.split(',');
      return { id: +id, group, time: +time, event: +event, age: +age, sex, stage: +stage };
    })
    .sort((a, b) => a.id - b.id);
  const rows = readFileSync('input/params.txt', 'ascii')
    .trimEnd()
    .split('\n')
    .map((line) => line.split(' ').slice(1));
  const variable = (name: string): Variable => (name === 'sex' ? 'sex' : 'stage');
  return {
    subjects,
    params: {
      groups: rows[0],
      reportTimes: rows[1].map(Number),
      tau: +rows[2][0],
      lifeWidth: +rows[3][0],
      lifeCount: +rows[3][1],
      strata: variable(rows[4][0]),
      subgroups: rows[5].map(variable),
      landmark: +rows[6][0],
      covariates: rows[7],
      residuals: +rows[8][0],
      width: +rows[9][0],
      height: +rows[9][1],
      plotTime: +rows[9][2],
      divisions: +rows[9][3],
    },
  };
}
