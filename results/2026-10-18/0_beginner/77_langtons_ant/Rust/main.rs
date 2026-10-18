fn main() {
    let mut black = [[false; 11]; 11];
    let dr = [-1, 0, 1, 0];
    let dc = [0, 1, 0, -1];
    let (mut r, mut c, mut d) = (5_i32, 5_i32, 0);
    for _ in 0..300 {
        d = (d + if black[r as usize][c as usize] { 3 } else { 1 }) % 4;
        black[r as usize][c as usize] = !black[r as usize][c as usize];
        r = (r + dr[d] + 11) % 11;
        c = (c + dc[d] + 11) % 11;
    }
    let mut count = 0;
    for i in 0..11 {
        for j in 0..11 {
            count += i32::from(black[i][j]);
            print!("{}", if i == r as usize && j == c as usize {
                'A'
            } else if black[i][j] {
                '#'
            } else {
                '.'
            });
        }
        println!();
    }
    println!("black: {}", count);
}
