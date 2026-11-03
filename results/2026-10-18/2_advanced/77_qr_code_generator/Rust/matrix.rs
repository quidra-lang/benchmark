pub type Grid = Vec<Vec<u8>>;
pub struct Matrix {
    pub modules: Grid,
    pub areas: Grid
}
pub fn remainder(mut value: usize, generator: usize) -> usize {
    let degree = usize::BITS-generator.leading_zeros();
    while value != 0 && usize::BITS-value.leading_zeros() >= degree {
        value ^= generator<<(usize::BITS-value.leading_zeros()-degree);
    }
    value
}
pub fn format(level: usize, mask: usize) -> usize {
    let indicator = [1,0,3,2][level];
    let value = 8*indicator+mask;
    ((value<<10)+remainder(value<<10,0b10100110111))^0b101010000010010
}
pub fn version(version: usize) -> usize {
    (version<<12)+remainder(version<<12,0b1111100100101)
}
pub fn format_positions(n: usize) -> [Vec<(usize,usize)>;2] {
    let first = (0..15).map(|i| if i <= 5 {
        (8,i)
    } else if i == 6 {
        (8,7)
    } else if i == 7 {
        (8,8)
    } else if i == 8 {
        (7,8)
    } else {
        (14-i,8)
    }).collect();
    let second = (0..15).map(|i| if i <= 7 {
        (n-1-i,8)
    } else {
        (8,n-15+i)
    }).collect();
    [first,second]
}
pub fn version_positions(n: usize) -> [Vec<(usize,usize)>;2] {
    [(0..18).map(|i| (n-11+i%3,i/3)).collect(),(0..18).map(|i| (i/3,n-11+i%3)).collect()]
}
pub fn write(grid: &mut Grid, positions: &[(usize,usize)], value: usize) {
    for (i,&(x,y)) in positions.iter().enumerate() {
        grid[y][x] = ((value>>i)&1) as u8;
    }
}
pub fn read(grid: &Grid, positions: &[(usize,usize)]) -> usize {
    positions.iter().enumerate().fold(0,|value,(i,&(x,y))| value+((grid[y][x] as usize)<<i))
}
pub fn build(version: usize, alignment: &[usize]) -> Matrix {
    let n = 17+4*version;
    let mut modules = vec![vec![0;n];n];
    let mut areas = modules.clone();
    for (cx,cy) in [(3,3),(n-4,3),(3,n-4)].iter().copied() {
        for dy in -4i32..=4 {
            for dx in -4i32..=4 {
                let x = cx as i32+dx;
                let y = cy as i32+dy;
                if x >= 0 && y >= 0 && x < n as i32 && y < n as i32 {
                    let d = dx.abs().max(dy.abs());
                    modules[y as usize][x as usize] = u8::from(d == 0 || d == 1 || d == 3);
                    areas[y as usize][x as usize] = 1;
                }
            }
        }
    }
    for i in 8..=n-9 {
        modules[i][6] = u8::from(i%2 == 0);
        modules[6][i] = u8::from(i%2 == 0);
        areas[i][6] = 1;
        areas[6][i] = 1;
    }
    if let Some(&first) = alignment.first() {
        let last = *alignment.last().unwrap();
        for &cx in alignment {
            for &cy in alignment {
                if (cx,cy) == (first,first) || (cx,cy) == (first,last) || (cx,cy) == (last,first) {
                    continue;
                }
                for dy in -2i32..=2 {
                    for dx in -2i32..=2 {
                        let x = (cx as i32+dx) as usize;
                        let y = (cy as i32+dy) as usize;
                        let d = dx.abs().max(dy.abs());
                        modules[y][x] = u8::from(d == 0 || d == 2);
                        areas[y][x] = 1;
                    }
                }
            }
        }
    }
    modules[n-8][8] = 1;
    areas[n-8][8] = 1;
    for positions in &format_positions(n) {
        for &(x,y) in positions {
            areas[y][x] = 2;
        }
    }
    if version >= 7 {
        for positions in &version_positions(n) {
            for &(x,y) in positions {
                areas[y][x] = 3;
            }
            write(&mut modules,positions,self::version(version));
        }
    }
    Matrix {
        modules,
        areas
    }
}
pub fn order(areas: &Grid) -> Vec<(usize,usize)> {
    let n = areas.len();
    let mut rights = Vec::new();
    let mut right = n-1;
    while right >= 8 {
        rights.push(right);
        right -= 2;
    }
    rights.extend([5,3,1].iter().copied());
    let mut result = Vec::new();
    for (pair,&right) in rights.iter().enumerate() {
        for index in 0..n {
            let y = if pair%2 == 0 {
                n-1-index
            } else {
                index
            };
            for x in [right,right-1].iter().copied() {
                if areas[y][x] == 0 {
                    result.push((x,y));
                }
            }
        }
    }
    result
}
