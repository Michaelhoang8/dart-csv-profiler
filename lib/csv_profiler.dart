enum _State { start, unquoted, quoted, afterQuote }

/// Parses strict CSV incrementally, including quoted newlines and doubled quotes.
/// CR, LF and CRLF delimit records outside quoted fields. A UTF-8 BOM is ignored.
Stream<List<String>> parseCsv(Stream<String> chunks,
    {int maxFieldCharacters = 1000000}) async* {
  if (maxFieldCharacters < 1) {
    throw ArgumentError.value(maxFieldCharacters, 'maxFieldCharacters');
  }
  var state = _State.start;
  var field = StringBuffer();
  var row = <String>[];
  var skipLf = false;
  var first = true;
  var record = 1;

  void append(String character) {
    field.write(character);
    if (field.length > maxFieldCharacters) {
      throw FormatException('Record $record exceeds field size limit');
    }
  }

  void endField() {
    row.add(field.toString());
    field = StringBuffer();
    state = _State.start;
  }

  await for (final chunk in chunks) {
    for (var index = 0; index < chunk.length; index++) {
      final character = chunk[index];
      if (first) {
        first = false;
        if (character == '\uFEFF') continue;
      }
      if (skipLf) {
        skipLf = false;
        if (character == '\n') continue;
      }
      if (state == _State.quoted) {
        if (character == '"') {
          state = _State.afterQuote;
        } else {
          append(character);
        }
        continue;
      }
      if (state == _State.afterQuote && character == '"') {
        append('"');
        state = _State.quoted;
        continue;
      }
      if (character == ',') {
        endField();
      } else if (character == '\r' || character == '\n') {
        endField();
        yield row;
        row = <String>[];
        record++;
        skipLf = character == '\r';
      } else if (state == _State.afterQuote) {
        throw FormatException(
            'Record $record has characters after a closing quote');
      } else if (character == '"') {
        if (state != _State.start) {
          throw FormatException(
              'Record $record has a quote inside an unquoted field');
        }
        state = _State.quoted;
      } else {
        append(character);
        state = _State.unquoted;
      }
    }
  }
  if (state == _State.quoted) {
    throw FormatException('Record $record has an unterminated quoted field');
  }
  if (row.isNotEmpty || field.isNotEmpty || state == _State.afterQuote) {
    endField();
    yield row;
  }
}

class ColumnStats {
  final String name;
  int nulls = 0;
  int integers = 0;
  int decimals = 0;
  int booleans = 0;
  int text = 0;
  double? minimum;
  double? maximum;
  double? mean;
  static final _integer = RegExp(r'^[+-]?\d+$');

  ColumnStats(this.name);
  int get numericCount => integers + decimals;
  int get nonNullCount => numericCount + booleans + text;

  void add(String raw, Set<String> nullTokens) {
    final value = raw.trim();
    if (nullTokens.contains(value)) {
      nulls++;
      return;
    }
    final number = double.tryParse(value);
    if (number != null && number.isFinite) {
      if (_integer.hasMatch(value)) {
        integers++;
      } else {
        decimals++;
      }
      minimum = minimum == null || number < minimum! ? number : minimum;
      maximum = maximum == null || number > maximum! ? number : maximum;
      final count = numericCount;
      // Weighted update avoids summing the entire numeric column.
      mean =
          count == 1 ? number : mean! * ((count - 1) / count) + number / count;
    } else if (value == 'true' || value == 'false') {
      booleans++;
    } else {
      text++;
    }
  }

  String get inferredType {
    if (nonNullCount == 0) return 'null';
    if (integers == nonNullCount) return 'integer';
    if (numericCount == nonNullCount) return 'number';
    if (booleans == nonNullCount) return 'boolean';
    if (text == nonNullCount) return 'text';
    return 'mixed';
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'type': inferredType,
        'null_count': nulls,
        'non_null_count': nonNullCount,
        'integer_count': integers,
        'decimal_count': decimals,
        'boolean_count': booleans,
        'text_count': text,
        'numeric_min': minimum,
        'numeric_max': maximum,
        'numeric_mean': mean,
      };
}

Future<Map<String, Object?>> profileCsv(Stream<String> chunks,
    {Set<String> nullTokens = const {''},
    int maxFieldCharacters = 1000000}) async {
  List<ColumnStats>? columns;
  var rowCount = 0;
  await for (final row
      in parseCsv(chunks, maxFieldCharacters: maxFieldCharacters)) {
    if (columns == null) {
      if (row.any((name) => name.trim().isEmpty) ||
          row.toSet().length != row.length) {
        throw const FormatException('Headers must be nonempty and unique');
      }
      columns = row.map(ColumnStats.new).toList();
      continue;
    }
    rowCount++;
    if (row.length != columns.length) {
      throw FormatException('Data row $rowCount has ${row.length} fields; '
          'expected ${columns.length}');
    }
    for (var index = 0; index < columns.length; index++) {
      columns[index].add(row[index], nullTokens);
    }
  }
  if (columns == null) throw const FormatException('CSV has no header');
  return {
    'rows': rowCount,
    'column_count': columns.length,
    'null_tokens': nullTokens.toList()..sort(),
    'columns': columns.map((column) => column.toJson()).toList(),
  };
}
