package main

import (
	"container/heap"
	"fmt"
)

type Task struct {
	name string
	priority, order int
}

type TaskQueue []Task

func (q TaskQueue) Len() int { return len(q) }

func (q TaskQueue) Less(i, j int) bool {
	if q[i].priority != q[j].priority {
		return q[i].priority < q[j].priority
	}
	return q[i].order < q[j].order
}

func (q TaskQueue) Swap(i, j int) { q[i], q[j] = q[j], q[i] }

func (q *TaskQueue) Push(value any) {
	*q = append(*q, value.(Task))
}

func (q *TaskQueue) Pop() any {
	last := (*q)[len(*q)-1]
	*q = (*q)[:len(*q)-1]
	return last
}

func main() {
	queue := TaskQueue{}
	sequence := 0
	for _, operation := range []string{"add email 3", "add backup 5", "add deploy 1", "run", "add report 3",
		"add test 2", "add lint 3", "run", "run", "add cleanup 5", "add review 2", "run", "add build 1",
		"add docs 4", "run", "run"} {
		if operation == "run" {
			task := heap.Pop(&queue).(Task)
			fmt.Printf("run: %s (priority %d)\n", task.name, task.priority)
		} else {
			task := Task{order: sequence}
			fmt.Sscanf(operation, "add %s %d", &task.name, &task.priority)
			sequence++
			heap.Push(&queue, task)
		}
	}
	fmt.Print("remaining:")
	for len(queue) > 0 {
		task := heap.Pop(&queue).(Task)
		fmt.Printf(" %s", task.name)
	}
	fmt.Println()
}
