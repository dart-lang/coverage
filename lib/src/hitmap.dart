// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert' show json;
import 'dart:io';

import 'resolver.dart';

Future<List<int>> _getIgnoredLines(String source, Resolver resolver, Loader loader) async {
  final ignoredLines = new List<int>();

  final resolvedPathFile = resolver.resolve(source);
  if (resolvedPathFile == null) {
    return ignoredLines;
  }

  final lines = await loader.load(resolvedPathFile);
  if (lines == null) {
    return ignoredLines;
  }
  var skipping = false;

  for (var i = 0; i < lines.length; i++) {
    if (skipping) {
      ignoredLines.add(i + 1);
      skipping = !lines[i].contains("// coverage:ignore-end");
    } else {
      skipping = lines[i].contains("// coverage:ignore-start");
    }

    if (lines[i].contains("// coverage:ignore-line")) {
      ignoredLines.add(i + 1);
    }
  }

  return ignoredLines;
}

/// Creates a single hitmap from a raw json object. Throws away all entries that
/// are not resolvable.
///
/// `jsonResult` is expected to be a List<Map<String, dynamic>>.
Future<Map<String, Map<int, int>>> createHitmap(List jsonResult) async {
  // Map of source file to map of line to hit count for that line.
  var globalHitMap = <String, Map<int, int>>{};
  var resolver = new Resolver();
  var loader = new Loader();

  void addToMap(Map<int, int> map, int line, int count) {
    var oldCount = map.putIfAbsent(line, () => 0);
    map[line] = count + oldCount;
  }

  for (Map<String, dynamic> e in jsonResult) {
    String source = e['source'];
    if (source == null) {
      // Couldn't resolve import, so skip this entry.
      continue;
    }

    final ignoredLines = await _getIgnoredLines(source, resolver, loader);

    var sourceHitMap = globalHitMap.putIfAbsent(source, () => <int, int>{});
    List<dynamic> hits = e['hits'];
    // hits is a flat array of the following format:
    // [ <line|linerange>, <hitcount>,...]
    // line: number.
    // linerange: '<line>-<line>'.
    for (var i = 0; i < hits.length; i += 2) {
      dynamic k = hits[i];
      if (k is num) {
        // Single line.
        if (!ignoredLines.contains(k)) {
          addToMap(sourceHitMap, k, hits[i + 1]);
        }
      } else {
        assert(k is String);
        // Linerange. We expand line ranges to actual lines at this point.
        int splitPos = k.indexOf('-');
        int start = int.parse(k.substring(0, splitPos));
        int end = int.parse(k.substring(splitPos + 1));
        for (var j = start; j <= end; j++) {
          if (!ignoredLines.contains(k)) {
            addToMap(sourceHitMap, j, hits[i + 1]);
          }
        }
      }
    }
  }
  return globalHitMap;
}

/// Merges [newMap] into [result].
void mergeHitmaps(
    Map<String, Map<int, int>> newMap, Map<String, Map<int, int>> result) {
  newMap.forEach((String file, Map<int, int> v) {
    if (result.containsKey(file)) {
      v.forEach((int line, int cnt) {
        if (result[file][line] == null) {
          result[file][line] = cnt;
        } else {
          result[file][line] += cnt;
        }
      });
    } else {
      result[file] = v;
    }
  });
}

/// Generates a merged hitmap from a set of coverage JSON files.
Future<Map> parseCoverage(Iterable<File> files, int _) async {
  var globalHitmap = <String, Map<int, int>>{};
  for (var file in files) {
    String contents = file.readAsStringSync();
    List jsonResult = json.decode(contents)['coverage'];
    Map<String, Map<int, int>> hitmap = await createHitmap(jsonResult);
    mergeHitmaps(hitmap, globalHitmap);
  }
  return globalHitmap;
}
