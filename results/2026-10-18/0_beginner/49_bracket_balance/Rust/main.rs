fn main() {
    for s in [
        "(a + b) * [c - d]",
        "{x = [1, 2, (3 + 4)]}",
        "f(a[i] + g(b)}",
        "(1 + 2)) * 3",
        "if (a < b) { c = d[0]; }",
        "((a + b] * c",
        "[{(x * y) - z}",
    ] {
        let mut stack = Vec::new();
        let mut error = None;
        for (i, c) in s.bytes().enumerate() {
            match c {
                b'(' | b'[' | b'{' => stack.push(c),
                b')' | b']' | b'}' => {
                    let expected = match c {
                        b')' => b'(',
                        b']' => b'[',
                        _ => b'{',
                    };
                    if stack.pop() != Some(expected) {
                        error = Some(i);
                        break;
                    }
                }
                _ => {}
            }
        }
        if error.is_none() && !stack.is_empty() {
            error = Some(s.len());
        }
        match error {
            None => println!("{} -> balanced", s),
            Some(i) => println!("{} -> error at index {}", s, i),
        }
    }
}
