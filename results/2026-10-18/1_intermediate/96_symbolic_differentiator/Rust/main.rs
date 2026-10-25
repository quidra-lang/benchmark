use std::cmp::Ordering;
use std::collections::{BTreeSet, HashMap};
use std::io::{self, Read};

type Outcome<T> = Result<T, String>;

#[derive(Clone, Copy, PartialEq, Eq)]
struct Rational {
    numerator: i128,
    denominator: i128,
}

fn gcd(mut a: i128, mut b: i128) -> i128 {
    while b != 0 {
        (a, b) = (b, a % b);
    }
    a.abs()
}

impl Rational {
    fn new(mut numerator: i128, mut denominator: i128) -> Self {
        assert_ne!(denominator, 0);
        if denominator < 0 {
            numerator = -numerator;
            denominator = -denominator;
        }
        let divisor = gcd(numerator, denominator);
        Self {
            numerator: numerator / divisor,
            denominator: denominator / divisor,
        }
    }

    fn integer(value: i128) -> Self {
        Self::new(value, 1)
    }

    fn add(self, other: Self) -> Self {
        Self::new(
            self.numerator * other.denominator + other.numerator * self.denominator,
            self.denominator * other.denominator,
        )
    }

    fn multiply(self, other: Self) -> Self {
        Self::new(
            self.numerator * other.numerator,
            self.denominator * other.denominator,
        )
    }

    fn negate(self) -> Self {
        Self::new(-self.numerator, self.denominator)
    }

    fn power(mut self, exponent: i128) -> Outcome<Self> {
        if exponent < 0 {
            if self.numerator == 0 {
                return Err("division by zero".into());
            }
            self = Self::new(self.denominator, self.numerator);
        }
        let mut n = exponent.unsigned_abs();
        let mut result = Self::integer(1);
        while n != 0 {
            if n & 1 != 0 {
                result = result.multiply(self);
            }
            n >>= 1;
            if n != 0 {
                self = self.multiply(self);
            }
        }
        Ok(result)
    }
}

#[derive(Clone, PartialEq, Eq)]
enum Expression {
    Number(Rational),
    Variable(String),
    Sum(Vec<Expression>),
    Product(Vec<Expression>),
    Power(Box<Expression>, Box<Expression>),
    Function(String, Box<Expression>),
}

fn number(numerator: i128, denominator: i128) -> Expression {
    Expression::Number(Rational::new(numerator, denominator))
}

fn integer(value: i128) -> Expression {
    number(value, 1)
}

fn zero() -> Expression {
    integer(0)
}

fn one() -> Expression {
    integer(1)
}

fn minus_one() -> Expression {
    integer(-1)
}

fn half() -> Expression {
    number(1, 2)
}

fn kind(expression: &Expression) -> usize {
    match expression {
        Expression::Variable(_) => 0,
        Expression::Sum(_) => 1,
        Expression::Product(_) => 2,
        Expression::Power(_, _) => 3,
        Expression::Function(_, _) => 4,
        Expression::Number(_) => 5,
    }
}

fn compare_sequence(left: &[Expression], right: &[Expression]) -> Ordering {
    for (a, b) in left.iter().zip(right) {
        let result = compare(a, b);
        if result != Ordering::Equal {
            return result;
        }
    }
    left.len().cmp(&right.len())
}

fn compare(left: &Expression, right: &Expression) -> Ordering {
    let order = kind(left).cmp(&kind(right));
    if order != Ordering::Equal {
        return order;
    }
    match (left, right) {
        (Expression::Variable(a), Expression::Variable(b)) => a.cmp(b),
        (Expression::Sum(a), Expression::Sum(b))
        | (Expression::Product(a), Expression::Product(b)) => compare_sequence(a, b),
        (Expression::Power(ab, ax), Expression::Power(bb, bx)) => {
            let first = compare(ab, bb);
            if first == Ordering::Equal {
                compare(ax, bx)
            } else {
                first
            }
        }
        (Expression::Function(an, aa), Expression::Function(bn, ba)) => {
            let first = an.cmp(bn);
            if first == Ordering::Equal {
                compare(aa, ba)
            } else {
                first
            }
        }
        (Expression::Number(a), Expression::Number(b)) => {
            (a.numerator * b.denominator).cmp(&(b.numerator * a.denominator))
        }
        _ => Ordering::Equal,
    }
}

fn is_integer(expression: &Expression) -> bool {
    matches!(expression, Expression::Number(value) if value.denominator == 1)
}

fn base(expression: &Expression) -> &Expression {
    match expression {
        Expression::Power(base, _) => base,
        _ => expression,
    }
}

fn exponent(expression: &Expression) -> Expression {
    match expression {
        Expression::Power(_, exponent) => *exponent.clone(),
        _ => one(),
    }
}

