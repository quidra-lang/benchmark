package main

import "strings"

func square(key string) string {
    text := strings.ReplaceAll(strings.ToUpper(key), "J", "I") + "ABCDEFGHIKLMNOPQRSTUVWXYZ"
    seen := map[byte]bool{}
    var output strings.Builder
    for i := 0; i < len(text); i++ {
        c := text[i]
        if !seen[c] {
            seen[c] = true
            output.WriteByte(c)
        }
    }
    return output.String()
}

func validPlayfair(text string) bool {
    normalized := strings.ReplaceAll(text, "J", "I")
    if len(normalized)%2 != 0 {
        return false
    }
    for i := 0; i < len(normalized); i += 2 {
        if normalized[i] == normalized[i+1] {
            return false
        }
    }
    return true
}

func preparePlayfair(text string) string {
    normalized := strings.ReplaceAll(text, "J", "I")
    var output strings.Builder
    for index := 0; index < len(normalized); {
        a := normalized[index]
        b := byte('X')
        if index+1 < len(normalized) && normalized[index+1] != a {
            b = normalized[index+1]
            index += 2
        } else {
            if a == 'X' {
                b = 'Q'
            }
            index++
        }
        output.WriteByte(a)
        output.WriteByte(b)
    }
    return output.String()
}

func playfair(text, key string, encrypt bool) string {
    board := square(key)
    input := strings.ReplaceAll(text, "J", "I")
    distance := 4
    if encrypt {
        input = preparePlayfair(text)
        distance = 1
    }
    result := make([]byte, len(input))
    for i := 0; i < len(input); i += 2 {
        a, b := strings.IndexByte(board, input[i]), strings.IndexByte(board, input[i+1])
        ar, ac := a/5, a%5
        br, bc := b/5, b%5
        if ar == br {
            ac = (ac+distance)%5
            bc = (bc+distance)%5
        } else if ac == bc {
            ar = (ar+distance)%5
            br = (br+distance)%5
        } else {
            ac, bc = bc, ac
        }
        result[i], result[i+1] = board[5*ar+ac], board[5*br+bc]
    }
    return string(result)
}
