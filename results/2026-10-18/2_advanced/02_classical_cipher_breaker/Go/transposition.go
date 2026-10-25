package main

import (
    "sort"
    "strings"
)

func railNumber(position, rails int) int {
    cycle := 2*rails - 2
    offset := position % cycle
    if offset < cycle-offset {
        return offset
    }
    return cycle-offset
}

func railFence(text string, rails int, encrypt bool) string {
    order := make([]int, len(text))
    for i := range order {
        order[i] = i
    }
    sort.Slice(order, func(i, j int) bool {
        left, right := railNumber(order[i], rails), railNumber(order[j], rails)
        if left != right {
            return left < right
        }
        return order[i] < order[j]
    })
    result := make([]byte, len(text))
    for index, position := range order {
        if encrypt {
            result[index] = text[position]
        } else {
            result[position] = text[index]
        }
    }
    return string(result)
}

func columnOrder(key string) []int {
    order := make([]int, len(key))
    for i := range order {
        order[i] = i
    }
    sort.Slice(order, func(i, j int) bool {
        if key[order[i]] != key[order[j]] {
            return key[order[i]] < key[order[j]]
        }
        return order[i] < order[j]
    })
    return order
}

func rankString(key string) string {
    result := make([]byte, len(key))
    for rank, position := range columnOrder(key) {
        result[position] = byte('1' + rank)
    }
    return string(result)
}

func columnar(text, key string, encrypt bool) string {
    var output strings.Builder
    if encrypt {
        for _, col := range columnOrder(key) {
            for i := col; i < len(text); i += len(key) {
                output.WriteByte(text[i])
            }
        }
        return output.String()
    }
    result := make([]byte, len(text))
    position := 0
    for _, col := range columnOrder(key) {
        for i := col; i < len(text); i += len(key) {
            result[i] = text[position]
            position++
        }
    }
    return string(result)
}
