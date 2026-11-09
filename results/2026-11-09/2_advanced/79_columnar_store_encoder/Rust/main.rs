mod schema_io;
mod bitstream;
mod encoding;
mod query;
use std::collections::{BTreeMap,BTreeSet};
use schema_io::{Column,Value};
use bitstream::Reader;
use query::{Condition,Literal,Query};
type Statistics = Option<(Value,Value)>;
fn statistics(values: &[Value]) -> Statistics {
    let values: Vec<_> = values.iter().filter(|v| **v != Value::Null).collect();
    values.iter().min().zip(values.iter().max()).map(|(a,b)| ((**a).clone(),(**b).clone()))
}
fn write_statistics(bytes: &mut Vec<u8>, statistics: &Statistics, kind: usize) {
    if let Some((minimum,maximum)) = statistics {
        bytes.push(1);
        encoding::write_stat(bytes,minimum,kind);
        encoding::write_stat(bytes,maximum,kind);
    } else {
        bytes.push(0);
    }
}
fn read_statistics(reader: &mut Reader<'_>, kind: usize) -> Statistics {
    if reader.byte() == 0 {
        None
    } else {
        Some((encoding::read_stat(reader,kind),encoding::read_stat(reader,kind)))
    }
}
fn statistics_text(statistics: &Statistics, kind: usize) -> String {
    statistics.as_ref().map_or_else(|| "stats none".to_owned(),|(lo,hi)| format!("min {} max {}",schema_io::text(lo,kind,false),schema_io::text(hi,kind,false)))
}
fn page(bytes: &mut Vec<u8>, kind: u8, method: usize, count: usize, nulls: usize, statistics: &Statistics, column: &Column, body: &[u8]) {
    bytes.push(kind);
    bytes.push(method as u8);
    bitstream::unsigned(bytes,count as u64);
    bitstream::unsigned(bytes,nulls as u64);
    bitstream::unsigned(bytes,body.len() as u64);
    bitstream::integer(bytes,bitstream::adler(body));
    write_statistics(bytes,statistics,column.kind);
    bytes.extend(body);
}
struct Candidate {
    bytes: Vec<u8>,
    dictionary: bool,
    methods: Vec<usize>,
    pages: usize,
    nulls: usize,
    statistics: Statistics,
    fallback: usize
}
fn chunk(values: &[Value], column: &Column, method: usize, page_size: usize, limit: usize) -> Candidate {
    let pages: Vec<_> = values.chunks(page_size).collect();
    let mut dictionary = Vec::new();
    let mut used = 0;
    if method == 1 {
        for values in &pages {
            let mut trial = dictionary.clone();
            for value in values.iter().filter(|v| **v != Value::Null) {
                if !trial.contains(value) {
                    trial.push(value.clone());
                }
            }
            if encoding::encode(&trial,column.kind,0,&[]).len() > limit {
                break;
            }
            dictionary = trial;
            used += 1;
        }
        if dictionary.is_empty() {
            used = 0;
        }
    }
    let mut bytes = Vec::new();
    let mut methods = BTreeSet::new();
    if used > 0 {
        let body = encoding::encode(&dictionary,column.kind,0,&[]);
        page(&mut bytes,1,0,dictionary.len(),0,&None,column,&body);
    }
    for (index,values) in pages.iter().enumerate() {
        let chosen = if method == 1 && index >= used {
            0
        } else {
            method
        };
        methods.insert(chosen);
        let mut body = Vec::new();
        if column.nullable {
            let definitions: Vec<_> = values.iter().map(|v| u64::from(*v != Value::Null)).collect();
            let encoded = bitstream::hybrid(&definitions,1);
            bitstream::integer(&mut body,encoded.len() as u64);
            body.extend(encoded);
        }
        let nonnull: Vec<_> = values.iter().filter(|v| **v != Value::Null).cloned().collect();
        body.extend(encoding::encode(&nonnull,column.kind,chosen,&dictionary));
        page(&mut bytes,0,chosen,values.len(),values.len()-nonnull.len(),&statistics(values),column,&body);
    }
    Candidate {
        bytes,
        dictionary: used > 0,
        methods: methods.into_iter().collect(),
        pages: pages.len(),
        nulls: values.iter().filter(|v| **v == Value::Null).count(),
        statistics: statistics(values),
        fallback: if method == 1 {
            pages.len()-used
        } else {
            0
        }
    }
}
struct Page {
    offset: usize,
    header: usize,
    body: usize,
    kind: usize,
    method: usize,
    count: usize,
    nulls: usize,
    checksum: u64,
    statistics: Statistics
}
struct Chunk {
    offset: usize,
    size: usize,
    methods: Vec<usize>,
    dictionary: bool,
    count: usize,
    nulls: usize,
    statistics: Statistics,
    pages: Vec<Page>
}
impl Chunk {
    fn data(&self, page: usize) -> &Page {
        &self.pages[usize::from(self.dictionary)+page]
    }
}
struct Group {
    rows: usize,
    first: usize,
    chunks: Vec<Chunk>
}
struct File {
    bytes: Vec<u8>,
    version: usize,
    schema: Vec<Column>,
    rows: usize,
    groups: Vec<Group>,
    footer_offset: usize,
    footer_bytes: usize
}
fn write_file(input: &schema_io::Input) -> (Vec<u8>,Vec<String>) {
    let mut bytes = b"MPTC".to_vec();
    let mut groups = Vec::new();
    let mut report = vec!["row_group,column,encoding,bytes,fallback_pages,chosen".to_owned()];
    for (g,rows) in input.table.chunks(input.options.group).enumerate() {
        let mut chunks = Vec::new();
        for (c,column) in input.schema.iter().enumerate() {
            let values: Vec<_> = rows.iter().map(|row| row[c].clone()).collect();
            let methods = encoding::candidates(column.kind);
            let candidates: Vec<_> = methods.iter().map(|&method| chunk(&values,column,method,input.options.page,input.options.dictionary)).collect();
            let configured = &input.options.methods[c];
            let mut chosen = if configured == "AUTO" {
                (0..methods.len()).min_by_key(|&i| (candidates[i].bytes.len(),methods[i])).unwrap()
            } else {
                methods.iter().position(|&m| encoding::METHODS[m] == configured).unwrap()
            };
            if methods[chosen] == 1 && !candidates[chosen].dictionary {
                chosen = methods.iter().position(|&m| m == 0).unwrap();
            }
            for (i,candidate) in candidates.iter().enumerate() {
                report.push(format!("{},{},{},{},{},{}",g,column.name,encoding::METHODS[methods[i]],candidate.bytes.len(),candidate.fallback,if i == chosen {
                    "yes"
                } else {
                    "no"
                }));
            }
            let selected = &candidates[chosen];
            let offset = bytes.len();
            bytes.extend(&selected.bytes);
            chunks.push(Chunk {
                offset,
                size: selected.bytes.len(),
                methods: selected.methods.clone(),
                dictionary: selected.dictionary,
                count: selected.pages,
                nulls: selected.nulls,
                statistics: selected.statistics.clone(),
                pages: Vec::new()
            });
        }
        groups.push(Group {
            rows: rows.len(),
            first: g*input.options.group,
            chunks
        });
    }
    let mut footer = Vec::new();
    bitstream::unsigned(&mut footer,1);
    bitstream::unsigned(&mut footer,input.schema.len() as u64);
    for column in &input.schema {
        bitstream::unsigned(&mut footer,column.name.len() as u64);
        footer.extend(column.name.bytes());
        footer.push(column.kind as u8);
        footer.push(u8::from(column.nullable));
    }
    bitstream::unsigned(&mut footer,input.table.len() as u64);
    bitstream::unsigned(&mut footer,groups.len() as u64);
    for group in &groups {
        bitstream::unsigned(&mut footer,group.rows as u64);
        for (c,chunk) in group.chunks.iter().enumerate() {
            bitstream::unsigned(&mut footer,chunk.offset as u64);
            bitstream::unsigned(&mut footer,chunk.size as u64);
            bitstream::unsigned(&mut footer,chunk.methods.len() as u64);
            footer.extend(chunk.methods.iter().map(|&m| m as u8));
            footer.push(u8::from(chunk.dictionary));
            bitstream::unsigned(&mut footer,chunk.count as u64);
            bitstream::unsigned(&mut footer,chunk.nulls as u64);
            write_statistics(&mut footer,&chunk.statistics,input.schema[c].kind);
        }
    }
    bytes.extend(&footer);
    bitstream::integer(&mut bytes,footer.len() as u64);
    bytes.extend(b"MPTC");
    (bytes,report)
}
fn parse_file(bytes: Vec<u8>) -> File {
    let footer_bytes = Reader {
        data: &bytes,
        at: bytes.len()-8
    }.integer() as usize;
    let footer_offset = bytes.len()-8-footer_bytes;
    let mut reader = Reader {
        data: &bytes,
        at: footer_offset
    };
    let version = reader.unsigned() as usize;
    let columns = reader.unsigned() as usize;
    let mut schema = Vec::new();
    for _ in 0..columns {
        let length = reader.unsigned() as usize;
        let name = String::from_utf8(reader.take(length).to_vec()).unwrap();
        schema.push(Column {
            name,
            kind: reader.byte() as usize,
            nullable: reader.byte() == 1
        });
    }
    let rows = reader.unsigned() as usize;
    let count = reader.unsigned() as usize;
    let mut groups = Vec::new();
    let mut first = 0;
    for _ in 0..count {
        let group_rows = reader.unsigned() as usize;
        let mut chunks = Vec::new();
        for column in &schema {
            let offset = reader.unsigned() as usize;
            let size = reader.unsigned() as usize;
            let method_count = reader.unsigned() as usize;
            let methods = (0..method_count).map(|_| reader.byte() as usize).collect();
            let dictionary = reader.byte() == 1;
            let count = reader.unsigned() as usize;
            let nulls = reader.unsigned() as usize;
            let statistics = read_statistics(&mut reader,column.kind);
            let mut pages = Vec::new();
            let mut at = offset;
            while at < offset+size {
                let mut page_reader = Reader {
                    data: &bytes,
                    at
                };
                let kind = page_reader.byte() as usize;
                let method = page_reader.byte() as usize;
                let count = page_reader.unsigned() as usize;
                let nulls = page_reader.unsigned() as usize;
                let body = page_reader.unsigned() as usize;
                let checksum = page_reader.integer();
                let statistics = read_statistics(&mut page_reader,column.kind);
                let header = page_reader.at-at;
                pages.push(Page {
                    offset: at,
                    header,
                    body,
                    kind,
                    method,
                    count,
                    nulls,
                    checksum,
                    statistics
                });
                at += header+body;
            }
            chunks.push(Chunk {
                offset,
                size,
                methods,
                dictionary,
                count,
                nulls,
                statistics,
                pages
            });
        }
        groups.push(Group {
            rows: group_rows,
            first,
            chunks
        });
        first += group_rows;
    }
    File {
        bytes,
        version,
        schema,
        rows,
        groups,
        footer_offset,
        footer_bytes
    }
}
fn body<'a>(file: &'a File, page: &Page) -> &'a [u8] {
    &file.bytes[page.offset+page.header..page.offset+page.header+page.body]
}
fn dictionary(file: &File, column: usize, page: &Page) -> Vec<Value> {
    encoding::decode(&mut Reader::new(body(file,page)),page.count,file.schema[column].kind,0,&[])
}
fn decode_page(file: &File, column: usize, page: &Page, dictionary: &[Value]) -> Vec<Value> {
    let mut reader = Reader::new(body(file,page));
    let definitions = if file.schema[column].nullable {
        let length = reader.integer() as usize;
        bitstream::decode_hybrid(&mut Reader::new(reader.take(length)),page.count,1)
    } else {
        vec![1;page.count]
    };
    let count = definitions.iter().filter(|&&d| d == 1).count();
    let values = encoding::decode(&mut reader,count,file.schema[column].kind,page.method,dictionary);
    let mut values = values.into_iter();
    definitions.into_iter().map(|definition| if definition == 0 {
        Value::Null
    } else {
        values.next().unwrap()
    }).collect()
}
fn methods(methods: &[usize]) -> String {
    methods.iter().map(|&m| encoding::METHODS[m]).collect::<Vec<_>>().join(",")
}
fn column_lines(schema: &[Column]) -> Vec<String> {
    schema.iter().enumerate().map(|(c,column)| format!("column {} {} {} {}",c,column.name,schema_io::TYPES[column.kind],if column.nullable {
        "NULLABLE"
    } else {
        "REQUIRED"
    })).collect()
}
fn metadata(file: &File, original: &[Vec<Value>]) -> Vec<String> {
    let mut lines = vec![format!("file bytes {} footer_offset {} footer_bytes {}",file.bytes.len(),file.footer_offset,file.footer_bytes),format!("table version {} rows {} columns {} row_groups {}",file.version,file.rows,file.schema.len(),file.groups.len())];
    lines.extend(column_lines(&file.schema));
    let mut cells = 0;
    let mut nulls = 0;
    let mut mismatches = 0;
    let mut checksum_errors = 0;
    for (g,group) in file.groups.iter().enumerate() {
        lines.push(format!("row_group {} rows {} first_row {} bytes {}",g,group.rows,group.first,group.chunks.iter().map(|c| c.size).sum::<usize>()));
        for (c,chunk) in group.chunks.iter().enumerate() {
            let column = &file.schema[c];
            lines.push(format!("chunk {} {} offset {} size {} encodings {} dictionary {} pages {} nulls {} {}",g,column.name,chunk.offset,chunk.size,methods(&chunk.methods),if chunk.dictionary {
                "yes"
            } else {
                "no"
            },chunk.count,chunk.nulls,statistics_text(&chunk.statistics,column.kind)));
            let mut dictionary_values = Vec::new();
            let mut p = 0;
            let mut row = group.first;
            for page in &chunk.pages {
                checksum_errors += usize::from(bitstream::adler(body(file,page)) != page.checksum);
                if page.kind == 1 {
                    lines.push(format!("page {} {} dict offset {} header {} body {} checksum {:08x} entries {}",g,column.name,page.offset,page.header,page.body,page.checksum,page.count));
                    dictionary_values = dictionary(file,c,page);
                } else {
                    lines.push(format!("page {} {} {} offset {} header {} body {} checksum {:08x} encoding {} values {} nulls {} {}",g,column.name,p,page.offset,page.header,page.body,page.checksum,encoding::METHODS[page.method],page.count,page.nulls,statistics_text(&page.statistics,column.kind)));
                    for value in decode_page(file,c,page,&dictionary_values) {
                        cells += 1;
                        nulls += usize::from(value == Value::Null);
                        mismatches += usize::from(value != original[row][c]);
                        row += 1;
                    }
                    p += 1;
                }
            }
        }
    }
    for (c,column) in file.schema.iter().enumerate() {
        let chunks: Vec<_> = file.groups.iter().map(|g| &g.chunks[c]).collect();
        let methods: BTreeSet<_> = chunks.iter().flat_map(|c| c.methods.iter().copied()).collect();
        lines.push(format!("summary {} bytes {} data_pages {} dictionary_pages {} encodings {}",column.name,chunks.iter().map(|c| c.size).sum::<usize>(),chunks.iter().map(|c| c.count).sum::<usize>(),chunks.iter().filter(|c| c.dictionary).count(),self::methods(&methods.into_iter().collect::<Vec<_>>())));
    }
    lines.push(format!("roundtrip {} cells {} nulls {} mismatches {} checksum_errors {}",if mismatches == 0 && checksum_errors == 0 {
        "ok"
    } else {
        "failed"
    },cells,nulls,mismatches,checksum_errors));
    lines
}
fn recover(file: &File) -> (Vec<String>,Vec<String>) {
    let mut lines = vec![format!("file bytes {} rows {} columns {} row_groups {}",file.bytes.len(),file.rows,file.schema.len(),file.groups.len())];
    lines.extend(column_lines(&file.schema));
    let mut recovered = vec![vec![Value::Null;file.schema.len()];file.rows];
    let mut examined = 0;
    let mut damaged = 0;
    let mut lost = 0;
    let mut cells = 0;
    for (g,group) in file.groups.iter().enumerate() {
        for (c,chunk) in group.chunks.iter().enumerate() {
            let mut dictionary_values = Vec::new();
            let mut dictionary_damaged = false;
            let mut p = 0;
            let mut row = group.first;
            for page in &chunk.pages {
                examined += 1;
                let checksum = bitstream::adler(body(file,page));
                let bad = checksum != page.checksum;
                if bad {
                    damaged += 1;
                    lines.push(format!("damaged {} {} {} offset {} stored {:08x} computed {:08x}",g,file.schema[c].name,if page.kind == 1 {
                        "dict".to_owned()
                    } else {
                        p.to_string()
                    },page.offset,page.checksum,checksum));
                }
                if page.kind == 1 {
                    dictionary_damaged = bad;
                    if !bad {
                        dictionary_values = dictionary(file,c,page);
                    }
                } else {
                    let reason = if bad {
                        Some("checksum")
                    } else if page.method == 1 && dictionary_damaged {
                        Some("dictionary")
                    } else {
                        None
                    };
                    let values = if let Some(reason) = reason {
                        lost += 1;
                        cells += page.count;
                        lines.push(format!("lost {} {} {} rows {} reason {}",g,file.schema[c].name,p,page.count,reason));
                        vec![Value::Unknown;page.count]
                    } else {
                        decode_page(file,c,page,&dictionary_values)
                    };
                    for value in values {
                        recovered[row][c] = value;
                        row += 1;
                    }
                    p += 1;
                }
            }
        }
    }
    lines.push(format!("summary pages {} damaged {} lost_pages {} lost_cells {} recovered_cells {}",examined,damaged,lost,cells,file.rows*file.schema.len()-cells));
    let mut csv = vec![file.schema.iter().map(|c| c.name.as_str()).collect::<Vec<_>>().join(",")];
    for row in recovered {
        csv.push(row.iter().zip(&file.schema).map(|(value,column)| schema_io::text(value,column.kind,true)).collect::<Vec<_>>().join(","));
    }
    (lines,csv)
}
fn column(schema: &[Column], name: &str) -> usize {
    schema.iter().position(|c| c.name == name).unwrap()
}
fn condition_columns(condition: &Condition, names: &mut BTreeSet<String>) {
    match condition {
        Condition::Comparison(name,_,_) => {
            names.insert(name.clone());
        },Condition::Not(child) => condition_columns(child,names),Condition::Binary(_,left,right) => {
            condition_columns(left,names);
            condition_columns(right,names);
        }
    }
}
fn aggregate(query: &Query) -> bool {
    query.group.is_some() || query.items.iter().any(|i| i.aggregate.is_some())
}
fn query_error(query: &Query, schema: &[Column]) -> Option<&'static str> {
    let mut names: BTreeSet<_> = query.items.iter().filter_map(|i| i.column.clone()).collect();
    if let Some(condition) = &query.condition {
        condition_columns(condition,&mut names);
    }
    if let Some(group) = &query.group {
        names.insert(group.clone());
    }
    if let Some((order,_)) = &query.order {
        names.insert(order.clone());
    }
    if names.iter().any(|name| !schema.iter().any(|c| c.name == *name)) {
        return Some("unknown_column");
    }
    fn mismatch(condition: &Condition, schema: &[Column]) -> bool {
        match condition {
            Condition::Comparison(name,_,literals) => {
                let kind = schema[column(schema,name)].kind;
                literals.iter().any(|literal| !matches!((kind,literal),(0,Literal::Integer(_)) | (1,Literal::String(_)) | (2,Literal::Boolean(_)) | (3,Literal::String(_))))
            },Condition::Not(child) => mismatch(child,schema),Condition::Binary(_,left,right) => mismatch(left,schema) || mismatch(right,schema)
        }
    }
    if query.condition.as_ref().map_or(false,|c| mismatch(c,schema)) {
        return Some("type_mismatch");
    }
    if query.items.iter().any(|i| (i.aggregate.as_deref() == Some("SUM") || i.aggregate.as_deref() == Some("AVG")) && schema[column(schema,i.column.as_ref().unwrap())].kind != 0) {
        return Some("bad_aggregate");
    }
    if aggregate(query) && query.items.iter().any(|i| i.aggregate.is_none() && i.column != query.group) {
        return Some("not_grouped");
    }
    if aggregate(query) && query.order.is_some() {
        return Some("bad_order");
    }
    None
}
fn literal(literal: &Literal, kind: usize) -> Value {
    match literal {
        Literal::Integer(v) => Value::Number(*v),Literal::Boolean(v) => Value::Boolean(*v),Literal::String(v) => if kind == 3 {
            Value::Number(schema_io::date(v))
        } else {
            Value::Text(v.clone())
        }
    }
}
fn not(value: u8) -> u8 {
    if value == 2 {
        2
    } else {
        1-value
    }
}
fn logical(and: bool, a: u8, b: u8) -> u8 {
    if and {
        if a == 1 || b == 1 {
            1
        } else if a == 2 || b == 2 {
            2
        } else {
            0
        }
    } else if a == 0 || b == 0 {
        0
    } else if a == 2 || b == 2 {
        2
    } else {
        1
    }
}
fn evaluate(condition: &Condition, row: &[Value], schema: &[Column]) -> u8 {
    match condition {
        Condition::Not(child) => not(evaluate(child,row,schema)),Condition::Binary(and,left,right) => logical(*and,evaluate(left,row,schema),evaluate(right,row,schema)), Condition::Comparison(name,operator,literals) => {
            let c = column(schema,name);
            let value = &row[c];
            if operator == "IS NULL" {
                return u8::from(*value != Value::Null);
            }
            if operator == "IS NOT NULL" {
                return u8::from(*value == Value::Null);
            }
            if *value == Value::Null {
                return 2;
            }
            let values: Vec<_> = literals.iter().map(|l| literal(l,schema[c].kind)).collect();
            let result = match operator.as_str() {
                "=" => *value == values[0],"<>" => *value != values[0],"<" => *value < values[0],"<=" => *value <= values[0],">" => *value > values[0],">=" => *value >= values[0],"BETWEEN" => values[0] <= *value && *value <= values[1],_ => values.contains(value)
            };
            u8::from(!result)
        }
    }
}
struct Zone<'a> {
    statistics: &'a Statistics,
    nulls: usize,
    rows: usize
}
fn zone(condition: &Condition, schema: &[Column], zones: &[Zone<'_>]) -> BTreeSet<u8> {
    match condition {
        Condition::Not(child) => zone(child,schema,zones).into_iter().map(not).collect(), Condition::Binary(and,left,right) => {
            let left = zone(left,schema,zones);
            let right = zone(right,schema,zones);
            left.iter().flat_map(|&a| right.iter().map(move |&b| logical(*and,a,b))).collect()
        }
        Condition::Comparison(name,operator,literals) => {
            let c = column(schema,name);
            let information = &zones[c];
            let mut result = BTreeSet::new();
            if operator == "IS NULL" || operator == "IS NOT NULL" {
                let positive = if operator == "IS NULL" {
                    information.nulls > 0
                } else {
                    information.nulls < information.rows
                };
                let negative = if operator == "IS NULL" {
                    information.nulls < information.rows
                } else {
                    information.nulls > 0
                };
                if positive {
                    result.insert(0);
                }
                if negative {
                    result.insert(1);
                }
                return result;
            }
            if information.nulls > 0 {
                result.insert(2);
            }
            if let Some((lo,hi)) = information.statistics {
                let values: Vec<_> = literals.iter().map(|l| literal(l,schema[c].kind)).collect();
                let x = &values[0];
                let (yes,no) = match operator.as_str() {
                    "=" => (lo <= x && x <= hi,!(lo == x && hi == x)),"<>" => (!(lo == x && hi == x),lo <= x && x <= hi),"<" => (lo < x,hi >= x),"<=" => (lo <= x,hi > x),">" => (hi > x,lo <= x),">=" => (hi >= x,lo < x),"BETWEEN" => (lo <= &values[1] && hi >= x && values[0] <= values[1],lo < x || hi > &values[1]),_ => (values.iter().any(|x| lo <= x && x <= hi),!(lo == hi && values.contains(lo)))
                };
                if yes {
                    result.insert(0);
                }
                if no {
                    result.insert(1);
                }
            }
            result
        }
    }
}
type Row = (usize,Vec<Value>);
struct Scan {
    rows: Vec<Row>,
    counts: [usize;9],
    records: Vec<Option<String>>,
    needed: Vec<usize>
}
fn read_column(file: &File, group: usize, column: usize, page: usize, dictionary_values: &mut [Option<Vec<Value>>], counts: &mut [usize;9]) -> Vec<Value> {
    let chunk = &file.groups[group].chunks[column];
    let data = chunk.data(page);
    if data.method == 1 && dictionary_values[column].is_none() {
        let page = &chunk.pages[0];
        dictionary_values[column] = Some(dictionary(file,column,page));
        counts[5] += 1;
        counts[6] += page.header+page.body;
    }
    counts[2] += 1;
    counts[6] += data.header+data.body;
    decode_page(file,column,data,dictionary_values[column].as_deref().unwrap_or(&[]))
}
fn scan(file: &File, query: &Query) -> Scan {
    let mut names: BTreeSet<_> = query.items.iter().filter_map(|i| i.column.clone()).collect();
    let mut condition_names = BTreeSet::new();
    if let Some(condition) = &query.condition {
        condition_columns(condition,&mut condition_names);
        names.extend(condition_names.iter().cloned());
    }
    if let Some(group) = &query.group {
        names.insert(group.clone());
    }
    if let Some((order,_)) = &query.order {
        names.insert(order.clone());
    }
    let needed: Vec<_> = file.schema.iter().enumerate().filter(|(_,c)| names.contains(&c.name)).map(|(i,_)| i).collect();
    let condition_columns: Vec<_> = needed.iter().copied().filter(|&c| condition_names.contains(&file.schema[c].name)).collect();
    let remaining: Vec<_> = needed.iter().copied().filter(|c| !condition_columns.contains(c)).collect();
    let mut result = Scan {
        rows: Vec::new(),
        counts: [0;9],
        records: Vec::new(),
        needed
    };
    for (g,group) in file.groups.iter().enumerate() {
        let zones: Vec<_> = group.chunks.iter().map(|c| Zone {
            statistics: &c.statistics,
            nulls: c.nulls,
            rows: group.rows
        }).collect();
        if query.condition.as_ref().map_or(false,|condition| !zone(condition,&file.schema,&zones).contains(&0)) {
            result.counts[1] += 1;
            result.records.push(None);
            continue;
        }
        result.counts[0] += 1;
        if result.needed.is_empty() {
            result.counts[7] += group.rows;
            for row in 0..group.rows {
                result.rows.push((group.first+row,vec![Value::Null;file.schema.len()]));
            }
            result.records.push(Some("-".to_owned()));
            continue;
        }
        let mut dictionary_values = vec![None;file.schema.len()];
        let mut record = String::new();
        let mut first = group.first;
        for p in 0..group.chunks[0].count {
            let count = group.chunks[0].data(p).count;
            let zones: Vec<_> = group.chunks.iter().map(|c| {
                let page = c.data(p);
                Zone {
                    statistics: &page.statistics,
                    nulls: page.nulls,
                    rows: page.count
                }
            }).collect();
            if query.condition.as_ref().map_or(false,|condition| !zone(condition,&file.schema,&zones).contains(&0)) {
                result.counts[3] += result.needed.len();
                record.push('s');
                first += count;
                continue;
            }
            result.counts[7] += count;
            let mut rows = vec![vec![Value::Null;file.schema.len()];count];
            for &c in &condition_columns {
                let values = read_column(file,g,c,p,&mut dictionary_values,&mut result.counts);
                for (row,value) in rows.iter_mut().zip(values) {
                    row[c] = value;
                }
            }
            let matched: Vec<_> = rows.iter().enumerate().filter(|(_,row)| query.condition.as_ref().map_or(true,|condition| evaluate(condition,row,&file.schema) == 0)).map(|(i,_)| i).collect();
            if matched.is_empty() && !remaining.is_empty() {
                result.counts[4] += remaining.len();
                record.push('u');
            } else {
                for &c in &remaining {
                    let values = read_column(file,g,c,p,&mut dictionary_values,&mut result.counts);
                    for (row,value) in rows.iter_mut().zip(values) {
                        row[c] = value;
                    }
                }
                for row in matched {
                    result.rows.push((first+row,rows[row].clone()));
                }
                record.push('r');
            }
            first += count;
        }
        result.records.push(Some(record));
    }
    result.counts[8] = result.rows.len();
    result
}
#[derive(PartialEq,Eq)] struct QueryResult {
    kind: &'static str,
    matched: usize,
    rows: Vec<String>
}
fn result(query: &Query, rows: &[Row], schema: &[Column]) -> QueryResult {
    let kind = if query.group.is_some() {
        "grouped"
    } else if aggregate(query) {
        "aggregate"
    } else {
        "rows"
    };
    let mut output = Vec::new();
    if kind == "rows" {
        let mut rows: Vec<_> = rows.iter().collect();
        if let Some((order,descending)) = &query.order {
            let c = column(schema,order);
            rows.sort_by(|a,b| if *descending {
                b.1[c].cmp(&a.1[c])
            } else {
                a.1[c].cmp(&b.1[c])
            });
        }
        for row in rows {
            output.push(query.items.iter().map(|i| {
                let c = column(schema,i.column.as_ref().unwrap());
                schema_io::text(&row.1[c],schema[c].kind,false)
            }).collect::<Vec<_>>().join(","));
        }
    } else {
        let groups: Vec<(Value,Vec<&Row>)> = if let Some(group) = &query.group {
            let c = column(schema,group);
            let mut groups = BTreeMap::<Value,Vec<&Row>>::new();
            for row in rows {
                groups.entry(row.1[c].clone()).or_default().push(row);
            }
            groups.into_iter().collect()
        } else {
            vec![(Value::Null,rows.iter().collect())]
        };
        for (key,group) in groups {
            let mut cells = Vec::new();
            for item in &query.items {
                if item.aggregate.is_none() {
                    let c = column(schema,item.column.as_ref().unwrap());
                    cells.push(schema_io::text(&key,schema[c].kind,false));
                    continue;
                }
                let name = item.aggregate.as_deref().unwrap();
                if item.column.is_none() {
                    cells.push(group.len().to_string());
                    continue;
                }
                let c = column(schema,item.column.as_ref().unwrap());
                let values: Vec<_> = group.iter().map(|row| &row.1[c]).filter(|v| **v != Value::Null).collect();
                if name == "COUNT" {
                    cells.push(if item.distinct {
                        values.iter().copied().collect::<BTreeSet<_>>().len()
                    } else {
                        values.len()
                    }.to_string());
                } else if values.is_empty() {
                    cells.push("NULL".to_owned());
                } else if name == "MIN" || name == "MAX" {
                    let value = if name == "MIN" {
                        values.iter().min().unwrap()
                    } else {
                        values.iter().max().unwrap()
                    };
                    cells.push(schema_io::text(value,schema[c].kind,false));
                } else {
                    let total: i64 = values.iter().map(|v| if let Value::Number(v) = v {
                        *v
                    } else {
                        unreachable!()
                    }).sum();
                    if name == "SUM" {
                        cells.push(total.to_string());
                    } else {
                        let mut a = total.abs();
                        let mut b = values.len() as i64;
                        while b != 0 {
                            let remainder = a%b;
                            a = b;
                            b = remainder;
                        }
                        let numerator = total/a;
                        let denominator = values.len() as i64/a;
                        cells.push(if denominator == 1 {
                            numerator.to_string()
                        } else {
                            format!("{}/{}",numerator,denominator)
                        });
                    }
                }
            }
            output.push(cells.join(","));
        }
    }
    if let Some(limit) = query.limit {
        output.truncate(limit);
    }
    QueryResult {
        kind,
        matched: rows.len(),
        rows: output
    }
}
fn count_text(counts: &[usize;9]) -> String {
    ["row_groups_read","row_groups_skipped","pages_read","pages_skipped","pages_unneeded","dictionary_pages_read","bytes_read","rows_scanned","rows_matched"].iter().zip(counts.iter()).map(|(name,count)| format!("{} {}",name,count)).collect::<Vec<_>>().join(" ")
}
fn main() {
    let input = schema_io::read();
    let (bytes,encoding_report) = write_file(&input);
    let hex: Vec<_> = bytes.chunks(32).map(|chunk| chunk.iter().map(|byte| format!("{:02x}",byte)).collect()).collect();
    let file = parse_file(bytes);
    let metadata = metadata(&file,&input.table);
    let damaged = parse_file(input.damaged.clone());
    let (recovery,recovered) = recover(&damaged);
    let mut query_results = Vec::new();
    let mut query_stats = Vec::new();
    let mut totals = [0usize;9];
    let mut errors = 0;
    let mut checks = 0;
    for (index,source) in input.queries.iter().enumerate() {
        let number = index+1;
        let mut query = query::parse(source);
        if query.star {
            query.items = file.schema.iter().map(|c| query::Item {
                column: Some(c.name.clone()),
                aggregate: None,
                distinct: false
            }).collect();
        }
        if let Some(error) = query_error(&query,&file.schema) {
            errors += 1;
            let line = format!("query {} error {}",number,error);
            query_results.push(line.clone());
            query_stats.push(line);
            continue;
        }
        let scan = scan(&file,&query);
        let output = result(&query,&scan.rows,&file.schema);
        let reference: Vec<_> = input.table.iter().enumerate().filter(|(_,row)| query.condition.as_ref().map_or(true,|condition| evaluate(condition,row,&file.schema) == 0)).map(|(i,row)| (i,row.clone())).collect();
        let check = output == result(&query,&reference,&file.schema);
        checks += usize::from(check);
        query_results.push(format!("query {} {} matched {} output {}",number,output.kind,output.matched,output.rows.len()));
        query_results.push(format!("columns {}",query.items.iter().map(query::Item::header).collect::<Vec<_>>().join(",")));
        query_results.extend(output.rows);
        let needed = if scan.needed.is_empty() {
            "-".to_owned()
        } else {
            scan.needed.iter().map(|&c| file.schema[c].name.as_str()).collect::<Vec<_>>().join(",")
        };
        query_stats.push(format!("query {} columns {} {} check {}",number,needed,count_text(&scan.counts),if check {
            "ok"
        } else {
            "mismatch"
        }));
        for (g,record) in scan.records.iter().enumerate() {
            query_stats.push(format!("query {} row_group {} {}",number,g,record.as_ref().map_or_else(|| "skipped".to_owned(),|r| format!("pages {}",r))));
        }
        for i in 0..9 {
            totals[i] += scan.counts[i];
        }
    }
    query_stats.push(format!("total queries {} errors {} {} checks_ok {}",input.queries.len(),errors,count_text(&totals),checks));
    for (name,lines) in [("file.hex",hex),("metadata.txt",metadata),("encoding_report.csv",encoding_report),("query_results.txt",query_results),("query_stats.txt",query_stats),("recovery.txt",recovery),("recovered.csv",recovered)] {
        schema_io::write(name,&lines);
    }
}
