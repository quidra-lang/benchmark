import 'dart:collection';
import 'dart:io';

sealed class FsNode {
  final int inode;
  int modified;
  late DirectoryNode parent;
  String name = '';
  FsNode(this.inode, this.modified);
  int get size;
  int get links => 1;
  String get tag;
}

final class DirectoryNode extends FsNode {
  final entries = SplayTreeMap<String, FsNode>();
  DirectoryNode(super.inode, super.modified);
  @override
  int get size => entries.length;
  @override
  int get links => 2 + entries.values.whereType<DirectoryNode>().length;
  @override
  String get tag => 'd';
}

final class FileNode extends FsNode {
  List<String> lines;
  FileNode(super.inode, super.modified, [Iterable<String> content = const []])
      : lines = content.toList();
  @override
  int get size => lines.fold(0, (sum, line) => sum + line.length + 1);
  @override
  String get tag => '-';
}

final class LinkNode extends FsNode {
  final String target;
  LinkNode(super.inode, super.modified, this.target);
  @override
  int get size => target.length;
  @override
  String get tag => 'l';
}

enum Failure { none, missing, notDirectory, loop }

final class Resolution {
  final FsNode? node;
  final Failure error;
  final DirectoryNode? creationParent;
  final String creationName;
  const Resolution.found(this.node)
      : error = Failure.none, creationParent = null, creationName = '';
  const Resolution.failed(this.error)
      : node = null, creationParent = null, creationName = '';
  const Resolution.absent(this.creationParent, this.creationName)
      : node = null, error = Failure.missing;
  bool get absent => creationParent != null;
  String get reason => switch (error) {
    Failure.missing => 'No such file or directory',
    Failure.notDirectory => 'Not a directory',
    Failure.loop => 'Too many levels of symbolic links',
    Failure.none => '',
  };
}

typedef Output = void Function(String);
typedef InputReader = void Function(List<String>, String?);

(Set<String>, List<String>) options(List<String> args) {
  final flags = <String>{};
  var at = 0;
  while (at < args.length && args[at].startsWith('-')) {
    flags.addAll(args[at].substring(1).split(''));
    at++;
  }
  return (flags, args.sublist(at));
}

String lastComponent(String path) => path.substring(path.lastIndexOf('/') + 1);
String joinPath(String path, String name) => path == '/' ? '/$name' : '$path/$name';
bool invalidSource(String path) => const ['', '.', '..'].contains(lastComponent(path));
int smaller(int a, int b) => a < b ? a : b;
int larger(int a, int b) => a > b ? a : b;

final class Shell {
  final Output terminal;
  final root = DirectoryNode(1, 0);
  late DirectoryNode current;
  String? previous;
  int clock = 0;
  int nextInode = 2;

  Shell(this.terminal) {
    root.parent = root;
    current = root;
  }

  String absolute(FsNode node) {
    final parts = <String>[];
    while (!identical(node, root)) {
      parts.add(node.name);
      node = node.parent;
    }
    return '/' + parts.reversed.join('/');
  }

  bool descendant(FsNode node, FsNode ancestor) {
    while (true) {
      if (identical(node, ancestor)) return true;
      if (identical(node, root)) return false;
      node = node.parent;
    }
  }

  T add<T extends FsNode>(DirectoryNode parent, String name, T node) {
    parent.entries[name] = node;
    parent.modified = clock;
    node.parent = parent;
    node.name = name;
    return node;
  }

  DirectoryNode makeDirectory(DirectoryNode parent, String name) =>
      add(parent, name, DirectoryNode(nextInode++, clock));
  FileNode makeFile(DirectoryNode parent, String name, [Iterable<String> lines = const []]) =>
      add(parent, name, FileNode(nextInode++, clock, lines));
  void detach(FsNode node) {
    node.parent.entries.remove(node.name);
    node.parent.modified = clock;
  }

  void write(FileNode file, Iterable<String> lines, {bool append = false}) {
    if (append) {
      file.lines.addAll(lines);
    } else {
      file.lines = lines.toList();
    }
    file.modified = clock;
  }

