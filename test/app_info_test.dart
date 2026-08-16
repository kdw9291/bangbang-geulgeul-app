import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapscratch/app_info.dart';

/// 버전 상수가 `pubspec.yaml` 과 어긋나지 않는지 본다.
///
/// `package_info_plus` 를 넣지 않는 대신 두는 방어선이다 — 카테고리 생성물에
/// 쓰는 freshness 검사와 같은 방식이다. **이 검사가 성립하는 전제**는 릴리스
/// 버전을 `pubspec.yaml` 만으로 정한다는 것이다. `--build-name`·`--build-number`
/// 나 flavor 가 생기면 상수가 실제 APK 와 달라지므로 그때는 `package_info_plus`
/// 로 바꾼다(Codex 22회차).
void main() {
  test('버전 상수가 pubspec.yaml 과 같다', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final value = line.substring('version:'.length).trim();

    expect(value, contains('+'), reason: 'pubspec 버전 형식이 바뀌었다: $value');
    final parts = value.split('+');
    expect(parts[0], kAppVersionName,
        reason: 'pubspec 을 고치고 kAppVersionName 을 안 고쳤다');
    expect(parts[1], kAppBuildNumber,
        reason: 'pubspec 을 고치고 kAppBuildNumber 를 안 고쳤다');
  });

  test('표시 문자열이 이름과 빌드 번호를 모두 담는다', () {
    expect(appVersionLabel, '$kAppVersionName ($kAppBuildNumber)');
  });

  group('출처 문구 — CC BY 4.0', () {
    test('저작자·라이선스·원자료가 들어 있다', () {
      expect(kMapAttributionBody, contains('vuski/admdongkor'));
      expect(kMapAttributionBody, contains('ver20260701'));
      expect(kMapAttributionBody, contains('CC BY 4.0'));
      expect(kMapAttributionBody, contains('통계청'));
    });

    test('**변경 고지**가 있다', () {
      // CC BY 4.0 은 자료를 고쳤으면 고쳤다고 밝히기를 요구한다.
      // 내 초안에서 빠져 있던 항목이다.
      expect(kMapAttributionChanges, contains('단순화'));
      expect(kMapAttributionChanges, contains('통합'));
      expect(kMapAttributionChanges, contains('독도'));
    });

    test('링크 셋이 실제 URL 이다', () {
      for (final url in [kMapDistributionUrl, kMapLicenseUrl, kMapSourceUrl]) {
        expect(Uri.tryParse(url)?.hasScheme, isTrue, reason: url);
        expect(url, startsWith('https://'), reason: url);
      }
      expect(kMapLicenseUrl, contains('creativecommons.org/licenses/by/4.0'));
    });
  });

  group('Android 백업 규칙', () {
    // 설정은 기기 로컬 전용이지만, 규칙이 없으면 Android 자동 백업이
    // 다른 기기로 옮겨 준다 (Codex 22회차).
    test('settings.json 만 백업에서 뺀다', () {
      for (final path in [
        'android/app/src/main/res/xml/backup_rules.xml',
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ]) {
        final xml = File(path).readAsStringSync();
        // **주석이 아니라 실제 exclude 항목을 본다.** 주석에 파일명을 적어 두면
        // 문자열 포함 검사는 통과해 버린다.
        //
        // **domain 까지 함께 본다.** path 만 검사하면 `domain="file"` 처럼
        // 엉뚱한 곳을 가리켜 아무것도 막지 못하는 규칙이 통과한다 —
        // 처음 쓴 규칙이 실제로 그랬다 (Codex 22회차).
        final excluded = RegExp(r'<exclude\s+domain="([^"]+)"\s+path="([^"]+)"')
            .allMatches(xml)
            .map((m) => '${m.group(1)}:${m.group(2)}')
            .toSet();
        expect(excluded, contains('root:app_flutter/settings.json'),
            reason: '$path 가 실제 설정 파일 위치를 가리키지 않는다');
        expect(excluded, contains('root:app_flutter/settings.json.tmp'),
            reason: path);
        // **긁은 기록은 백업돼야 한다.** 브리프의 성공 기준이
        // "앱 삭제·기기 변경 후에도 보존" 이다.
        expect(excluded.any((e) => e.contains('collection.json')), isFalse,
            reason: '$path 가 수집 기록까지 백업에서 뺐다');
      }
    });

    test('매니페스트가 두 규칙을 모두 건다', () {
      final m = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(m, contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(m,
          contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      // allowBackup=false 로 전체를 막으면 수집 기록까지 빠진다.
      expect(m.contains('android:allowBackup="false"'), isFalse);
    });
  });
}
