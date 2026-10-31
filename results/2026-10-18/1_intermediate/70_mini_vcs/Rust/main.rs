use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::io::{self, Read};
type Tree = BTreeMap<String, String>;
#[derive(Clone)]
struct Commit {
    id: String, parents: Vec<usize>, tree: Tree, message: String
}
#[derive(Clone)]
struct Stash {
    label: String, base: usize, tree: Tree
}
struct Repository {
    commits: Vec<Option<Commit>>, branches: BTreeMap<String, usize>, tags: BTreeMap<String, usize>,
    head: usize, attached: Option<String>, work: Tree, index: Tree, conflicts: BTreeSet<String>,
    pending: Option<(String, usize)>, stashes: Vec<Stash>, ignores: Vec<String>,
}
fn paths(trees: &[&Tree]) -> BTreeSet<String> {
    trees.iter().flat_map(|t| t.keys().cloned()).collect()
}
fn differences(a: &Tree, b: &Tree) -> BTreeSet<String> {
    paths(&[a,b]).into_iter().filter(|p| a.get(p) != b.get(p)).collect()
}
fn match_path(target: &mut Tree, source: &Tree, p: &str) {
    if let Some(value) = source.get(p) {
        target.insert(p.into(),value.clone());
    } else {
        target.remove(p);
    }
}
fn changes(a: &Tree, b: &Tree) -> Vec<String> {
    let result: Vec<_> = differences(a,b).iter().map(|p| match (a.get(p),b.get(p)) {
        (None,Some(v)) => format!("A {p}: {v}"), (Some(v),None) => format!("D {p}: {v}"),
        (Some(x),Some(y)) => format!("M {p}: {x} -> {y}"), _ => unreachable!(),
    }).collect();
    if result.is_empty() {
        vec!["(no changes)".into()]
    } else {
        result
    }
}
fn three_way(base: &Tree, ours: &Tree, theirs: &Tree) -> (Tree,BTreeMap<String,String>) {
    let mut merged = Tree::new();
    let mut conflicts = BTreeMap::new();
    for p in paths(&[base,ours,theirs]) {
        let b = base.get(&p);
        let o = ours.get(&p);
        let t = theirs.get(&p);
        if t == b || o == t {
            match_path(&mut merged,ours,&p);
        }
        else if o == b {
            match_path(&mut merged,theirs,&p);
        }
        else {
            match_path(&mut merged,ours,&p);
            conflicts.insert(p,format!("<<<<<<< {} ======= {} >>>>>>>",o.map_or("(deleted)",String::as_str),t.map_or("(deleted)",String::as_str)));
        }
    }
    (merged,conflicts)
}
fn glob(pattern: &str, path: &str) -> bool {
    let mut previous = vec![false; path.len()+1];
    previous[0] = true;
    for c in pattern.bytes() {
        let mut next = vec![false; path.len()+1];
        if c == b'*' {
            next[0] = previous[0];
        }
        for (i,b) in path.bytes().enumerate() {
            next[i+1] = if c == b'*' {
                previous[i+1] || next[i]
            } else {
                previous[i] && (c == b'?' || c == b)
            };
        }
        previous = next;
    }
    previous[path.len()]
}
impl Repository {
    fn new() -> Self {
        let mut repo = Self {
            commits: Vec::new(), branches: BTreeMap::new(), tags: BTreeMap::new(), head: 0, attached: Some("main".into()), work: Tree::new(), index: Tree::new(), conflicts: BTreeSet::new(), pending: None, stashes: Vec::new(), ignores: Vec::new()
        };
        repo.create(Vec::new(),Tree::new(),"init".into());
        repo.branches.insert("main".into(),0);
        repo
    }
    fn commit(&self, i: usize) -> &Commit {
        self.commits[i].as_ref().unwrap()
    }
    fn h(&self) -> &Tree {
        &self.commit(self.head).tree
    }
    fn create(&mut self, parents: Vec<usize>, tree: Tree, message: String) -> usize {
        let sequence = self.commits.len();
        let mut text = format!("commit {sequence}\n");
        for &p in &parents {
            text += &format!("parent {}\n",self.commit(p).id);
        }
        for (p,v) in &tree {
            text += &format!("file {p} {v}\n");
        }
        text += &format!("message {message}\n");
        let hash = text.bytes().fold(0u64,|h,c| (h*131+c as u64)%2147483647);
        self.commits.push(Some(Commit {
            id: format!("{hash:08x}"), parents, tree, message
        }));
        sequence
    }
    fn move_head(&mut self, target: usize) {
        self.head = target;
        if let Some(branch) = &self.attached {
            self.branches.insert(branch.clone(),target);
        }
    }
    fn record(&mut self, parents: Vec<usize>, tree: Tree, message: String) -> String {
        let old = &self.commit(parents[0]).tree;
        let mut counts = [0;3];
        for p in differences(old,&tree) {
            counts[if !old.contains_key(&p) {
                0
            } else if !tree.contains_key(&p) {
                2
            } else {
                1
            }] += 1;
        }
        let target = self.create(parents,tree,message.clone());
        self.move_head(target);
        format!("[{} {}] {message} ({} added, {} modified, {} deleted)",self.attached.as_deref().unwrap_or("detached HEAD"),self.commit(target).id,counts[0],counts[1],counts[2])
    }
    fn resolve(&self, revision: &str) -> Result<usize,String> {
        let (anchor,count) = revision.split_once('~').map_or((revision,0),|(a,n)|(a,n.parse::<usize>().unwrap()));
        let mut result = if anchor == "HEAD" {
            Some(self.head)
        } else {
            self.branches.get(anchor).or_else(||self.tags.get(anchor)).copied().or_else(||self.commits.iter().position(|c|c.as_ref().is_some_and(|c|c.id == anchor)))
        };
        for _ in 0..count {
            result = result.and_then(|i|self.commit(i).parents.first().copied());
        }
        result.ok_or_else(||format!("error: unknown revision '{revision}'"))
    }
    fn distances(&self, start: usize) -> BTreeMap<usize,usize> {
        let mut result = BTreeMap::from([(start,0)]);
        let mut queue = VecDeque::from([start]);
        while let Some(i) = queue.pop_front() {
            let d = result[&i]+1;
            for &p in &self.commit(i).parents {
                if let std::collections::btree_map::Entry::Vacant(entry) = result.entry(p) {
                    entry.insert(d);
                    queue.push_back(p);
                }
            }
        }
        result
    }
    fn ancestor(&self, a: usize, b: usize) -> bool {
        self.distances(b).contains_key(&a)
    }
    fn merge_base(&self, x: usize, y: usize) -> usize {
        let a = self.distances(x);
        let b = self.distances(y);
        let common: Vec<_> = a.keys().filter(|c|b.contains_key(*c)).copied().collect();
        common.iter().copied().filter(|&z|!common.iter().any(|&w|z != w && self.ancestor(z,w))).min_by_key(|&z|(a[&z].max(b[&z]),std::cmp::Reverse(z))).unwrap()
    }
    fn in_progress(&self) -> Result<(),String> {
        if let Some((kind,_)) = &self.pending {
            Err(format!("error: {kind} in progress"))
        } else {
            Ok(())
        }
    }
    fn uncommitted(&self) -> bool {
        self.index != *self.h() || self.index.keys().any(|p| self.work.get(p) != self.index.get(p))
    }
    fn clean(&self) -> Result<(),String> {
        if self.uncommitted() {
            Err("error: uncommitted changes".into())
        } else {
            Ok(())
        }
    }
    fn overwrite(&self, paths: &BTreeSet<String>) -> Result<(),String> {
        for p in paths {
            if self.index.get(p) != self.h().get(p) || self.work.get(p) != self.h().get(p) {
                return Err(format!("error: local changes to '{p}' would be overwritten"));
            }
        } Ok(())
    }
    fn switch_tree(&mut self, tree: &Tree) -> Result<(),String> {
        let changed = differences(self.h(),tree);
        self.overwrite(&changed)?;
        for p in changed {
            match_path(&mut self.work,tree,&p);
            match_path(&mut self.index,tree,&p);
        } Ok(())
    }
    fn ignored(&self, p: &str) -> bool {
        !self.index.contains_key(p) && !self.conflicts.contains(p) && self.ignores.iter().any(|pattern|glob(pattern,p))
    }
    fn summary(&self, i: usize) -> String {
        let commit = self.commit(i);
        let mut references = Vec::new();
        if self.head == i {
            references.push(self.attached.as_ref().map_or("HEAD".into(),|b|format!("HEAD -> {b}")));
        }
        for (b,&target) in &self.branches {
            if target == i && self.attached.as_ref() != Some(b) {
                references.push(b.clone());
            }
        }
        for (tag,&target) in &self.tags {
            if target == i {
                references.push(format!("tag: {tag}"));
            }
        }
        format!("{}{} {}",commit.id,if references.is_empty() {
            String::new()
        } else {
            format!(" ({})",references.join(", "))
        },commit.message)
    }
    fn apply(&mut self, base: &Tree, theirs: &Tree, kind: &str, target: usize, message: String, parents: Vec<usize>, merge_base: Option<usize>) -> Result<Vec<String>,String> {
        let (merged,conflicts) = three_way(base,self.h(),theirs);
        let mut changed = differences(self.h(),&merged);
        changed.extend(conflicts.keys().cloned());
        self.overwrite(&changed)?;
        let mut out = Vec::new();
        if let Some(base) = merge_base {
            out.push(format!("Merge base {}",self.commit(base).id));
        }
        if kind != "merge" && conflicts.is_empty() && merged == *self.h() {
            out.push("nothing to commit".into());
            return Ok(out);
        }
        for p in differences(self.h(),&merged) {
            match_path(&mut self.work,&merged,&p);
            match_path(&mut self.index,&merged,&p);
        }
        if conflicts.is_empty() {
            out.push(self.record(parents,merged,message));
        }
        else {
            for (p,value) in &conflicts {
                self.work.insert(p.clone(),value.clone());
                out.push(format!("CONFLICT {p}"));
            }
            self.conflicts = conflicts.into_keys().collect();
            self.pending = Some((kind.into(),target));
            out.push(if kind == "merge" {
                "Automatic merge failed; fix conflicts and then commit the result.".into()
            } else {
                format!("error: could not {} {}",if kind == "revert" {
                    "revert"
                } else {
                    "apply"
                },self.commit(target).id)
            });
        }
        Ok(out)
    }
    fn reachable(&self, include_saved: bool) -> BTreeSet<usize> {
        let mut starts = vec![self.head];
        starts.extend(self.branches.values().copied());
        starts.extend(self.tags.values().copied());
        if include_saved {
            starts.extend(self.stashes.iter().map(|s|s.base));
            if let Some((_,i)) = &self.pending {
                starts.push(*i);
            }
        }
        starts.into_iter().flat_map(|i|self.distances(i).into_keys()).collect()
    }
    fn command(&mut self, line: &str) -> Result<Vec<String>,String> {
        let words: Vec<_> = line.split(' ').collect();
        let c = words[0];
        let a = &words[1..];
        let mut out = Vec::new();
        match c {
            "WRITE" => {
                self.work.insert(a[0].into(),line.splitn(3,' ').nth(2).unwrap().into());
            }
            "REMOVE" => {
                if self.work.remove(a[0]).is_none() {
                    return Err(format!("error: no such file '{}'",a[0]));
                }
            }
            "ADD" => {
                if a[0] == "ALL" {
                    let selected: Vec<_> = paths(&[&self.work,&self.index]).into_iter().filter(|p|!self.ignored(p)).collect();
                    for p in selected {
                        match_path(&mut self.index,&self.work,&p);
                    }
                    self.conflicts.clear();
                }
                else {
                    let p = a[0];
                    if self.work.contains_key(p) && self.ignored(p) {
                        return Err(format!("error: path '{p}' is ignored"));
                    }
                    if !self.work.contains_key(p) && !self.index.contains_key(p) && !self.conflicts.contains(p) {
                        return Err(format!("error: pathspec '{p}' did not match any files"));
                    } match_path(&mut self.index,&self.work,p);
                    self.conflicts.remove(p);
                }
            }
            "RM" => {
                if self.index.remove(a[0]).is_none() {
                    return Err(format!("error: pathspec '{}' did not match any files",a[0]));
                }
                self.work.remove(a[0]);
                self.conflicts.remove(a[0]);
            }
            "UNSTAGE" => {
                if !self.index.contains_key(a[0]) && !self.h().contains_key(a[0]) {
                    return Err(format!("error: pathspec '{}' did not match any files",a[0]));
                }
                let tree = self.h().clone();
                match_path(&mut self.index,&tree,a[0]);
            }
            "RESTORE" => {
                if a.len() == 1 {
                    let value = self.index.get(a[0]).ok_or_else(||format!("error: pathspec '{}' did not match any files",a[0]))?.clone();
                    self.work.insert(a[0].into(),value);
                }
                else {
                    let i = self.resolve(a[1])?;
                    let value = self.commit(i).tree.get(a[0]).ok_or_else(||format!("error: path '{}' does not exist in '{}'",a[0],a[1]))?.clone();
                    self.work.insert(a[0].into(),value.clone());
                    self.index.insert(a[0].into(),value);
                    self.conflicts.remove(a[0]);
                }
            }
            "IGNORE" => self.ignores.push(a[0].into()),
            "COMMIT" | "AMEND" => {
                let message = line.split_once(' ').unwrap().1.to_string();
                let parents = if c == "AMEND" {
                    self.in_progress()?;
                    if self.commit(self.head).parents.is_empty() {
                        return Err("error: cannot amend the root commit".into());
                    }
                    self.commit(self.head).parents.clone()
                }
                else {
                    if !self.conflicts.is_empty() {
                        return Err("error: unresolved conflicts".into());
                    }
                    if let Some((kind,i)) = &self.pending {
                        if kind == "merge" {
                            vec![self.head,*i]
                        } else {
                            vec![self.head]
                        }
                    } else {
                        vec![self.head]
                    }
                };
                if c == "COMMIT" && parents.len() != 2 && self.index == *self.h() {
                    out.push("nothing to commit".into());
                }
                else {
                    out.push(self.record(parents,self.index.clone(),message));
                    self.pending = None;
                }
            }
            "STATUS" => {
                out.push(self.attached.as_ref().map_or(format!("HEAD detached at {}",self.commit(self.head).id),|b|format!("On branch {b}")));
                if let Some((kind,i)) = &self.pending {
                    out.push(format!("{} {}",match kind.as_str() {
                        "merge" => "Merging", "revert" => "Reverting", _ => "Cherry-picking"
                    },self.commit(*i).id));
                }
                let start = out.len();
                let mut all = paths(&[self.h(),&self.index,&self.work]);
                all.extend(self.conflicts.iter().cloned());
                for p in all {
                    if self.conflicts.contains(&p) {
                        out.push(format!("UU {p}"));
                    }
                    else if let Some(value) = self.index.get(&p) {
                        let x = if !self.h().contains_key(&p) {
                            'A'
                        } else if self.h().get(&p) != Some(value) {
                            'M'
                        } else {
                            '.'
                        };
                        let y = if !self.work.contains_key(&p) {
                            'D'
                        } else if self.work.get(&p) != Some(value) {
                            'M'
                        } else {
                            '.'
                        };
                        if x != '.' || y != '.' {
                            out.push(format!("{x}{y} {p}"));
                        }
                    }
                    else {
                        if self.h().contains_key(&p) {
                            out.push(format!("D. {p}"));
                        }
                        if self.work.contains_key(&p) && !self.ignored(&p) {
                            out.push(format!("?? {p}"));
                        }
                    }
                }
                if out.len() == start {
                    out.push("nothing to commit, working tree clean".into());
                }
            }
            "LS" | "CAT" => {
                let revision = if c == "LS" {
                    a.first().copied()
                } else {
                    a.get(1).copied()
                };
                let tree = if let Some(r) = revision {
                    &self.commit(self.resolve(r)?).tree
                } else {
                    &self.work
                };
                if c == "CAT" {
                    out.push(tree.get(a[0]).ok_or_else(||if let Some(r) = revision {
                        format!("error: path '{}' does not exist in '{r}'",a[0])
                    } else {
                        format!("error: no such file '{}'",a[0])
                    })?.clone());
                }
                else if tree.is_empty() {
                    out.push("(empty)".into());
                } else {
                    out.extend(tree.iter().map(|(p,v)|format!("{p} {v}")));
                }
            }
            "DIFF" => {
                if a.is_empty() {
                    let work: Tree = self.work.iter().filter(|(p,_)|self.index.contains_key(*p)).map(|(p,v)|(p.clone(),v.clone())).collect();
                    out = changes(&self.index,&work);
                } else if a[0] == "STAGED" {
                    out = changes(self.h(),&self.index);
                } else {
                    let x = self.resolve(a[0])?;
                    let y = self.resolve(a[1])?;
                    out = changes(&self.commit(x).tree,&self.commit(y).tree);
                }
            }
            "LOG" => {
                let limit = a.first().map_or(usize::MAX,|s|s.parse().unwrap());
                let mut current = self.head;
                for _ in 0..limit {
                    out.push(self.summary(current));
                    if let Some(&p) = self.commit(current).parents.first() {
                        current = p;
                    } else {
                        break;
                    }
                }
            }
            "SHOW" => {
                let i = self.resolve(a.first().copied().unwrap_or("HEAD"))?;
                let commit = self.commit(i);
                out.push(format!("commit {}",self.summary(i)));
                out.push(format!("parents: {}",if commit.parents.is_empty() {
                    "none".into()
                } else {
                    commit.parents.iter().map(|&p|self.commit(p).id.clone()).collect::<Vec<_>>().join(" ")
                }));
                out.extend(changes(&commit.parents.first().map_or(Tree::new(),|&p|self.commit(p).tree.clone()),&commit.tree));
            }
            "BLAME" => {
                let value = self.h().get(a[0]).ok_or_else(||format!("error: path '{}' does not exist in 'HEAD'",a[0]))?;
                let mut i = self.head;
                while let Some(&p) = self.commit(i).parents.first() {
                    if self.commit(p).tree.get(a[0]) != Some(value) {
                        break;
                    } i = p;
                }
                out.push(format!("{} ({}) {value}",self.commit(i).id,self.commit(i).message));
            }
            "BRANCH" | "TAG" => {
                let branch = c == "BRANCH";
                let noun = if branch {
                    "branch"
                } else {
                    "tag"
                };
                if a[0] == "-d" {
                    let name = a[1];
                    let target = (if branch {
                        &self.branches
                    } else {
                        &self.tags
                    }).get(name).copied().ok_or_else(||format!("error: no such {noun} '{name}'"))?;
                    if branch && self.attached.as_deref() == Some(name) {
                        return Err(format!("error: cannot delete current branch '{name}'"));
                    }
                    if branch && !self.ancestor(target,self.head) {
                        return Err(format!("error: branch '{name}' is not fully merged"));
                    }
                    if branch {
                        self.branches.remove(name);
                    } else {
                        self.tags.remove(name);
                    }
                    out.push(format!("Deleted {noun} {name} (was {})",self.commit(target).id));
                } else {
                    let name = a[0];
                    if (if branch {
                        &self.branches
                    } else {
                        &self.tags
                    }).contains_key(name) {
                        return Err(format!("error: {noun} '{name}' already exists"));
                    }
                    let target = self.resolve(a.get(1).copied().unwrap_or("HEAD"))?;
                    if branch {
                        self.branches.insert(name.into(),target);
                    } else {
                        self.tags.insert(name.into(),target);
                    }
                    out.push(format!("Created {noun} {name} at {}",self.commit(target).id));
                }
            }
            "BRANCHES" => {
                if self.attached.is_none() {
                    out.push(format!("* (HEAD detached at {})",self.commit(self.head).id));
                }
                for (b,&i) in &self.branches {
                    out.push(format!("{} {b} {} {}",if self.attached.as_ref() == Some(b) {
                        "*"
                    } else {
                        " "
                    },self.commit(i).id,self.commit(i).message));
                }
            }
            "TAGS" => {
                for (tag,&i) in &self.tags {
                    out.push(format!("{tag} {} {}",self.commit(i).id,self.commit(i).message));
                }
                if out.is_empty() {
                    out.push("(no tags)".into());
                }
            }
            "SWITCH" => {
                let target = self.branches.get(a[0]).copied().ok_or_else(||format!("error: no such branch '{}'",a[0]))?;
                if self.attached.as_deref() == Some(a[0]) {
                    out.push(format!("Already on '{}'",a[0]));
                } else {
                    self.in_progress()?;
                    self.switch_tree(&self.commit(target).tree.clone())?;
                    self.attached = Some(a[0].into());
                    self.head = target;
                    out.push(format!("Switched to branch '{}'",a[0]));
                }
            }
            "DETACH" => {
                let target = self.resolve(a[0])?;
                self.in_progress()?;
                self.switch_tree(&self.commit(target).tree.clone())?;
                self.attached = None;
                self.head = target;
                out.push(format!("HEAD is now at {} {}",self.commit(target).id,self.commit(target).message));
            }
            "MERGE" => {
                let target = self.resolve(a[0])?;
                self.in_progress()?;
                if self.ancestor(target,self.head) {
                    out.push("Already up to date".into());
                } else if self.ancestor(self.head,target) {
                    let old = self.head;
                    self.switch_tree(&self.commit(target).tree.clone())?;
                    self.move_head(target);
                    out.push(format!("Fast-forward {}..{}",self.commit(old).id,self.commit(target).id));
                } else {
                    self.clean()?;
                    let base = self.merge_base(self.head,target);
                    out = self.apply(&self.commit(base).tree.clone(),&self.commit(target).tree.clone(),"merge",target,format!("Merge {}",a[0]),vec![self.head,target],Some(base))?;
                }
            }
            "MERGEBASE" => {
                let x = self.resolve(a[0])?;
                let y = self.resolve(a[1])?;
                out.push(self.commit(self.merge_base(x,y)).id.clone());
            }
            "REBASE" => {
                let target = self.resolve(a[0])?;
                self.in_progress()?;
                if self.ancestor(target,self.head) {
                    return Ok(vec!["Already up to date".into()]);
                }
                self.clean()?;
                let mut list = Vec::new();
                let mut current = self.head;
                while !self.ancestor(current,target) {
                    list.push(current);
                    current = self.commit(current).parents[0];
                } list.reverse();
                let mut tree = self.commit(target).tree.clone();
                let mut planned = Vec::new();
                for &i in &list {
                    let commit = self.commit(i);
                    let (merged,conflicts) = three_way(&self.commit(commit.parents[0]).tree,&tree,&commit.tree);
                    if let Some(p) = conflicts.keys().next() {
                        return Err(format!("error: could not rebase {}: conflict in '{p}'",commit.id));
                    }
                    if merged == tree {
                        planned.push(None);
                    } else {
                        planned.push(Some(merged.clone()));
                        tree = merged;
                    }
                }
                self.switch_tree(&tree)?;
                let mut parent = target;
                for (i,planned) in list.into_iter().zip(planned) {
                    let commit = self.commit(i).clone();
                    if let Some(tree) = planned {
                        let next = self.create(vec![parent],tree,commit.message.clone());
                        out.push(format!("pick {} -> {} {}",commit.id,self.commit(next).id,commit.message));
                        parent = next;
                    } else {
                        out.push(format!("skip {} {}",commit.id,commit.message));
                    }
                }
                self.move_head(parent);
                out.push(format!("HEAD is now at {} {}",self.commit(parent).id,self.commit(parent).message));
            }
            "RESET" => {
                let target = self.resolve(a[1])?;
                let tree = self.commit(target).tree.clone();
                if a[0] == "HARD" {
                    let mut all = paths(&[&self.index,&tree]);
                    all.extend(self.conflicts.iter().cloned());
                    for p in all {
                        match_path(&mut self.work,&tree,&p);
                    }
                }
                if a[0] != "SOFT" {
                    self.index = tree;
                }
                self.move_head(target);
                self.conflicts.clear();
                self.pending = None;
                out.push(format!("HEAD is now at {} {}",self.commit(target).id,self.commit(target).message));
            }
            "REVERT" | "CHERRYPICK" => {
                let target = self.resolve(a[0])?;
                self.in_progress()?;
                self.clean()?;
                let commit = self.commit(target).clone();
                let parent = commit.parents.first().map_or(Tree::new(),|&p|self.commit(p).tree.clone());
                let (base,theirs,kind,message) = if c == "REVERT" {
                    (commit.tree,parent,"revert",format!("Revert \"{}\"",commit.message))
                } else {
                    (parent,commit.tree,"cherry-pick",commit.message)
                };
                out = self.apply(&base,&theirs,kind,target,message,vec![self.head],None)?;
            }
            "STASH" => {
                if a.is_empty() {
                    self.in_progress()?;
                    if !self.uncommitted() {
                        out.push("No local changes to save".into());
                    } else {
                        let all = paths(&[&self.index,self.h()]);
                        let saved: Tree = all.iter().filter_map(|p|self.work.get(p).map(|v|(p.clone(),v.clone()))).collect();
                        let head = self.h().clone();
                        for p in all {
                            match_path(&mut self.work,&head,&p);
                        }
                        self.index = head;
                        let label = format!("WIP on {}: {} {}",self.attached.as_deref().unwrap_or("(no branch)"),self.commit(self.head).id,self.commit(self.head).message);
                        self.stashes.insert(0,Stash {
                            label: label.clone(),base:self.head,tree:saved
                        });
                        out.push(format!("Saved stash@{{0}}: {label}"));
                    }
                }
                else if a[0] == "LIST" {
                    out.extend(self.stashes.iter().enumerate().map(|(i,s)|format!("stash@{{{i}}}: {}",s.label)));
                    if out.is_empty() {
                        out.push("(no stash entries)".into());
                    }
                }
                else {
                    let stash = self.stashes.first().ok_or("error: no stash entries")?.clone();
                    if a[0] == "DROP" {
                        self.stashes.remove(0);
                        out.push(format!("Dropped stash@{{0}}: {}",stash.label));
                    } else {
                        self.in_progress()?;
                        self.clean()?;
                        let (merged,conflicts) = three_way(&self.commit(stash.base).tree,self.h(),&stash.tree);
                        if let Some(p) = conflicts.keys().next() {
                            return Err(format!("error: stash conflict in '{p}'"));
                        }
                        let changed = differences(self.h(),&merged);
                        self.overwrite(&changed)?;
                        for p in changed {
                            match_path(&mut self.work,&merged,&p);
                        }
                        self.stashes.remove(0);
                        out.push(format!("Restored stash@{{0}}: {}",stash.label));
                        out.extend(changes(self.h(),&merged));
                    }
                }
            }
            "GRAPH" => {
                let mut lanes = Vec::new();
                for i in self.reachable(false).into_iter().rev() {
                    if !lanes.contains(&i) {
                        lanes.push(i);
                    }
                    let k = lanes.iter().position(|&v|v == i).unwrap();
                    let symbols = lanes.iter().enumerate().map(|(j,&v)|if j == k {
                        "*"
                    } else if v == i {
                        "/"
                    } else {
                        "|"
                    }).collect::<Vec<_>>().join(" ");
                    out.push(format!("{symbols} {}",self.summary(i)));
                    let mut j = lanes.len();
                    while j > k+1 {
                        j -= 1;
                        if lanes[j] == i {
                            lanes.remove(j);
                        }
                    }
                    let parents = &self.commit(i).parents;
                    if parents.is_empty() {
                        lanes.remove(k);
                    } else {
                        lanes[k] = parents[0];
                        if parents.len() == 2 && !lanes.contains(&parents[1]) {
                            lanes.insert(k+1,parents[1]);
                        }
                    }
                }
            }
            "DESCRIBE" => {
                let target = self.resolve(a.first().copied().unwrap_or("HEAD"))?;
                let distance = self.distances(target);
                let choice = self.tags.iter().filter_map(|(tag,i)|distance.get(i).map(|&d|(d,tag))).min();
                let (d,tag) = choice.ok_or_else(||format!("error: no tag can describe '{}'",self.commit(target).id))?;
                out.push(if d == 0 {
                    tag.clone()
                } else {
                    format!("{tag}-{d}-g{}",self.commit(target).id)
                });
            }
            "GC" => {
                let keep = self.reachable(true);
                let mut count = 0;
                for (i,c) in self.commits.iter_mut().enumerate() {
                    if c.is_some() && !keep.contains(&i) {
                        *c = None;
                        count += 1;
                    }
                }
                out.push(format!("Removed unreachable commits: {count}"));
            }
            _ => unreachable!(),
        }
        Ok(out)
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut repository = Repository::new();
    for line in input.lines().take_while(|&line|line != "EXIT") {
        match repository.command(line) {
            Ok(out) => for line in out {
                println!("{line}");
            }, Err(error) => println!("{error}")
        }
    }
}
