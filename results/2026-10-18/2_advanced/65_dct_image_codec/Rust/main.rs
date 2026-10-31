mod image_io;
mod color;
mod dct;
mod entropy;
mod bitstream;

use std::collections::BTreeMap;
use image_io::{Image, Tables};
use color::Plane;
use entropy::Table;

#[derive(Clone)]
struct Component { identifier: usize, h: usize, v: usize, quant: usize, dc: usize, ac: usize }
#[derive(Clone)]
struct Layout { width: usize, height: usize, hmax: usize, vmax: usize, mx: usize, my: usize, restart: usize, components: Vec<Component> }
#[derive(Clone)]
struct Block { mcu: usize, component: usize, x: usize, y: usize, coefficients: [i64; 64] }

impl Layout {
    fn new(width: usize, height: usize, components: Vec<Component>, restart: usize) -> Self {
        let hmax = components.iter().map(|c| c.h).max().unwrap();
        let vmax = components.iter().map(|c| c.v).max().unwrap();
        Self { width, height, hmax, vmax, mx: (width+8*hmax-1)/(8*hmax), my: (height+8*vmax-1)/(8*vmax), restart, components }
    }
    fn encoding(image: &Image, sampling: &str, restart: usize) -> Self {
        let (h, v) = match sampling { "444" => (1, 1), "422" => (2, 1), _ => (2, 2) };
        Self::new(image.width, image.height, (0..3).map(|k| Component { identifier: k+1, h: if k == 0 { h } else { 1 },
            v: if k == 0 { v } else { 1 }, quant: usize::from(k > 0), dc: usize::from(k > 0), ac: usize::from(k > 0) }).collect(), restart)
    }
    fn factors(&self) -> Vec<(usize, usize)> { self.components.iter().map(|c| (c.h, c.v)).collect() }
    fn intervals(&self) -> Vec<(usize, usize)> {
        let count = self.mx*self.my;
        let size = if self.restart == 0 { count } else { self.restart };
        (0..count).step_by(size).map(|first| (first, size.min(count-first))).collect()
    }
    fn blocks(&self) -> Vec<Block> {
        let mut blocks = Vec::new();
        for mcu in 0..self.mx*self.my {
            for (k, c) in self.components.iter().enumerate() {
                for v in 0..c.v { for h in 0..c.h {
                    blocks.push(Block { mcu, component: k, x: c.h*(mcu%self.mx)+h, y: c.v*(mcu/self.mx)+v, coefficients: [0; 64] });
                } }
            }
        }
        blocks
    }
}

struct Symbol { table: usize, value: u8, extra: i64 }
struct Encoded {
    layout: Layout, blocks: Vec<Block>, quant: [[i64; 64]; 2], planes: Vec<Plane>, tables: Vec<Table>,
    symbols: Vec<Vec<Symbol>>, frequencies: [[usize; 256]; 4], differences: Vec<i64>, bits: Vec<usize>,
    bytes: Vec<u8>, header: usize, padding: usize, stuffed: usize, intervals: Vec<(usize, usize, usize, usize)>,
}

fn word(bytes: &mut Vec<u8>, value: usize) { bytes.extend([(value/256) as u8, (value%256) as u8]); }
fn segment(bytes: &mut Vec<u8>, marker: u8, contents: &[u8]) {
    bytes.extend([255, marker]); word(bytes, contents.len()+2); bytes.extend_from_slice(contents);
}

