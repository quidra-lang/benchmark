package main

import (
	"fmt"
)

type Task struct {
	name string
	priority, order int
}

func before(a, b Task) bool {
	if a.priority != b.priority {
		return a.priority < b.priority
	}
	return a.order < b.order
}

func push(heap * []Task, task Task) {
	* heap = append(*heap, task)
	i := len(*heap) - 1
	for i > 0 {
		p := (i - 1) / 2
		if !before(task, (*heap)[p]) {
			break
		}
		(*heap)[i] = (*heap)[p]
		i = p
	}
	(*heap)[i] = task
}

func pop(heap * []Task) Task {
	result := (*heap)[0]
	last := (*heap)[len(*heap) - 1]
	* heap = (*heap)[: len(*heap) - 1]
	if len(*heap) > 0 {
		i := 0
		for 2 * i + 1 < len(*heap) {
			c := 2 * i + 1
			if c + 1 < len(*heap) && before((*heap)[c + 1], (*heap)[c]) {
				c++
			}
			if !before((*heap)[c], last) {
				break
			}
			(*heap)[i] = (*heap)[c]
			i = c
		}
		(*heap)[i] = last
	}
	return result
}

func main() {
	queue := []Task{}
	sequence := 0
	for _, operation := range []string{"add email 3", "add backup 5", "add deploy 1", "run", "add report 3",
		"add test 2", "add lint 3", "run", "run", "add cleanup 5", "add review 2", "run", "add build 1",
		"add docs 4", "run", "run"} {
		if operation == "run" {
			task := pop(&queue)
			fmt.Printf("run: %s (priority %d)\n", task.name, task.priority)
		} else {
			task := Task{order: sequence}
			fmt.Sscanf(operation, "add %s %d", &task.name, &task.priority)
			sequence++
			push(&queue, task)
		}
	}
	fmt.Print("remaining:")
	for len(queue) > 0 {
		task := pop(&queue)
		fmt.Printf(" %s", task.name)
	}
	fmt.Println()
}
