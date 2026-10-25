package main

import (
    "fmt"
    "os"
    "regexp"
    "sort"
    "strconv"
    "strings"
)

var commands = []string{"ENCRYPT", "DECRYPT", "BREAK", "ANALYZE", "COMPARE", "IDENTIFY"}
var allCiphers = []string{"caesar", "affine", "vigenere", "autokey", "railfence", "columnar", "playfair"}
var affineMultipliers = []int{1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25}

type Candidate struct {
    Key string
    Plain string
    Score int
    Order int
}

type BreakOutcome struct {
    Ranked []Candidate
    Choice Candidate
    Length int
    Method string
    Passes int
    Changes int
    Kasiski KasiskiData
}

type OptionRule struct {
    Min int
    Max int
    Default int
}

type Benchmark struct {
    Messages map[string][]string
    Totals map[string]*[2]int
    Results []string
    Candidates []string
    Analysis []string
    Weights Weights
}

func NewBenchmark() *Benchmark {
    b := &Benchmark{
        Messages: map[string][]string{},
        Totals: map[string]*[2]int{},
        Results: []string{},
        Candidates: []string{},
        Analysis: []string{},
        Weights: readWeights("input/weights.txt"),
    }
    for _, command := range commands {
        b.Totals[command] = &[2]int{}
    }
    b.readMessages("input/messages.txt")
    return b
}

func inputLines(path string) []string {
    data, err := os.ReadFile(path)
    if err != nil {
        panic(err)
    }
    text := string(data)
    if text == "" {
        return []string{}
    }
    return strings.Split(strings.TrimSuffix(text, "\n"), "\n")
}

func (b *Benchmark) readMessages(path string) {
    current := ""
    lines := []string{}
    for _, line := range inputLines(path) {
        if current == "" {
            if line == "" {
                continue
            }
            current = strings.TrimPrefix(line, "MESSAGE ")
            lines = []string{}
        } else if line == "END" {
            b.Messages[current] = lines
            current = ""
        } else {
            lines = append(lines, line)
        }
    }
}

func (b *Benchmark) body(name string) string {
    return strings.Join(b.Messages[name], "\n")
}

func (b *Benchmark) messageLetters(name string) string {
    return letters(b.body(name))
}

func contain(values []string, needle string) bool {
    for _, value := range values {
        if value == needle {
            return true
        }
    }
    return false
}

func validName(text string) bool {
    return regexp.MustCompile("^[a-z0-9_]{1,16}$").MatchString(text)
}

func digits(text string, length int) bool {
    return regexp.MustCompile(fmt.Sprintf("^[0-9]{1,%d}$", length)).MatchString(text)
}

func substitution(cipher string) bool {
    return contain([]string{"caesar", "affine", "vigenere", "autokey"}, cipher)
}

func normalizeKey(cipher, key string) (string, error) {
    if cipher == "caesar" || cipher == "railfence" {
        if !digits(key, 2) {
            return "", fmt.Errorf("bad key %s", key)
        }
        value, _ := strconv.Atoi(key)
        if cipher == "caesar" && value > 25 || cipher == "railfence" && (value < 2 || value > 20) {
            return "", fmt.Errorf("bad key %s", key)
        }
        return strconv.Itoa(value), nil
    }
    if cipher == "affine" {
        parts := strings.Split(key, ",")
        if len(parts) != 2 || !digits(parts[0], 2) || !digits(parts[1], 2) {
            return "", fmt.Errorf("bad key %s", key)
        }
        a, _ := strconv.Atoi(parts[0])
        c, _ := strconv.Atoi(parts[1])
        allowed := false
        for _, value := range affineMultipliers {
            if value == a {
                allowed = true
                break
            }
        }
        if !allowed || c > 25 {
            return "", fmt.Errorf("bad key %s", key)
        }
        return fmt.Sprintf("%d,%d", a, c), nil
    }
    pattern := ""
    switch cipher {
    case "vigenere", "autokey":
        pattern = "^[A-Za-z]{1,20}$"
    case "playfair":
        pattern = "^[A-Za-z]{1,25}$"
    case "columnar":
        pattern = "^[A-Za-z0-9]{2,9}$"
    }
    if !regexp.MustCompile(pattern).MatchString(key) {
        return "", fmt.Errorf("bad key %s", key)
    }
    key = strings.ToUpper(key)
    if cipher == "playfair" {
        key = strings.ReplaceAll(key, "J", "I")
    }
    return key, nil
}

