package main

import (
	"fmt"
	"strings"
	"strconv"
)

func main() {
	commands := []string{"undo", "type hello world", "delete 5", "type there", "undo", "undo", "redo",
		"type friend", "redo", "delete 20", "undo", "redo", "redo", "type see you"}
	buffer := ""
	undo, redo := []string{}, []string{}
	for _, command := range commands {
		if command == "undo" {
			if len(undo) == 0 {
				fmt.Println("undo => nothing to undo")
				continue
			}
			redo = append(redo, buffer)
			buffer = undo[len(undo) - 1]
			undo = undo[: len(undo) - 1]
		} else if command == "redo" {
			if len(redo) == 0 {
				fmt.Println("redo => nothing to redo")
				continue
			}
			undo = append(undo, buffer)
			buffer = redo[len(redo) - 1]
			redo = redo[: len(redo) - 1]
		} else {
			undo = append(undo, buffer)
			redo = nil
			if strings.HasPrefix(command, "type ") {
				buffer += command[5:]
			} else {
				count, _ := strconv.Atoi(command[7:])
				buffer = buffer[: max(0, len(buffer) - count)]
			}
		}
		fmt.Printf("%s => \"%s\"\n", command, buffer)
	}
}
