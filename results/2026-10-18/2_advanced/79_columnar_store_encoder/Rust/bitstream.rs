pub struct Reader<'a> {
    pub data: &'a [u8],
    pub at: usize
}
impl<'a> Reader<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Self {
            data,
            at: 0
        }
    }
    pub fn byte(&mut self) -> u8 {
        let value = self.data[self.at];
        self.at += 1;
        value
    }
    pub fn take(&mut self, count: usize) -> &'a [u8] {
        let start = self.at;
        self.at += count;
        &self.data[start..self.at]
    }
    pub fn unsigned(&mut self) -> u64 {
        let mut result = 0;
        let mut shift = 0;
        loop {
            let byte = self.byte();
            result |= ((byte&127) as u64)<<shift;
            if byte < 128 {
                return result;
            }
            shift += 7;
        }
    }
    pub fn zigzag(&mut self) -> i64 {
        let value = self.unsigned();
        if value%2 == 0 {
            (value/2) as i64
        } else {
            -(((value+1)/2) as i64)
        }
    }
    pub fn integer(&mut self) -> u64 {
        let bytes = self.take(4);
        bytes.iter().enumerate().map(|(i,&b)| (b as u64)<<(8*i)).sum()
    }
    pub fn signed(&mut self) -> i64 {
        let value = self.integer();
        if value >= 1<<31 {
            value as i64-(1i64<<32)
        } else {
            value as i64
        }
    }
}
pub fn unsigned(output: &mut Vec<u8>, mut value: u64) {
    while value >= 128 {
        output.push((value%128) as u8+128);
        value /= 128;
    }
    output.push(value as u8);
}
pub fn zigzag(output: &mut Vec<u8>, value: i64) {
    unsigned(output,if value >= 0 {
        (2*value) as u64
    } else {
        (-2*value-1) as u64
    });
}
pub fn integer(output: &mut Vec<u8>, value: u64) {
    for i in 0..4 {
        output.push(((value>>(8*i))&255) as u8);
    }
}
pub fn bits(value: u64) -> usize {
    (64-value.leading_zeros()) as usize
}
pub fn pack(values: &[u64], width: usize) -> Vec<u8> {
    let mut output = vec![0;values.len()*width/8];
    for (i,&value) in values.iter().enumerate() {
        for j in 0..width {
            let bit = i*width+j;
            output[bit/8] |= (((value>>j)&1) as u8)<<(bit%8);
        }
    }
    output
}
pub fn unpack(reader: &mut Reader<'_>, count: usize, width: usize) -> Vec<u64> {
    let bytes = reader.take(count*width/8);
    (0..count).map(|i| (0..width).fold(0,|value,j| {
        let bit = i*width+j;
        value+((((bytes[bit/8]>>(bit%8))&1) as u64)<<j)
    })).collect()
}
pub fn adler(bytes: &[u8]) -> u64 {
    let (mut a,mut b) = (1u64,0u64);
    for &byte in bytes {
        a = (a+byte as u64)%65521;
        b = (b+a)%65521;
    }
    b*65536+a
}
pub fn hybrid(values: &[u64], width: usize) -> Vec<u8> {
    let run = |i: usize| values[i..].iter().take_while(|&&v| v == values[i]).count();
    let mut output = Vec::new();
    let mut i = 0;
    while i < values.len() {
        let repeated = run(i);
        if repeated >= 8 {
            unsigned(&mut output,(2*repeated) as u64);
            for b in 0..(width+7)/8 {
                output.push(((values[i]>>(8*b))&255) as u8);
            }
            i += repeated;
        } else {
            let mut end = i;
            let mut groups = 0;
            loop {
                end += 8;
                groups += 1;
                if end >= values.len() || groups == 63 || run(end) >= 8 {
                    break;
                }
            }
            unsigned(&mut output,(2*groups+1) as u64);
            let mut packed = values[i..end.min(values.len())].to_vec();
            packed.resize(8*groups,0);
            output.extend(pack(&packed,width));
            i = end;
        }
    }
    output
}
pub fn decode_hybrid(reader: &mut Reader<'_>, count: usize, width: usize) -> Vec<u64> {
    let mut values = Vec::new();
    while values.len() < count {
        let header = reader.unsigned() as usize;
        if header%2 == 0 {
            let mut value = 0;
            for i in 0..(width+7)/8 {
                value |= (reader.byte() as u64)<<(8*i);
            }
            values.extend(std::iter::repeat(value).take(header/2));
        } else {
            values.extend(unpack(reader,8*((header-1)/2),width));
        }
    }
    values.truncate(count);
    values
}
