package main

import (
    "strconv"
    "strings"
)

func modulo(value int, modulus int) int {
    return (value%modulus + modulus) % modulus
}

func inverse(a int) int {
    for i := 1; i < 26; i++ {
        if (a*i)%26 == 1 {
            return i
        }
    }
    panic("noninvertible affine key")
}

func substitute(text, cipher, key string, encrypt bool) string {
    a, b := 1, 0
    if cipher == "caesar" {
        b, _ = strconv.Atoi(key)
    } else if cipher == "affine" {
        parts := strings.Split(key, ",")
        a, _ = strconv.Atoi(parts[0])
        b, _ = strconv.Atoi(parts[1])
    }
    inverseA := 1
    if cipher == "affine" {
        inverseA = inverse(a)
    }
    plain := []int{}
    var output strings.Builder
    index := 0
    for i := 0; i < len(text); i++ {
        c := text[i]
        if !isLetter(c) {
            output.WriteByte(c)
            continue
        }
        x, shift := letterValue(c), 0
        if cipher == "vigenere" {
            shift = letterValue(key[index%len(key)])
        } else if cipher == "autokey" {
            if index < len(key) {
                shift = letterValue(key[index])
            } else {
                shift = plain[index-len(key)]
            }
        }
        y := 0
        switch cipher {
        case "caesar":
            if encrypt {
                y = modulo(x+b, 26)
            } else {
                y = modulo(x-b, 26)
            }
        case "affine":
            if encrypt {
                y = modulo(a*x+b, 26)
            } else {
                y = modulo(inverseA*(x-b), 26)
            }
        case "vigenere", "autokey":
            if encrypt {
                y = modulo(x+shift, 26)
            } else {
                y = modulo(x-shift, 26)
            }
        }
        if encrypt {
            plain = append(plain, x)
        } else {
            plain = append(plain, y)
        }
        base := byte('A')
        if c >= 'a' {
            base = 'a'
        }
        output.WriteByte(base + byte(y))
        index++
    }
    return output.String()
}