  Resolution resolve(String path, {bool follow = true, bool parents = false}) {
    var expansions = 0;
    Resolution walk(String path, DirectoryNode base, bool follow, bool original) {
      FsNode node = path.startsWith('/') ? root : base;
      final parts = path.split('/').where((part) => part.isNotEmpty).toList();
      for (var i = 0; i < parts.length; i++) {
        if (node is! DirectoryNode) return const Resolution.failed(Failure.notDirectory);
        final directory = node;
        final part = parts[i], last = i + 1 == parts.length;
        if (part == '.') continue;
        if (part == '..') {
          node = directory.parent;
          continue;
        }
        var child = directory.entries[part];
        if (child == null) {
          if (original && last) return Resolution.absent(directory, part);
          if (original && parents) {
            child = makeDirectory(directory, part);
          } else {
            return const Resolution.failed(Failure.missing);
          }
        }
        if (child is LinkNode && (!last || follow)) {
          if (++expansions > 8) return const Resolution.failed(Failure.loop);
          final result = walk(child.target, directory, true, false);
          if (result.node == null) return result;
          child = result.node!;
        }
        node = child;
      }
      return Resolution.found(node);
    }
    return walk(path, current, follow, true);
  }

  void clone(FsNode source, DirectoryNode parent, String name) {
    switch (source) {
      case FileNode():
        makeFile(parent, name, source.lines);
      case LinkNode():
        add(parent, name, LinkNode(nextInode++, clock, source.target));
      case DirectoryNode():
        final directory = makeDirectory(parent, name);
        for (final entry in source.entries.entries) {
          clone(entry.value, directory, entry.key);
        }
    }
  }

  void move(String sourcePath, String destination) {
    void problem(String path, String reason) =>
        terminal("mv: cannot move '$sourcePath' to '$path': $reason");
    if (invalidSource(sourcePath)) {
      problem(destination, 'Invalid argument');
      return;
    }
    final sourceResult = resolve(sourcePath, follow: false);
    final source = sourceResult.node;
    if (source == null) {
      terminal("mv: cannot stat '$sourcePath': " + sourceResult.reason);
      return;
    }
    DirectoryNode parent;
    String name, display;
    final destinationNode = resolve(destination).node;
    if (destinationNode is DirectoryNode) {
      parent = destinationNode;
      name = lastComponent(sourcePath);
      display = joinPath(destination, name);
    } else {
      final result = resolve(destination, follow: false);
      if (result.absent) {
        parent = result.creationParent!;
        name = result.creationName;
      } else if (result.node case final node?) {
        parent = node.parent;
        name = node.name;
      } else {
        problem(destination, result.reason);
        return;
      }
      display = destination;
    }
    final existing = parent.entries[name];
    if (source is DirectoryNode && descendant(parent, source)) {
      terminal("mv: cannot move '$sourcePath' to a subdirectory of itself, '$display'");
    } else if (identical(existing, source)) {
      terminal("mv: '$sourcePath' and '$display' are the same file");
    } else if (existing != null && source is DirectoryNode && existing is! DirectoryNode) {
      terminal("mv: cannot overwrite non-directory '$display' with directory '$sourcePath'");
    } else if (source is! DirectoryNode && existing is DirectoryNode) {
      terminal("mv: cannot overwrite directory '$display' with non-directory '$sourcePath'");
    } else if (existing is DirectoryNode && existing.entries.isNotEmpty) {
      problem(display, 'Directory not empty');
    } else if (identical(existing, current)) {
      problem(display, 'Device or resource busy');
    } else {
      if (existing != null) detach(existing);
      detach(source);
      add(parent, name, source);
    }
  }

  void copy(String sourcePath, String destination, bool recursive) {
    void problem(String path, String reason) =>
        terminal("cp: cannot copy '$sourcePath' to '$path': $reason");
    if (invalidSource(sourcePath)) {
      problem(destination, 'Invalid argument');
      return;
    }
    final sourceResult = resolve(sourcePath);
    final source = sourceResult.node;
    if (source == null) {
      terminal("cp: cannot stat '$sourcePath': " + sourceResult.reason);
      return;
    }
    if (source is DirectoryNode && !recursive) {
      terminal("cp: -r not specified; omitting directory '$sourcePath'");
      return;
    }
    final result = resolve(destination);
    if (result.node == null && !result.absent) {
      problem(destination, result.reason);
      return;
    }
    final display = result.node is DirectoryNode
        ? joinPath(destination, lastComponent(sourcePath)) : destination;
    final target = resolve(display, follow: source is! DirectoryNode);
    if (source is DirectoryNode) {
      if (target.node != null) {
        problem(display, 'File exists');
      } else if (descendant(target.creationParent!, source)) {
        terminal("cp: cannot copy a directory, '$sourcePath', into itself, '$display'");
      } else {
        clone(source, target.creationParent!, target.creationName);
      }
    } else {
      final file = source as FileNode;
      if (target.absent) {
        makeFile(target.creationParent!, target.creationName, file.lines);
      } else if (identical(target.node, source)) {
        terminal("cp: '$sourcePath' and '$display' are the same file");
      } else if (target.node is DirectoryNode) {
        terminal("cp: cannot overwrite directory '$display' with non-directory '$sourcePath'");
      } else if (target.node case final FileNode other) {
        write(other, file.lines);
      } else {
        problem(display, target.reason);
      }
    }
  }