fn coefficient(expression: &Expression) -> (Rational, Vec<Expression>) {
    match expression {
        Expression::Number(value) => (*value, Vec::new()),
        Expression::Product(factors) => {
            if let Expression::Number(value) = &factors[0] {
                (*value, factors[1..].to_vec())
            } else {
                (Rational::integer(1), factors.clone())
            }
        }
        _ => (Rational::integer(1), vec![expression.clone()]),
    }
}

fn product(coefficient: Rational, mut factors: Vec<Expression>) -> Expression {
    if factors.is_empty() {
        return Expression::Number(coefficient);
    }
    if coefficient != Rational::integer(1) {
        factors.insert(0, Expression::Number(coefficient));
    }
    if factors.len() == 1 {
        factors.remove(0)
    } else {
        Expression::Product(factors)
    }
}

fn compare_exponents(left: &Expression, right: &Expression) -> Ordering {
    match (left, right) {
        (Expression::Number(_), Expression::Number(_)) => compare(left, right),
        (Expression::Number(_), _) => Ordering::Less,
        (_, Expression::Number(_)) => Ordering::Greater,
        _ => compare(left, right),
    }
}

fn compare_terms(left: &Expression, right: &Expression) -> Ordering {
    let (_, a) = coefficient(left);
    let (_, b) = coefficient(right);
    let mut bases: Vec<Expression> = a.iter().chain(&b).map(|f| base(f).clone()).collect();
    bases.sort_by(compare);
    bases.dedup();
    for current in bases {
        let x = a.iter().find(|f| base(f) == &current).map(exponent).unwrap_or_else(zero);
        let y = b.iter().find(|f| base(f) == &current).map(exponent).unwrap_or_else(zero);
        let comparison = compare_exponents(&x, &y);
        if comparison != Ordering::Equal {
            return comparison.reverse();
        }
    }
    Ordering::Equal
}

fn add(expressions: Vec<Expression>) -> Outcome<Expression> {
    let mut terms = Vec::new();
    for expression in expressions {
        match expression {
            Expression::Sum(parts) => terms.extend(parts),
            Expression::Product(factors)
                if factors.len() == 2
                    && matches!(factors[0], Expression::Number(_))
                    && matches!(factors[1], Expression::Sum(_)) =>
            {
                if let Expression::Sum(parts) = &factors[1] {
                    for part in parts {
                        terms.push(multiply(vec![factors[0].clone(), part.clone()])?);
                    }
                }
            }
            other => terms.push(other),
        }
    }
    let mut groups: Vec<(Vec<Expression>, Rational)> = Vec::new();
    for expression in terms {
        let (c, monomial) = coefficient(&expression);
        if let Some((_, value)) = groups.iter_mut().find(|(m, _)| *m == monomial) {
            *value = value.add(c);
        } else {
            groups.push((monomial, c));
        }
    }
    let mut result: Vec<Expression> = groups
        .into_iter()
        .filter(|(_, c)| c.numerator != 0)
        .map(|(monomial, c)| product(c, monomial))
        .collect();
    result.sort_by(compare_terms);
    Ok(match result.len() {
        0 => zero(),
        1 => result.remove(0),
        _ => Expression::Sum(result),
    })
}

fn multiply(expressions: Vec<Expression>) -> Outcome<Expression> {
    let mut remaining = expressions;
    loop {
        let mut factors = Vec::new();
        for expression in remaining {
            if let Expression::Product(parts) = expression {
                factors.extend(parts);
            } else {
                factors.push(expression);
            }
        }
        let mut scalar = Rational::integer(1);
        let mut groups: Vec<(Expression, Vec<Expression>)> = Vec::new();
        for factor in factors {
            if let Expression::Number(value) = factor {
                scalar = scalar.multiply(value);
            } else {
                let key = base(&factor).clone();
                if let Some((_, values)) = groups.iter_mut().find(|(b, _)| b == &key) {
                    values.push(factor);
                } else {
                    groups.push((key, vec![factor]));
                }
            }
        }
        if scalar.numerator == 0 {
            return Ok(zero());
        }
        let mut reduced = Vec::new();
        for (key, factors) in groups {
            if factors.len() == 1 {
                reduced.push(factors.into_iter().next().unwrap());
            } else {
                let powers = factors.iter().map(exponent).collect();
                reduced.push(power(key, add(powers)?)?);
            }
        }
        let composite = reduced.iter().any(|f| {
            matches!(f, Expression::Number(_) | Expression::Product(_))
        });
        let duplicate = reduced.iter().enumerate().any(|(i, f)| {
            reduced[..i].iter().any(|g| base(f) == base(g))
        });
        if composite || duplicate {
            remaining = vec![Expression::Number(scalar)];
            remaining.extend(reduced);
            continue;
        }
        reduced.sort_by(|a, b| compare(base(a), base(b)));
        return Ok(product(scalar, reduced));
    }
}