func optionRules(command, cipher string) map[string]OptionRule {
    rules := map[string]OptionRule{}
    if command == "ANALYZE" {
        rules["MAXLEN"] = OptionRule{2, 20, 10}
    }
    if command != "BREAK" {
        return rules
    }
    rules["TOP"] = OptionRule{1, 20, 5}
    switch cipher {
    case "vigenere":
        rules["MAXLEN"] = OptionRule{2, 20, 10}
        rules["IOC"] = OptionRule{1, 100000, 6000}
        rules["KASISKI"] = OptionRule{1, 100, 60}
        rules["REFINE"] = OptionRule{0, 10, 5}
    case "autokey":
        rules["MAXLEN"] = OptionRule{1, 20, 8}
    case "railfence":
        rules["MAXRAILS"] = OptionRule{2, 20, 10}
    case "columnar":
        rules["MAXLEN"] = OptionRule{2, 6, 6}
    }
    return rules
}

func parseOptions(command, cipher string, words []string) (map[string]string, error) {
    rules := optionRules(command, cipher)
    options := map[string]string{}
    for name, rule := range rules {
        options[name] = strconv.Itoa(rule.Default)
    }
    seen := map[string]bool{}
    for _, word := range words {
        index := strings.IndexByte(word, '=')
        name, value := "", ""
        if index >= 0 {
            name, value = word[:index], word[index+1:]
        }
        if index < 0 || seen[name] {
            return nil, fmt.Errorf("bad option %s", word)
        }
        seen[name] = true
        if name == "KEYS" && (command == "IDENTIFY" || command == "BREAK" && cipher == "playfair") {
            if !validName(value) {
                return nil, fmt.Errorf("bad option %s", word)
            }
            options[name] = value
            continue
        }
        rule, allowed := rules[name]
        if !allowed || !digits(value, 6) {
            return nil, fmt.Errorf("bad option %s", word)
        }
        number, _ := strconv.Atoi(value)
        if number < rule.Min || number > rule.Max {
            return nil, fmt.Errorf("bad option %s", word)
        }
        options[name] = strconv.Itoa(number)
    }
    if command == "BREAK" && cipher == "playfair" && options["KEYS"] == "" {
        return nil, fmt.Errorf("missing option KEYS")
    }
    return options, nil
}

func option(values map[string]string, name string) int {
    number, _ := strconv.Atoi(values[name])
    return number
}

func (b *Benchmark) decrypt(text, cipher, key string) string {
    if substitution(cipher) {
        return letters(substitute(text, cipher, key, false))
    }
    switch cipher {
    case "railfence":
        number, _ := strconv.Atoi(key)
        return railFence(text, number, false)
    case "columnar":
        return columnar(text, key, false)
    default:
        return playfair(text, key, false)
    }
}

func (b *Benchmark) transform(text, cipher, key string, encrypt bool) string {
    if substitution(cipher) {
        return substitute(text, cipher, key, encrypt)
    }
    text = letters(text)
    switch cipher {
    case "railfence":
        number, _ := strconv.Atoi(key)
        return railFence(text, number, encrypt)
    case "columnar":
        return columnar(text, key, encrypt)
    default:
        return playfair(text, key, encrypt)
    }
}

func (b *Benchmark) keyList(name string) []string {
    input := b.body(name)
    found := regexp.MustCompile("[A-Za-z]+").FindAllString(input, -1)
    keys, seen := []string{}, map[string]bool{}
    for _, original := range found {
        key := strings.ReplaceAll(strings.ToUpper(original), "J", "I")
        if !seen[key] {
            seen[key] = true
            keys = append(keys, key)
        }
    }
    return keys
}