  void readInputs(String command, List<String> paths, List<String> input, InputReader consume) {
    if (paths.isEmpty) {
      consume(input, null);
      return;
    }
    for (final path in paths) {
      final result = resolve(path);
      switch (result.node) {
        case FileNode file:
          consume(file.lines, path);
        case DirectoryNode():
          terminal('$command: $path: Is a directory');
        default:
          terminal('$command: $path: ' + result.reason);
      }
    }
  }

  void walk(FsNode node, String path, void Function(FsNode, String, int) visit,
      {bool hidden = true, int? maxDepth, int depth = 0}) {
    visit(node, path, depth);
    if (node is DirectoryNode && (maxDepth == null || depth < maxDepth)) {
      for (final entry in node.entries.entries) {
        if (hidden || !entry.key.startsWith('.')) {
          walk(entry.value, joinPath(path, entry.key), visit,
              hidden: hidden, maxDepth: maxDepth, depth: depth + 1);
        }
      }
    }
  }

  void list(List<String> args, Output output) {
    final (flags, given) = options(args);
    final paths = given.isEmpty ? ['.'] : given;
    for (final path in paths) {
      final result = resolve(path, follow: !flags.contains('l'));
      final node = result.node;
      if (node == null) {
        terminal("ls: cannot access '$path': " + result.reason);
        continue;
      }
      var entries = <(String, FsNode)>[];
      if (node is DirectoryNode) {
        if (paths.length >= 2) output('$path:');
        if (flags.contains('a')) entries.addAll([('.', node), ('..', node.parent)]);
        for (final entry in node.entries.entries) {
          if (flags.contains('a') || !entry.key.startsWith('.')) {
            entries.add((entry.key, entry.value));
          }
        }
      } else {
        entries.add((path, node));
      }
      if (flags.contains('t')) {
        final indexed = entries.indexed.toList();
        indexed.sort((a, b) {
          final comparison = b.$2.$2.modified.compareTo(a.$2.$2.modified);
          return comparison != 0 ? comparison : a.$1.compareTo(b.$1);
        });
        entries = [for (final entry in indexed) entry.$2];
      }
      if (flags.contains('r')) entries = entries.reversed.toList();
      var linkWidth = 0, sizeWidth = 0, timeWidth = 0;
      for (final (_, node) in entries) {
        linkWidth = larger(linkWidth, node.links.toString().length);
        sizeWidth = larger(sizeWidth, node.size.toString().length);
        timeWidth = larger(timeWidth, node.modified.toString().length);
      }
      for (final (name, node) in entries) {
        if (!flags.contains('l')) {
          output(name);
        } else {
          var line = node.tag + ' ' + node.links.toString().padLeft(linkWidth) + ' ' +
              node.size.toString().padLeft(sizeWidth) + ' ' +
              node.modified.toString().padLeft(timeWidth) + ' ' + name;
          if (node is LinkNode) line += ' -> ' + node.target;
          output(line);
        }
      }
    }
  }

  void find(List<String> args, Output output) {
    var at = 0, path = '.';
    if (args.isNotEmpty && !args[0].startsWith('-')) path = args[at++];
    String? pattern, type;
    int? maxDepth;
    while (at < args.length) {
      final test = args[at++], value = args[at++];
      switch (test) {
        case '-name': pattern = value;
        case '-type': type = value;
        case '-maxdepth': maxDepth = int.parse(value);
      }
    }
    final result = resolve(path), node = result.node;
    if (node == null) {
      terminal("find: '$path': " + result.reason);
      return;
    }
    walk(node, path, (node, display, depth) {
      final name = depth == 0 ? (path == '/' ? '/' : lastComponent(path)) : node.name;
      final kind = node is FileNode ? 'f' : node.tag;
      if ((pattern == null || globMatch(pattern!, name)) && (type == null || type == kind)) {
        output(display);
      }
    }, maxDepth: maxDepth);
  }

