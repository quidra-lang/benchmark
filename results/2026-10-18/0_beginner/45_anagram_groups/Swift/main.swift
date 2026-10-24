var groups = [String:[String]](), keys = [String]()
for word in ["listen","stone","night","silent","notes","apple","thing","enlist","earth","onset","heart","tones"] {
    let key = String(word.sorted())
    if groups[key] == nil { keys.append(key) }
    groups[key, default: []].append(word)
}
for key in keys { print(groups[key]!.joined(separator: " ")) }