fn encode_coefficients(layout: Layout, blocks: Vec<Block>, quant: [[i64; 64]; 2], standard: &[Table], optimized: bool, planes: Vec<Plane>) -> Encoded {
    let mut predictor = [0; 3];
    let mut symbols = Vec::new();
    let mut differences = Vec::new();
    let mut frequencies = [[0; 256]; 4];
    let mut previous_interval = None;
    for block in &blocks {
        let interval = if layout.restart == 0 { 0 } else { block.mcu/layout.restart };
        if previous_interval != Some(interval) { predictor = [0; 3]; previous_interval = Some(interval); }
        let k = block.component;
        let dc_table = if k == 0 { 0 } else { 2 };
        let ac_table = dc_table+1;
        let difference = block.coefficients[0]-predictor[k]; predictor[k] = block.coefficients[0];
        differences.push(difference);
        let mut list = vec![Symbol { table: dc_table, value: entropy::category(difference) as u8, extra: difference }];
        let mut run = 0;
        for &value in &block.coefficients[1..] {
            if value == 0 { run += 1; continue; }
            while run >= 16 { list.push(Symbol { table: ac_table, value: 0xf0, extra: 0 }); run -= 16; }
            list.push(Symbol { table: ac_table, value: (16*run+entropy::category(value)) as u8, extra: value });
            run = 0;
        }
        if run > 0 { list.push(Symbol { table: ac_table, value: 0, extra: 0 }); }
        for symbol in &list { frequencies[symbol.table][symbol.value as usize] += 1; }
        symbols.push(list);
    }
    let tables: Vec<_> = if optimized { frequencies.iter().map(entropy::optimized).collect() } else { standard.to_vec() };
    let mut header = vec![255, 0xd8];
    let zigzag = dct::zigzag();
    let mut contents = Vec::new();
    for t in 0..2 { contents.push(t as u8); contents.extend(zigzag.iter().map(|&p| quant[t][p] as u8)); }
    segment(&mut header, 0xdb, &contents);
    let mut contents = vec![8]; word(&mut contents, layout.height); word(&mut contents, layout.width); contents.push(3);
    for (k, component) in layout.components.iter().enumerate() { contents.extend([(k+1) as u8, (16*component.h+component.v) as u8, usize::from(k > 0) as u8]); }
    segment(&mut header, 0xc0, &contents);
    let mut contents = Vec::new();
    for (i, table) in tables.iter().enumerate() {
        contents.push((16*(i%2)+i/2) as u8);
        contents.extend(table.counts.iter().map(|&n| n as u8)); contents.extend_from_slice(&table.symbols);
    }
    segment(&mut header, 0xc4, &contents);
    if layout.restart > 0 { let mut contents = Vec::new(); word(&mut contents, layout.restart); segment(&mut header, 0xdd, &contents); }
    header.extend([255, 0xda, 0, 12, 3, 1, 0, 2, 0x11, 3, 0x11, 0, 0x3f, 0]);
    let header_size = header.len();
    let mut writer = bitstream::Writer::new();
    let mut intervals = Vec::new();
    let mut bits = vec![0; blocks.len()];
    for (j, (first, count)) in layout.intervals().into_iter().enumerate() {
        if j > 0 { writer.marker(j-1); }
        let start = writer.bytes.len();
        for (i, _) in blocks.iter().enumerate().filter(|(_, b)| first <= b.mcu && b.mcu < first+count) {
            for symbol in &symbols[i] {
                let (code, length) = tables[symbol.table].codes[symbol.value as usize].unwrap();
                writer.write(code, length);
                let (extra, size) = entropy::extra(symbol.extra);
                writer.write(extra, size); bits[i] += length+size;
            }
        }
        writer.pad();
        intervals.push((first, count, header_size+start, writer.bytes.len()-start));
    }
    header.extend_from_slice(&writer.bytes); header.extend([255, 0xd9]);
    Encoded { layout, blocks, quant, planes, tables, symbols, frequencies, differences, bits,
        bytes: header, header: header_size, padding: writer.padding, stuffed: writer.stuffed, intervals }
}

fn encode(image: &Image, quality: usize, sampling: &str, optimized: bool, restart: usize, tables: &Tables) -> Encoded {
    let layout = Layout::encoding(image, sampling, restart);
    let planes = color::components(image, &layout.factors());
    let quant = dct::quantization(&tables.basic, quality);
    let mut blocks = layout.blocks();
    let zigzag = dct::zigzag();
    for block in &mut blocks {
        let plane = &planes[block.component];
        let mut input = [0; 64];
        for y in 0..8 { for x in 0..8 { input[y*8+x] = plane.pixels[(8*block.y+y)*plane.width+8*block.x+x]-128; } }
        let transformed = dct::transform(&input, &tables.dct);
        for (k, &p) in zigzag.iter().enumerate() { block.coefficients[k] = dct::quantize(transformed[p], quant[usize::from(block.component > 0)][p]); }
    }
    encode_coefficients(layout, blocks, quant, &tables.huffman, optimized, planes)
}

