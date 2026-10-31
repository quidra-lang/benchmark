package main

import (
    "fmt"
    "sort"
    "strings"
)

type Repetition struct {
    Text string
    Positions []int
    Gaps []int
    GCD int
}

type KasiskiData struct {
    Repeats []Repetition
    Gaps []int
}

func (k KasiskiData) Count(period int) int {
    result := 0
    for _, gap := range k.Gaps {
        if gap%period == 0 {
            result++
        }
    }
    return result
}

func frequency(text string) []int {
    counts := make([]int, 26)
    for i := 0; i < len(text); i++ {
        counts[int(text[i]-'A')]++
    }
    return counts
}

func ioc(text string) int {
    if len(text) < 2 {
        return 0
    }
    sum := int64(0)
    for _, count := range frequency(text) {
        sum += int64(count) * int64(count-1)
    }
    return int(100000*sum / int64(len(text)*(len(text)-1)))
}

func column(text string, period, position int) string {
    var out strings.Builder
    for i := position; i < len(text); i += period {
        out.WriteByte(text[i])
    }
    return out.String()
}

func columnIocs(text string, period int) []int {
    result := make([]int, period)
    for i := 0; i < period; i++ {
        result[i] = ioc(column(text, period, i))
    }
    return result
}

func averageIoc(text string, period int) int {
    total := 0
    for _, value := range columnIocs(text, period) {
        total += value
    }
    return total/period
}

func gcd(a, b int) int {
    for b != 0 {
        a, b = b, a%b
    }
    return a
}

func kasiski(text string) KasiskiData {
    positions := map[string][]int{}
    for i := 0; i+2 < len(text); i++ {
        key := text[i:i+3]
        positions[key] = append(positions[key], i+1)
    }
    keys := make([]string, 0, len(positions))
    for key := range positions {
        keys = append(keys, key)
    }
    sort.Strings(keys)
    result := KasiskiData{Repeats: []Repetition{}, Gaps: []int{}}
    for _, key := range keys {
        points := positions[key]
        if len(points) < 2 {
            continue
        }
        gaps := make([]int, 0, len(points)-1)
        divisor := 0
        for i := 1; i < len(points); i++ {
            gap := points[i]-points[i-1]
            gaps = append(gaps, gap)
            divisor = gcd(divisor, gap)
        }
        result.Gaps = append(result.Gaps, gaps...)
        result.Repeats = append(result.Repeats, Repetition{
            Text: key, Positions: points, Gaps: gaps, GCD: divisor,
        })
    }
    return result
}

func numbers(values []int) string {
    parts := make([]string, len(values))
    for i, value := range values {
        parts[i] = fmt.Sprint(value)
    }
    return strings.Join(parts, ",")
}

func periodTable(text string, limit int, data KasiskiData) []string {
    result := []string{}
    for period := 1; period <= limit; period++ {
        columns := columnIocs(text, period)
        total := 0
        for _, value := range columns {
            total += value
        }
        result = append(result, fmt.Sprintf("L=%d ioc=%d kasiski=%d cols=%s",
            period, total/period, data.Count(period), numbers(columns)))
    }
    return result
}

func kasiskiTable(data KasiskiData) []string {
    result := []string{fmt.Sprintf("kasiski repeats=%d spacings=%d",
        len(data.Repeats), len(data.Gaps))}
    for _, item := range data.Repeats {
        result = append(result, fmt.Sprintf("%s at=%s gaps=%s gcd=%d",
            item.Text, numbers(item.Positions), numbers(item.Gaps), item.GCD))
    }
    return result
}

func topPairs(text string, digraphs bool) string {
    counts := map[string]int{}
    step := 1
    if digraphs {
        step = 2
    }
    for i := 0; i+1 < len(text); i += step {
        counts[text[i:i+2]]++
    }
    keys := make([]string, 0, len(counts))
    for key := range counts {
        keys = append(keys, key)
    }
    sort.Slice(keys, func(i, j int) bool {
        if counts[keys[i]] != counts[keys[j]] {
            return counts[keys[i]] > counts[keys[j]]
        }
        return keys[i] < keys[j]
    })
    if len(keys) > 10 {
        keys = keys[:10]
    }
    pairs := make([]string, 0, len(keys))
    for _, key := range keys {
        pairs = append(pairs, fmt.Sprintf("%s:%d", key, counts[key]))
    }
    return strings.Join(pairs, " ")
}

func percentage(count, total int) string {
    tenths := (2000*count + total) / (2*total)
    return fmt.Sprintf("%d.%d", tenths/10, tenths%10)
}

func analyze(job int, source, text string, weights Weights, maxlen int) []string {
    data := kasiski(text)
    counts := frequency(text)
    doubles, pairDoubles, distinct := 0, 0, 0
    for _, count := range counts {
        if count != 0 {
            distinct++
        }
    }
    for i := 0; i+1 < len(text); i++ {
        if text[i] == text[i+1] {
            doubles++
            if i%2 == 0 {
                pairDoubles++
            }
        }
    }
    result := []string{
        fmt.Sprintf("JOB %d ANALYZE source=%s", job, source),
        fmt.Sprintf("letters=%d", len(text)),
        fmt.Sprintf("ioc=%d mono=%d bigram=%d", ioc(text),
            monogram(text, weights.Mono), bigram(text, weights.Bi)),
        fmt.Sprintf("doubles=%d pair_doubles=%d distinct=%d",
            doubles, pairDoubles, distinct),
    }
    for i := 0; i < 26; i++ {
        result = append(result, fmt.Sprintf("%c %d %s",
            uppercase(i), counts[i], percentage(counts[i], len(text))))
    }
    result = append(result, "bigrams "+topPairs(text, false))
    result = append(result, periodTable(text, maxlen, data)...)
    result = append(result, kasiskiTable(data)...)
    return result
}