fn exact_root(value: i128, degree: i128) -> Option<i128> {
    if value == 1 {
        return Some(1);
    }
    if degree > 32 || degree <= 0 {
        return None;
    }
    let nearest = (value as f64).powf(1.0 / degree as f64).round() as i128;
    for candidate in (nearest - 2).max(0)..=nearest + 2 {
        let mut result = 1_i128;
        let mut complete = true;
        for _ in 0..degree {
            if let Some(next) = result.checked_mul(candidate) {
                result = next;
            } else {
                complete = false;
                break;
            }
            if result > value {
                break;
            }
        }
        if complete && result == value {
            return Some(candidate);
        }
    }
    None
}

fn power(base: Expression, exponent: Expression) -> Outcome<Expression> {
    if exponent == zero() {
        return Ok(one());
    }
    if exponent == one() {
        return Ok(base);
    }
    if let Expression::Number(b) = base {
        if b == Rational::integer(1) {
            return Ok(one());
        }
        if let Expression::Number(x) = exponent {
            if b.numerator == 0 {
                if x.numerator > 0 {
                    return Ok(zero());
                }
                return Err("division by zero".into());
            }
            if x.denominator == 1 {
                return Ok(Expression::Number(b.power(x.numerator)?));
            }
            if b.numerator > 0 {
                if let (Some(s), Some(t)) = (
                    exact_root(b.numerator, x.denominator),
                    exact_root(b.denominator, x.denominator),
                ) {
                    return Ok(Expression::Number(Rational::new(s, t).power(x.numerator)?));
                }
            }
            return Ok(Expression::Power(
                Box::new(Expression::Number(b)),
                Box::new(Expression::Number(x)),
            ));
        }
        return Ok(Expression::Power(
            Box::new(Expression::Number(b)),
            Box::new(exponent),
        ));
    }
    if is_integer(&exponent) {
        if let Expression::Power(inner, previous) = &base {
            return power(*inner.clone(), multiply(vec![*previous.clone(), exponent])?);
        }
        if let Expression::Product(factors) = &base {
            let mut expanded = Vec::new();
            for factor in factors {
                expanded.push(power(factor.clone(), exponent.clone())?);
            }
            return multiply(expanded);
        }
    }
    Ok(Expression::Power(Box::new(base), Box::new(exponent)))
}

fn function(name: &str, argument: Expression) -> Outcome<Expression> {
    if name == "sqrt" {
        return power(argument, half());
    }
    if argument == zero() {
        match name {
            "sin" | "tan" | "ln" => {
                if name != "ln" {
                    return Ok(zero());
                }
            }
            "cos" | "exp" => return Ok(one()),
            _ => {}
        }
    }
    if name == "ln" && argument == one() {
        return Ok(zero());
    }
    if ["sin", "cos", "tan"].contains(&name)
        && coefficient(&argument).0.numerator < 0
    {
        let positive = multiply(vec![minus_one(), argument])?;
        let transformed = function(name, positive)?;
        return if name == "cos" {
            Ok(transformed)
        } else {
            multiply(vec![minus_one(), transformed])
        };
    }
    if let Expression::Function(inner, value) = &argument {
        if (name == "exp" && inner == "ln") || (name == "ln" && inner == "exp") {
            return Ok(*value.clone());
        }
    }
    Ok(Expression::Function(name.to_owned(), Box::new(argument)))
}

fn collect_variables(expression: &Expression, names: &mut BTreeSet<String>) {
    match expression {
        Expression::Variable(name) => {
            names.insert(name.clone());
        }
        Expression::Sum(parts) | Expression::Product(parts) => {
            for part in parts {
                collect_variables(part, names);
            }
        }
        Expression::Power(base, exponent) => {
            collect_variables(base, names);
            collect_variables(exponent, names);
        }
        Expression::Function(_, argument) => collect_variables(argument, names),
        Expression::Number(_) => {}
    }
}

fn variables(expression: &Expression) -> Vec<String> {
    let mut names = BTreeSet::new();
    collect_variables(expression, &mut names);
    names.into_iter().collect()
}

fn derivative(expression: &Expression, variable: &str) -> Outcome<Expression> {
    match expression {
        Expression::Number(_) => Ok(zero()),
        Expression::Variable(name) => Ok(if name == variable { one() } else { zero() }),
        Expression::Sum(parts) => {
            let mut result = Vec::new();
            for part in parts {
                result.push(derivative(part, variable)?);
            }
            add(result)
        }
        Expression::Product(factors) => {
            let mut terms = Vec::new();
            for i in 0..factors.len() {
                let mut parts = factors.clone();
                parts[i] = derivative(&factors[i], variable)?;
                terms.push(multiply(parts)?);
            }
            add(terms)
        }
        Expression::Power(base, exponent) => {
            let base = &**base;
            let exponent = &**exponent;
            let depends_on_exponent = variables(exponent).iter().any(|v| v == variable);
            let depends_on_base = variables(base).iter().any(|v| v == variable);
            if !depends_on_exponent {
                return multiply(vec![
                    exponent.clone(),
                    power(base.clone(), add(vec![exponent.clone(), minus_one()])?)?,
                    derivative(base, variable)?,
                ]);
            }
            let original = expression.clone();
            if !depends_on_base {
                return multiply(vec![
                    original,
                    function("ln", base.clone())?,
                    derivative(exponent, variable)?,
                ]);
            }
            multiply(vec![
                original,
                add(vec![
                    multiply(vec![
                        derivative(exponent, variable)?,
                        function("ln", base.clone())?,
                    ])?,
                    multiply(vec![
                        exponent.clone(),
                        derivative(base, variable)?,
                        power(base.clone(), minus_one())?,
                    ])?,
                ])?,
            ])
        }
        Expression::Function(name, argument) => {
            let argument = &**argument;
            let factor = match name.as_str() {
                "sin" => function("cos", argument.clone())?,
                "cos" => multiply(vec![minus_one(), function("sin", argument.clone())?])?,
                "tan" => power(function("cos", argument.clone())?, integer(-2))?,
                "exp" => expression.clone(),
                _ => power(argument.clone(), minus_one())?,
            };
            multiply(vec![factor, derivative(argument, variable)?])
        }
    }
}

