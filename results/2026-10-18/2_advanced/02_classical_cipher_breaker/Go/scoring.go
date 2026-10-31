package main

import (
    "os"
    "strconv"
    "strings"
)

type Weights struct {
    Mono []int
    Bi [][]int
}

func isLetter(c byte) bool {
    return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z'
}

func letterValue(c byte) int {
    if c >= 'a' && c <= 'z' {
        return int(c - 'a')
    }
    return int(c - 'A')
}

func uppercase(value int) byte {
    return byte('A' + value)
}

func letters(text string) string {
    var out strings.Builder
    for i := 0; i < len(text); i++ {
        c := text[i]
        if !isLetter(c) {
            continue
        }
        out.WriteByte(uppercase(letterValue(c)))
    }
    return out.String()
}

func groups(text string) []string {
    result := []string{}
    batch := []string{}
    for i := 0; i < len(text); i += 5 {
        end := i + 5
        if end > len(text) {
            end = len(text)
        }
        batch = append(batch, text[i:end])
        if len(batch) == 10 {
            result = append(result, strings.Join(batch, " "))
            batch = []string{}
        }
    }
    if len(batch) > 0 {
        result = append(result, strings.Join(batch, " "))
    }
    return result
}

func monogram(text string, weights []int) int {
    result := 0
    for i := 0; i < len(text); i++ {
        result += weights[int(text[i] - 'A')]
    }
    return result
}

func bigram(text string, weights [][]int) int {
    result := 0
    for i := 1; i < len(text); i++ {
        result += weights[int(text[i - 1] - 'A')][int(text[i] - 'A')]
    }
    return result
}

func readWeights(path string) Weights {
    data, err := os.ReadFile(path)
    if err != nil {
        panic(err)
    }
    lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
    parse := func(line string) []int {
        fields := strings.Split(line, " ")
        values := make([]int, len(fields))
        for i, word := range fields {
            value, err := strconv.Atoi(word)
            if err != nil {
                panic(err)
            }
            values[i] = value
        }
        return values
    }
    result := Weights{Mono: parse(lines[1]), Bi: make([][]int, 26)}
    for i := 0; i < 26; i++ {
        result.Bi[i] = parse(lines[i + 3])
    }
    return result
}
