import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:crypto/crypto.dart';

// Read-only source extraction: offsets come from the Dart parser, not braces.
void main(List<String> args) {
  final configFile = File(args.single);
  final output = configFile.parent;
  final config = jsonDecode(configFile.readAsStringSync()) as List;
  final index = <Map<String, Object?>>[];
  final manifest = <Map<String, Object?>>[];
  final errors = <String>[];
  for (final entry in config.cast<Map<String, dynamic>>()) {
    final path = entry['path'] as String;
    final group = entry['group'] as String;
    final source = File(path).readAsStringSync();
    final parsed = parseString(content: source, path: path, throwIfDiagnostics: false);
    final nodes = <String, AstNode>{};
    void members(String owner, Iterable<ClassMember> values) {
      for (final member in values) {
        if (member is MethodDeclaration) nodes['$owner.${member.name.lexeme}'] = member;
        if (member is ConstructorDeclaration) {
          nodes['$owner.${member.name?.lexeme ?? 'new'}'] = member;
        }
        if (member is FieldDeclaration) {
          for (final field in member.fields.variables) {
            nodes['$owner.${field.name.lexeme}'] = member;
          }
        }
      }
    }
    for (final declaration in parsed.unit.declarations) {
      if (declaration is ClassDeclaration) {
        final name = declaration.name.lexeme;
        nodes[name] = declaration;
        members(name, declaration.members);
      } else if (declaration is MixinDeclaration) {
        final name = declaration.name.lexeme;
        nodes[name] = declaration;
        members(name, declaration.members);
      } else if (declaration is ExtensionDeclaration) {
        final name = declaration.name?.lexeme ?? '<extension>';
        nodes[name] = declaration;
        members(name, declaration.members);
      } else if (declaration is EnumDeclaration) {
        nodes[declaration.name.lexeme] = declaration;
      } else if (declaration is FunctionDeclaration) {
        nodes[declaration.name.lexeme] = declaration;
      } else if (declaration is TopLevelVariableDeclaration) {
        for (final variable in declaration.variables.variables) {
          nodes[variable.name.lexeme] = declaration;
        }
      }
    }
    for (final node in nodes.entries) {
      index.add({'path': path, 'selector': node.key,
        'start': parsed.lineInfo.getLocation(node.value.offset).lineNumber,
        'end': parsed.lineInfo.getLocation(node.value.end).lineNumber});
    }
    for (final selector in (entry['selectors'] as List).cast<String>()) {
      final node = nodes[selector];
      if (selector != '@file' && node == null) {
        errors.add('$path :: $selector');
        continue;
      }
      final begin = node?.offset ?? 0;
      final end = node?.end ?? source.length;
      final text = source.substring(begin, end);
      final startLine = parsed.lineInfo.getLocation(begin).lineNumber;
      final endLine = parsed.lineInfo.getLocation(end).lineNumber;
      final slug = path.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
      final name = selector.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
      final relative = 'source/$group/$slug--$name.txt';
      final target = File('${output.path}/$relative');
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(text);
      manifest.add({'group': group, 'sourcePath': path, 'selector': selector,
        'startLine': startLine, 'endLine': endLine, 'snapshot': relative,
        'sourceSha256': sha256.convert(File(path).readAsBytesSync()).toString(),
        'excerptSha256': sha256.convert(utf8.encode(text)).toString()});
    }
  }
  const encoder = JsonEncoder.withIndent('  ');
  File('${output.path}/symbol-index.json').writeAsStringSync(encoder.convert(index));
  File('${output.path}/source-manifest.json').writeAsStringSync(encoder.convert(manifest));
  stdout.writeln(jsonEncode({'sourceFiles': config.length, 'symbols': index.length,
    'snapshots': manifest.length, 'missingSelectors': errors}));
  if (errors.isNotEmpty) exitCode = 1;
}
