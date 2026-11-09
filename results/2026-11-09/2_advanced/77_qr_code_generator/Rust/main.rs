mod bitstream;
mod reed_solomon;
mod matrix;
mod masking;
mod render;
use std::collections::{BTreeMap,BTreeSet};
use std::fs;
use matrix::Grid;
use bitstream::{binary,hexadecimal,ALPHANUMERIC};
const MODES: [&str;4] = ["NUMERIC","ALPHANUMERIC","BYTE","MIXED"];
const LEVELS: [&str;4] = ["L","M","Q","H"];
struct BlockTable {
    ec: usize,
    sizes: Vec<usize>
}
impl BlockTable {
    fn data(&self) -> usize {
        self.sizes.iter().sum()
    }
    fn total(&self) -> usize {
        self.data()+self.ec*self.sizes.len()
    }
}
struct Tables {
    blocks: Vec<Vec<BlockTable>>,
    alignment: Vec<Vec<usize>>
}
impl Tables {
    fn read() -> Self {
        let source = fs::read_to_string("input/tables.txt").unwrap();
        let mut blocks: Vec<Vec<BlockTable>> = (0..10).map(|_| Vec::new()).collect();
        let mut alignment = vec![Vec::new();10];
        for line in source.lines() {
            let w: Vec<_> = line.split_whitespace().collect();
            let v = w[1].parse::<usize>().unwrap()-1;
            if w[0] == "block" {
                let ec = w[3].parse().unwrap();
                let b1 = w[4].parse::<usize>().unwrap();
                let k1 = w[5].parse::<usize>().unwrap();
                let b2 = w[6].parse::<usize>().unwrap();
                let k2 = w[7].parse::<usize>().unwrap();
                let sizes = std::iter::repeat(k1).take(b1).chain(std::iter::repeat(k2).take(b2)).collect();
                blocks[v].push(BlockTable {
                    ec,
                    sizes
                });
            } else {
                alignment[v] = w[2..].iter().map(|s| s.parse().unwrap()).collect();
            }
        }
        Self {
            blocks,
            alignment
        }
    }
    fn table(&self, version: usize, level: usize) -> &BlockTable {
        &self.blocks[version-1][level]
    }
}
#[derive(Clone)] struct Segment {
    mode: usize,
    bytes: Vec<u8>
}
fn count_width(mode: usize, version: usize) -> usize {
    if version <= 9 {
        [10,9,8][mode]
    } else {
        [12,11,16][mode]
    }
}
fn data_width(mode: usize, count: usize) -> usize {
    match mode {
        0 => 10*(count/3)+[0,4,7][count%3],1 => 11*(count/2)+6*(count%2),_ => 8*count
    }
}
fn encodable(mode: usize, byte: u8) -> bool {
    match mode {
        0 => byte.is_ascii_digit(),1 => ALPHANUMERIC.contains(&byte),_ => true
    }
}
fn split(bytes: &[u8], mode: usize, version: usize) -> (Vec<Segment>,usize) {
    if mode != 3 {
        return (vec![Segment {
            mode,bytes: bytes.to_vec()
        }],4+count_width(mode,version)+data_width(mode,bytes.len()));
    }
    let n = bytes.len();
    let mut invalid = vec![vec![0usize;n+1];3];
    for m in 0..3 {
        for i in 0..n {
            invalid[m][i+1] = invalid[m][i]+usize::from(!encodable(m,bytes[i]));
        }
    }
    let mut cost = vec![usize::MAX;n+1];
    let mut choices = vec![(0,0);n+1];
    cost[0] = 0;
    for i in 1..=n {
        for j in 0..i {
            for m in 0..3 {
                if invalid[m][i] == invalid[m][j] {
                    let candidate = cost[j]+4+count_width(m,version)+data_width(m,i-j);
                    if candidate < cost[i] {
                        cost[i] = candidate;
                        choices[i] = (j,m);
                    }
                }
            }
        }
    }
    let mut segments = Vec::new();
    let mut i = n;
    while i > 0 {
        let (j,m) = choices[i];
        segments.push(Segment {
            mode: m,
            bytes: bytes[j..i].to_vec()
        });
        i = j;
    }
    segments.reverse();
    (segments,cost[n])
}
fn groups(segment: &Segment) -> Vec<(usize,usize,Vec<u8>)> {
    let width = [3,2,1][segment.mode];
    segment.bytes.chunks(width).map(|group| match segment.mode {
        0 => (group.iter().fold(0,|n,&b| 10*n+(b-b'0') as usize),[0,4,7,10][group.len()],group.to_vec()),1 => {
            let first = ALPHANUMERIC.iter().position(|&b| b == group[0]).unwrap();
            if group.len() == 1 {
                (first,6,group.to_vec())
            } else {
                (45*first+ALPHANUMERIC.iter().position(|&b| b == group[1]).unwrap(),11,group.to_vec())
            }
        },_ => (group[0] as usize,8,group.to_vec())
    }).collect()
}
fn pad(bits: &mut Vec<u8>, capacity: usize) -> (usize,usize,usize) {
    let terminator = 4.min(capacity-bits.len());
    bits.extend(std::iter::repeat(0).take(terminator));
    let zero = (8-bits.len()%8)%8;
    bits.extend(std::iter::repeat(0).take(zero));
    let mut count = 0;
    while bits.len() < capacity {
        bitstream::append(bits,if count%2 == 0 {
            0xec
        } else {
            0x11
        },8);
        count += 1;
    }
    (terminator,zero,count)
}
fn placement(table: &BlockTable) -> Vec<(usize,usize)> {
    let mut order = Vec::new();
    for i in 0..*table.sizes.iter().max().unwrap() {
        for (b,&size) in table.sizes.iter().enumerate() {
            if i < size {
                order.push((b,i));
            }
        }
    }
    for i in 0..table.ec {
        for (b,&size) in table.sizes.iter().enumerate() {
            order.push((b,size+i));
        }
    }
    order
}
fn rotate(grid: &Grid) -> Grid {
    let n = grid.len();
    (0..n).map(|y| (0..n).map(|x| grid[n-1-x][y]).collect()).collect()
}
fn transpose(grid: &Grid) -> Grid {
    (0..grid.len()).map(|y| (0..grid.len()).map(|x| grid[x][y]).collect()).collect()
}
struct Decoded {
    lines: Vec<String>,
    text: Option<String>,
    blocks: [usize;4]
}
fn failure(lines: Vec<String>, blocks: [usize;4]) -> Decoded {
    Decoded {
        lines,
        text: None,
        blocks
    }
}
fn attempt(grid: &Grid, tables: &Tables, field: &reed_solomon::Field) -> Decoded {
    let n = grid.len();
    let version = (n-17)/4;
    let mut lines = Vec::new();
    let mut statistics = [0usize;4];
    let positions = matrix::format_positions(n);
    let f1 = matrix::read(grid,&positions[0]);
    let f2 = matrix::read(grid,&positions[1]);
    let nearest = |value: usize| {
        let mut best = (usize::MAX,0,0);
        for level in 0..4 {
            for mask in 0..8 {
                let distance = (matrix::format(level,mask)^value).count_ones() as usize;
                if distance < best.0 {
                    best = (distance,level,mask);
                }
            }
        }
        best
    };
    let a = nearest(f1);
    let b = nearest(f2);
    let chosen = if b.0 < a.0 {
        b
    } else {
        a
    };
    let (distance,level,mask) = chosen;
    if distance > 3 {
        lines.push(format!("format {} {} distance {} {} unreadable",binary(f1,15),binary(f2,15),a.0,b.0));
        return failure(lines,statistics);
    }
    lines.push(format!("format {} {} distance {} {} level {} mask {}",binary(f1,15),binary(f2,15),a.0,b.0,LEVELS[level],mask));
    if version >= 7 {
        let positions = matrix::version_positions(n);
        let g1 = matrix::read(grid,&positions[0]);
        let g2 = matrix::read(grid,&positions[1]);
        let nearest = |value: usize| (7..=40).map(|v| ((matrix::version(v)^value).count_ones() as usize,v)).min().unwrap();
        let a = nearest(g1);
        let b = nearest(g2);
        let chosen = if b.0 < a.0 {
            b
        } else {
            a
        };
        if chosen.0 > 3 {
            lines.push(format!("version {} {} distance {} {} unreadable",binary(g1,18),binary(g2,18),a.0,b.0));
            return failure(lines,statistics);
        }
        lines.push(format!("version {} {} distance {} {} decoded {}",binary(g1,18),binary(g2,18),a.0,b.0,chosen.1));
        if chosen.1 != version {
            return failure(lines,statistics);
        }
    }
    let matrix = matrix::build(version,&tables.alignment[version-1]);
    let unmasked = masking::apply(grid,&matrix.areas,mask);
    let reading = matrix::order(&matrix.areas);
    let table = tables.table(version,level);
    let order = placement(table);
    let bits: Vec<_> = reading.iter().take(8*table.total()).map(|&(x,y)| unmasked[y][x]).collect();
    let words = bitstream::codewords(&bits);
    let mut blocks: Vec<_> = table.sizes.iter().map(|&k| vec![0;k+table.ec]).collect();
    for (&word,&(block,position)) in words.iter().zip(&order) {
        blocks[block][position] = word;
    }
    let mut failed = false;
    for b in 0..blocks.len() {
        let correction = field.correct(&blocks[b],table.ec);
        let mut line = format!("block {} syndromes {}",b,hexadecimal(&correction.syndromes));
        if let Some(words) = correction.codewords {
            blocks[b] = words;
            if correction.positions.is_empty() {
                statistics[0] += 1;
                line.push_str(" ok");
            } else {
                statistics[1] += 1;
                statistics[3] += correction.positions.len();
                line.push_str(&format!(" corrected {}",correction.positions.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")));
            }
        } else {
            failed = true;
            statistics[2] += 1;
            line.push_str(" failed");
        }
        lines.push(line);
    }
    if failed {
        return failure(lines,statistics);
    }
    let data: Vec<_> = blocks.iter().zip(&table.sizes).flat_map(|(b,&k)| b[..k].iter().copied()).collect();
    let bits = bitstream::bits(&data);
    let mut at = 0;
    let mut end = 0;
    let mut text = Vec::new();
    while bits.len()-at >= 4 {
        let indicator = bitstream::read(&bits,&mut at,4);
        if indicator == 0 {
            break;
        }
        let mode = match indicator {
            1 => 0,2 => 1,4 => 2,_ => {
                lines.push(format!("parse failed indicator {}",binary(indicator,4)));
                return failure(lines,statistics);
            }
        };
        if bits.len()-at < count_width(mode,version) {
            lines.push(format!("parse failed length {}",MODES[mode]));
            return failure(lines,statistics);
        }
        let count = bitstream::read(&bits,&mut at,count_width(mode,version));
        if bits.len()-at < data_width(mode,count) {
            lines.push(format!("parse failed length {}",MODES[mode]));
            return failure(lines,statistics);
        }
        let mut remaining = count;
        while remaining > 0 {
            let group = remaining.min([3,2,1][mode]);
            let width = match mode {
                0 => [0,4,7,10][group],1 => if group == 2 {
                    11
                } else {
                    6
                },_ => 8
            };
            let value = bitstream::read(&bits,&mut at,width);
            let valid = match mode {
                0 => value < [1,10,100,1000][group],1 => value < if group == 2 {
                    2025
                } else {
                    45
                },_ => (32..=126).contains(&value)
            };
            if !valid {
                lines.push(format!("parse failed value {}",MODES[mode]));
                return failure(lines,statistics);
            }
            match mode {
                0 => text.extend(format!("{:0width$}",value,width=group).bytes()),1 => {
                    if group == 2 {
                        text.push(ALPHANUMERIC[value/45]);
                    }
                    text.push(ALPHANUMERIC[value%45]);
                },_ => text.push(value as u8)
            }
            remaining -= group;
        }
        lines.push(format!("segment {} {}",MODES[mode],count));
        end = at;
    }
    let mut expected = bits[..end].to_vec();
    pad(&mut expected,bits.len());
    lines.push(format!("padding {}",if expected == bits {
        "ok"
    } else {
        "bad"
    }));
    let text = String::from_utf8(text).unwrap();
    lines.push(format!("text \"{}\"",text));
    Decoded {
        lines,
        text: Some(text),
        blocks: statistics
    }
}
fn decode(grid: &Grid, tables: &Tables, field: &reed_solomon::Field) -> Decoded {
    let n = grid.len();
    let corners = [(n-7,n-7),(n-7,0),(0,0),(0,n-7)];
    let scores: Vec<_> = corners.iter().map(|&(x,y)| (0..7).map(|j| (0..7).filter(|&i| {
        let d = (i as i32-3).abs().max((j as i32-3).abs());
        grid[y+j][x+i] == u8::from(d != 2)
    }).count()).sum::<usize>()).collect();
    let rotations = (0..4).min_by_key(|&k| (scores[k],k)).unwrap();
    let mut oriented = grid.clone();
    for _ in 0..rotations {
        oriented = rotate(&oriented);
    }
    let first = attempt(&oriented,tables,field);
    let (mut adopted,mirrored) = if first.text.is_some() {
        (first,false)
    } else {
        let second = attempt(&transpose(&oriented),tables,field);
        if second.text.is_some() {
            (second,true)
        } else {
            (first,false)
        }
    };
    adopted.lines.insert(0,format!("orientation rotations {} mirrored {}",rotations,if mirrored {
        "yes"
    } else {
        "no"
    }));
    adopted
}
fn read_image(lines: &[String]) -> (Grid,usize,usize,usize,usize,bool) {
    let dimensions: Vec<usize> = lines[1].split_whitespace().map(|s| s.parse().unwrap()).collect();
    let (width,height) = (dimensions[0],dimensions[1]);
    let pixels: Grid = lines[2..].iter().map(|line| line.bytes().map(|b| b-b'0').collect()).collect();
    let mut left = width;
    let mut right = 0;
    let mut top = height;
    for y in 0..height {
        for x in 0..width {
            if pixels[y][x] == 1 {
                left = left.min(x);
                right = right.max(x);
                top = top.min(y);
            }
        }
    }
    let mut run = 0;
    while left+run < width && pixels[top][left+run] == 1 {
        run += 1;
    }
    let scale = run/7;
    let n = (right-left+1)/scale;
    let grid: Grid = (0..n).map(|y| (0..n).map(|x| pixels[top+scale*y][left+scale*x]).collect()).collect();
    let mut good = true;
    for y in 0..height {
        for x in 0..width {
            let expected = if left <= x && x < left+scale*n && top <= y && y < top+scale*n {
                grid[(y-top)/scale][(x-left)/scale]
            } else {
                0
            };
            good &= pixels[y][x] == expected;
        }
    }
    (grid,width,height,left/scale,scale,good)
}
fn result(decoded: &Decoded, text: &str) -> usize {
    match &decoded.text {
        Some(found) => usize::from(found != text),None => 2
    }
}
fn write(name: &str, lines: &[String]) {
    let content = if lines.is_empty() {
        String::new()
    } else {
        lines.join("\n")+"\n"
    };
    fs::write(format!("output/{}",name),content).unwrap();
}
fn main() {
    let tables = Tables::read();
    let field = reed_solomon::Field::new();
    let params: Vec<usize> = fs::read_to_string("input/params.txt").unwrap().lines().map(|l| l.split_whitespace().nth(1).unwrap().parse().unwrap()).collect();
    let (quiet,scale) = (params[0],params[1]);
    let mut damage = BTreeMap::<String,Vec<Vec<String>>>::new();
    for line in fs::read_to_string("input/damage.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().map(str::to_owned).collect();
        damage.entry(w[0].clone()).or_default().push(w[1..].to_vec());
    }
    let source = fs::read_to_string("input/requests.txt").unwrap();
    let requests: Vec<_> = source.lines().collect();
    let mut codes = Vec::new();
    let mut codewords = Vec::new();
    let mut bitstream_lines = Vec::new();
    let mut selfcheck = Vec::new();
    let mut error_counts = [0usize;7];
    let mut mode_counts = [0usize;4];
    let mut level_counts = [0usize;4];
    let mut version_counts = [0usize;10];
    let mut mask_counts = [0usize;8];
    let mut totals = [0usize;7];
    let mut check_counts = [0usize;3];
    let mut block_counts = [0usize;4];
    let mut boosted = 0;
    fs::create_dir_all("output").unwrap();
    for line in &requests {
        let (header,text) = line.split_once(':').unwrap();
        let w: Vec<_> = header.split_whitespace().collect();
        let id = w[0];
        let bytes = text.as_bytes();
        codes.push(format!("request {}",id));
        let mut error = None;
        let mut base = 0;
        let mut mode = 0;
        if let Some(level) = ["L","M","Q","H","L+","M+","Q+","H+"].iter().position(|&l| l == w[1]) {
            base = level%4;
        } else {
            error = Some((0,format!("level {}",w[1])));
        }
        if error.is_none() {
            mode = match w[2] {
                "NUMERIC" => 0,"ALPHANUMERIC" => 1,"BYTE" => 2,"MIXED" => 3,"AUTO" => (0..3).find(|&m| bytes.iter().all(|&b| encodable(m,b))).unwrap(),_ => {
                    error = Some((1,format!("mode {}",w[2])));
                    0
                }
            };
        }
        if error.is_none() && w[3] != "AUTO" && !(1..=10).any(|v| v.to_string() == w[3]) {
            error = Some((2,format!("version {}",w[3])));
        }
        if error.is_none() && w[4] != "AUTO" && !(0..8).any(|m| m.to_string() == w[4]) {
            error = Some((3,format!("mask {}",w[4])));
        }
        if error.is_none() && bytes.is_empty() {
            error = Some((4,"text".to_owned()));
        }
        if error.is_none() && (w[2] == "NUMERIC" || w[2] == "ALPHANUMERIC") {
            if let Some(position) = bytes.iter().position(|&b| !encodable(mode,b)) {
                error = Some((5,format!("charset position {}",position)));
            }
        }
        let mut version = 0;
        if error.is_none() {
            if w[3] == "AUTO" {
                version = (1..=10).find(|&v| split(bytes,mode,v).1 <= 8*tables.table(v,base).data()).unwrap_or(0);
            } else {
                let v = w[3].parse().unwrap();
                if split(bytes,mode,v).1 <= 8*tables.table(v,base).data() {
                    version = v;
                }
            }
            if version == 0 {
                let v = if w[3] == "AUTO" {
                    10
                } else {
                    w[3].parse().unwrap()
                };
                error = Some((6,format!("capacity bits {} capacity {}",split(bytes,mode,v).1,8*tables.table(v,base).data())));
            }
        }
        if let Some((kind,error)) = error {
            error_counts[kind] += 1;
            codes.push(format!("error {}",error));
            continue;
        }
        let (segments,length) = split(bytes,mode,version);
        let level = if w[1].ends_with('+') {
            (base..4).rev().find(|&l| length <= 8*tables.table(version,l).data()).unwrap()
        } else {
            base
        };
        boosted += usize::from(level != base);
        let table = tables.table(version,level);
        let capacity = 8*table.data();
        let mut bits = Vec::new();
        bitstream_lines.push(format!("request {} version {} bits {} capacity {}",id,version,length,capacity));
        for segment in &segments {
            let indicator = [1,2,4][segment.mode];
            let count = segment.bytes.len();
            bitstream::append(&mut bits,indicator,4);
            bitstream::append(&mut bits,count,count_width(segment.mode,version));
            bitstream_lines.push(format!("segment {} indicator {} count {} {}",MODES[segment.mode],binary(indicator,4),count,binary(count,count_width(segment.mode,version))));
            for (value,width,group) in groups(segment) {
                bitstream::append(&mut bits,value,width);
                bitstream_lines.push(format!("group {} {} \"{}\"",value,binary(value,width),String::from_utf8(group).unwrap()));
            }
        }
        let (terminator,zero,pads) = pad(&mut bits,capacity);
        bitstream_lines.push(format!("terminator {} zero_fill {} pad_bytes {}",terminator,zero,pads));
        let data = bitstream::codewords(&bits);
        let mut blocks = Vec::new();
        let mut at = 0;
        codewords.push(format!("request {} version {} level {} blocks {} data {} ec_per_block {} total {}",id,version,LEVELS[level],table.sizes.len(),table.data(),table.ec,table.total()));
        for (b,&size) in table.sizes.iter().enumerate() {
            let mut words = data[at..at+size].to_vec();
            at += size;
            let ec = field.error_correction(&words,table.ec);
            codewords.push(format!("block {} data {}",b,hexadecimal(&words)));
            codewords.push(format!("block {} ec {}",b,hexadecimal(&ec)));
            words.extend(ec);
            blocks.push(words);
        }
        let placement = placement(table);
        let interleaved: Vec<_> = placement.iter().map(|&(b,i)| blocks[b][i]).collect();
        codewords.push(format!("interleaved {}",hexadecimal(&interleaved)));
        let mut matrix = matrix::build(version,&tables.alignment[version-1]);
        let reading = matrix::order(&matrix.areas);
        let encoded = bitstream::bits(&interleaved);
        for (&(x,y),&bit) in reading.iter().zip(&encoded) {
            matrix.modules[y][x] = bit;
        }
        let mut symbols = Vec::new();
        let mut penalties = Vec::new();
        for mask in 0..8 {
            let mut symbol = masking::apply(&matrix.modules,&matrix.areas,mask);
            for positions in &matrix::format_positions(symbol.len()) {
                matrix::write(&mut symbol,positions,matrix::format(level,mask));
            }
            penalties.push(masking::penalty(&symbol));
            symbols.push(symbol);
        }
        let mask = if w[4] == "AUTO" {
            (0..8).min_by_key(|&m| (penalties[m].iter().sum::<usize>(),m)).unwrap()
        } else {
            w[4].parse().unwrap()
        };
        let symbol = &symbols[mask];
        let n = symbol.len();
        let dark = symbol.iter().flatten().map(|&v| v as usize).sum::<usize>();
        let alternatives: Vec<_> = (0..3).map(|m| if bytes.iter().all(|&b| encodable(m,b)) {
            (4+count_width(m,version)+data_width(m,bytes.len())).to_string()
        } else {
            "-".to_owned()
        }).collect();
        let fits: Vec<_> = (0..4).map(|l| (1..=10).find(|&v| split(bytes,mode,v).1 <= 8*tables.table(v,l).data()).map_or_else(|| "-".to_owned(),|v| v.to_string())).collect();
        codes.push(format!("symbol version {} level {} mask {} size {}",version,LEVELS[level],mask,n));
        codes.push(format!("segments {} {}",segments.len(),segments.iter().map(|s| format!("{}:{}",MODES[s.mode],s.bytes.len())).collect::<Vec<_>>().join(" ")));
        codes.push(format!("bits data {} capacity {} alternatives NUMERIC {} ALPHANUMERIC {} BYTE {} MIXED {}",length,capacity,alternatives[0],alternatives[1],alternatives[2],split(bytes,3,version).1));
        codes.push(format!("fits L {} M {} Q {} H {}",fits[0],fits[1],fits[2],fits[3]));
        codes.push(format!("modules function {} data {} remainder {} dark {}",n*n-reading.len(),reading.len(),reading.len()-8*table.total(),dark));
        codes.push(format!("format {} version {}",binary(matrix::format(level,mask),15),if version >= 7 {
            binary(matrix::version(version),18)
        } else {
            "none".to_owned()
        }));
        for (m,p) in penalties.iter().enumerate() {
            codes.push(format!("penalty {} n1 {} n2 {} n3 {} n4 {} total {}",m,p[0],p[1],p[2],p[3],p.iter().sum::<usize>()));
        }
        codes.extend(render::symbol(symbol));
        let image = render::pbm(symbol,quiet,scale);
        let filename = format!("qr_{}.pbm",id);
        write(&filename,&image);
        let image: Vec<_> = fs::read_to_string(format!("output/{}",filename)).unwrap().lines().map(str::to_owned).collect();
        let (read,width,height,q,u,well_formed) = read_image(&image);
        selfcheck.push(format!("request {}",id));
        selfcheck.push(format!("image {} {} quiet {} scale {} size {} {}",width,height,q,u,read.len(),if well_formed {
            "ok"
        } else {
            "bad"
        }));
        selfcheck.push("check clean".to_owned());
        let clean = decode(&read,&tables,&field);
        let status = result(&clean,text);
        check_counts[status] += 1;
        for i in 0..4 {
            block_counts[i] += clean.blocks[i];
        }
        selfcheck.extend(clean.lines);
        selfcheck.push(format!("result {}",["ok","mismatch","failed"][status]));
        if let Some(operations) = damage.get(id) {
            let mut damaged = symbol.clone();
            for operation in operations {
                let number = |i: usize| operation[i].parse::<usize>().unwrap();
                if operation[0] == "flip" {
                    damaged[number(2)][number(1)] ^= 1;
                } else if operation[0] == "fill" {
                    for y in number(2)..number(2)+number(4) {
                        for x in number(1)..number(1)+number(3) {
                            damaged[y][x] = u8::from(operation[5] == "dark");
                        }
                    }
                }
            }
            let mut category = [0usize;5];
            let mut damaged_words = BTreeSet::new();
            let mut locations = vec![vec![None;n];n];
            for (j,&(x,y)) in reading.iter().enumerate() {
                locations[y][x] = Some(j);
            }
            for y in 0..n {
                for x in 0..n {
                    if damaged[y][x] != symbol[y][x] {
                        let area = matrix.areas[y][x];
                        if area > 0 {
                            category[area as usize-1] += 1;
                        } else {
                            let j = locations[y][x].unwrap();
                            if j < 8*table.total() {
                                category[3] += 1;
                                damaged_words.insert(j/8);
                            } else {
                                category[4] += 1;
                            }
                        }
                    }
                }
            }
            let mut errors = vec![0usize;table.sizes.len()];
            for word in damaged_words {
                errors[placement[word].0] += 1;
            }
            selfcheck.push(format!("check damaged operations {}",operations.len()));
            selfcheck.push(format!("damage changed {} function {} format {} version {} data {} remainder {}",category.iter().sum::<usize>(),category[0],category[1],category[2],category[3],category[4]));
            selfcheck.push(format!("errors {} limit {}",errors.iter().map(usize::to_string).collect::<Vec<_>>().join(" "),table.ec/2));
            for operation in operations {
                if operation[0] == "rotate" {
                    damaged = rotate(&damaged);
                } else if operation[0] == "mirror" {
                    damaged = transpose(&damaged);
                }
            }
            let decoded = decode(&damaged,&tables,&field);
            let status = result(&decoded,text);
            check_counts[status] += 1;
            for i in 0..4 {
                block_counts[i] += decoded.blocks[i];
            }
            selfcheck.extend(decoded.lines);
            selfcheck.push(format!("result {}",["ok","mismatch","failed"][status]));
        }
        let mut tolerances = [n;2];
        for color in 0..2 {
            for size in 1..=n {
                let a = (n-size)/2;
                let mut damaged = symbol.clone();
                for row in &mut damaged[a..a+size] {
                    row[a..a+size].fill(color as u8);
                }
                if result(&decode(&damaged,&tables,&field),text) != 0 {
                    tolerances[color] = size-1;
                    break;
                }
            }
        }
        selfcheck.push(format!("tolerance light {} dark {}",tolerances[0],tolerances[1]));
        mode_counts[mode] += 1;
        level_counts[level] += 1;
        version_counts[version-1] += 1;
        mask_counts[mask] += 1;
        totals[0] += 1;
        totals[1] += segments.len();
        totals[2] += table.data();
        totals[3] += table.ec*table.sizes.len();
        totals[4] += n*n;
        totals[5] += dark;
    }
    let mut scans = Vec::new();
    let source = fs::read_to_string("input/scans.txt").unwrap();
    let lines: Vec<_> = source.lines().collect();
    let mut at = 0;
    let mut scan_counts = [0usize;2];
    while at < lines.len() {
        let name = lines[at].split_whitespace().nth(1).unwrap();
        let n = lines[at+1].len();
        let grid: Grid = lines[at+1..at+1+n].iter().map(|line| line.bytes().map(|b| u8::from(b == b'#')).collect()).collect();
        at += n+1;
        scans.push(format!("scan {} size {}",name,n));
        let decoded = decode(&grid,&tables,&field);
        let success = decoded.text.is_some();
        scan_counts[usize::from(!success)] += 1;
        scans.extend(decoded.lines);
        scans.push(format!("result {}",if success {
            "decoded"
        } else {
            "failed"
        }));
    }
    let mut capacity = Vec::new();
    for version in 1..=10 {
        let matrix = matrix::build(version,&tables.alignment[version-1]);
        let modules = matrix::order(&matrix.areas).len();
        let table = tables.table(version,0);
        let alignment = &tables.alignment[version-1];
        capacity.push(format!("version {} size {} data_modules {} codewords {} remainder {} alignment {}",version,17+4*version,modules,table.total(),modules-8*table.total(),if alignment.is_empty() {
            "none".to_owned()
        } else {
            alignment.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")
        }));
        for level in 0..4 {
            let table = tables.table(version,level);
            let counts: Vec<_> = (0..3).map(|mode| {
                let mut count = 0;
                while 4+count_width(mode,version)+data_width(mode,count+1) <= 8*table.data() {
                    count += 1;
                }
                count
            }).collect();
            capacity.push(format!("level {} blocks {} data {} ec_per_block {} numeric {} alphanumeric {} byte {}",LEVELS[level],table.sizes.len(),table.data(),table.ec,counts[0],counts[1],counts[2]));
        }
    }
    let summary = vec![format!("requests {} encoded {} errors {}",requests.len(),totals[0],error_counts.iter().sum::<usize>()),format!("error_kinds level {} mode {} version {} mask {} text {} charset {} capacity {}",error_counts[0],error_counts[1],error_counts[2],error_counts[3],error_counts[4],error_counts[5],error_counts[6]),format!("modes NUMERIC {} ALPHANUMERIC {} BYTE {} MIXED {}",mode_counts[0],mode_counts[1],mode_counts[2],mode_counts[3]),format!("levels L {} M {} Q {} H {} boosted {}",level_counts[0],level_counts[1],level_counts[2],level_counts[3],boosted),format!("versions {}",version_counts.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")),format!("masks {}",mask_counts.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")),format!("segments {} data_codewords {} ec_codewords {}",totals[1],totals[2],totals[3]),format!("modules {} dark {}",totals[4],totals[5]),format!("checks {} ok {} mismatch {} failed {}",check_counts.iter().sum::<usize>(),check_counts[0],check_counts[1],check_counts[2]),format!("blocks ok {} corrected {} failed {} codewords {}",block_counts[0],block_counts[1],block_counts[2],block_counts[3]),format!("scans {} decoded {} failed {}",scan_counts.iter().sum::<usize>(),scan_counts[0],scan_counts[1])];
    for (name,lines) in [("codes.txt",codes),("codewords.txt",codewords),("bitstream.txt",bitstream_lines),("selfcheck.txt",selfcheck),("scans.txt",scans),("capacity.txt",capacity),("summary.txt",summary)] {
        write(name,&lines);
    }
}
