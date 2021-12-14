// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

import 'resolver.dart';
import 'hitmap.dart';

abstract class Formatter {
  /// Returns the formatted coverage data.
  @Deprecated('Migrate to formatV2')
  Future<String> format(Map<String, Map<int, int>> hitmap);

  /// Returns the formatted coverage data.
  Future<String> formatV2(Map<String, HitMap> hitmap);
}

/// Converts the given hitmap to lcov format and appends the result to
/// env.output.
///
/// Returns a [Future] that completes as soon as all map entries have been
/// emitted.
class LcovFormatter implements Formatter {
  /// Creates a LCOV formatter.
  ///
  /// If [reportOn] is provided, coverage report output is limited to files
  /// prefixed with one of the paths included. If [basePath] is provided, paths
  /// are reported relative to that path.
  LcovFormatter(this.resolver, {this.reportOn, this.basePath});

  final Resolver resolver;
  final String? basePath;
  final List<String>? reportOn;

  @Deprecated('Migrate to formatV2')
  @override
  Future<String> format(Map<String, Map<int, int>> hitmap) {
    return formatV2(hitmap.map((key, value) => MapEntry(key, HitMap(value))));
  }

  @override
  Future<String> formatV2(Map<String, HitMap> hitmap) async {
    final pathFilter = _getPathFilter(reportOn);
    final buf = StringBuffer();
    for (var key in hitmap.keys) {
      final v = hitmap[key]!;
      final lineHits = v.lineHits;
      final funcHits = v.funcHits;
      final funcNames = v.funcNames;
      var source = resolver.resolve(key);
      if (source == null) {
        continue;
      }

      if (!pathFilter(source)) {
        continue;
      }

      if (basePath != null) {
        source = p.relative(source, from: basePath);
      }

      buf.write('SF:$source\n');
      if (funcHits != null && funcNames != null) {
        for (var k in funcNames.keys.toList()..sort()) {
          buf.write('FN:$k,${funcNames[k]}\n');
        }
        for (var k in funcHits.keys.toList()..sort()) {
          if (funcHits[k]! != 0) {
            buf.write('FNDA:${funcHits[k]},${funcNames[k]}\n');
          }
        }
        buf.write('FNF:${funcNames.length}\n');
        buf.write('FNH:${funcHits.values.where((v) => v > 0).length}\n');
      }
      for (var k in lineHits.keys.toList()..sort()) {
        buf.write('DA:$k,${lineHits[k]}\n');
      }
      buf.write('LF:${lineHits.length}\n');
      buf.write('LH:${lineHits.values.where((v) => v > 0).length}\n');
      buf.write('end_of_record\n');
    }

    return buf.toString();
  }
}

/// Converts the given hitmap to a pretty-print format and appends the result
/// to env.output.
///
/// Returns a [Future] that completes as soon as all map entries have been
/// emitted.
class PrettyPrintFormatter implements Formatter {
  /// Creates a pretty-print formatter.
  ///
  /// If [reportOn] is provided, coverage report output is limited to files
  /// prefixed with one of the paths included.
  PrettyPrintFormatter(this.resolver, this.loader,
      {this.reportOn, this.reportFuncs = false});

  final Resolver resolver;
  final Loader loader;
  final List<String>? reportOn;
  final bool reportFuncs;

  @Deprecated('Migrate to formatV2')
  @override
  Future<String> format(Map<String, Map<int, int>> hitmap) {
    return formatV2(hitmap.map((key, value) => MapEntry(key, HitMap(value))));
  }

  @override
  Future<String> formatV2(Map<String, HitMap> hitmap) async {
    final pathFilter = _getPathFilter(reportOn);
    final buf = StringBuffer();
    for (var key in hitmap.keys) {
      final v = hitmap[key]!;
      if (reportFuncs && v.funcHits == null) {
        throw 'Function coverage formatting was requested, but the hit map is '
            'missing function coverage information. Did you run '
            'collect_coverage with the --function-coverage flag?';
      }
      final hits = reportFuncs ? v.funcHits! : v.lineHits;
      final source = resolver.resolve(key);
      if (source == null) {
        continue;
      }

      if (!pathFilter(source)) {
        continue;
      }

      final lines = await loader.load(source);
      if (lines == null) {
        continue;
      }
      buf.writeln(source);
      for (var line = 1; line <= lines.length; line++) {
        var prefix = _prefix;
        if (hits.containsKey(line)) {
          prefix = hits[line].toString().padLeft(_prefix.length);
        }
        buf.writeln('$prefix|${lines[line - 1]}');
      }
    }

    return buf.toString();
  }
}

const _prefix = '       ';

typedef _PathFilter = bool Function(String path);

_PathFilter _getPathFilter(List<String>? reportOn) {
  if (reportOn == null) return (String path) => true;

  final absolutePaths = reportOn.map(p.absolute).toList();
  return (String path) => absolutePaths.any((item) => path.startsWith(item));
}