fn substitute(
    expression: &Expression,
    values: &HashMap<String, Expression>,
) -> Outcome<Expression> {
    match expression {
        Expression::Variable(name) => {
            Ok(values.get(name).cloned().unwrap_or_else(|| expression.clone()))
        }
        Expression::Number(_) => Ok(expression.clone()),
        Expression::Sum(parts) => {
            let mut replaced = Vec::new();
            for part in parts {
                replaced.push(substitute(part, values)?);
            }
            add(replaced)
        }
        Expression::Product(factors) => {
            let mut replaced = Vec::new();
            for factor in factors {
                replaced.push(substitute(factor, values)?);
            }
            multiply(replaced)
        }
        Expression::Power(base, exponent) => {
            power(substitute(base, values)?, substitute(exponent, values)?)
        }
        Expression::Function(name, argument) => {
            function(name, substitute(argument, values)?)
        }
    }
}

fn distribute(left: Expression, right: Expression) -> Outcome<Expression> {
    let left_terms = if let Expression::Sum(parts) = left {
        parts
    } else {
        vec![left]
    };
    let right_terms = if let Expression::Sum(parts) = right {
        parts
    } else {
        vec![right]
    };
    let mut products = Vec::new();
    for a in left_terms {
        for b in &right_terms {
            products.push(multiply(vec![a.clone(), b.clone()])?);
        }
    }
    add(products)
}

fn expand(expression: &Expression) -> Outcome<Expression> {
    match expression {
        Expression::Number(_) | Expression::Variable(_) => Ok(expression.clone()),
        Expression::Function(name, argument) => function(name, expand(argument)?),
        Expression::Sum(parts) => {
            let mut transformed = Vec::new();
            for part in parts {
                transformed.push(expand(part)?);
            }
            add(transformed)
        }
        Expression::Product(factors) => {
            let mut parts = factors.iter();
            let mut result = expand(parts.next().unwrap())?;
            for part in parts {
                result = distribute(result, expand(part)?)?;
            }
            Ok(result)
        }
        Expression::Power(base, exponent) => {
            let b = expand(base)?;
            let x = expand(exponent)?;
            if matches!(b, Expression::Sum(_)) {
                if let Expression::Number(order) = x {
                    if order.denominator == 1 && order.numerator > 0 {
                        let mut result = b.clone();
                        for _ in 1..order.numerator {
                            result = distribute(result, b.clone())?;
                        }
                        return Ok(result);
                    }
                    return power(b, Expression::Number(order));
                }
            }
            power(b, x)
        }
    }
}

fn numerical_value(expression: &Expression) -> Outcome<f64> {
    match expression {
        Expression::Number(r) => Ok(r.numerator as f64 / r.denominator as f64),
        Expression::Variable(_) => unreachable!(),
        Expression::Sum(parts) => {
            let mut result = 0.0;
            for part in parts {
                result += numerical_value(part)?;
            }
            Ok(result)
        }
        Expression::Product(factors) => {
            let mut result = 1.0;
            for factor in factors {
                result *= numerical_value(factor)?;
            }
            Ok(result)
        }
        Expression::Power(base, exponent) => {
            let u = numerical_value(base)?;
            let x = numerical_value(exponent)?;
            let valid_integer = match &**exponent {
                Expression::Number(r) => r.denominator == 1,
                _ => x.fract() == 0.0,
            };
            if u < 0.0 && !valid_integer {
                return Err("domain error".into());
            }
            if **exponent == half() {
                Ok(u.sqrt())
            } else {
                Ok(u.powf(x))
            }
        }
        Expression::Function(name, argument) => {
            let a = numerical_value(argument)?;
            match name.as_str() {
                "sin" => Ok(a.sin()),
                "cos" => Ok(a.cos()),
                "tan" => Ok(a.tan()),
                "exp" => Ok(a.exp()),
                _ => {
                    if a <= 0.0 {
                        Err("domain error".into())
                    } else {
                        Ok(a.ln())
                    }
                }
            }
        }
    }
}

