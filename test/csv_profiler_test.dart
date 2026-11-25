import 'dart:convert';
import 'dart:io';
import 'package:csv_profiler/csv_profiler.dart';
import 'package:test/test.dart';

Stream<String> chunks(String input, int width) async* {
  for (var start = 0; start < input.length; start += width) {
    yield input.substring(
        start, start + width < input.length ? start + width : input.length);
  }
}

void main() {
  test('quotes, commas, CRLF and embedded newlines across every chunk width',
      () async {
    const csv = '\uFEFFid,note\r\n1,"a,b"\r\n2,"say ""yes""\nand go"\r\n3,""';
    final expected = [
      ['id', 'note'],
      ['1', 'a,b'],
      ['2', 'say "yes"\nand go'],
      ['3', '']
    ];
    for (var width = 1; width <= csv.length; width++) {
      expect(await parseCsv(chunks(csv, width)).toList(), expected);
    }
  });
  test('malformed quote states and field limit are rejected', () async {
    for (final csv in ['a\n"unterminated', 'a\nab"c', 'a\n"value"x']) {
      await expectLater(
          parseCsv(Stream.value(csv)).toList(), throwsFormatException);
    }
    await expectLater(
        parseCsv(Stream.value('a\nlong'), maxFieldCharacters: 3).toList(),
        throwsFormatException);
  });
  test('empty files, headers, row widths and trailing delimiters', () async {
    expect(await parseCsv(Stream.value('')).toList(), isEmpty);
    expect(await parseCsv(Stream.value('a,b\nx,')).toList(), [
      ['a', 'b'],
      ['x', '']
    ]);
    expect(await parseCsv(Stream.value('a\n')).toList(), [
      ['a']
    ]);
    for (final input in ['', ',b\n1,2', 'a,a\n1,2', 'a,b\n1', 'a\n1,2']) {
      await expectLater(profileCsv(Stream.value(input)), throwsFormatException);
    }
  });
  test('null policy, types and numeric statistics', () async {
    final result = await profileCsv(
        Stream.value(
            'amount,flag,label\n10,true,a\n20.5,false,b\n, ,c\nNA,true,d'),
        nullTokens: {'', 'NA'});
    final columns = result['columns'] as List;
    expect(result['rows'], 4);
    expect(columns[0]['type'], 'number');
    expect(columns[0]['null_count'], 2);
    expect(columns[0]['numeric_mean'], 15.25);
    expect(columns[0]['numeric_min'], 10);
    expect(columns[0]['numeric_max'], 20.5);
    expect(columns[1]['type'], 'boolean');
    expect(columns[2]['type'], 'text');
  });
  test(
      'nonfinite numbers remain text; numeric values do not require a stored sum',
      () async {
    final result =
        await profileCsv(Stream.value('large,mixed\n1e308,NaN\n1e308,2'));
    final columns = result['columns'] as List;
    expect(columns[0]['numeric_mean'], 1e308);
    expect(columns[1]['type'], 'mixed');
  });
  test('fixture and generated stream do not depend on whole-file buffering',
      () async {
    final fixture = await profileCsv(
        File('fixtures/sensors.csv').openRead().transform(utf8.decoder));
    expect(fixture['rows'], 4);
    Stream<String> generated() async* {
      yield 'value\n';
      for (var index = 1; index <= 10000; index++) {
        yield '$index\n';
      }
    }

    final result = await profileCsv(generated());
    expect(result['rows'], 10000);
    expect((result['columns'] as List).first['numeric_mean'],
        closeTo(5000.5, 1e-8));
  });
}
