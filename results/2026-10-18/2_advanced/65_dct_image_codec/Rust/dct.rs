pub fn zigzag() -> Vec<usize> {
    let mut order: Vec<_> = (0..64).collect();
    order.sort_by_key(|&p| { let (u, v) = (p/8, p%8); (u+v, if (u+v)%2 == 1 { u } else { 7-u }) });
    order
}

fn round(value: i64, shift: usize) -> i64 { (value+(1i64<<(shift-1))).div_euclid(1i64<<shift) }

pub fn transform(input: &[i64; 64], c: &[[i64; 8]; 8]) -> [i64; 64] {
    let mut e = [[0; 8]; 8];
    for u in 0..8 { for x in 0..8 { e[u][x] = round((0..8).map(|y| c[u][y]*input[y*8+x]).sum(), 11); } }
    let mut result = [0; 64];
    for u in 0..8 { for v in 0..8 { result[u*8+v] = round((0..8).map(|x| e[u][x]*c[v][x]).sum(), 15); } }
    result
}

pub fn inverse(input: &[i64; 64], c: &[[i64; 8]; 8]) -> [i64; 64] {
    let mut s = [[0; 8]; 8];
    for y in 0..8 { for v in 0..8 { s[y][v] = round((0..8).map(|u| c[u][y]*input[u*8+v]).sum(), 11); } }
    let mut result = [0; 64];
    for y in 0..8 { for x in 0..8 { result[y*8+x] = (round((0..8).map(|v| s[y][v]*c[v][x]).sum(), 15)+128).clamp(0, 255); } }
    result
}

pub fn quantization(basic: &[[i64; 64]; 2], quality: usize) -> [[i64; 64]; 2] {
    let scale = if quality < 50 { 5000/quality as i64 } else { 200-2*quality as i64 };
    let mut tables = [[0; 64]; 2];
    for t in 0..2 { for p in 0..64 { tables[t][p] = ((basic[t][p]*scale+50)/100).clamp(1, 255); } }
    tables
}

pub fn quantize(value: i64, q: i64) -> i64 {
    let a = (value.abs()+q/2)/q;
    if value < 0 { -a } else { a }
}

pub fn dequantize(sequence: &[i64; 64], table: &[i64; 64], keep: usize) -> [i64; 64] {
    let mut result = [0; 64];
    for (k, p) in zigzag().into_iter().enumerate().take(keep) { result[p] = sequence[k]*table[p]; }
    result
}