fn atomic(expression: &Expression) -> bool {
    match expression {
        Expression::Variable(_) | Expression::Function(_, _) => true,
        Expression::Number(r) => r.denominator == 1 && r.numerator >= 0,
        Expression::Power(_, exponent) => **exponent == half(),
        _ => false,
    }
}

fn atom(expression: &Expression) -> String {
    if atomic(expression) {
        show(expression)
    } else {
        format!("({})", show(expression))
    }
}

fn show_power(base: &Expression, exponent: &Expression) -> String {
    if *exponent == half() {
        format!("sqrt({})", show(base))
    } else {
        format!("{}^{}", atom(base), atom(exponent))
    }
}

fn show_factor(expression: &Expression) -> String {
    match expression {
        Expression::Sum(_) => format!("({})", show(expression)),
        Expression::Power(base, exponent) => show_power(base, exponent),
        _ => show(expression),
    }
}

fn quotient(coefficient: Rational, factors: &[Expression]) -> String {
    let mut numerator = Vec::new();
    let mut denominator = Vec::new();
    if coefficient.numerator.abs() != 1 {
        numerator.push(coefficient.numerator.abs().to_string());
    }
    if coefficient.denominator != 1 {
        denominator.push(coefficient.denominator.to_string());
    }
    for factor in factors {
        if let Expression::Power(base, exponent_expression) = factor {
            if let Expression::Number(exponent) = &**exponent_expression {
                if exponent.numerator < 0 {
                    let positive = Expression::Number(exponent.negate());
                    if positive == one() {
                        denominator.push(show_factor(base));
                    } else {
                        denominator.push(show_power(base, &positive));
                    }
                    continue;
                }
            }
        }
        numerator.push(show_factor(factor));
    }
    let top = if numerator.is_empty() {
        "1".to_owned()
    } else {
        numerator.join("*")
    };
    let result = match denominator.len() {
        0 => top,
        1 => format!("{}/{}", top, denominator[0]),
        _ => format!("{}/({})", top, denominator.join("*")),
    };
    if coefficient.numerator < 0 {
        format!("-{}", result)
    } else {
        result
    }
}

fn show(expression: &Expression) -> String {
    match expression {
        Expression::Number(r) => {
            if r.denominator == 1 {
                r.numerator.to_string()
            } else {
                format!("{}/{}", r.numerator, r.denominator)
            }
        }
        Expression::Variable(name) => name.clone(),
        Expression::Function(name, argument) => format!("{}({})", name, show(argument)),
        Expression::Power(base, exponent) => {
            if matches!(&**exponent, Expression::Number(r) if r.numerator < 0) {
                quotient(Rational::integer(1), &[expression.clone()])
            } else {
                show_power(base, exponent)
            }
        }
        Expression::Product(_) => {
            let (scalar, factors) = coefficient(expression);
            quotient(scalar, &factors)
        }
        Expression::Sum(terms) => {
            let mut output = String::new();
            for (i, term) in terms.iter().enumerate() {
                let rendered = show(term);
                if i == 0 {
                    output.push_str(&rendered);
                } else if let Some(rest) = rendered.strip_prefix('-') {
                    output.push_str(" - ");
                    output.push_str(rest);
                } else {
                    output.push_str(" + ");
                    output.push_str(&rendered);
                }
            }
            output
        }
    }
}

fn tokenize(source: &str) -> Outcome<Vec<String>> {
    let input = source.as_bytes();
    let mut position = 0;
    let mut result = Vec::new();
    while position < input.len() {
        let start = position;
        let byte = input[position];
        if byte == b' ' {
            position += 1;
            continue;
        }
        if byte.is_ascii_digit() {
            while position < input.len() && input[position].is_ascii_digit() {
                position += 1;
            }
        } else if byte.is_ascii_lowercase() {
            while position < input.len()
                && (input[position].is_ascii_lowercase() || input[position].is_ascii_digit())
            {
                position += 1;
            }
        } else if byte.is_ascii_uppercase() {
            while position < input.len()
                && (input[position].is_ascii_uppercase() || input[position].is_ascii_digit())
            {
                position += 1;
            }
        } else if b"+-*/^()".contains(&byte) {
            position += 1;
        } else {
            return Err(format!("invalid character '{}'", byte as char));
        }
        result.push(source[start..position].to_string());
    }
    Ok(result)
}

enum Tree {
    Value(Expression),
    Operation(String, Vec<Tree>),
}

struct Parser<'a> {
    tokens: Vec<String>,
    position: usize,
    names: &'a HashMap<String, Expression>,
}