  void diskUsage(List<String> args, Output output) {
    final (flags, given) = options(args);
    final paths = given.isEmpty ? ['.'] : given;
    int report(FsNode node, String path, bool show) {
      var usage = node is DirectoryNode ? 0 : node.size;
      if (node is DirectoryNode) {
        for (final entry in node.entries.entries) {
          usage += report(entry.value, joinPath(path, entry.key),
              !flags.contains('s') && (entry.value is DirectoryNode || flags.contains('a')));
        }
      }
      if (show) output('$usage $path');
      return usage;
    }
    for (final path in paths) {
      final result = resolve(path), node = result.node;
      if (node == null) {
        terminal("du: cannot access '$path': " + result.reason);
      } else {
        report(node, path, true);
      }
    }
  }

  void tree(List<String> args, Output output) {
    final (flags, paths) = options(args);
    final path = paths.isEmpty ? '.' : paths[0];
    final result = resolve(path), node = result.node;
    if (node == null) {
      terminal('tree: $path: ' + result.reason);
      return;
    }
    if (node is! DirectoryNode) {
      terminal('tree: $path: Not a directory');
      return;
    }
    var directories = 0, files = 0;
    void draw(DirectoryNode directory, String prefix) {
      final entries = directory.entries.entries
          .where((entry) => flags.contains('a') || !entry.key.startsWith('.')).toList();
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i], child = entry.value, last = i + 1 == entries.length;
        var line = prefix + (last ? '`-- ' : '|-- ') + entry.key;
        if (child is LinkNode) line += ' -> ' + child.target;
        output(line);
        if (child is DirectoryNode) {
          directories++;
          draw(child, prefix + (last ? '    ' : '|   '));
        } else {
          files++;
        }
      }
    }
    output(path);
    draw(node, '');
    output('$directories ' + (directories == 1 ? 'directory' : 'directories') +
        ', $files ' + (files == 1 ? 'file' : 'files'));
  }

  void wordCount(List<String> args, List<String> input, Output output) {
    final (flags, paths) = options(args);
    if (flags.isEmpty) flags.addAll(['l', 'w', 'c']);
    var totalLines = 0, totalWords = 0, totalBytes = 0;
    void report(int lines, int words, int bytes, String? name) {
      final values = [
        if (flags.contains('l')) lines,
        if (flags.contains('w')) words,
        if (flags.contains('c')) bytes,
      ];
      output(values.join(' ') + (name == null ? '' : ' $name'));
    }
    readInputs('wc', paths, input, (lines, name) {
      var words = 0, bytes = 0;
      for (final line in lines) {
        var inside = false;
        for (final character in line.codeUnits) {
          if (character != 32 && !inside) words++;
          inside = character != 32;
        }
        bytes += line.length + 1;
      }
      totalLines += lines.length;
      totalWords += words;
      totalBytes += bytes;
      report(lines.length, words, bytes, name);
    });
    if (paths.length >= 2) report(totalLines, totalWords, totalBytes, 'total');
  }

  void ends(String command, List<String> args, List<String> input, Output output) {
    var count = '10', at = 0;
    if (args.isNotEmpty && args[0] == '-n') {
      count = args[1];
      at = 2;
    }
    final special = count.startsWith('-') || count.startsWith('+');
    final amount = int.parse(special ? count.substring(1) : count);
    readInputs(command, args.sublist(at), input, (lines, _) {
      var first = 0, end = lines.length;
      if (command == 'head') {
        end = special ? larger(0, lines.length - amount) : smaller(lines.length, amount);
      } else {
        first = special ? smaller(lines.length, larger(0, amount - 1)) : larger(0, lines.length - amount);
      }
      for (var i = first; i < end; i++) output(lines[i]);
    });
  }

  void grep(List<String> args, List<String> input, Output output) {
    final (flags, rest) = options(args);
    final pattern = flags.contains('i') ? rest[0].toLowerCase() : rest[0];
    final paths = rest.sublist(1);
    void consume(List<String> lines, String? name) {
      final prefix = paths.length >= 2 || flags.contains('r') ? '$name:' : '';
      var selected = 0;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i], compared = flags.contains('i') ? line.toLowerCase() : line;
        if (compared.contains(pattern) == flags.contains('v')) continue;
        selected++;
        if (!flags.contains('c')) {
          final number = flags.contains('n') ? (i + 1).toString() + ':' : '';
          output(prefix + number + line);
        }
      }
      if (flags.contains('c')) output('$prefix$selected');
    }
    if (!flags.contains('r')) {
      readInputs('grep', paths, input, consume);
    } else {
      for (final path in paths.isEmpty ? ['.'] : paths) {
        final result = resolve(path), node = result.node;
        if (node == null) {
          terminal('grep: $path: ' + result.reason);
        } else {
          walk(node, path, (child, display, _) {
            if (child is FileNode) consume(child.lines, display);
          });
        }
      }
    }
  }

  void sortLines(List<String> args, List<String> input, Output output) {
    final (flags, paths) = options(args);
    final lines = <String>[];
    readInputs('sort', paths, input, (part, _) => lines.addAll(part));
    lines.sort((a, b) {
      if (flags.contains('n')) {
        final comparison = numericPrefix(a).compareTo(numericPrefix(b));
        if (comparison != 0) return comparison;
      }
      return a.compareTo(b);
    });
    for (final line in flags.contains('r') ? lines.reversed : lines) output(line);
  }

  void unique(List<String> args, List<String> input, Output output) {
    final (flags, paths) = options(args);
    readInputs('uniq', paths, input, (lines, _) {
      for (var first = 0; first < lines.length;) {
        var end = first + 1;
        while (end < lines.length && lines[end] == lines[first]) end++;
        output((flags.contains('c') ? (end - first).toString() + ' ' : '') + lines[first]);
        first = end;
      }
    });
  }

  void execute(String text, List<String> input, Output output) {
    final words = text.split(' '), command = words[0], args = words.sublist(1);
    switch (command) {
      case 'pwd': output(absolute(current));
      case 'echo': output(text.substring(5));
      case 'cd':
        final back = args.isNotEmpty && args[0] == '-';
        if (back && previous == null) {
          terminal('cd: OLDPWD not set');
          return;
        }
        final path = back ? previous! : (args.isEmpty ? '/' : args[0]);
        final result = resolve(path), node = result.node;
        if (node == null) {
          terminal('cd: $path: ' + result.reason);
        } else if (node is! DirectoryNode) {
          terminal('cd: $path: Not a directory');
        } else {
          previous = absolute(current);
          current = node;
          if (back) output(absolute(current));
        }
      case 'mkdir':
        final (flags, paths) = options(args);
        for (final path in paths) {
          final result = resolve(path, follow: false, parents: flags.contains('p'));
          if (result.absent) {
            makeDirectory(result.creationParent!, result.creationName);
          } else if (result.node == null) {
            terminal("mkdir: cannot create directory '$path': " + result.reason);
          } else if (!flags.contains('p') || resolve(path).node is! DirectoryNode) {
            terminal("mkdir: cannot create directory '$path': File exists");
          }
        }
      case 'touch':
        for (final path in args) {
          final result = resolve(path), node = result.node;
          if (result.absent) {
            makeFile(result.creationParent!, result.creationName);
          } else if (node != null) {
            node.modified = clock;
          } else {
            terminal("touch: cannot touch '$path': " + result.reason);
          }
        }
      case 'cat': readInputs(command, args, input, (lines, _) { lines.forEach(output); });
      case 'ls': list(args, output);
      case 'stat':
        for (final path in args) {
          final result = resolve(path, follow: false), node = result.node;
          if (node == null) {
            terminal("stat: cannot stat '$path': " + result.reason);
          } else {
            final type = switch (node) {
              DirectoryNode() => 'directory',
              LinkNode() => 'symbolic link',
              FileNode(:final lines) => lines.isEmpty ? 'regular empty file' : 'regular file',
            };
            output('$path: $type, size ' + node.size.toString() + ', inode ' + node.inode.toString() +
                ', links ' + node.links.toString() + ', modified ' + node.modified.toString());
          }
        }
      case 'rm':
        final (flags, paths) = options(args);
        for (final path in paths) {
          void problem(String reason) => terminal("rm: cannot remove '$path': $reason");
          if (const ['.', '..'].contains(lastComponent(path))) {
            terminal("rm: refusing to remove '.' or '..' directory: skipping '$path'");
            continue;
          }
          final result = resolve(path, follow: false), node = result.node;
          if (node == null) {
            if (!(flags.contains('f') && result.error == Failure.missing)) problem(result.reason);
          } else if (node is DirectoryNode && !flags.contains('r')) {
            problem('Is a directory');
          } else if (descendant(current, node)) {
            problem('Device or resource busy');
          } else {
            detach(node);
          }
        }
      case 'rmdir':
        for (final path in args) {
          void problem(String reason) => terminal("rmdir: failed to remove '$path': $reason");
          if (const ['.', '..'].contains(lastComponent(path))) {
            problem('Invalid argument');
            continue;
          }
          final result = resolve(path, follow: false), node = result.node;
          if (node == null) {
            problem(result.reason);
          } else if (node is! DirectoryNode) {
            problem('Not a directory');
          } else if (descendant(current, node)) {
            problem('Device or resource busy');
          } else if (node.entries.isNotEmpty) {
            problem('Directory not empty');
          } else {
            detach(node);
          }
        }
      case 'mv':
      case 'cp':
        final (flags, paths) = command == 'cp' ? options(args) : (<String>{}, args);
        final destination = paths.last, sources = paths.sublist(0, paths.length - 1);
        if (sources.length >= 2 && resolve(destination).node is! DirectoryNode) {
          terminal("$command: target '$destination' is not a directory");
          return;
        }
        for (final source in sources) {
          if (command == 'mv') {
            move(source, destination);
          } else {
            copy(source, destination, flags.contains('r'));
          }
        }
      case 'ln':
        final target = args[1], path = args[2], result = resolve(path, follow: false);
        if (result.absent) {
          add(result.creationParent!, result.creationName, LinkNode(nextInode++, clock, target));
        } else {
          final reason = result.node == null ? result.reason : 'File exists';
          terminal("ln: failed to create symbolic link '$path': $reason");
        }
      case 'readlink':
        final path = args[0], result = resolve(path, follow: false);
        if (result.node case final LinkNode link) {
          output(link.target);
        } else {
          final reason = result.node == null ? result.reason : 'Invalid argument';
          terminal('readlink: $path: $reason');
        }
      case 'realpath':
        final path = args[0], result = resolve(path), node = result.node;
        if (node == null) {
          terminal('realpath: $path: ' + result.reason);
        } else {
          output(absolute(node));
        }
      case 'find': find(args, output);
      case 'du': diskUsage(args, output);
      case 'tree': tree(args, output);
      case 'wc': wordCount(args, input, output);
      case 'head':
      case 'tail': ends(command, args, input, output);
      case 'grep': grep(args, input, output);
      case 'sort': sortLines(args, input, output);
      case 'uniq': unique(args, input, output);
      default: terminal('$command: command not found');
    }
  }

  void process(String line) {
    clock++;
    terminal(absolute(current) + r'$ ' + line);
    var pipeline = line;
    FileNode? redirect;
    final marker = line.indexOf(' >');
    if (marker >= 0) {
      pipeline = line.substring(0, marker);
      final append = line.startsWith(' >> ', marker);
      final path = line.substring(marker + (append ? 4 : 3));
      final result = resolve(path), node = result.node;
      if (result.absent) {
        redirect = makeFile(result.creationParent!, result.creationName);
      } else if (node is FileNode) {
        redirect = node;
        if (!append) write(node, const []);
      } else {
        final reason = node is DirectoryNode ? 'Is a directory' : result.reason;
        terminal('sh: $path: $reason');
        return;
      }
    }
    var input = <String>[];
    final commands = pipeline.split(' | ');
    for (var i = 0; i < commands.length; i++) {
      final output = <String>[];
      final direct = i + 1 == commands.length && redirect == null;
      execute(commands[i], input, direct ? terminal : output.add);
      input = output;
    }
    if (redirect != null && input.isNotEmpty) write(redirect, input, append: true);
  }
}

bool globMatch(String pattern, String text) {
  var previous = List<bool>.filled(text.length + 1, false);
  previous[0] = true;
  for (final character in pattern.split('')) {
    final next = List<bool>.filled(text.length + 1, false);
    next[0] = character == '*' && previous[0];
    for (var i = 1; i <= text.length; i++) {
      next[i] = character == '*' ? previous[i] || next[i - 1] :
          previous[i - 1] && (character == '?' || character == text[i - 1]);
    }
    previous = next;
  }
  return previous[text.length];
}

int numericPrefix(String line) {
  var at = line.startsWith('-') ? 1 : 0, value = 0;
  while (at < line.length) {
    final digit = line.codeUnitAt(at) - 48;
    if (digit < 0 || digit > 9) break;
    value = value * 10 + digit;
    at++;
  }
  return line.startsWith('-') ? -value : value;
}

void main() {
  final shell = Shell(stdout.writeln);
  while (true) {
    final line = stdin.readLineSync();
    if (line == null || line == 'exit') break;
    shell.process(line);
  }
}
