package main

import (
	"fmt"
	"strings"
	"strconv"
	"sort"
)

func decode(s string) string {
	out := []byte{}
	for i := 0; i < len(s); i++ {
		if s[i] == '+' {
			out = append(out, ' ')
		} else if s[i] == '%' {
			value, _ := strconv.ParseUint(s[i + 1: i + 3], 16, 8)
			out = append(out, byte(value))
			i += 2
		} else {
			out = append(out, s[i])
		}
	}
	return string(out)
}

func main() {
	for k, query := range []string{"name=Alice+Smith&age=30&city=New%20York", "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
		"msg=50%25+off%21&debug&lang=en&ref=&lang=ja", "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips"} {
		values := map[string][]string{}
		for _, item := range strings.Split(query, "&") {
			parts := strings.SplitN(item, "=", 2)
			key := decode(parts[0])
			value := ""
			if len(parts) > 1 {
				value = decode(parts[1])
			}
			values[key] = append(values[key], value)
		}
		keys := []string{}
		for key := range values {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		fmt.Printf("query %d:\n", k + 1)
		for _, key := range keys {
			fmt.Printf("  %s: ", key)
			for i, value := range values[key] {
				if i > 0 {
					fmt.Print(", ")
				}
				fmt.Printf("\"%s\"", value)
			}
			fmt.Println()
		}
	}
}
