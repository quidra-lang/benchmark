import Foundation

struct Task {
    let name: String
    let priority: Int
    let sequence: Int
    func precedes(_ other: Task) -> Bool {
        return priority == other.priority ? sequence < other.sequence : priority < other.priority
    }
}
struct Heap {
    var tasks = [Task]()
    mutating func push(_ task: Task) {
        tasks.append(task)
        var i = tasks.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            if !tasks[i].precedes(tasks[parent]) { break }
            tasks.swapAt(i,parent)
            i = parent
        }
    }
    mutating func pop() -> Task {
        let result = tasks[0], last = tasks.removeLast()
        if tasks.isEmpty { return result }
        tasks[0] = last
        var i = 0
        while 2 * i + 1 < tasks.count {
            var child = 2 * i + 1
            if child + 1 < tasks.count && tasks[child + 1].precedes(tasks[child]) { child += 1 }
            if !tasks[child].precedes(tasks[i]) { break }
            tasks.swapAt(i,child)
            i = child
        }
        return result
    }
}
let operations = ["add email 3", "add backup 5", "add deploy 1", "run", "add report 3", "add test 2",
    "add lint 3", "run", "run", "add cleanup 5", "add review 2", "run", "add build 1",
    "add docs 4", "run", "run"]
var queue = Heap(), sequence = 0
for operation in operations {
    let parts = operation.split(separator: " ")
    if parts[0] == "add" {
        queue.push(Task(name: String(parts[1]), priority: Int(parts[2])!, sequence: sequence))
        sequence += 1
    } else {
        let task = queue.pop()
        print("run: \(task.name) (priority \(task.priority))")
    }
}
var remaining = [String]()
while !queue.tasks.isEmpty { remaining.append(queue.pop().name) }
print("remaining: \(remaining.joined(separator: " "))")
