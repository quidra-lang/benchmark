import { readFileSync } from 'node:fs';

export interface Operation {
    index: number; job: number; jobIndex: number; number: number; machine: number;
    duration: number; head: number; tail: number; predecessor: number; successor: number; notation: string;
}
export interface Job { number: number; index: number; letter: string; work: number; operations: number[] }
export interface Machine {
    number: number; operations: number[]; load: number; head: number; tail: number; bound: number; jackson: number;
}
export interface Instance {
    jobs: Job[]; operations: Operation[]; machines: Machine[]; errors: string[];
    machineCount: number; byNumber: Map<number, Job>; work: number;
}

export function readInstance(): Instance {
    const lines = readFileSync('input/instance.txt', 'ascii').trimEnd().split('\n');
    const [jobLines, machineCount] = lines[0].split(' ').map(Number);
    const jobs: Job[] = [], operations: Operation[] = [], errors: string[] = [];
    for (let number = 1; number <= jobLines; number++) {
        const tokens = lines[number].split(' ').map(token => token.split(':').map(Number));
        const seen = new Set<number>();
        let error: string | undefined;
        for (let i = 0; i < tokens.length; i++) {
            const [machine, duration] = tokens[i];
            let reason: string | undefined;
            if (machine < 1 || machine > machineCount) reason = `unknown machine ${machine}`;
            else if (duration < 1 || duration > 99) reason = `bad duration ${duration}`;
            else if (seen.has(machine)) reason = `repeated machine ${machine}`;
            if (reason !== undefined) { error = `job ${number} operation ${i + 1}: ${reason}`; break; }
            seen.add(machine);
        }
        if (error !== undefined) { errors.push(error); continue; }
        const work = tokens.reduce((sum, [, duration]) => sum + duration, 0);
        const job: Job = { number, index: jobs.length, letter: String.fromCharCode(64 + number), work, operations: [] };
        let head = 0;
        for (let i = 0; i < tokens.length; i++) {
            const [machine, duration] = tokens[i];
            const index = operations.length;
            operations.push({ index, job: number, jobIndex: job.index, number: i + 1, machine: machine - 1,
                duration, head, tail: work - head - duration, predecessor: i === 0 ? -1 : index - 1,
                successor: i + 1 === tokens.length ? -1 : index + 1, notation: `J${number}-${i + 1}` });
            job.operations.push(index);
            head += duration;
        }
        jobs.push(job);
    }
    const machines: Machine[] = [];
    for (let machine = 0; machine < machineCount; machine++) {
        const selected = operations.filter(operation => operation.machine === machine);
        const load = selected.reduce((sum, operation) => sum + operation.duration, 0);
        const head = Math.min(...selected.map(operation => operation.head));
        const tail = Math.min(...selected.map(operation => operation.tail));
        machines.push({ number: machine + 1, operations: selected.map(operation => operation.index), load, head, tail,
            bound: head + load + tail, jackson: 0 });
    }
    return { jobs, operations, machines, errors, machineCount, byNumber: new Map(jobs.map(job => [job.number, job])),
        work: jobs.reduce((sum, job) => sum + job.work, 0) };
}