#[derive(Clone)]
enum IntervalState { Ok, Lost, Damaged { kind: String, mcu: usize, offset: usize, resync: usize } }
struct Decoded {
    layout: Layout, blocks: Vec<Block>, quant: BTreeMap<usize, [i64; 64]>, huffman: BTreeMap<(usize, usize), Table>,
    segments: Vec<(usize, String, usize)>, intervals: Vec<IntervalState>, scan_start: usize, total: usize,
    planes: Vec<Plane>, decoded_planes: Vec<Plane>, image: Image,
}

fn read_word(bytes: &[u8], position: usize) -> usize { 256*bytes[position] as usize+bytes[position+1] as usize }
fn read_symbol(reader: &mut bitstream::Reader<'_>, table: &Table) -> Result<u8, &'static str> {
    let mut code = 0;
    for length in 1..=16 {
        code = 2*code+reader.read(1)?;
        if let Some(&symbol) = table.symbols.iter().find(|&&s| table.codes[s as usize] == Some((code, length))) { return Ok(symbol); }
    }
    Err("code")
}

fn read_block(reader: &mut bitstream::Reader<'_>, component: &Component, huffman: &BTreeMap<(usize, usize), Table>, predictor: &mut i64) -> Result<[i64; 64], &'static str> {
    let mut coefficients = [0; 64];
    let size = read_symbol(reader, &huffman[&(0, component.dc)])? as usize;
    *predictor += entropy::value(reader.read(size)?, size); coefficients[0] = *predictor;
    let mut i = 1;
    while i <= 63 {
        let symbol = read_symbol(reader, &huffman[&(1, component.ac)])?;
        if symbol == 0 { break; }
        let (run, size) = ((symbol/16) as usize, (symbol%16) as usize);
        i += run;
        if i > 63 { return Err("index"); }
        if size > 0 { coefficients[i] = entropy::value(reader.read(size)?, size); }
        i += 1;
    }
    Ok(coefficients)
}

fn reconstruct(layout: &Layout, blocks: &[Block], quant: &BTreeMap<usize, [i64; 64]>, c: &[[i64; 8]; 8], keep: usize) -> Vec<Plane> {
    let mut planes: Vec<_> = layout.components.iter().map(|component| {
        let (width, height) = (8*component.h*layout.mx, 8*component.v*layout.my);
        Plane { width, height, pixels: vec![0; width*height] }
    }).collect();
    for block in blocks {
        let component = &layout.components[block.component];
        let coefficients = dct::dequantize(&block.coefficients, &quant[&component.quant], if block.component == 0 { keep } else { 64 });
        let values = dct::inverse(&coefficients, c);
        let plane = &mut planes[block.component];
        for y in 0..8 { for x in 0..8 { plane.pixels[(block.y*8+y)*plane.width+block.x*8+x] = values[y*8+x]; } }
    }
    planes
}

fn decode(bytes: &[u8], tables: &Tables) -> Decoded {
    let mut position = 2;
    let mut quant = BTreeMap::new();
    let mut huffman = BTreeMap::new();
    let mut components = Vec::new();
    let (mut width, mut height, mut restart) = (0, 0, 0);
    let mut segments = vec![(0, "SOI".to_owned(), 0)];
    let zigzag = dct::zigzag();
    loop {
        let marker = bytes[position+1];
        let length = read_word(bytes, position+2);
        let contents = &bytes[position+4..position+length+2];
        let name = match marker {
            0xdb => "DQT".to_owned(), 0xc0 => "SOF0".to_owned(), 0xc4 => "DHT".to_owned(),
            0xdd => "DRI".to_owned(), 0xda => "SOS".to_owned(), 0xfe => "COM".to_owned(),
            _ => format!("APP{}", marker-0xe0),
        };
        segments.push((position, name, length));
        match marker {
            0xdb => for group in contents.chunks(65) {
                let mut q = [0; 64];
                for (i, &p) in zigzag.iter().enumerate() { q[p] = group[i+1] as i64; }
                quant.insert(group[0] as usize, q);
            },
            0xc4 => {
                let mut p = 0;
                while p < contents.len() {
                    let key = ((contents[p]/16) as usize, (contents[p]%16) as usize); p += 1;
                    let mut counts = [0; 16];
                    for i in 0..16 { counts[i] = contents[p+i] as usize; }
                    p += 16;
                    let count: usize = counts.iter().sum();
                    let symbols = contents[p..p+count].to_vec(); p += count;
                    huffman.insert(key, Table::new(counts, symbols));
                }
            }
            0xc0 => {
                height = read_word(contents, 1); width = read_word(contents, 3);
                for component in contents[6..].chunks(3) {
                    components.push(Component { identifier: component[0] as usize, h: (component[1]/16) as usize, v: (component[1]%16) as usize,
                        quant: component[2] as usize, dc: 0, ac: 0 });
                }
            }
            0xdd => restart = read_word(contents, 0),
            0xda => for (k, pair) in contents[1..7].chunks(2).enumerate() {
                components[k].dc = (pair[1]/16) as usize; components[k].ac = (pair[1]%16) as usize;
            },
            _ => {}
        }
        position += length+2;
        if marker == 0xda { break; }
    }
    let scan_start = position;
    segments.push((bytes.len()-2, "EOI".to_owned(), 0));
    let layout = Layout::new(width, height, components, restart);
    let mut blocks = layout.blocks();
    let interval_ranges = layout.intervals();
    let mut states = vec![IntervalState::Lost; interval_ranges.len()];
    let mut reader = bitstream::Reader::new(bytes, position);
    let mut j = 0;
    while j < interval_ranges.len() {
        let (first, count) = interval_ranges[j];
        let mut predictor = [0; 3];
        let mut decoded = Vec::new();
        let mut failure = None;
        for (i, block) in blocks.iter().enumerate().filter(|(_, b)| first <= b.mcu && b.mcu < first+count) {
            match read_block(&mut reader, &layout.components[block.component], &huffman, &mut predictor[block.component]) {
                Ok(coefficients) => decoded.push((i, coefficients)),
                Err(kind) => { failure = Some((kind, block.mcu)); break; }
            }
        }
        reader.clear();
        if failure.is_none() {
            let expected = if j+1 == interval_ranges.len() { 0xd9 } else { 0xd0+(j%8) as u8 };
            if bytes.get(reader.position) == Some(&255) && bytes.get(reader.position+1) == Some(&expected) {
                for (i, coefficients) in decoded { blocks[i].coefficients = coefficients; }
                states[j] = IntervalState::Ok; reader.position += 2; j += 1; continue;
            }
            failure = Some(("sync", first+count-1));
        }
        let (kind, mcu) = failure.unwrap();
        let offset = reader.position;
        let resync = reader.resync();
        states[j] = IntervalState::Damaged { kind: kind.to_owned(), mcu, offset, resync };
        let marker = bytes[resync+1];
        if marker == 0xd9 { break; }
        let number = (marker-0xd0) as usize;
        j = j+1+(number+8-j%8)%8;
        reader.position = resync+2;
    }
    let planes = reconstruct(&layout, &blocks, &quant, &tables.dct, 64);
    let (image, decoded_planes) = color::upsample(&planes, &layout.factors(), width, height);
    Decoded { layout, blocks, quant, huffman, segments, intervals: states, scan_start, total: bytes.len(), planes, decoded_planes, image }
}

fn psnr(a: &[i64], b: &[i64]) -> String {
    let error: i64 = a.iter().zip(b).map(|(a, b)| { let e = a-b; e*e }).sum();
    if error == 0 { "inf".to_owned() } else { format!("{:.2}", 10.0*(65025.0*a.len() as f64/error as f64).log10()) }
}
fn flattened(image: &Image) -> Vec<i64> { image.pixels.iter().flat_map(|p| p.iter().copied()).collect() }
fn fraction(mut numerator: usize, mut denominator: usize) -> String {
    let (mut a, mut b) = (numerator, denominator);
    while b > 0 { let remainder = a%b; a = b; b = remainder; }
    numerator /= a; denominator /= a;
    format!("{}/{}", numerator, denominator)
}
fn component_errors(original: &[Plane], decoded: &Decoded) -> Vec<String> {
    (0..3).map(|k| psnr(&original[k].pixels, &decoded.decoded_planes[k].pixels)).collect()
}

fn main() {
    let image = Image::read();
    let params = image_io::params();
    let tables = image_io::tables();
    let original = color::convert(&image);
    let original_rgb = flattened(&image);
    let mut rate = vec!["quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error".to_owned()];
    for &quality in &params.qualities {
        let standard = encode(&image, quality, &params.sampling, false, params.restart, &tables);
        let optimized = encode(&image, quality, &params.sampling, true, params.restart, &tables);
        let encoding = if params.optimized { &optimized } else { &standard };
        let decoded = decode(&encoding.bytes, &tables);
        let errors = component_errors(&original, &decoded);
        let decoded_rgb = flattened(&decoded.image);
        let maximum = original_rgb.iter().zip(&decoded_rgb).map(|(a, b)| (a-b).abs()).max().unwrap();
        rate.push(format!("{},{},{},{},{},{},{},{},{}", quality, standard.bytes.len(), optimized.bytes.len(),
            fraction(8*encoding.bytes.len(), image.width*image.height), errors[0], errors[1], errors[2], psnr(&original_rgb, &decoded_rgb), maximum));
    }
    let reference = encode(&image, params.qualities[0], &params.sampling, params.optimized, params.restart, &tables);
    let decoded = decode(&reference.bytes, &tables);
    let layout = &reference.layout;
    let zigzag = dct::zigzag();
    let mut block_lines = vec![format!("blocks {}", reference.blocks.len())];
    let mut component_stats = [(0usize, 0usize, 0i64); 3];
    for (i, block) in reference.blocks.iter().enumerate() {
        let (source, restored) = (&reference.planes[block.component], &decoded.planes[block.component]);
        let mut error = 0;
        for y in 0..8 { for x in 0..8 {
            let p = (8*block.y+y)*source.width+8*block.x+x;
            let e = source.pixels[p]-restored.pixels[p]; error += e*e;
        } }
        let ac = block.coefficients[1..].iter().filter(|&&v| v != 0).count();
        let last = block.coefficients.iter().rposition(|&v| v != 0).unwrap_or(0);
        block_lines.push(format!("block {} {} {} {} dc {} diff {} nonzero {} last {} bits {} sse {}", i, ["Y", "Cb", "Cr"][block.component],
            block.x, block.y, block.coefficients[0], reference.differences[i], ac, last, reference.bits[i], error));
        component_stats[block.component].0 += reference.bits[i];
        component_stats[block.component].1 += block.coefficients.iter().filter(|&&v| v != 0).count();
        component_stats[block.component].2 += error;
    }
    let mut huffman_lines = Vec::new();
    for (t, table) in reference.tables.iter().enumerate() {
        let counts = &reference.frequencies[t];
        let coded: usize = counts.iter().sum();
        let bits: usize = table.symbols.iter().map(|&s| counts[s as usize]*table.codes[s as usize].unwrap().1).sum();
        huffman_lines.push(format!("table {} class {} id {} symbols {} coded {} bits {}", ["dc_luma", "ac_luma", "dc_chroma", "ac_chroma"][t],
            t%2, t/2, table.symbols.len(), coded, bits));
        huffman_lines.push(format!("counts {}", table.counts.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")));
        for &symbol in &table.symbols {
            let (code, length) = table.codes[symbol as usize].unwrap();
            huffman_lines.push(format!("symbol {:02x} length {} code {:0width$b} count {}", symbol, length, code, counts[symbol as usize], width=length));
        }
    }
    let mut thumbnail = Image { width: (image.width+7)/8, height: (image.height+7)/8, pixels: Vec::new() };
    for y in 0..thumbnail.height { for x in 0..thumbnail.width {
        let mut values = [0; 3];
        for k in 0..3 {
            let c = &decoded.layout.components[k];
            let (bx, by) = (x*c.h/layout.hmax, y*c.v/layout.vmax);
            let block = decoded.blocks.iter().find(|b| b.component == k && b.x == bx && b.y == by).unwrap();
            values[k] = ((block.coefficients[0]*decoded.quant[&c.quant][0]+4).div_euclid(8)+128).clamp(0, 255);
        }
        thumbnail.pixels.push(color::rgb(values[0], values[1], values[2]));
    } }
    let mut report = vec![format!("image {} {}", image.width, image.height),
        format!("sampling {} mcu {} {} grid {} {}", params.sampling, 8*layout.hmax, 8*layout.vmax, layout.mx, layout.my),
        format!("padded {} {}", 8*layout.hmax*layout.mx, 8*layout.vmax*layout.my),
        format!("blocks {}", (0..3).map(|k| reference.blocks.iter().filter(|b| b.component == k).count().to_string()).collect::<Vec<_>>().join(" ")),
        format!("restart_interval {} markers {}", params.restart, reference.intervals.len()-1),
        format!("huffman {}", if params.optimized { "optimized" } else { "standard" }), format!("quality {}", params.qualities[0])];
    for t in 0..2 { report.push(format!("quant {} {}", t, zigzag.iter().map(|&p| reference.quant[t][p].to_string()).collect::<Vec<_>>().join(" "))); }
    report.push(format!("symbols {}", reference.frequencies.iter().map(|f| f.iter().sum::<usize>().to_string()).collect::<Vec<_>>().join(" ")));
    let all_symbols: Vec<_> = reference.symbols.iter().flatten().collect();
    let eob = all_symbols.iter().filter(|s| s.table%2 == 1 && s.value == 0).count();
    let zrl = all_symbols.iter().filter(|s| s.table%2 == 1 && s.value == 0xf0).count();
    report.push(format!("eob {} zrl {}", eob, zrl));
    report.push(format!("zero_ac_blocks {}", reference.blocks.iter().filter(|b| b.coefficients[1..].iter().all(|&v| v == 0)).count()));
    report.push(format!("nonzero {}", (0..64).map(|i| reference.blocks.iter().filter(|b| b.coefficients[i] != 0).count().to_string()).collect::<Vec<_>>().join(" ")));
    for k in 0..3 { let (bits, nonzero, error) = component_stats[k]; report.push(format!("component {} bits {} nonzero {} sse {}", ["Y", "Cb", "Cr"][k], bits, nonzero, error)); }
    report.extend([format!("padding_bits {}", reference.padding), format!("stuffed_bytes {}", reference.stuffed), format!("header_bytes {}", reference.header),
        format!("scan_bytes {}", reference.bytes.len()-reference.header-2), format!("total_bytes {}", reference.bytes.len())]);
    for (j, &(first, count, position, length)) in reference.intervals.iter().enumerate() { report.push(format!("interval {} {} {} {} {}", j, first, count, position, length)); }
    let decoded_rgb = flattened(&decoded.image);
    let mut histogram = [0; 8];
    for (a, b) in original_rgb.iter().zip(&decoded_rgb) {
        let error = (a-b).abs();
        let bin = match error { 0 => 0, 1 => 1, 2..=3 => 2, 4..=7 => 3, 8..=15 => 4, 16..=31 => 5, 32..=63 => 6, _ => 7 };
        histogram[bin] += 1;
    }
    report.push(format!("error_histogram {}", histogram.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")));
    for &keep in &params.truncate {
        let planes = reconstruct(&decoded.layout, &decoded.blocks, &decoded.quant, &tables.dct, keep);
        let cropped: Vec<_> = (0..image.height).flat_map(|y| {
            let plane = &planes[0]; (0..image.width).map(move |x| plane.pixels[y*plane.width+x])
        }).collect();
        report.push(format!("truncate {} {}", keep, psnr(&original[0].pixels, &cropped)));
    }
    for sampling in ["444", "422", "420"] {
        let encoded = encode(&image, params.qualities[0], sampling, params.optimized, params.restart, &tables);
        let restored = decode(&encoded.bytes, &tables);
        let errors = component_errors(&original, &restored);
        report.push(format!("sampling_compare {} {} {} {} {}", sampling, encoded.bytes.len(), errors[1], errors[2], psnr(&original_rgb, &flattened(&restored.image))));
    }
    let mut current = image.clone();
    for generation in 1..=params.generations {
        let encoded = encode(&current, params.qualities[0], &params.sampling, params.optimized, params.restart, &tables);
        let restored = decode(&encoded.bytes, &tables);
        let changed = current.pixels.iter().zip(&restored.image.pixels).filter(|(a, b)| a != b).count();
        report.push(format!("generation {} {} {} {}", generation, encoded.bytes.len(), psnr(&original_rgb, &flattened(&restored.image)), changed));
        current = restored.image;
    }
    let (mut lo, mut hi) = (1, 100);
    while lo < hi {
        let mid = (lo+hi+1)/2;
        let bytes = encode(&image, mid, &params.sampling, params.optimized, params.restart, &tables).bytes.len();
        report.push(format!("rate_control_step {} {}", mid, bytes));
        if bytes <= params.target { lo = mid; } else { hi = mid-1; }
    }
    let control = encode(&image, lo, &params.sampling, params.optimized, params.restart, &tables);
    let control_decoded = decode(&control.bytes, &tables);
    report.push(format!("rate_control {} {} {} {}", lo, control.bytes.len(), if control.bytes.len() <= params.target { "yes" } else { "no" }, psnr(&original_rgb, &flattened(&control_decoded.image))));
    let stream_bytes = image_io::read_hex();
    let stream = decode(&stream_bytes, &tables);
    for (position, name, length) in &stream.segments { report.push(format!("stream_segment {} {} {}", position, name, length)); }
    report.push(format!("stream_image {} {}", stream.layout.width, stream.layout.height));
    for c in &stream.layout.components { report.push(format!("stream_component {} {} {} {} {} {}", c.identifier, c.h, c.v, c.quant, c.dc, c.ac)); }
    for (t, q) in &stream.quant { report.push(format!("stream_quant {} {}", t, zigzag.iter().map(|&p| q[p].to_string()).collect::<Vec<_>>().join(" "))); }
    for (&(class, id), table) in &stream.huffman {
        let longest = table.counts.iter().rposition(|&n| n > 0).unwrap()+1;
        report.push(format!("stream_huffman {} {} symbols {} longest {}", class, id, table.symbols.len(), longest));
    }
    report.push(format!("stream_restart {} intervals {} ok {} damaged {} lost {}", stream.layout.restart, stream.intervals.len(),
        stream.intervals.iter().filter(|s| matches!(s, IntervalState::Ok)).count(), stream.intervals.iter().filter(|s| matches!(s, IntervalState::Damaged { .. })).count(),
        stream.intervals.iter().filter(|s| matches!(s, IntervalState::Lost)).count()));
    for (j, (first, count)) in stream.layout.intervals().into_iter().enumerate() {
        let state = match &stream.intervals[j] {
            IntervalState::Ok => "ok".to_owned(), IntervalState::Lost => "lost".to_owned(),
            IntervalState::Damaged { kind, mcu, offset, resync } => format!("damaged {} mcu {} offset {} resync {}", kind, mcu, offset, resync),
        };
        report.push(format!("stream_interval {} {} {} {}", j, first, count, state));
    }
    report.push(format!("stream_scan_bytes {}", stream.total-stream.scan_start-2));
    let mut repair_layout = stream.layout.clone();
    let repair_quant = [stream.quant[&stream.layout.components[0].quant], stream.quant[&stream.layout.components[1].quant]];
    for (k, c) in repair_layout.components.iter_mut().enumerate() { c.identifier = k+1; c.quant = usize::from(k > 0); c.dc = usize::from(k > 0); c.ac = usize::from(k > 0); }
    let repair = encode_coefficients(repair_layout, stream.blocks.clone(), repair_quant, &tables.huffman, true, Vec::new());
    let repaired = decode(&repair.bytes, &tables);
    report.push(format!("repair {} {} {} identical {}", repair.bytes.len(), repair.header, repair.bytes.len()-repair.header-2,
        if stream.image.pixels == repaired.image.pixels { "yes" } else { "no" }));
    decoded.image.write("decoded.ppm"); thumbnail.write("thumbnail.ppm"); stream.image.write("stream_decoded.ppm");
    image_io::write_hex("bitstream.hex", &reference.bytes); image_io::write_hex("repaired.hex", &repair.bytes);
    image_io::write("rate_distortion.csv", &rate); image_io::write("huffman_tables.txt", &huffman_lines);
    image_io::write("blocks.txt", &block_lines); image_io::write("report.txt", &report);
}
