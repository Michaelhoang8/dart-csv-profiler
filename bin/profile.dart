import 'dart:convert';
import 'dart:io';
import 'package:csv_profiler/csv_profiler.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run bin/profile.dart file.csv');
    exitCode = 2;
    return;
  }
  try {
    final report =
        await profileCsv(File(args.single).openRead().transform(utf8.decoder));
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } on Object catch (error) {
    stderr.writeln('Error: $error');
    exitCode = 2;
  }
}
