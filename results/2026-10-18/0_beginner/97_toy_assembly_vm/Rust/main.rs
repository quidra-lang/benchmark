fn value(token: &str, registers: &[i64; 4]) -> i64 {
    let c = token.as_bytes()[0];
    if (b'A'..=b'D').contains(&c) {
        registers[(c - b'A') as usize]
    } else {
        token.parse().unwrap()
    }
}

fn main() {
    let program = [
        "SET A 1",
        "SET B 1",
        "SET D 8",
        "MUL A B",
        "PRINT A",
        "ADD B 1",
        "SUB D 1",
        "JNZ D -4",
        "SET A 1071",
        "SET B 462",
        "SET C A",
        "MOD C B",
        "SET A B",
        "SET B C",
        "JNZ B -4",
        "PRINT A",
        "HALT",
    ];
    let mut registers = [0_i64; 4];
    let (mut pc, mut executed) = (0_i32, 0);
    while (0..program.len() as i32).contains(&pc) {
        let parts: Vec<&str> = program[pc as usize].split(' ').collect();
        executed += 1;
        let op = parts[0];
        if op == "HALT" {
            break;
        }
        if op == "JNZ" {
            pc += if value(parts[1], &registers) != 0 {
                parts[2].parse::<i32>().unwrap()
            } else {
                1
            };
            continue;
        }
        if op == "PRINT" {
            println!("{}", value(parts[1], &registers));
        } else {
            let r = (parts[1].as_bytes()[0] - b'A') as usize;
            let x = value(parts[2], &registers);
            match op {
                "SET" => registers[r] = x,
                "ADD" => registers[r] += x,
                "SUB" => registers[r] -= x,
                "MUL" => registers[r] *= x,
                "MOD" => registers[r] %= x,
                _ => unreachable!(),
            }
        }
        pc += 1;
    }
    println!("executed: {}", executed);
}