func permutations(length int) []string {
    letters := make([]byte, length)
    for i := range letters {
        letters[i] = byte('1' + i)
    }
    result := []string{}
    var visit func(int)
    visit = func(index int) {
        if index == length {
            result = append(result, string(letters))
            return
        }
        for i := index; i < length; i++ {
            letters[index], letters[i] = letters[i], letters[index]
            visit(index + 1)
            letters[index], letters[i] = letters[i], letters[index]
        }
    }
    visit(0)
    sort.Strings(result)
    return result
}

func (b *Benchmark) columnKey(text string, length int, autokey bool) string {
    key := make([]byte, length)
    for col := 0; col < length; col++ {
        segment := column(text, length, col)
        best, high := 0, -1
        for guess := 0; guess < 26; guess++ {
            score := 0
            if !autokey {
                plaintext := substitute(segment, "caesar", strconv.Itoa(guess), false)
                score = monogram(plaintext, b.Weights.Mono)
            } else {
                previous := guess
                for i := 0; i < len(segment); i++ {
                    previous = modulo(letterValue(segment[i])-previous, 26)
                    score += b.Weights.Mono[previous]
                }
            }
            if score > high {
                best, high = guess, score
            }
        }
        key[col] = uppercase(best)
    }
    return string(key)
}

func (b *Benchmark) candidateKeys(cipher, text string,
    options map[string]string, keys []string) []string {
    result := []string{}
    switch cipher {
    case "caesar":
        for i := 0; i < 26; i++ {
            result = append(result, strconv.Itoa(i))
        }
    case "affine":
        for _, a := range affineMultipliers {
            for c := 0; c < 26; c++ {
                result = append(result, fmt.Sprintf("%d,%d", a, c))
            }
        }
    case "railfence":
        for i := 2; i <= option(options, "MAXRAILS"); i++ {
            result = append(result, strconv.Itoa(i))
        }
    case "columnar":
        for i := 2; i <= option(options, "MAXLEN"); i++ {
            result = append(result, permutations(i)...)
        }
    case "playfair":
        result = append(result, keys...)
    default:
        for i := 1; i <= option(options, "MAXLEN"); i++ {
            result = append(result, b.columnKey(text, i, cipher == "autokey"))
        }
    }
    return result
}

func (b *Benchmark) score(cipher, text string) int {
    if cipher == "caesar" || cipher == "affine" {
        return monogram(text, b.Weights.Mono)
    }
    return bigram(text, b.Weights.Bi)
}

