use crate::bitstream::{self,Reader};
use crate::schema_io::Value;
pub const METHODS: [&str;5] = ["PLAIN","DICTIONARY","RLE","DELTA_BINARY_PACKED","DELTA_LENGTH_BYTE_ARRAY"];
pub fn candidates(kind: usize) -> Vec<usize> {
    match kind {
        0 | 3 => vec![0,1,3],1 => vec![0,1,4],_ => vec![0,2]
    }
}
pub fn delta(values: &[i64]) -> Vec<u8> {
    let mut output = Vec::new();
    bitstream::unsigned(&mut output,128);
    bitstream::unsigned(&mut output,4);
    bitstream::unsigned(&mut output,values.len() as u64);
    bitstream::zigzag(&mut output,values.first().copied().unwrap_or(0));
    let deltas: Vec<_> = values.windows(2).map(|v| v[1]-v[0]).collect();
    for block in deltas.chunks(128) {
        let minimum = *block.iter().min().unwrap();
        bitstream::zigzag(&mut output,minimum);
        let mut widths = [0usize;4];
        for (i,mini) in block.chunks(32).enumerate() {
            widths[i] = bitstream::bits(mini.iter().map(|&d| (d-minimum) as u64).max().unwrap());
        }
        output.extend(widths.iter().map(|&w| w as u8));
        for (i,mini) in block.chunks(32).enumerate() {
            let mut values: Vec<_> = mini.iter().map(|&d| (d-minimum) as u64).collect();
            values.resize(32,0);
            output.extend(bitstream::pack(&values,widths[i]));
        }
    }
    output
}
pub fn decode_delta(reader: &mut Reader<'_>) -> Vec<i64> {
    reader.unsigned();
    reader.unsigned();
    let count = reader.unsigned() as usize;
    let first = reader.zigzag();
    let mut values = Vec::new();
    if count > 0 {
        values.push(first);
    }
    while values.len() < count {
        let minimum = reader.zigzag();
        let widths: Vec<_> = (0..4).map(|_| reader.byte() as usize).collect();
        for width in widths {
            if values.len() == count {
                break;
            }
            let unpacked = bitstream::unpack(reader,32,width);
            for value in unpacked.into_iter().take((count-values.len()).min(32)) {
                let next = *values.last().unwrap()+minimum+value as i64;
                values.push(next);
            }
        }
    }
    values
}
pub fn encode(values: &[Value], kind: usize, method: usize, dictionary: &[Value]) -> Vec<u8> {
    let mut output = Vec::new();
    match method {
        0 => match kind {
            0 | 3 => for value in values {
                if let Value::Number(v) = value {
                    bitstream::integer(&mut output,(*v as u64)&0xffffffff);
                }
            },1 => for value in values {
                if let Value::Text(v) = value {
                    bitstream::integer(&mut output,v.len() as u64);
                    output.extend(v.bytes());
                }
            },_ => {
                let mut values: Vec<_> = values.iter().map(|v| u64::from(*v == Value::Boolean(true))).collect();
                values.resize((values.len()+7)/8*8,0);
                output.extend(bitstream::pack(&values,1));
            }
        }, 1 => {
            let width = bitstream::bits((dictionary.len()-1) as u64);
            output.push(width as u8);
            let indices: Vec<_> = values.iter().map(|v| dictionary.iter().position(|d| d == v).unwrap() as u64).collect();
            output.extend(bitstream::hybrid(&indices,width));
        }
        2 => {
            let values: Vec<_> = values.iter().map(|v| u64::from(*v == Value::Boolean(true))).collect();
            let encoded = bitstream::hybrid(&values,1);
            bitstream::integer(&mut output,encoded.len() as u64);
            output.extend(encoded);
        }
        3 => {
            let values: Vec<_> = values.iter().map(|v| if let Value::Number(v) = v {
                *v
            } else {
                unreachable!()
            }).collect();
            output.extend(delta(&values));
        }
        _ => {
            let strings: Vec<_> = values.iter().map(|v| if let Value::Text(v) = v {
                v
            } else {
                unreachable!()
            }).collect();
            output.extend(delta(&strings.iter().map(|s| s.len() as i64).collect::<Vec<_>>()));
            for string in strings {
                output.extend(string.bytes());
            }
        }
    }
    output
}
pub fn decode(reader: &mut Reader<'_>, count: usize, kind: usize, method: usize, dictionary: &[Value]) -> Vec<Value> {
    match method {
        0 => match kind {
            0 | 3 => (0..count).map(|_| Value::Number(reader.signed())).collect(),1 => (0..count).map(|_| {
                let length = reader.integer() as usize;
                Value::Text(String::from_utf8(reader.take(length).to_vec()).unwrap())
            }).collect(),_ => bitstream::unpack(reader,(count+7)/8*8,1).into_iter().take(count).map(|v| Value::Boolean(v == 1)).collect()
        }, 1 => {
            let width = reader.byte() as usize;
            bitstream::decode_hybrid(reader,count,width).into_iter().map(|i| dictionary[i as usize].clone()).collect()
        }
        2 => {
            reader.integer();
            bitstream::decode_hybrid(reader,count,1).into_iter().map(|v| Value::Boolean(v == 1)).collect()
        }
        3 => decode_delta(reader).into_iter().map(Value::Number).collect(), _ => {
            let lengths = decode_delta(reader);
            lengths.into_iter().map(|length| Value::Text(String::from_utf8(reader.take(length as usize).to_vec()).unwrap())).collect()
        }
    }
}
pub fn write_stat(output: &mut Vec<u8>, value: &Value, kind: usize) {
    match kind {
        0 | 3 => if let Value::Number(v) = value {
            bitstream::zigzag(output,*v);
        },1 => if let Value::Text(v) = value {
            bitstream::unsigned(output,v.len() as u64);
            output.extend(v.bytes());
        },_ => output.push(u8::from(*value == Value::Boolean(true)))
    }
}
pub fn read_stat(reader: &mut Reader<'_>, kind: usize) -> Value {
    match kind {
        0 | 3 => Value::Number(reader.zigzag()),1 => {
            let length = reader.unsigned() as usize;
            Value::Text(String::from_utf8(reader.take(length).to_vec()).unwrap())
        },_ => Value::Boolean(reader.byte() == 1)
    }
}
