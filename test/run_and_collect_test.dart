// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:coverage/coverage.dart';
import 'package:test/test.dart';

import 'test_util.dart';

void main() {
  group('runAndCollect', () {
    test('collects correctly', () async {
      var lineHits = await runAndCollect(testAppPath);

      validateTestAppCoverage(lineHits);
    });

    test('handles hanging apps correctly', () async {
      var caught = false;
      try {
        await runAndCollect(testAppPath,
            scriptArgs: ['never-exit'], timeout: const Duration(seconds: 1));
      } on CoverageTimeoutException catch (e) {
        caught = true;
        expect(e.toString(), 'Failed to pause isolates within 1s.');
      }

      expect(caught, isTrue);
    });

    test('handle invalid application correctly', () async {
      var caught = false;
      try {
        await runAndCollect('_not_an_app');
      } on CoverageTimeoutException catch (e) {
        caught = true;
        expect(e.toString(),
            'Failed to get the VM object from the VM service within 5s.');
      }

      expect(caught, isTrue);
    });
  });
}
