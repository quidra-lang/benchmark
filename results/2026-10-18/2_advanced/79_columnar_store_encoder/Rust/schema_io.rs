use std::fs;
pub const TYPES: [&str;4] = ["INT","STRING","BOOL","DATE"];
#[derive(Clone,PartialEq,Eq,PartialOrd,Ord)] pub enum Value {
    Null,
    Number(i64),
    Text(String),
    Boolean(bool),
    Unknown
}
#[derive(Clone)] pub struct Column {
    pub name: String,
    pub kind: usize,
    pub nullable: bool
}
pub struct Options {
    pub group: usize,
    pub page: usize,
    pub dictionary: usize,
    pub methods: Vec<String>
}
pub struct Input {
    pub schema: Vec<Column>,
    pub table: Vec<Vec<Value>>,
    pub options: Options,
    pub queries: Vec<String>,
    pub damaged: Vec<u8>
}
pub fn leap(year: i64) -> bool {
    year%4 == 0 && (year%100 != 0 || year%400 == 0)
}
fn year_days(year: i64) -> i64 {
    if leap(year) {
        366
    } else {
        365
    }
}
fn month_days(year: i64, month: usize) -> i64 {
    if month == 2 && leap(year) {
        29
    } else {
        [31,28,31,30,31,30,31,31,30,31,30,31][month-1]
    }
}
pub fn date(source: &str) -> i64 {
    let p: Vec<i64> = source.split('-').map(|s| s.parse().unwrap()).collect();
    let (year,month,day) = (p[0],p[1] as usize,p[2]);
    let before = |y: i64| (y-1)/4-(y-1)/100+(y-1)/400;
    let mut days = 365*(year-1970)+before(year)-before(1970);
    for m in 1..month {
        days += month_days(year,m);
    }
    days+day-1
}
pub fn date_text(mut days: i64) -> String {
    let mut year = 1970;
    while days < 0 {
        year -= 1;
        days += year_days(year);
    }
    while days >= year_days(year) {
        days -= year_days(year);
        year += 1;
    }
    let mut month = 1;
    while days >= month_days(year,month) {
        days -= month_days(year,month);
        month += 1;
    }
    format!("{:04}-{:02}-{:02}",year,month,days+1)
}
pub fn field(source: &str, kind: usize) -> Value {
    if source.is_empty() {
        Value::Null
    } else {
        match kind {
            0 => Value::Number(source.parse().unwrap()),1 => Value::Text(source.to_owned()),2 => Value::Boolean(source == "true"),_ => Value::Number(date(source))
        }
    }
}
pub fn text(value: &Value, kind: usize, csv: bool) -> String {
    match value {
        Value::Null => if csv {
            String::new()
        } else {
            "NULL".to_owned()
        },Value::Number(v) => if kind == 3 {
            date_text(*v)
        } else {
            v.to_string()
        },Value::Text(v) => v.clone(),Value::Boolean(v) => v.to_string(),Value::Unknown => "?".to_owned()
    }
}
pub fn read() -> Input {
    let schema: Vec<_> = fs::read_to_string("input/schema.txt").unwrap().lines().map(|line| {
        let w: Vec<_> = line.split_whitespace().collect();
        Column {
            name: w[0].to_owned(),
            kind: TYPES.iter().position(|&t| t == w[1]).unwrap(),
            nullable: w[2] == "NULLABLE"
        }
    }).collect();
    let table = fs::read_to_string("input/table.csv").unwrap().lines().skip(1).map(|line| line.split(',').zip(&schema).map(|(value,column)| field(value,column.kind)).collect()).collect();
    let source = fs::read_to_string("input/options.txt").unwrap();
    let lines: Vec<Vec<_>> = source.lines().map(|l| l.split_whitespace().collect()).collect();
    let options = Options {
        group: lines[0][1].parse().unwrap(),
        page: lines[1][1].parse().unwrap(),
        dictionary: lines[2][1].parse().unwrap(),
        methods: lines[3..].iter().map(|w| w[2].to_owned()).collect()
    };
    let queries = fs::read_to_string("input/queries.txt").unwrap().lines().map(str::to_owned).collect();
    let hex: String = fs::read_to_string("input/damaged.hex").unwrap().lines().collect();
    let damaged = (0..hex.len()).step_by(2).map(|i| u8::from_str_radix(&hex[i..i+2],16).unwrap()).collect();
    Input {
        schema,
        table,
        options,
        queries,
        damaged
    }
}
pub fn write(name: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    let content = if lines.is_empty() {
        String::new()
    } else {
        lines.join("\n")+"\n"
    };
    fs::write(format!("output/{}",name),content).unwrap();
}
