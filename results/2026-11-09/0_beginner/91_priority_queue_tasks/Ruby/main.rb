def push(heap, task)
  heap << task
  index = heap.length - 1
  while index.positive?
    parent = (index - 1) / 2
    break if (heap[index] <=> heap[parent]) >= 0
    heap[index], heap[parent] = heap[parent], heap[index]
    index = parent
  end
end

def pop(heap)
  first, last = heap[0], heap.pop
  unless heap.empty?
    heap[0] = last
    index = 0
    while 2 * index + 1 < heap.length
      child = 2 * index + 1
      child += 1 if child + 1 < heap.length && (heap[child + 1] <=> heap[child]).negative?
      break if (heap[child] <=> heap[index]) >= 0
      heap[index], heap[child] = heap[child], heap[index]
      index = child
    end
  end
  first
end

operations = [
  'add email 3', 'add backup 5', 'add deploy 1', 'run', 'add report 3', 'add test 2',
  'add lint 3', 'run', 'run', 'add cleanup 5', 'add review 2', 'run',
  'add build 1', 'add docs 4', 'run', 'run'
]
queue = []
sequence = 0
operations.each do |operation|
  parts = operation.split
  if parts[0] == 'add'
    push(queue, [parts[2].to_i, sequence, parts[1]])
    sequence += 1
  else
    priority, _, name = pop(queue)
    puts "run: #{name} (priority #{priority})"
  end
end
remaining = []
remaining << pop(queue)[2] until queue.empty?
puts "remaining: #{remaining.join(' ')}"
