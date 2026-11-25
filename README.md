# Dart CSV Profiler

Parses CSV as a stream and reports row counts, null counts, inferred column types, and numeric minimum, maximum and mean. The parser and profiler have no runtime package dependencies.

## Run

Requires Dart 3.5 or later.

```sh
dart pub get
dart run bin/profile.dart fixtures/sensors.csv
dart test
dart analyze
```

The sensor fixture includes quoted commas, doubled quotes, an embedded newline, and a missing numeric reading. It contains four data records, even though it occupies more than five physical lines.

## Parsing and inference

The state machine accepts CR, LF and CRLF record delimiters, UTF-8 BOMs, quoted newlines, and doubled quote escapes. It preserves whitespace inside parsed fields and rejects stray quotes, text after closing quotes, unfinished quoted fields, duplicate or empty headers, and inconsistent record widths. A field-size limit defaults to one million UTF-16 code units. Memory grows with column statistics and the largest record; the input file is never read into one whole-file string.

Profiling trims field values. Empty trimmed values are null by default; library callers can supply explicit null tokens. `true` and `false` are case-sensitive booleans. Finite numeric values are classified as integer or decimal notation; other values, including `NaN` and infinity, remain text. Mixed columns retain each type's counts. Numeric summaries describe the numeric subset only and use IEEE-754 doubles, so they are approximate for large integers and are not suitable for exact accounting. Type inference does not validate semantic types such as dates or identifiers.

The CLI writes JSON to stdout. Invalid input or I/O errors produce an error on stderr and exit 2.

## Verification

Tests parse a quoted multiline fixture at every possible chunk width, exercise malformed CSV and header/width failures, verify null and type policies, check large finite numbers, and profile a generated 10,000-record stream. CI also runs static analysis and the fixture command.

[Dart streams documentation](https://dart.dev/libraries/async/using-streams)

MIT licensed. Sensor readings are explicitly illustrative fixtures.
