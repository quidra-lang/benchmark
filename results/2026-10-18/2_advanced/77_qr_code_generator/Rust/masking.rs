use crate::matrix::Grid;
pub fn condition(mask: usize, x: usize, y: usize) -> bool {
    match mask {
        0 => (x+y)%2 == 0,1 => y%2 == 0,2 => x%3 == 0,3 => (x+y)%3 == 0,4 => (y/2+x/3)%2 == 0,5 => (x*y)%2+(x*y)%3 == 0,6 => ((x*y)%2+(x*y)%3)%2 == 0,_ => ((x+y)%2+(x*y)%3)%2 == 0
    }
}
pub fn apply(grid: &Grid, areas: &Grid, mask: usize) -> Grid {
    let mut result = grid.clone();
    for y in 0..grid.len() {
        for x in 0..grid.len() {
            if areas[y][x] == 0 && condition(mask,x,y) {
                result[y][x] ^= 1;
            }
        }
    }
    result
}
pub fn penalty(grid: &Grid) -> [usize;4] {
    let n = grid.len();
    let mut result = [0;4];
    for down in [false,true].iter().copied() {
        for outer in 0..n {
            let values: Vec<_> = (0..n).map(|inner| if down {
                grid[inner][outer]
            } else {
                grid[outer][inner]
            }).collect();
            let mut first = 0;
            while first < n {
                let mut end = first+1;
                while end < n && values[end] == values[first] {
                    end += 1;
                }
                if end-first >= 5 {
                    result[0] += end-first-2;
                }
                first = end;
            }
            for window in values.windows(11) {
                if window == [1,0,1,1,1,0,1,0,0,0,0] || window == [0,0,0,0,1,0,1,1,1,0,1] {
                    result[2] += 40;
                }
            }
        }
    }
    for y in 0..n-1 {
        for x in 0..n-1 {
            if grid[y][x] == grid[y+1][x] && grid[y][x] == grid[y][x+1] && grid[y][x] == grid[y+1][x+1] {
                result[1] += 3;
            }
        }
    }
    let dark = grid.iter().flatten().map(|&v| v as usize).sum::<usize>();
    result[3] = 10*((20*dark).abs_diff(10*n*n)/(n*n));
    result
}