func (b *Benchmark) breakCipher(cipher, text string,
    opts map[string]string, keys []string) BreakOutcome {
    raw := []Candidate{}
    for _, key := range b.candidateKeys(cipher, text, opts, keys) {
        plain := b.decrypt(text, cipher, key)
        raw = append(raw, Candidate{key, plain, b.score(cipher, plain), len(raw)})
    }
    ranked := append([]Candidate{}, raw...)
    sort.Slice(ranked, func(i, j int) bool {
        if ranked[i].Score != ranked[j].Score {
            return ranked[i].Score > ranked[j].Score
        }
        return ranked[i].Order < ranked[j].Order
    })
    if cipher != "vigenere" {
        return BreakOutcome{Ranked: ranked, Choice: ranked[0]}
    }
    maxlen, threshold := option(opts, "MAXLEN"), option(opts, "IOC")
    data := kasiski(text)
    averages := make([]int, maxlen)
    for length := 1; length <= maxlen; length++ {
        averages[length-1] = averageIoc(text, length)
    }
    kasiskiLength := 0
    for length := 2; length <= maxlen; length++ {
        if len(data.Gaps) > 0 && 100*data.Count(length) >= option(opts, "KASISKI")*len(data.Gaps) {
            kasiskiLength = length
        }
    }
    chosen, method := 0, ""
    if kasiskiLength != 0 && averages[kasiskiLength-1] >= threshold {
        chosen, method = kasiskiLength, "kasiski"
    } else {
        for length := 1; length <= maxlen; length++ {
            if averages[length-1] >= threshold {
                chosen = length
                break
            }
        }
        if chosen != 0 {
            method = "ioc"
        } else {
            chosen, method = 1, "maxioc"
            for length := 2; length <= maxlen; length++ {
                if averages[length-1] > averages[chosen-1] {
                    chosen = length
                }
            }
        }
    }
    key := raw[chosen-1].Key
    reference, passes, changes := b.score(cipher, b.decrypt(text, cipher, key)), 0, 0
    for attempt := 0; attempt < option(opts, "REFINE"); attempt++ {
        passes++
        changed := 0
        for position := 0; position < len(key); position++ {
            winner, high := key[position], reference
            for value := 0; value < 26; value++ {
                trial := key[:position]+string(uppercase(value))+key[position+1:]
                current := b.score(cipher, b.decrypt(text, cipher, trial))
                if current > high {
                    winner, high = uppercase(value), current
                }
            }
            if high > reference {
                key = key[:position]+string(winner)+key[position+1:]
                reference = high
                changes++
                changed++
            }
        }
        if changed == 0 {
            break
        }
    }
    choice := Candidate{key, b.decrypt(text, cipher, key), reference, -1}
    return BreakOutcome{Ranked: ranked, Choice: choice, Length: chosen, Method: method,
        Passes: passes, Changes: changes, Kasiski: data}
}

func (b *Benchmark) candidateReport(job int, cipher, source string,
    broken BreakOutcome, top int) {
    count, margin := len(broken.Ranked), 0
    if count >= 2 {
        margin = broken.Ranked[0].Score-broken.Ranked[1].Score
    }
    b.Candidates = append(b.Candidates, fmt.Sprintf(
        "JOB %d BREAK %s source=%s tried=%d margin=%d", job, cipher, source, count, margin))
    for index, candidate := range broken.Ranked {
        if index >= top {
            break
        }
        preview := candidate.Plain
        if len(preview) > 40 {
            preview = preview[:40]
        }
        b.Candidates = append(b.Candidates, fmt.Sprintf(
            "%d %s %d %s", index+1, candidate.Key, candidate.Score, preview))
    }
}

func (b *Benchmark) breakAnalysis(job int, cipher, source, text string,
    opts map[string]string, broken BreakOutcome) {
    if cipher == "vigenere" {
        b.Analysis = append(b.Analysis,
            fmt.Sprintf("JOB %d BREAK vigenere source=%s", job, source),
            fmt.Sprintf("letters=%d", len(text)))
        b.Analysis = append(b.Analysis, periodTable(text, option(opts, "MAXLEN"), broken.Kasiski)...)
        b.Analysis = append(b.Analysis, kasiskiTable(broken.Kasiski)...)
        b.Analysis = append(b.Analysis,
            fmt.Sprintf("decision length=%d method=%s", broken.Length, broken.Method),
            fmt.Sprintf("refine passes=%d changes=%d key=%s",
                broken.Passes, broken.Changes, broken.Choice.Key))
    } else if cipher == "playfair" {
        text = strings.ReplaceAll(text, "J", "I")
        unique := map[string]bool{}
        for i := 0; i < len(text); i += 2 {
            unique[text[i:i+2]] = true
        }
        board := square(broken.Choice.Key)
        rows := []string{}
        for i := 0; i < 5; i++ {
            rows = append(rows, board[i*5:i*5+5])
        }
        b.Analysis = append(b.Analysis,
            fmt.Sprintf("JOB %d BREAK playfair source=%s", job, source),
            fmt.Sprintf("letters=%d", len(text)),
            fmt.Sprintf("digraphs pairs=%d distinct=%d", len(text)/2, len(unique)),
            "top "+topPairs(text, true),
            "square "+strings.Join(rows, " "))
    }
}

