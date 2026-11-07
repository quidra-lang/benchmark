package main

import (
	"fmt"
	"net/url"
	"sort"
	"strings"
)

func main() {
	queries := []string{
		"name=Alice+Smith&age=30&city=New%20York",
		"q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
		"msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
		"redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips",
	}
	for k, query := range queries {
		values := map[string][]string{}
		for _, item := range strings.Split(query, "&") {
			rawKey, rawValue, _ := strings.Cut(item, "=")
			key, _ := url.QueryUnescape(rawKey)
			value, _ := url.QueryUnescape(rawValue)
			values[key] = append(values[key], value)
		}
		keys := []string{}
		for key := range values {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		fmt.Printf("query %d:\n", k+1)
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
