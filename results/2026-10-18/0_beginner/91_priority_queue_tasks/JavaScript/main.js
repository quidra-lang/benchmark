const heap = [];
const less = (a, b) => a.priority < b.priority || (a.priority === b.priority && a.sequence < b.sequence);
function push(task) {
  heap.push(task);
  let index = heap.length - 1;
  while (index > 0) {
    const parent = Math.floor((index - 1) / 2);
    if (!less(heap[index], heap[parent])) break;
    [heap[index], heap[parent]] = [heap[parent], heap[index]];
    index = parent;
  }
}
function pop() {
  const first = heap[0], last = heap.pop();
  if (heap.length > 0) {
    heap[0] = last;
    let index = 0;
    while (2 * index + 1 < heap.length) {
      let child = 2 * index + 1;
      if (child + 1 < heap.length && less(heap[child + 1], heap[child])) child++;
      if (!less(heap[child], heap[index])) break;
      [heap[index], heap[child]] = [heap[child], heap[index]];
      index = child;
    }
  }
  return first;
}
const operations = [
  "add email 3", "add backup 5", "add deploy 1", "run", "add report 3", "add test 2",
  "add lint 3", "run", "run", "add cleanup 5", "add review 2", "run",
  "add build 1", "add docs 4", "run", "run"
];
let sequence = 0;
for (const operation of operations) {
  const parts = operation.split(" ");
  if (parts[0] === "add") {
    push({name: parts[1], priority: Number(parts[2]), sequence});
    sequence++;
  } else {
    const task = pop();
    console.log(`run: ${task.name} (priority ${task.priority})`);
  }
}
const remaining = [];
while (heap.length > 0) remaining.push(pop().name);
console.log(`remaining: ${remaining.join(" ")}`);