func (b *Benchmark) outputText(source, cipher, key string, encrypt bool) []string {
    result := b.transform(source, cipher, key, encrypt)
    if substitution(cipher) {
        return strings.Split(result, "\n")
    }
    return groups(result)
}

func (b *Benchmark) save(target string, lines []string) {
    if target != "" {
        b.Messages[target] = append([]string{}, lines...)
    }
}

func (b *Benchmark) cipherJob(job int, command, cipher, key, source, target string) error {
    text := b.messageLetters(source)
    if text == "" {
        return fmt.Errorf("no letters")
    }
    if command == "DECRYPT" && cipher == "playfair" && !validPlayfair(text) {
        return fmt.Errorf("bad playfair text")
    }
    output := b.outputText(b.body(source), cipher, key, command == "ENCRYPT")
    count := 0
    for _, line := range output {
        count += len(letters(line))
    }
    heading := fmt.Sprintf("JOB %d %s %s key=%s source=%s letters=%d lines=%d",
        job, command, cipher, key, source, count, len(output))
    if target != "" {
        heading += " as="+target
    }
    b.Results = append(b.Results, heading)
    b.Results = append(b.Results, output...)
    b.save(target, output)
    return nil
}

func (b *Benchmark) breakJob(job int, cipher, source, target string,
    opts map[string]string) error {
    text := b.messageLetters(source)
    if len(text) < 40 {
        return fmt.Errorf("text too short")
    }
    if cipher == "playfair" && !validPlayfair(text) {
        return fmt.Errorf("bad playfair text")
    }
    var keys []string
    if cipher == "playfair" {
        keys = b.keyList(opts["KEYS"])
        if len(keys) == 0 {
            return fmt.Errorf("empty key list")
        }
    }
    broken := b.breakCipher(cipher, text, opts, keys)
    output := b.outputText(b.body(source), cipher, broken.Choice.Key, false)
    heading := fmt.Sprintf("JOB %d BREAK %s source=%s key=%s score=%d lines=%d",
        job, cipher, source, broken.Choice.Key, broken.Choice.Score, len(output))
    if target != "" {
        heading += " as="+target
    }
    b.Results = append(b.Results, heading)
    b.Results = append(b.Results, output...)
    b.candidateReport(job, cipher, source, broken, option(opts, "TOP"))
    b.breakAnalysis(job, cipher, source, text, opts, broken)
    b.save(target, output)
    return nil
}

func (b *Benchmark) analyzeJob(job int, source string, opts map[string]string) error {
    text := b.messageLetters(source)
    if len(text) < 40 {
        return fmt.Errorf("text too short")
    }
    b.Results = append(b.Results,
        fmt.Sprintf("JOB %d ANALYZE source=%s letters=%d", job, source, len(text)))
    b.Analysis = append(b.Analysis, analyze(job, source, text, b.Weights, option(opts, "MAXLEN"))...)
    return nil
}

func (b *Benchmark) compareJob(job int, leftName, rightName string) {
    left, right := b.messageLetters(leftName), b.messageLetters(rightName)
    length := len(left)
    if len(right) < length {
        length = len(right)
    }
    first, mismatches := length+1, 0
    for i := 0; i < length; i++ {
        if left[i] != right[i] {
            if mismatches == 0 {
                first = i+1
            }
            mismatches++
        }
    }
    if left == right {
        b.Results = append(b.Results, fmt.Sprintf(
            "JOB %d COMPARE %s %s equal letters=%d", job, leftName, rightName, len(left)))
    } else {
        b.Results = append(b.Results, fmt.Sprintf(
            "JOB %d COMPARE %s %s differ letters=%d,%d first=%d mismatches=%d",
            job, leftName, rightName, len(left), len(right), first, mismatches))
    }
}

