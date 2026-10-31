import { readFileSync } from 'node:fs';
export interface Settings {
  nodes: number;
  electionMin: number;
  electionMax: number;
  heartbeat: number;
  batch: number;
  quorum: number;
  seed: number;
  end: number;
  retry: number;
  attempts: number;
  sample: number;
}
export type Control =
  | { kind: 'CRASH' | 'RESTART'; node: number }
  | { kind: 'PARTITION'; groups: number[][] }
  | { kind: 'HEAL' }
  | { kind: 'TRANSFER'; source: number; target: number };
export interface ClientRequest {
  number: number;
  time: number;
  startNode: number;
  destination: number;
  scheduled: number;
  command: string;
  attempts: number;
  redirects: number;
  accepted: { index: number; term: number } | null;
  abandoned: boolean;
}
const lines = (path: string) => readFileSync(path, 'ascii').split('\n').slice(0, -1);
export const partitionGroups = (tokens: string[]) =>
  tokens.map((token) => token.split(',').map(Number));
export function read() {
  const values = new Map<string, number[]>();
  for (const line of lines('input/cluster.txt')) {
    const [key, ...fields] = line.split(' ');
    values.set(key, fields.map(Number));
  }
  const get = (key: string) => values.get(key)![0];
  const election = values.get('ELECTION')!;
  const settings: Settings = {
    nodes: get('NODES'),
    electionMin: election[0],
    electionMax: election[1],
    heartbeat: get('HEARTBEAT'),
    batch: get('BATCH'),
    quorum: get('QUORUM'),
    seed: get('SEED'),
    end: get('END'),
    retry: get('RETRY'),
    attempts: get('ATTEMPTS'),
    sample: get('SAMPLE'),
  };
  const controls = new Map<number, Control[]>();
  const requests: ClientRequest[] = [];
  for (const line of lines('input/script.txt')) {
    const [when, kind, ...args] = line.split(' ');
    const time = Number(when);
    if (kind === 'REQUEST') {
      requests.push({
        number: requests.length + 1,
        time,
        startNode: Number(args[0]),
        destination: Number(args[0]),
        scheduled: time,
        command: args.slice(1).join(' '),
        attempts: 0,
        redirects: 0,
        accepted: null,
        abandoned: false,
      });
    } else {
      let event: Control;
      if (kind === 'CRASH' || kind === 'RESTART') event = { kind, node: Number(args[0]) };
      else if (kind === 'PARTITION') event = { kind, groups: partitionGroups(args) };
      else if (kind === 'HEAL') event = { kind };
      else event = { kind: 'TRANSFER', source: Number(args[0]), target: Number(args[1]) };
      const at = controls.get(time) ?? [];
      at.push(event);
      controls.set(time, at);
    }
  }
  return { settings, controls, requests };
}
