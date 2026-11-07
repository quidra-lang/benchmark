const ASCII = BitSet(0:127)
const DIGITS = BitSet(Int('0'):Int('9'))
const LOWER = BitSet(Int('a'):Int('z'))
const UPPER = BitSet(Int('A'):Int('Z'))
const WORD = union(DIGITS,LOWER,UPPER,BitSet([Int('_')]))
const SPACE = BitSet([9,10,11,12,13,32])
const STANDARD = Dict('d'=>DIGITS,'w'=>WORD,'s'=>SPACE)
is_letter(character) = Int(character) in LOWER || Int(character) in UPPER
is_digit(character) = character !== nothing && '0' <= character <= '9'
function switched(character)
    Int(character) in LOWER && return Char(Int(character)-32)
    Int(character) in UPPER && return Char(Int(character)+32)
    character
end
function escaped_set(letter)
    base = STANDARD[lowercase(letter)]
    isuppercase(letter) ? setdiff(ASCII,base) : copy(base)
end
characters_equal(a,b,flags) = a == b || ('i' in flags && is_letter(a) && switched(a) == b)
test_char(text,position,expected,flags) = position < length(text) && characters_equal(text[position+1],expected,flags)
test_any(text,position,flags) = position < length(text) && ('s' in flags || text[position+1] != '\n')
function test_class(text,position,codes,negated,flags)
    position >= length(text) && return false
    character = text[position+1]
    present = Int(character) in codes || ('i' in flags && is_letter(character) && Int(switched(character)) in codes)
    present != negated
end
is_word_at(text,position) = 0 <= position < length(text) && Int(text[position+1]) in WORD
function assertion(kind,text,position,flags)
    kind == "BOL" && return position == 0 || ('m' in flags && text[position] == '\n')
    kind == "EOL" && return position == length(text) || ('m' in flags && text[position+1] == '\n')
    edge = is_word_at(text,position-1) != is_word_at(text,position)
    kind == "WORD" ? edge : !edge
end