impl Parser<'_> {
    fn peek(&self) -> Option<&str> {
        self.tokens.get(self.position).map(String::as_str)
    }

    fn unexpected(&self) -> String {
        match self.peek() {
            Some(token) => format!("unexpected '{}'", token),
            None => "unexpected end of expression".into(),
        }
    }

    fn accept(&mut self, symbol: &str) -> bool {
        if self.peek() == Some(symbol) {
            self.position += 1;
            true
        } else {
            false
        }
    }

    fn expect(&mut self, symbol: &str) -> Outcome<()> {
        if self.accept(symbol) {
            Ok(())
        } else {
            Err(self.unexpected())
        }
    }

    fn atom(&mut self) -> Outcome<Tree> {
        if self.accept("(") {
            let result = self.expression()?;
            self.expect(")")?;
            return Ok(result);
        }
        let token = self.peek().ok_or_else(|| self.unexpected())?.to_owned();
        let first = token.as_bytes()[0];
        if first.is_ascii_digit() {
            self.position += 1;
            return Ok(Tree::Value(integer(token.parse::<i128>().unwrap())));
        }
        if first.is_ascii_uppercase() {
            self.position += 1;
            return match self.names.get(&token) {
                Some(value) => Ok(Tree::Value(value.clone())),
                None => Err(format!("undefined name '{}'", token)),
            };
        }
        if first.is_ascii_lowercase() {
            self.position += 1;
            if is_function(&token) {
                self.expect("(")?;
                let child = self.expression()?;
                self.expect(")")?;
                return Ok(Tree::Operation(token, vec![child]));
            }
            return Ok(Tree::Value(Expression::Variable(token)));
        }
        Err(self.unexpected())
    }

    fn unary(&mut self) -> Outcome<Tree> {
        if self.accept("-") {
            return Ok(Tree::Operation("neg".into(), vec![self.unary()?]));
        }
        let start = self.atom()?;
        if self.accept("^") {
            Ok(Tree::Operation("^".into(), vec![start, self.unary()?]))
        } else {
            Ok(start)
        }
    }

    fn term(&mut self) -> Outcome<Tree> {
        let mut result = self.unary()?;
        while matches!(self.peek(), Some("*") | Some("/")) {
            let operator = self.peek().unwrap().to_owned();
            self.position += 1;
            result = Tree::Operation(operator, vec![result, self.unary()?]);
        }
        Ok(result)
    }

    fn expression(&mut self) -> Outcome<Tree> {
        let mut result = self.term()?;
        while matches!(self.peek(), Some("+") | Some("-")) {
            let operator = self.peek().unwrap().to_owned();
            self.position += 1;
            result = Tree::Operation(operator, vec![result, self.term()?]);
        }
        Ok(result)
    }
}

fn evaluate(tree: Tree) -> Outcome<Expression> {
    match tree {
        Tree::Value(value) => Ok(value),
        Tree::Operation(operation, children) => {
            let mut values = Vec::new();
            for child in children {
                values.push(evaluate(child)?);
            }
            match operation.as_str() {
                "+" => add(values),
                "-" => add(vec![
                    values[0].clone(),
                    multiply(vec![minus_one(), values[1].clone()])?,
                ]),
                "*" => multiply(values),
                "/" => multiply(vec![
                    values[0].clone(),
                    power(values[1].clone(), minus_one())?,
                ]),
                "^" => power(values[0].clone(), values[1].clone()),
                "neg" => multiply(vec![minus_one(), values[0].clone()]),
                name => function(name, values.remove(0)),
            }
        }
    }
}

fn parse_expression(source: &str, names: &HashMap<String, Expression>) -> Outcome<Expression> {
    let tokens = tokenize(source)?;
    let mut parser = Parser {
        tokens,
        position: 0,
        names,
    };
    let tree = parser.expression()?;
    if parser.position != parser.tokens.len() {
        return Err(parser.unexpected());
    }
    evaluate(tree)
}

fn is_function(name: &str) -> bool {
    matches!(name, "sin" | "cos" | "tan" | "exp" | "ln" | "sqrt")
}

fn valid_variable(name: &str) -> bool {
    let mut bytes = name.bytes();
    matches!(bytes.next(), Some(b'a'..=b'z'))
        && bytes.all(|b| b.is_ascii_lowercase() || b.is_ascii_digit())
        && !is_function(name)
}

fn valid_name(name: &str) -> bool {
    let mut bytes = name.bytes();
    matches!(bytes.next(), Some(b'A'..=b'Z'))
        && bytes.all(|b| b.is_ascii_uppercase() || b.is_ascii_digit())
}

fn valid_literal(source: &str) -> bool {
    let number = source.strip_prefix('-').unwrap_or(source);
    let (numerator, denominator) = match number.split_once('/') {
        Some((n, d)) => (n, Some(d)),
        None => (number, None),
    };
    !numerator.is_empty()
        && numerator.bytes().all(|b| b.is_ascii_digit())
        && denominator.map_or(true, |d| !d.is_empty() && d.bytes().all(|b| b.is_ascii_digit()))
}

