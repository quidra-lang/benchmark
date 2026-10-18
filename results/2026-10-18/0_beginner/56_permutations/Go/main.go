package main

import (
	"fmt"
)

func search(p[]byte, used[4]bool, count * int) {
	if len(p) == 4 {
		(*count)++;
		fmt.Printf("%d: %s\n", *count, p);
		return
	};
	for i := 0; i < 4; i++ {
		if ! used[i] {
			used[i] = true;
			search(append(p, byte('A' + i)), used, count);
			used[i] = false
		}
	}
}

func main() {
	search(nil, [4]bool{}, new(int))
}
