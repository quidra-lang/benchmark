pub struct Writer { pub bytes: Vec<u8>, buffer: u8, count: usize, pub padding: usize, pub stuffed: usize }

impl Writer {
    pub fn new() -> Self { Self { bytes: Vec::new(), buffer: 0, count: 0, padding: 0, stuffed: 0 } }
    pub fn write(&mut self, value: u32, length: usize) {
        for bit in (0..length).rev() {
            self.buffer = (self.buffer<<1)|((value>>bit)&1) as u8;
            self.count += 1;
            if self.count == 8 {
                self.bytes.push(self.buffer);
                if self.buffer == 255 { self.bytes.push(0); self.stuffed += 1; }
                self.count = 0; self.buffer = 0;
            }
        }
    }
    pub fn pad(&mut self) {
        while self.count != 0 { self.padding += 1; self.write(1, 1); }
    }
    pub fn marker(&mut self, number: usize) { self.pad(); self.bytes.extend([255, 0xd0+(number%8) as u8]); }
}

pub struct Reader<'a> { pub bytes: &'a [u8], pub position: usize, buffer: u8, count: usize }

impl<'a> Reader<'a> {
    pub fn new(bytes: &'a [u8], position: usize) -> Self { Self { bytes, position, buffer: 0, count: 0 } }
    pub fn clear(&mut self) { self.count = 0; }
    pub fn read(&mut self, length: usize) -> Result<u32, &'static str> {
        let mut result = 0;
        for _ in 0..length {
            if self.count == 0 {
                let b = self.bytes[self.position];
                if b == 255 {
                    if self.bytes.get(self.position+1) != Some(&0) { return Err("marker"); }
                    self.position += 2;
                } else { self.position += 1; }
                self.buffer = b; self.count = 8;
            }
            self.count -= 1;
            result = 2*result+((self.buffer>>self.count)&1) as u32;
        }
        Ok(result)
    }
    pub fn resync(&self) -> usize {
        (self.position..self.bytes.len()-1).find(|&q| self.bytes[q] == 255 &&
            ((0xd0..=0xd7).contains(&self.bytes[q+1]) || self.bytes[q+1] == 0xd9)).unwrap()
    }
}
