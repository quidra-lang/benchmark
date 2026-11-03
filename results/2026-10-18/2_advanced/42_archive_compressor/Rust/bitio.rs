pub struct DecodeError {
    pub kind: &'static str,
    pub position: usize,
}

impl DecodeError {
    pub fn new(kind: &'static str, position: usize) -> Self { Self { kind, position } }
}

pub fn bits(value: usize) -> usize { if value == 0 { 0 } else { usize::BITS as usize - value.leading_zeros() as usize } }

#[derive(Default)]
pub struct Writer {
    pub bits: Vec<u8>,
}

impl Writer {
    pub fn write(&mut self, value: usize, width: usize) {
        for shift in (0..width).rev() { self.bits.push(((value >> shift) & 1) as u8); }
    }
    pub fn append(&mut self, other: &Self) { self.bits.extend_from_slice(&other.bits); }
    pub fn bytes(&self) -> Vec<u8> {
        self.bits.chunks(8).map(|chunk| chunk.iter().enumerate().fold(0, |byte, (i, &bit)| byte | (bit << (7 - i)))).collect()
    }
}

pub struct Reader<'a> {
    bytes: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    pub fn new(bytes: &'a [u8]) -> Self { Self { bytes, position: 0 } }
    pub fn read(&mut self, width: usize, output: usize) -> Result<usize, DecodeError> {
        if self.position + width > self.bytes.len() * 8 { return Err(DecodeError::new("end_of_data", output)); }
        let mut value = 0;
        for _ in 0..width { value = value * 2 + self.zero_bit(); }
        Ok(value)
    }
    pub fn zero_bit(&mut self) -> usize {
        let bit = if self.position < self.bytes.len() * 8 { usize::from((self.bytes[self.position / 8] >> (7 - self.position % 8)) & 1) } else { 0 };
        self.position += 1;
        bit
    }
}
