use crate::dataframe::{Input, Value};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone)]
pub struct Factor {
    pub name: String,
    pub column: usize,
    pub categorical: bool,
    pub power: usize,
}

#[derive(Clone)]
pub struct Term {
    pub factors: Vec<Factor>,
}

impl Term {
    pub fn name(&self) -> String { self.factors.iter().map(|f| f.name.clone()).collect::<Vec<_>>().join(":") }
    pub fn contained(&self, other: &Self) -> bool {
        self.factors.len() < other.factors.len() && self.factors.iter().all(|f| other.factors.iter().any(|other| other.name == f.name))
    }
}

pub struct Model {
    pub formula: String,
    pub response: usize,
    pub weight: Option<usize>,
    pub terms: Vec<Term>,
}

fn factor(text: &str, names: &[String]) -> Factor {
    let categorical = text.starts_with("C(");
    let (column, power) = if categorical { (&text[2..text.len() - 1], 1) }
        else if text.starts_with("I(") {
            let (name, exponent) = text[2..text.len() - 1].split_once('^').unwrap();
            (name, exponent.parse().unwrap())
        } else { (text, 1) };
    Factor { name: text.into(), column: names.iter().position(|name| name == column).unwrap(), categorical, power }
}

pub fn parse(text: &str, input: &Input) -> Model {
    let (formula, weight) = text.split_once(" weights=").map_or((text, None), |(formula, weight)| (formula, Some(input.names.iter().position(|name| name == weight).unwrap())));
    let (response, expressions) = formula.split_once(" ~ ").unwrap();
    let mut terms: Vec<Term> = Vec::new();
    for expression in expressions.split(" + ") {
        let star = expression.contains('*');
        let factors: Vec<_> = expression.split(if star { '*' } else { ':' }).map(|text| factor(text, &input.names)).collect();
        let subsets = if star {
            let mut subsets: Vec<Vec<usize>> = (1..1_usize << factors.len()).map(|mask| (0..factors.len()).filter(|&i| mask & (1 << i) != 0).collect()).collect();
            subsets.sort_by_key(|subset| (subset.len(), subset.clone()));
            subsets
        } else { vec![(0..factors.len()).collect()] };
        for subset in subsets {
            let term = Term { factors: subset.iter().map(|&i| factors[i].clone()).collect() };
            let set: BTreeSet<_> = term.factors.iter().map(|f| f.name.clone()).collect();
            if !terms.iter().any(|other| other.factors.iter().map(|f| f.name.clone()).collect::<BTreeSet<_>>() == set) { terms.push(term); }
        }
    }
    Model { formula: formula.into(), response: input.names.iter().position(|name| name == response).unwrap(), weight, terms }
}

pub fn format(model: &Model, selected: &[usize], input: &Input) -> String {
    let terms: Vec<_> = selected.iter().map(|&term| model.terms[term].name()).collect();
    std::format!("{} ~ {}", input.names[model.response], if terms.is_empty() { "1".into() } else { terms.join(" + ") })
}

#[derive(Clone)]
struct Component {
    name: String,
    column: usize,
    level: Option<String>,
    power: usize,
}

pub struct Column {
    pub name: String,
    pub term: Option<usize>,
    components: Vec<Component>,
}

pub struct Design {
    pub used: Vec<usize>,
    pub levels: BTreeMap<usize, Vec<String>>,
    pub columns: Vec<Column>,
    factor_columns: BTreeSet<usize>,
}

impl Design {
    pub fn build(input: &Input, model: &Model) -> Self {
        let factor_columns: BTreeSet<_> = model.terms.iter().flat_map(|term| term.factors.iter().map(|factor| factor.column)).collect();
        let mut variables = factor_columns.clone();
        variables.insert(model.response);
        if let Some(weight) = model.weight { variables.insert(weight); }
        let used: Vec<_> = input.rows.iter().enumerate().filter(|(_, row)| variables.iter().all(|&column| !row[column].missing())).map(|(i, _)| i).collect();
        let mut levels = BTreeMap::new();
        for &column in factor_columns.iter().filter(|&&column| input.categorical[column]) {
            levels.insert(column, used.iter().map(|&i| input.rows[i][column].label().unwrap().to_string()).collect::<BTreeSet<_>>().into_iter().collect::<Vec<_>>());
        }
        let mut columns = vec![Column { name: "(Intercept)".into(), term: None, components: Vec::new() }];
        for (term_index, term) in model.terms.iter().enumerate() {
            let components: Vec<Vec<Component>> = term.factors.iter().map(|factor| {
                if factor.categorical {
                    levels[&factor.column].iter().skip(1).map(|level| Component { name: std::format!("{}{}", factor.name, level), column: factor.column, level: Some(level.clone()), power: 1 }).collect()
                } else { vec![Component { name: factor.name.clone(), column: factor.column, level: None, power: factor.power }] }
            }).collect();
            let count: usize = components.iter().map(Vec::len).product();
            for index in 0..count {
                let mut stride = 1;
                let mut selected = Vec::new();
                for factor in &components { selected.push(factor[index / stride % factor.len()].clone()); stride *= factor.len(); }
                columns.push(Column { name: selected.iter().map(|component| component.name.clone()).collect::<Vec<_>>().join(":"), term: Some(term_index), components: selected });
            }
        }
        Self { used, levels, columns, factor_columns }
    }

    pub fn values(&self, row: &[Value]) -> Vec<f64> {
        self.columns.iter().map(|column| column.components.iter().fold(1.0, |product, component| {
            let value = if let Some(level) = &component.level { if row[component.column].label() == Some(level.as_str()) { 1.0 } else { 0.0 } }
                else { let value = row[component.column].number().unwrap(); match component.power { 2 => value * value, 3 => value * value * value, _ => value } };
            product * value
        })).collect()
    }

    pub fn predictable(&self, row: &[Value]) -> bool {
        self.factor_columns.iter().all(|&column| !row[column].missing() && self.levels.get(&column).is_none_or(|levels| row[column].label().is_some_and(|level| levels.iter().any(|candidate| candidate == level))))
    }

    pub fn indices(&self, selected: &[usize]) -> Vec<usize> {
        self.columns.iter().enumerate().filter(|(_, column)| column.term.is_none_or(|term| selected.contains(&term))).map(|(i, _)| i).collect()
    }
}