fn parse_literal(source: &str) -> Outcome<Expression> {
    if !valid_literal(source) {
        return Err(format!("invalid number '{}'", source));
    }
    let (n, d) = match source.split_once('/') {
        Some((n, d)) => (n, d),
        None => (source, "1"),
    };
    let denominator: i128 = d.parse().unwrap();
    if denominator == 0 {
        return Err("division by zero".into());
    }
    Ok(number(n.parse().unwrap(), denominator))
}

fn parse_variable(source: &str) -> Outcome<String> {
    if valid_variable(source) {
        Ok(source.to_owned())
    } else {
        Err(format!("invalid variable '{}'", source))
    }
}

fn parse_order(source: &str) -> Outcome<usize> {
    if source.len() == 1 && matches!(source.as_bytes()[0], b'1'..=b'8') {
        Ok(source.parse().unwrap())
    } else {
        Err(format!("invalid order '{}'", source))
    }
}

fn substitute_one(expression: &Expression, variable: &str, value: Expression) -> Outcome<Expression> {
    substitute(expression, &HashMap::from([(variable.to_owned(), value)]))
}

fn process_command(
    line: &str,
    definitions: &mut HashMap<String, Expression>,
) -> Outcome<Vec<String>> {
    let (command, argument) = match line.split_once(' ') {
        Some((command, argument)) => (command, Some(argument)),
        None => (line, None),
    };

    if command == "LET" {
        let input = argument.unwrap_or("");
        let position = input.find('=').ok_or("wrong number of arguments")?;
        let name = input[..position].trim();
        if !valid_name(name) {
            return Err(format!("invalid name '{}'", name));
        }
        let value = parse_expression(input[position + 1..].trim(), definitions)?;
        let output = format!("{} = {}", name, show(&value));
        definitions.insert(name.to_owned(), value);
        return Ok(vec![output]);
    }

    let signature = match command {
        "SIMPLIFY" | "EXPAND" | "GRAD" | "HESSIAN" => "e",
        "DIFF" => "ev",
        "DIFFN" => "evn",
        "IMPLICIT" => "evv",
        "SUBST" => "eve",
        "EVAL" => "ea",
        "TANGENT" | "LIMIT" => "evc",
        "TAYLOR" => "evcn",
        _ => return Err(format!("unknown command {}", command)),
    };
    let fields: Vec<&str> = match argument {
        Some(arg) => arg.split(';').map(str::trim).collect(),
        None => Vec::new(),
    };
    if if command == "EVAL" {
        fields.len() != 1 && fields.len() != 2
    } else {
        fields.len() != signature.len()
    } {
        return Err("wrong number of arguments".into());
    }

    let expression = parse_expression(fields[0], definitions)?;
    match command {
        "SIMPLIFY" => Ok(vec![format!("simplified: {}", show(&expression))]),
        "EXPAND" => Ok(vec![format!("expanded: {}", show(&expand(&expression)?))]),
        "DIFF" => {
            let variable = parse_variable(fields[1])?;
            Ok(vec![format!(
                "d/d{} = {}",
                variable,
                show(&derivative(&expression, &variable)?)
            )])
        }
        "DIFFN" => {
            let variable = parse_variable(fields[1])?;
            let order = parse_order(fields[2])?;
            let mut current = expression;
            let mut output = Vec::new();
            for k in 1..=order {
                current = derivative(&current, &variable)?;
                output.push(format!("d^{}/d{}^{} = {}", k, variable, k, show(&current)));
            }
            Ok(output)
        }
        "GRAD" | "HESSIAN" => {
            let names = variables(&expression);
            if names.is_empty() {
                return Ok(vec!["no variables".into()]);
            }
            let mut output = Vec::new();
            for (i, variable) in names.iter().enumerate() {
                let first = derivative(&expression, variable)?;
                if command == "GRAD" {
                    output.push(format!("d/d{} = {}", variable, show(&first)));
                } else {
                    for second in &names[i..] {
                        output.push(format!(
                            "d2/d{}d{} = {}",
                            variable,
                            second,
                            show(&derivative(&first, second)?)
                        ));
                    }
                }
            }
            Ok(output)
        }
        "IMPLICIT" => {
            let variable = parse_variable(fields[1])?;
            let other = parse_variable(fields[2])?;
            if variable == other {
                return Err("same variable".into());
            }
            let result = multiply(vec![
                minus_one(),
                derivative(&expression, &variable)?,
                power(derivative(&expression, &other)?, minus_one())?,
            ])?;
            Ok(vec![format!("d{}/d{} = {}", other, variable, show(&result))])
        }
        "SUBST" => {
            let variable = parse_variable(fields[1])?;
            let replacement = parse_expression(fields[2], definitions)?;
            Ok(vec![format!(
                "substituted: {}",
                show(&substitute_one(&expression, &variable, replacement)?)
            )])
        }
        "EVAL" => {
            let mut assignments = HashMap::new();
            if fields.len() == 2 {
                for word in fields[1].split_whitespace() {
                    let pair = word.split_once('=');
                    let (variable, literal) = pair.unwrap_or(("", ""));
                    if pair.is_none() || !valid_variable(variable) || !valid_literal(literal) {
                        return Err(format!("invalid assignment '{}'", word));
                    }
                    let value = parse_literal(literal)?;
                    if assignments.contains_key(variable) {
                        return Err(format!("duplicate variable {}", variable));
                    }
                    assignments.insert(variable.to_owned(), value);
                }
            }
            for variable in variables(&expression) {
                if !assignments.contains_key(&variable) {
                    return Err(format!("no value for {}", variable));
                }
            }
            let reduced = substitute(&expression, &assignments)?;
            match reduced {
                Expression::Number(_) => Ok(vec![format!("exact: {}", show(&reduced))]),
                _ => Ok(vec![format!("approx: {:.6}", numerical_value(&reduced)?)]),
            }
        }
        "TANGENT" => {
            let variable = parse_variable(fields[1])?;
            let point = parse_literal(fields[2])?;
            let slope = substitute_one(&derivative(&expression, &variable)?, &variable, point.clone())?;
            let y = substitute_one(&expression, &variable, point.clone())?;
            let negative_point = match &point {
                Expression::Number(r) => Expression::Number(r.negate()),
                _ => unreachable!(),
            };
            let line = add(vec![
                multiply(vec![slope.clone(), Expression::Variable(variable.clone())])?,
                y.clone(),
                multiply(vec![negative_point, slope.clone()])?,
            ])?;
            let first = format!("tangent: y = {}", show(&line));
            if slope == zero() {
                return Ok(vec![first, format!("normal: {} = {}", variable, show(&point))]);
            }
            let reciprocal = power(slope, minus_one())?;
            let normal = add(vec![
                multiply(vec![
                    minus_one(),
                    reciprocal.clone(),
                    Expression::Variable(variable),
                ])?,
                y,
                multiply(vec![point, reciprocal])?,
            ])?;
            Ok(vec![first, format!("normal: y = {}", show(&normal))])
        }
        "LIMIT" => {
            let variable = parse_variable(fields[1])?;
            let point = parse_literal(fields[2])?;
            let factors = match expression {
                Expression::Product(parts) => parts,
                value => vec![value],
            };
            let mut numerator = Vec::new();
            let mut denominator = Vec::new();
            for factor in factors {
                match &factor {
                    Expression::Power(base, exponent)
                        if matches!(&**exponent, Expression::Number(r) if r.numerator < 0) =>
                    {
                        if let Expression::Number(r) = &**exponent {
                            denominator.push(power(*base.clone(), Expression::Number(r.negate()))?);
                        }
                    }
                    _ => numerator.push(factor),
                }
            }
            let mut top = multiply(numerator)?;
            let mut bottom = multiply(denominator)?;
            for k in 0..=5 {
                let a = substitute_one(&top, &variable, point.clone())?;
                let b = substitute_one(&bottom, &variable, point.clone())?;
                if b != zero() {
                    let result = multiply(vec![a, power(b, minus_one())?])?;
                    return Ok(vec![format!("limit: {}", show(&result))]);
                }
                if a != zero() {
                    return Ok(vec!["limit: unbounded".into()]);
                }
                if k == 5 {
                    return Ok(vec!["limit: unknown".into()]);
                }
                top = derivative(&top, &variable)?;
                bottom = derivative(&bottom, &variable)?;
            }
            unreachable!()
        }
        "TAYLOR" => {
            let variable = parse_variable(fields[1])?;
            let point = parse_literal(fields[2])?;
            let order = parse_order(fields[3])?;
            let mut derivatives = vec![expression];
            for _ in 0..order {
                let next = derivative(derivatives.last().unwrap(), &variable)?;
                derivatives.push(next);
            }
            let negative_point = if let Expression::Number(r) = point.clone() {
                Expression::Number(r.negate())
            } else {
                unreachable!()
            };
            let difference = add(vec![Expression::Variable(variable.clone()), negative_point])?;
            let mut factorial = 1_i128;
            let mut terms = Vec::new();
            for (k, derivative) in derivatives.iter().enumerate() {
                if k > 0 {
                    factorial *= k as i128;
                }
                let value = substitute_one(derivative, &variable, point.clone())?;
                let coefficient = multiply(vec![value, number(1, factorial)])?;
                terms.push(multiply(vec![
                    coefficient,
                    power(difference.clone(), integer(k as i128))?,
                ])?);
            }
            Ok(vec![format!("taylor: {}", show(&expand(&add(terms)?)?))])
        }
        _ => unreachable!(),
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count = lines.next().unwrap_or("0").trim().parse::<usize>().unwrap_or(0);
    let mut definitions = HashMap::new();
    let mut output = Vec::new();
    for _ in 0..count {
        let line = lines.next().unwrap_or("").trim_end_matches('\r');
        match process_command(line, &mut definitions) {
            Ok(lines) => output.extend(lines),
            Err(error) => output.push(format!("error: {}", error)),
        }
    }
    if !output.is_empty() {
        println!("{}", output.join("\n"));
    }
}
