pub const ALPHANUMERIC: &[u8] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
pub fn append(bits: &mut Vec<u8>, value: usize, width: usize) {
    for i in (0..width).rev() {
        bits.push(((value>>i)&1) as u8);
    }
}
pub fn read(bits: &[u8], at: &mut usize, width: usize) -> usize {
    let mut value = 0;
    for &bit in &bits[*at..*at+width] {
        value = 2*value+bit as usize;
    }
    *at += width;
    value
}
pub fn bits(codewords: &[u8]) -> Vec<u8> {
    let mut result = Vec::new();
    for &word in codewords {
        append(&mut result,word as usize,8);
    }
    result
}
pub fn codewords(bits: &[u8]) -> Vec<u8> {
    bits.chunks(8).map(|b| b.iter().fold(0,|v,&b| 2*v+b)).collect()
}
pub fn binary(value: usize, width: usize) -> String {
    format!("{:0width$b}",value,width=width)
}
pub fn hexadecimal(codewords: &[u8]) -> String {
    codewords.iter().map(|word| format!("{:02x}",word)).collect()
}
