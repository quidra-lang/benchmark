use std::{collections::BTreeMap, fs, io};

pub struct Point {
    pub id: i64,
    pub x: i64,
    pub y: i64,
}

pub struct Params {
    pub eps: Vec<i64>,
    pub min_pts: usize,
    pub max_eps: i64,
    pub extract: Vec<i64>,
    pub xi: String,
    pub u: i64,
    pub v: i64,
    pub min_size: usize,
    pub width: usize,
    pub height: usize,
    pub k_width: usize,
    pub k_height: usize,
    pub plot_width: usize,
}

pub fn read_inputs() -> io::Result<(Vec<Point>, Params)> {
    let text = fs::read_to_string("input/points.csv")?;
    let mut points: Vec<Point> = text.lines().skip(1).map(|line| {
        let row: Vec<i64> = line.split(',').map(|v| v.parse().unwrap()).collect();
        Point { id: row[0], x: row[1], y: row[2] }
    }).collect();
    points.sort_by_key(|p| p.id);
    let text = fs::read_to_string("input/params.txt")?;
    let rows: BTreeMap<&str, Vec<&str>> = text.lines().map(|line| {
        let mut fields = line.split(' ');
        (fields.next().unwrap(), fields.collect())
    }).collect();
    let list = |key: &str| rows[key].iter().map(|v| v.parse::<i64>().unwrap()).collect::<Vec<_>>();
    let xi = rows["XI"][0].to_owned();
    let (u, v) = xi.split_once('/').unwrap();
    let params = Params {
        eps: list("EPS"), min_pts: list("MIN_PTS")[0] as usize,
        max_eps: list("OPTICS_MAX_EPS")[0], extract: list("EXTRACT_EPS"),
        u: u.parse().unwrap(), v: v.parse().unwrap(), xi,
        min_size: list("XI_MIN_SIZE")[0] as usize,
        width: list("MAP_SIZE")[0] as usize, height: list("MAP_SIZE")[1] as usize,
        k_width: list("KDIST_PLOT")[0] as usize, k_height: list("KDIST_PLOT")[1] as usize,
        plot_width: list("PLOT_WIDTH")[0] as usize,
    };
    Ok((points, params))
}
