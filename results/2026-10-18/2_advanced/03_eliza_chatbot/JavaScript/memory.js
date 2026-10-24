function store(memory, session, capacity, keyword, text) {
  const prefix = `${session.name} ${session.turns}`;
  if (memory.queue.includes(text)) {
    memory.log.push(`${prefix} SKIP ${keyword} ${text}`);
    return;
  }
  if (memory.queue.length === capacity) {
    memory.log.push(`${prefix} DROP ${memory.queue.shift()}`);
  }
  memory.queue.push(text);
  memory.log.push(`${prefix} STORE ${keyword} ${text}`);
  session.stored += 1;
}

function recall(memory, session) {
  const text = memory.queue.shift();
  memory.log.push(`${session.name} ${session.turns} RECALL ${text}`);
  session.recalled += 1;
  return text;
}

function clear(memory, name, turn) {
  const count = memory.queue.length;
  if (count > 0) {
    memory.queue.length = 0;
    memory.log.push(`${name} ${turn} CLEAR ${count}`);
  }
  return count;
}

module.exports = { store, recall, clear };
