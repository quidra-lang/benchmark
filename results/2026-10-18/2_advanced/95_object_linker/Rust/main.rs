mod object_parser;
mod archive;
mod resolver;
mod layout;
mod relocator;
use std::collections::{
    BTreeMap,
    BTreeSet,
    VecDeque
};
use std::fs;
use object_parser::{
    Object,
    Definition,
    Relocation
};
use layout::{
    Segment,
    OutputSection,
    Component,
    Kind,
    align
};
use resolver::Resolution;
struct Linker {
    entry: String,
    gc: bool,
    segments: Vec<Segment>,
    outputs: Vec<OutputSection>,
    loads: Vec<(String, String)>,
    keeps: BTreeSet<String>,
    sorts: BTreeSet<String>,
    wraps: BTreeSet<String>,
    defines: Vec<(String, String)>,
    checksum: Option<(String, String)>,
    inputs: Vec<Vec<String>>,
    objects: Vec<Object>,
    archives: BTreeMap<String,
    archive::Archive>,
    entries: BTreeMap<String,
    Vec<(usize, usize)>>,
    names: BTreeMap<String,
    Resolution>,
    comdats: Vec<(String, String, Vec<String>)>,
    extractions: Vec<(String, String, String)>,
    veneers: BTreeSet<(usize, String)>,
}
fn number(text: &str) -> i64 {
    if text.starts_with("0x") {
        i64::from_str_radix(&text[2..], 16).unwrap()
    } else {
        text.parse().unwrap()
    }
}
impl Linker {
    fn read() -> Self {
        let mut linker = Self {
            entry: String::new(),
            gc: true,
            segments: Vec::new(),
            outputs: Vec::new(),
            loads: Vec::new(),
            keeps: BTreeSet::new(),
            sorts: BTreeSet::new(),
            wraps: BTreeSet::new(),
            defines: Vec::new(),
            checksum: None,
            inputs: Vec::new(),
            objects: Vec::new(),
            archives: BTreeMap::new(),
            entries: BTreeMap::new(),
            names: BTreeMap::new(),
            comdats: Vec::new(),
            extractions: Vec::new(),
            veneers: BTreeSet::new()
        };
        for line in object_parser::lines("link.txt") {
            let fields: Vec<&str> = line.split(' ').collect();
            match fields[0] {
                "entry" => linker.entry = fields[1].into(),
                "gc" => linker.gc = fields[1] == "on",
                "segment" => {
                    let mut outputs = Vec::new();
                    for name in &fields[5..] {
                        outputs.push(linker.outputs.len());
                        linker.outputs.push(OutputSection {
                            name: name.to_string(),
                            components: Vec::new(),
                            address: 0,
                            size: 0,
                            alignment: 1
                        });
                    }
                    linker.segments.push(Segment {
                        name: fields[1].into(),
                        base: number(fields[2]),
                        length: number(fields[3]),
                        fill: number(fields[4]) as u8,
                        outputs,
                        memsz: 0,
                        filesz: 0,
                        paddr: 0,
                        used: 0,
                        image: Vec::new()
                    });
                },
                "load" => linker.loads.push((fields[1].into(), fields[2].into())),
                "keep" => {
                    linker.keeps.insert(fields[1].into());
                },
                "sort" => {
                    linker.sorts.insert(fields[1].into());
                },
                "wrap" => {
                    linker.wraps.insert(fields[1].into());
                },
                "define" => {
                    let (left, expression) = line.split_once(" = ").unwrap();
                    linker.defines.push((left[7..].into(), expression.into()));
                },
                "checksum" => linker.checksum = Some((fields[1].into(), fields[2].into())),
                _ => linker.inputs.push(fields.iter().map(|s| s.to_string()).collect())
            }
        }
        linker
    }
    fn undefined(&self, name: &str) -> bool {
        if self.defines.iter().any(|d| d.0 == name) {
            return false;
        }
        let entries = self.entries.get(name).map(Vec::as_slice).unwrap_or(&[]);
        if entries.iter().any(|&(o, s)| !matches!(self.objects[o].symbols[s].definition, Definition::Undefined)) {
            return false;
        }
        name == self.entry || entries.iter().any(|&(o, s)| self.objects[o].symbols[s].binding == "global")
    }
    fn load(&mut self, mut object: Object) {
        for (signature, sections) in &object.groups {
            if let Some(group) = self.comdats.iter_mut().find(|g| g.0 == *signature) {
                for &s in sections {
                    object.sections[s].discard = Some("comdat");
                }
                group.2.push(object.name.clone());
            }
            else {
                self.comdats.push((signature.clone(), object.name.clone(), Vec::new()));
            }
        }
        for symbol in &mut object.symbols {
            if symbol.binding != "local" {
                if let Definition::Section(section, _) = symbol.definition {
                    if object.sections[section].discard == Some("comdat") {
                        symbol.definition = Definition::Undefined;
                    }
                }
            }
            if matches!(symbol.definition, Definition::Undefined) {
                if self.wraps.contains(&symbol.name) {
                    symbol.name = format!("__wrap_{}", symbol.name);
                }
                else if let Some(real) = symbol.name.strip_prefix("__real_") {
                    if self.wraps.contains(real) {
                        symbol.name = real.into();
                    }
                }
            }
        }
        let o = self.objects.len();
        for (s, symbol) in object.symbols.iter().enumerate() {
            if symbol.binding != "local" {
                self.entries.entry(symbol.name.clone()).or_default().push((o, s));
            }
        }
        self.objects.push(object);
    }
    fn scan(&mut self, name: &str) -> bool {
        let mut archive = self.archives.remove(name).unwrap_or_else(|| archive::Archive::read(name));
        let changed = archive.scan(|member| {
            let reason = match member.exports.iter().find(|name| self.undefined(name)) {
                Some(reason) => reason.clone(),
                None => return false
            };
            let referrer = self.entries.get(&reason).into_iter().flat_map(|e| e.iter()).find(|&&(o, s)| self.objects[o].symbols[s].binding == "global" && matches!(self.objects[o].symbols[s].definition, Definition::Undefined)).map(|&(o, _)| self.objects[o].name.clone()).unwrap_or("*entry*".into());
            self.extractions.push((member.object.name.clone(), referrer, reason));
            self.load(member.object.clone());
            true
        });
        self.archives.insert(name.into(), archive);
        changed
    }
    fn load_inputs(&mut self) {
        for fields in self.inputs.clone() {
            if fields[0] == "object" {
                self.load(object_parser::parse(fields[1].clone(), &object_parser::lines(&fields[1])));
            }
            else if fields[0] == "library" {
                self.scan(&fields[1]);
            }
            else {
                loop {
                    let mut changed = false;
                    for name in &fields[1..] {
                        changed |= self.scan(name);
                    }
                    if !changed {
                        break;
                    }
                }
            }
        }
        let scripts: BTreeSet<String> = self.defines.iter().map(|d| d.0.clone()).collect();
        let names: BTreeSet<String> = self.entries.keys().cloned().chain(scripts.iter().cloned()).collect();
        for name in names {
            let entries = self.entries.get(&name).map(Vec::as_slice).unwrap_or(&[]);
            self.names.insert(name.clone(), resolver::resolve(&self.objects, entries, scripts.contains(&name)));
        }
        for object in &mut self.objects {
            for section in &mut object.sections {
                if section.discard.is_none() {
                    section.output = layout::output(&section.name, &self.outputs);
                    if section.output.is_none() {
                        section.discard = Some("orphan");
                    }
                }
            }
        }
    }
    fn target(&self, o: usize, relocation: &Relocation) -> Option<(Option<(usize, usize)>, Option<String>)> {
        let symbol = &self.objects[o].symbols[relocation.symbol];
        if symbol.binding == "local" {
            if let Definition::Section(s, _) = symbol.definition {
                return Some((Some((o, s)), None));
            }
        }
        else {
            let name = &self.names[&symbol.name];
            if name.kind == "common" {
                return Some((None, Some(symbol.name.clone())));
            }
            if let Some((o, s)) = name.definition {
                if let Definition::Section(section, _) = self.objects[o].symbols[s].definition {
                    return Some((Some((o, section)), None));
                }
            }
        }
        None
    }
    fn collect(&mut self) {
        let mut pending: VecDeque<(Option<(usize, usize)>, Option<String>)> = VecDeque::new();
        for (o, object) in self.objects.iter().enumerate() {
            for (s, section) in object.sections.iter().enumerate() {
                if section.discard.is_none() && (!self.gc || self.keeps.contains(&self.outputs[section.output.unwrap()].name)) {
                    pending.push_back((Some((o, s)), None));
                }
            }
        }
        for (name, resolution) in &self.names {
            if resolution.kind == "common" && !self.gc {
                pending.push_back((None, Some(name.clone())));
            }
        }
        if let Some(entry) = self.names.get(&self.entry) {
            if entry.kind == "common" {
                pending.push_back((None, Some(self.entry.clone())));
            }
            else if let Some((o, s)) = entry.definition {
                if let Definition::Section(section, _) = self.objects[o].symbols[s].definition {
                    pending.push_back((Some((o, section)), None));
                }
            }
        }
        while let Some((section, common)) = pending.pop_front() {
            if let Some((o, s)) = section {
                if self.objects[o].sections[s].live || self.objects[o].sections[s].discard.is_some() {
                    continue;
                }
                self.objects[o].sections[s].live = true;
                for relocation in &self.objects[o].relocations {
                    if relocation.section == s {
                        if let Some(target) = self.target(o, relocation) {
                            pending.push_back(target);
                        }
                    }
                }
            } else if let Some(name) = common {
                self.names.get_mut(&name).unwrap().live = true;
            }
        }
        for object in &mut self.objects {
            for section in &mut object.sections {
                if section.discard.is_none() && !section.live {
                    section.discard = Some("gc");
                }
            }
        }
        for resolution in self.names.values_mut() {
            if let Some((o, s)) = resolution.definition {
                if let Definition::Section(section, _) = self.objects[o].symbols[s].definition {
                    resolution.live = self.objects[o].sections[section].live;
                }
            }
        }
    }
    fn merged(&self, sections: &[(usize, usize)]) -> Component {
        let mut unique: BTreeMap<Vec<u8>,
        i64> = BTreeMap::new();
        let mut data = Vec::new();
        let mut positions = Vec::new();
        let mut strings = 0;
        let mut total = 0;
        for &(o, s) in sections {
            let section = &self.objects[o].sections[s];
            total += section.size;
            let mut start = 0;
            for end in 0..section.data.len() {
                if section.data[end] == 0 {
                    let string = section.data[start..=end].to_vec();
                    let offset = if let Some(&offset) = unique.get(&string) {
                        offset
                    } else {
                        let offset = data.len() as i64;
                        data.extend(&string);
                        unique.insert(string, offset);
                        offset
                    };
                    positions.push((o, s, start as i64, offset));
                    strings += 1;
                    start = end + 1;
                }
            }
        }
        Component {
            kind: Kind::Merged {
                sections: sections.len(),
                strings,
                unique: unique.len(),
                saved: total - data.len() as i64,
                positions
            },
            size: data.len() as i64,
            alignment: 1,
            address: 0,
            data
        }
    }
    fn layout(&mut self) {
        for index in 0..self.outputs.len() {
            let name = self.outputs[index].name.clone();
            let mut sections = Vec::new();
            for (o, object) in self.objects.iter().enumerate() {
                for (s, section) in object.sections.iter().enumerate() {
                    if section.live && section.output == Some(index) {
                        sections.push((o, s));
                    }
                }
            }
            if self.sorts.contains(&name) {
                sections.sort_by_key(|&(o, s)| {
                    let section = &self.objects[o].sections[s];
                    if section.name == name {
                        65536
                    } else {
                        section.name[name.len() + 1..].parse::<i64>().unwrap()
                    }
                });
            }
            let strings: Vec<(usize, usize)> = sections.iter().copied().filter(|&(o, s)| object_parser::strings(&self.objects[o].sections[s].name)).collect();
            let mut emitted = false;
            let mut components = Vec::new();
            for (o, s) in sections {
                let section = &self.objects[o].sections[s];
                if object_parser::strings(&section.name) {
                    if !emitted {
                        components.push(self.merged(&strings));
                        emitted = true;
                    }
                }
                else {
                    components.push(Component {
                        kind: Kind::Input(o, s),
                        size: section.size,
                        alignment: section.alignment,
                        address: 0,
                        data: section.data.clone()
                    });
                }
            }
            if name == ".bss" {
                let mut commons: Vec<_> = self.names.iter().filter(|e| e.1.kind == "common" && e.1.live).collect();
                commons.sort_by(|a, b| b.1.alignment.cmp(&a.1.alignment).then_with(|| a.0.cmp(b.0)));
                for (name, resolution) in commons {
                    components.push(Component {
                        kind: Kind::Common(name.clone()),
                        size: resolution.size,
                        alignment: resolution.alignment,
                        address: 0,
                        data: Vec::new()
                    });
                }
            }
            for (_, name) in self.veneers.iter().filter(|e| e.0 == index) {
                components.push(Component {
                    kind: Kind::Veneer(name.clone()),
                    size: 8,
                    alignment: 4,
                    address: 0,
                    data: Vec::new()
                });
            }
            self.outputs[index].components = components;
        }
        for segment in &mut self.segments {
            layout::assign(segment, &mut self.outputs);
        }
        for output in &self.outputs {
            for component in &output.components {
                match &component.kind {
                    Kind::Input(o, s) => self.objects[*o].sections[*s].address = component.address,
                    Kind::Merged {
                        positions,
                        ..
                    } => for &(o, s, offset, merged) in positions {
                        self.objects[o].sections[s].strings.insert(offset, component.address + merged);
                    },
                    Kind::Common(name) => self.names.get_mut(name).unwrap().address = component.address,
                    _ => ()
                }
            }
        }
        for resolution in self.names.values_mut() {
            if let Some((o, s)) = resolution.definition {
                if let Definition::Section(section, offset) = self.objects[o].symbols[s].definition {
                    let section = &self.objects[o].sections[section];
                    resolution.address = if object_parser::strings(&section.name) && section.live {
                        section.strings[&offset]
                    } else {
                        section.address + offset
                    };
                }
            }
        }
    }
    fn far_calls(&self) -> BTreeSet<(usize, String)> {
        let mut result = BTreeSet::new();
        for object in &self.objects {
            for relocation in &object.relocations {
                let section = &object.sections[relocation.section];
                if !section.live || relocation.kind != "CALL24" {
                    continue;
                }
                let symbol = &object.symbols[relocation.symbol];
                if symbol.binding == "local" {
                    continue;
                }
                let resolution = &self.names[&symbol.name];
                if resolution.kind != "global" && resolution.kind != "weak" {
                    continue;
                }
                if !relocator::fits("CALL24", resolution.address + relocation.addend - section.address - relocation.offset) {
                    result.insert((section.output.unwrap(), symbol.name.clone()));
                }
            }
        }
        result
    }
    fn finish_layout(&mut self) {
        loop {
            self.layout();
            let far = self.far_calls();
            if far.is_subset(&self.veneers) {
                break;
            }
            self.veneers.extend(far);
        }
        let mut storage: Vec<i64> = self.segments.iter().map(|s| s.base + s.memsz).collect();
        for (a, b) in &self.loads {
            let a = self.segments.iter().position(|s| s.name == *a).unwrap();
            let b = self.segments.iter().position(|s| s.name == *b).unwrap();
            self.segments[a].paddr = align(storage[b], 4);
            storage[b] = self.segments[a].paddr + self.segments[a].filesz;
        }
        for (i, segment) in self.segments.iter_mut().enumerate() {
            segment.used = storage[i] - segment.base;
        }
        let mut values = BTreeMap::new();
        for (name, expression) in &self.defines {
            let value = ScriptParser::evaluate(expression, &values, &self.outputs, &self.segments);
            values.insert(name.clone(), value);
            self.names.get_mut(name).unwrap().address = value;
        }
    }
    fn symbol_value(&self, o: usize, symbol_index: usize) -> Option<i64> {
        let symbol = &self.objects[o].symbols[symbol_index];
        if symbol.binding == "local" {
            if let Definition::Section(s, offset) = symbol.definition {
                let section = &self.objects[o].sections[s];
                return Some(if object_parser::strings(&section.name) {
                    section.strings[&offset]
                } else {
                    section.address + offset
                });
            }
            unreachable!()
        } else {
            let resolution = &self.names[&symbol.name];
            if resolution.kind == "undefined" {
                None
            } else {
                Some(resolution.address)
            }
        }
    }
    fn diagnostics(&self) -> Vec<String> {
        let mut lines = Vec::new();
        let mut orphans: BTreeMap<String,
        usize> = BTreeMap::new();
        for object in &self.objects {
            for section in &object.sections {
                if section.discard == Some("orphan") {
                    *orphans.entry(section.name.clone()).or_insert(0) += 1;
                }
            }
        }
        for (name, count) in orphans {
            lines.push(format!("warning: orphan section {} discarded from {} object(s)", name, count));
        }
        for (name, resolution) in &self.names {
            let mut definers: Vec<String> = resolution.strong.iter().map(|&o| self.objects[o].name.clone()).collect();
            if resolution.kind == "script" {
                definers.insert(0, "*script*".into());
            }
            if definers.len() >= 2 {
                lines.push(format!("error: multiple definition of {}: {}", name, definers.join(" ")));
            }
            if !resolution.common.is_empty() && (resolution.kind == "global" || resolution.kind == "script") {
                lines.push(format!("warning: common symbol {} overridden by {}", name, resolution.definer));
            }
            let distinct: BTreeSet<(i64, i64)> = resolution.common.iter().copied().collect();
            if resolution.kind == "common" && distinct.len() >= 2 {
                lines.push(format!("warning: common symbol {} merged to size {} align {}", name, resolution.size, resolution.alignment));
            }
        }
        if self.names.get(&self.entry).map_or(true, |r| r.kind == "undefined" || r.kind == "weakundef") {
            lines.push(format!("error: entry symbol {} is undefined", self.entry));
        }
        for (name, resolution) in &self.names {
            if resolution.kind == "undefined" {
                let referrers: Vec<String> = self.objects.iter().filter(|object| object.relocations.iter().any(|r| object.sections[r.section].live && object.symbols[r.symbol].binding != "local" && object.symbols[r.symbol].name == *name)).map(|o| o.name.clone()).collect();
                if !referrers.is_empty() {
                    lines.push(format!("error: undefined symbol {} referenced by {}", name, referrers.join(" ")));
                }
            }
        }
        for segment in &self.segments {
            if segment.used > segment.length {
                lines.push(format!("error: segment {} overflows its length by {} bytes", segment.name, segment.used - segment.length));
            }
        }
        for (i, a) in self.segments.iter().enumerate() {
            for b in &self.segments[i + 1..] {
                if a.memsz > 0 && b.memsz > 0 && a.base < b.base + b.memsz && b.base < a.base + a.memsz {
                    lines.push(format!("error: segments {} and {} overlap", a.name, b.name));
                }
            }
        }
        lines
    }
    fn relocate(&mut self, diagnostics: &mut Vec<String>) -> Vec<String> {
        let mut lines = Vec::new();
        let mut counts: BTreeMap<String,
        [usize; 4]> = relocator::TYPES.iter().map(|s| (s.to_string(), [0; 4])).collect();
        let far = self.far_calls();
        let mut veneers = BTreeMap::new();
        let mut order = Vec::new();
        for (output_index, output) in self.outputs.iter().enumerate() {
            for component in &output.components {
                if let Kind::Veneer(name) = &component.kind {
                    veneers.insert((output_index, name.clone()), component.address);
                }
                if let Kind::Input(o, s) = component.kind {
                    order.push((o, s));
                }
            }
        }
        let gp = self.names.get("_gp").map_or(0, |r| r.address);
        for (o, s) in order {
            let relocations: Vec<Relocation> = self.objects[o].relocations.iter().filter(|r| r.section == s).cloned().collect();
            for (index, relocation) in relocations.iter().enumerate() {
                let name = self.objects[o].symbols[relocation.symbol].name.clone();
                let section_name = self.objects[o].sections[s].name.clone();
                let location = format!("{} {}+{}", self.objects[o].name, section_name, relocation.offset);
                if relocator::unpaired(&relocations, index) {
                    diagnostics.push(format!("error: unpaired HI16 at {} against {}", location, name));
                }
                let position = self.objects[o].sections[s].address + relocation.offset;
                let mut symbol = self.symbol_value(o, relocation.symbol);
                let mut status = "ok";
                let output = self.objects[o].sections[s].output.unwrap();
                if relocation.kind == "CALL24" && far.contains(&(output, name.clone())) && self.objects[o].symbols[relocation.symbol].binding != "local" {
                    symbol = Some(veneers[&(output, name.clone())]);
                    status = "veneer";
                }
                if let Some(symbol) = symbol {
                    let value = relocator::value(&relocation.kind, symbol, relocation.addend, position, gp);
                    let field = relocator::field(&relocation.kind, value);
                    let width = relocator::width(&relocation.kind);
                    if !relocator::fits(&relocation.kind, value) {
                        status = "overflow";
                        diagnostics.push(format!("error: relocation overflow at {}: {} value {} against {}", location, relocation.kind, value, name));
                    }
                    for (i, byte) in relocator::little(field, width).into_iter().enumerate() {
                        self.objects[o].sections[s].data[relocation.offset as usize + i] = byte;
                    }
                    lines.push(format!("{:08x} {} {}+{} {} {} {} {:08x} {} {:0width$x} {}", position, self.objects[o].name, section_name, relocation.offset, relocation.kind, name, relocation.addend, symbol, value, field, status, width = width * 2));
                } else {
                    status = "undefined";
                    lines.push(format!("{:08x} {} {}+{} {} {} {} - - - undefined", position, self.objects[o].name, section_name, relocation.offset, relocation.kind, name, relocation.addend));
                }
                let n = match status {
                    "ok" => 0,
                    "veneer" => 1,
                    "overflow" => 2,
                    _ => 3
                };
                counts.get_mut(&relocation.kind).unwrap()[n] += 1;
            }
        }
        for kind in &relocator::TYPES {
            let c = counts[*kind];
            lines.push(format!("summary {} total {} ok {} veneer {} overflow {} undefined {}", kind, c.iter().sum::<usize>(), c[0], c[1], c[2], c[3]));
        }
        lines
    }
    fn images(&mut self) {
        for segment in &mut self.segments {
            let mut image = vec![segment.fill; segment.filesz as usize];
            for &index in &segment.outputs {
                if object_parser::nobits(&self.outputs[index].name) {
                    continue;
                }
                for component in &self.outputs[index].components {
                    let data = match &component.kind {
                        Kind::Input(o, s) => self.objects[*o].sections[*s].data.clone(),
                        Kind::Veneer(name) => {
                            let mut data = vec![4, 240, 31, 229];
                            data.extend(relocator::little(self.names[name].address, 4));
                            data
                        },
                        _ => component.data.clone()
                    };
                    let offset = (component.address - segment.base) as usize;
                    image[offset..offset + data.len()].copy_from_slice(&data);
                }
            }
            segment.image = image;
        }
        if let Some((name, symbol)) = &self.checksum {
            let segment = self.segments.iter_mut().find(|s| s.name == *name).unwrap();
            let offset = (self.names[symbol].address - segment.base) as usize;
            segment.image[offset..offset + 4].fill(0);
            let mut sum = 0i64;
            for chunk in segment.image.chunks(4) {
                for (i, &byte) in chunk.iter().enumerate() {
                    sum += (byte as i64) << (8 * i);
                }
            }
            segment.image[offset..offset + 4].copy_from_slice(&relocator::little((-sum).rem_euclid(4294967296), 4));
        }
    }
    fn map(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for (object, referrer, reason) in &self.extractions {
            lines.push(format!("member {} {} {}", object, referrer, reason));
        }
        for (signature, keeper, discarded) in &self.comdats {
            lines.push(format!("comdat {} {} {}", signature, keeper, if discarded.is_empty() {
                "-".into()
            } else {
                discarded.join(",")
            }));
        }
        let mut symbols: Vec<(i64, String, String, String)> = Vec::new();
        for segment in &self.segments {
            lines.push(format!("segment {} vaddr {:08x} paddr {:08x} filesz {} memsz {} used {} length {} {}%", segment.name, segment.base, segment.paddr, segment.filesz, segment.memsz, segment.used, segment.length, 100 * segment.used / segment.length));
            for &index in &segment.outputs {
                let output = &self.outputs[index];
                lines.push(format!("section {} {:08x} {} {}", output.name, output.address, output.size, output.alignment));
                for component in &output.components {
                    match &component.kind {
                        Kind::Input(o, s) => lines.push(format!("input {:08x} {} {} {} {}", component.address, component.size, component.alignment, self.objects[*o].name, self.objects[*o].sections[*s].name)),
                        Kind::Merged {
                            sections,
                            strings,
                            unique,
                            saved,
                            ..
                        } => lines.push(format!("merged {:08x} {} sections {} strings {} unique {} saved {}", component.address, component.size, sections, strings, unique, saved)),
                        Kind::Common(name) => lines.push(format!("common {:08x} {} {} {} {}", component.address, component.size, component.alignment, self.names[name].definer, name)),
                        Kind::Veneer(name) => {
                            lines.push(format!("veneer {:08x} 8 {}", component.address, name));
                            symbols.push((component.address, format!("__veneer_{}", name), "veneer".into(), "*linker*".into()));
                        }
                    }
                }
            }
        }
        for object in &self.objects {
            for section in &object.sections {
                if let Some(reason) = section.discard {
                    lines.push(format!("discard {} {} {} {}", object.name, section.name, section.size, reason));
                }
            }
        }
        for (name, resolution) in &self.names {
            if resolution.kind == "common" && !resolution.live {
                lines.push(format!("discard {} COMMON({}) {} gc", resolution.definer, name, resolution.size));
            }
            if resolution.live && ["global", "weak", "common", "script"].contains(&resolution.kind) {
                symbols.push((resolution.address, name.clone(), resolution.kind.into(), resolution.definer.clone()));
            }
        }
        symbols.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)));
        for (address, name, kind, definer) in symbols {
            lines.push(format!("symbol {:08x} {} {} {}", address, name, kind, definer));
        }
        lines
    }
    fn xref(&self) -> Vec<String> {
        self.names.iter().map(|(name, r)| format!("{} {} {} {} {}", name, r.kind, if r.kind == "undefined" || r.kind == "weakundef" {
            "-"
        } else if r.live {
            "kept"
        } else {
            "discarded"
        }, r.definer, if r.referrers.is_empty() {
            "-".into()
        } else {
            r.referrers.iter().map(|&o| self.objects[o].name.clone()).collect::<Vec<_>>().join(",")
        })).collect()
    }
    fn output(&self, relocations: &[String], diagnostics: &mut Vec<String>) {
        let entry = self.names.get(&self.entry).filter(|r| ["global", "weak", "common"].contains(&r.kind)).map_or(0, |r| r.address);
        let mut image = vec![format!("entry {:08x} {}", entry, self.entry)];
        for segment in &self.segments {
            image.push(format!("segment {} vaddr {:08x} paddr {:08x} filesz {} memsz {}", segment.name, segment.base, segment.paddr, segment.filesz, segment.memsz));
            for (i, chunk) in segment.image.chunks(16).enumerate() {
                image.push(format!("{:08x} {}", segment.base + (16 * i) as i64, chunk.iter().map(|b| format!("{:02x}", b)).collect::<Vec<_>>().join(" ")));
            }
        }
        let mut hex = Vec::new();
        let mut segments: Vec<_> = self.segments.iter().filter(|s| s.filesz > 0).collect();
        segments.sort_by_key(|s| s.paddr);
        let mut upper = 0;
        for segment in segments {
            let mut k = 0;
            while k < segment.image.len() {
                let address = segment.paddr + k as i64;
                let n = 16usize.min(segment.image.len() - k).min((65536 - address.rem_euclid(65536)) as usize);
                if address / 65536 != upper {
                    upper = address / 65536;
                    hex.push(record(0, 4, &[(upper / 256) as u8, (upper % 256) as u8]));
                }
                hex.push(record(address.rem_euclid(65536), 0, &segment.image[k..k + n]));
                k += n;
            }
        }
        hex.push(record(0, 5, &[(entry >> 24) as u8, (entry >> 16) as u8, (entry >> 8) as u8, entry as u8]));
        hex.push(record(0, 1, &[]));
        let errors = diagnostics.iter().filter(|l| l.starts_with("error")).count();
        let warnings = diagnostics.iter().filter(|l| l.starts_with("warning")).count();
        diagnostics.push(format!("errors {} warnings {}", errors, warnings));
        write("image.hex", &image);
        write("flash.ihex", &hex);
        write("link.map", &self.map());
        write("xref.txt", &self.xref());
        write("relocations.txt", relocations);
        write("diagnostics.txt", diagnostics);
    }
}
struct ScriptParser<'a> {
    tokens: Vec<String>,
    index: usize,
    values: &'a BTreeMap<String,
    i64>,
    outputs: &'a [OutputSection],
    segments: &'a [Segment]
}
impl<'a> ScriptParser<'a> {
    fn evaluate(text: &str, values: &'a BTreeMap<String, i64>, outputs: &'a [OutputSection], segments: &'a [Segment]) -> i64 {
        let bytes = text.as_bytes();
        let mut tokens = Vec::new();
        let mut i = 0;
        while i < bytes.len() {
            if bytes[i] == b' ' {
                i += 1;
                continue;
            }
            if b"(),+-".contains(&bytes[i]) {
                tokens.push((bytes[i] as char).to_string());
                i += 1;
            } else {
                let start = i;
                while i < bytes.len() && bytes[i] != b' ' && !b"(),+-".contains(&bytes[i]) {
                    i += 1;
                }
                tokens.push(text[start..i].into());
            }
        }
        Self {
            tokens,
            index: 0,
            values,
            outputs,
            segments
        }.expression()
    }
    fn peek(&self) -> &str {
        self.tokens.get(self.index).map_or("", String::as_str)
    }
    fn expression(&mut self) -> i64 {
        let mut value = self.term();
        while self.peek() == "+" || self.peek() == "-" {
            let plus = self.peek() == "+";
            self.index += 1;
            let right = self.term();
            value = if plus {
                value + right
            } else {
                value - right
            };
        }
        value
    }
    fn term(&mut self) -> i64 {
        let token = self.tokens[self.index].clone();
        self.index += 1;
        if token == "(" {
            let value = self.expression();
            self.index += 1;
            return value;
        }
        if token.as_bytes()[0].is_ascii_digit() {
            return number(&token);
        }
        if self.peek() != "(" {
            return self.values[&token];
        }
        self.index += 1;
        if token == "align" {
            let value = self.expression();
            self.index += 1;
            let alignment = self.expression();
            self.index += 1;
            return align(value, alignment);
        }
        let name = self.tokens[self.index].clone();
        self.index += 2;
        let index = self.outputs.iter().position(|o| o.name == name).unwrap();
        let output = &self.outputs[index];
        match token.as_str() {
            "start" => output.address,
            "end" => output.address + output.size,
            "size" => output.size,
            "loadaddr" => {
                let segment = self.segments.iter().find(|s| s.outputs.contains(&index)).unwrap();
                segment.paddr + output.address - segment.base
            },
            _ => unreachable!()
        }
    }
}
fn record(address: i64, kind: u8, data: &[u8]) -> String {
    let mut bytes = vec![data.len() as u8, (address >> 8) as u8, address as u8, kind];
    bytes.extend(data);
    let sum: usize = bytes.iter().map(|&b| b as usize).sum();
    bytes.push(((256 - sum % 256) % 256) as u8);
    format!(":{}", bytes.iter().map(|b| format!("{:02X}", b)).collect::<Vec<_>>().join(""))
}
fn write(name: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}", name), if lines.is_empty() {
        String::new()
    } else {
        lines.join("\n") + "\n"
    }).unwrap();
}
fn main() {
    let mut linker = Linker::read();
    linker.load_inputs();
    linker.collect();
    linker.finish_layout();
    let mut diagnostics = linker.diagnostics();
    let relocations = linker.relocate(&mut diagnostics);
    linker.images();
    linker.output(&relocations, &mut diagnostics);
}