func (b *Benchmark) identifyJob(job int, source string, opts map[string]string) error {
    text := b.messageLetters(source)
    if len(text) < 40 {
        return fmt.Errorf("text too short")
    }
    coincidence, mean := ioc(text), monogram(text, b.Weights.Mono)/len(text)
    distinct := 0
    for _, count := range frequency(text) {
        if count != 0 {
            distinct++
        }
    }
    shape := !strings.Contains(text, "J") && validPlayfair(text)
    family := ""
    if shape {
        family = "playfair"
    } else if coincidence >= 5500 && mean >= 44 {
        family = "transposition"
    } else if coincidence >= 5500 {
        family = "monoalphabetic"
    } else {
        family = "polyalphabetic"
    }
    var keys []string
    if family == "playfair" && opts["KEYS"] != "" {
        keys = b.keyList(opts["KEYS"])
        if len(keys) == 0 {
            return fmt.Errorf("empty key list")
        }
    }
    cipherNames := []string{}
    switch family {
    case "transposition":
        cipherNames = []string{"railfence", "columnar"}
    case "monoalphabetic":
        cipherNames = []string{"affine"}
    case "polyalphabetic":
        cipherNames = []string{"vigenere", "autokey"}
    case "playfair":
        if opts["KEYS"] != "" {
            cipherNames = []string{"playfair"}
        }
    }
    type Trial struct {
        Cipher string
        Choice Candidate
    }
    trials := []Trial{}
    var best *Trial
    for _, cipher := range cipherNames {
        raw := []string{}
        if cipher == "playfair" {
            raw = []string{"KEYS="+opts["KEYS"]}
        }
        defaults, err := parseOptions("BREAK", cipher, raw)
        if err != nil {
            return err
        }
        trial := Trial{cipher, b.breakCipher(cipher, text, defaults, keys).Choice}
        trials = append(trials, trial)
        if best == nil || trial.Choice.Score > best.Choice.Score {
            copy := trial
            best = &copy
        }
    }
    heading := fmt.Sprintf("JOB %d IDENTIFY source=%s family=%s", job, source, family)
    reported := ""
    if best != nil {
        reported, key := best.Cipher, best.Choice.Key
        if reported == "affine" {
            pair := strings.Split(key, ",")
            if pair[0] == "1" {
                reported, key = "caesar", pair[1]
            }
        }
        output := b.outputText(b.body(source), reported, key, false)
        heading += fmt.Sprintf(" cipher=%s key=%s score=%d lines=%d",
            reported, key, best.Choice.Score, len(output))
        b.Results = append(b.Results, heading)
        b.Results = append(b.Results, output...)
    } else {
        b.Results = append(b.Results, heading)
    }
    shapeText := "no"
    if shape {
        shapeText = "yes"
    }
    b.Analysis = append(b.Analysis, fmt.Sprintf("JOB %d IDENTIFY source=%s", job, source),
        fmt.Sprintf("letters=%d ioc=%d mono_avg=%d distinct=%d shape=%s",
            len(text), coincidence, mean, distinct, shapeText),
        "family="+family)
    for _, trial := range trials {
        b.Analysis = append(b.Analysis,
            fmt.Sprintf("try %s key=%s score=%d",
                trial.Cipher, trial.Choice.Key, trial.Choice.Score))
    }
    if best != nil {
        b.Analysis = append(b.Analysis, "choice "+reported)
    }
    return nil
}

