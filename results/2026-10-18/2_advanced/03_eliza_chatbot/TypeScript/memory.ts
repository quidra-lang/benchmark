export interface Memory { queue: string[]; log: string[] }
export function store(memory: Memory, capacity: number, prefix: string, keyword: string, text: string): boolean {
  if (memory.queue.includes(text)) { memory.log.push(`${prefix} SKIP ${keyword} ${text}`); return false; }
  if (memory.queue.length === capacity) memory.log.push(`${prefix} DROP ${memory.queue.shift()!}`);
  memory.queue.push(text); memory.log.push(`${prefix} STORE ${keyword} ${text}`); return true;
}
export function recall(memory: Memory, prefix: string): string {
  const text = memory.queue.shift()!; memory.log.push(`${prefix} RECALL ${text}`); return text;
}
export function clear(memory: Memory, prefix: string): number {
  const count = memory.queue.length;
  if (count) { memory.queue = []; memory.log.push(`${prefix} CLEAR ${count}`); }
  return count;
}
