Alphanumeric =: '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:'
write_bits =: 4 : '(x#2)#:y'
read_bits =: 4 : 0
    result =. #.x{.ReadPosition}.y
    ReadPosition =: ReadPosition+x
    result
)
from_codewords =: 3 : ',(8#2)#:y'
to_codewords =: 3 : '#.((8 intdiv~#y),8)$y'
hexadecimal =: 3 : 0
    digits =. '0123456789abcdef'
    ,digits{~(2#16)#:y
)
binary_text =: 4 : '''01''{~x write_bits y'