func (b *Benchmark) execute(job int, line string) error {
    words := strings.Split(line, " ")
    command := words[0]
    if !contain(commands, command) {
        return fmt.Errorf("unknown command")
    }
    target := ""
    if contain([]string{"ENCRYPT", "DECRYPT", "BREAK"}, command) &&
        len(words) >= 5 && words[len(words)-2] == "AS" {
        target = words[len(words)-1]
        words = words[:len(words)-2]
        if !validName(target) {
            return fmt.Errorf("bad syntax")
        }
    }
    syntax := false
    switch command {
    case "ENCRYPT", "DECRYPT":
        syntax = len(words) == 4
    case "BREAK":
        syntax = len(words) >= 3
    case "ANALYZE", "IDENTIFY":
        syntax = len(words) == 2 || len(words) == 3
    case "COMPARE":
        syntax = len(words) == 3
    }
    if !syntax {
        return fmt.Errorf("bad syntax")
    }
    cipher := ""
    if contain([]string{"ENCRYPT", "DECRYPT", "BREAK"}, command) {
        cipher = words[1]
        if !contain(allCiphers, cipher) {
            return fmt.Errorf("unknown cipher %s", cipher)
        }
    }
    key := ""
    if command == "ENCRYPT" || command == "DECRYPT" {
        var err error
        key, err = normalizeKey(cipher, words[2])
        if err != nil {
            return err
        }
    }
    optionsStart := len(words)
    if command == "BREAK" {
        optionsStart = 3
    } else if command == "ANALYZE" || command == "IDENTIFY" {
        optionsStart = 2
    }
    opts, err := parseOptions(command, cipher, words[optionsStart:])
    if err != nil {
        return err
    }
    source := words[1]
    if command == "ENCRYPT" || command == "DECRYPT" {
        source = words[3]
    } else if command == "BREAK" {
        source = words[2]
    }
    if _, found := b.Messages[source]; !found {
        return fmt.Errorf("unknown message %s", source)
    }
    if keys, exists := opts["KEYS"]; exists {
        if _, found := b.Messages[keys]; !found {
            return fmt.Errorf("unknown message %s", keys)
        }
    }
    if command == "COMPARE" {
        if _, found := b.Messages[words[2]]; !found {
            return fmt.Errorf("unknown message %s", words[2])
        }
    }
    if target != "" {
        if _, found := b.Messages[target]; found {
            return fmt.Errorf("duplicate message %s", target)
        }
    }
    switch command {
    case "ENCRYPT", "DECRYPT":
        return b.cipherJob(job, command, cipher, key, words[3], target)
    case "BREAK":
        return b.breakJob(job, cipher, words[2], target, opts)
    case "ANALYZE":
        return b.analyzeJob(job, words[1], opts)
    case "COMPARE":
        b.compareJob(job, words[1], words[2])
    case "IDENTIFY":
        return b.identifyJob(job, words[1], opts)
    }
    return nil
}

func (b *Benchmark) runJobs(path string) {
    jobs, ok, errors := 0, 0, 0
    for _, line := range inputLines(path) {
        if line == "" || strings.HasPrefix(line, "#") {
            continue
        }
        jobs++
        command := strings.Split(line, " ")[0]
        err := b.execute(jobs, line)
        if err == nil {
            ok++
            if _, found := b.Totals[command]; found {
                b.Totals[command][0]++
            }
        } else {
            errors++
            if _, found := b.Totals[command]; found {
                b.Totals[command][1]++
            }
            b.Results = append(b.Results, fmt.Sprintf("JOB %d ERROR %s", jobs, err.Error()))
        }
    }
    for _, command := range commands {
        counts := b.Totals[command]
        b.Results = append(b.Results, fmt.Sprintf(
            "TOTAL %s ok=%d errors=%d", command, counts[0], counts[1]))
    }
    b.Results = append(b.Results, fmt.Sprintf(
        "SUMMARY jobs=%d ok=%d errors=%d messages=%d", jobs, ok, errors, len(b.Messages)))
}

func writeFile(path string, lines []string) {
    content := ""
    if len(lines) > 0 {
        content = strings.Join(lines, "\n")+"\n"
    }
    if err := os.WriteFile(path, []byte(content), 0644); err != nil {
        panic(err)
    }
}

func main() {
    benchmark := NewBenchmark()
    benchmark.runJobs("input/jobs.txt")
    if err := os.MkdirAll("output", 0755); err != nil {
        panic(err)
    }
    writeFile("output/results.txt", benchmark.Results)
    writeFile("output/candidates.txt", benchmark.Candidates)
    writeFile("output/analysis.txt", benchmark.Analysis)
}
