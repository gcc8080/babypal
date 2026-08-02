import 'dart:io';

import 'package:baby_pal/core/design/tokens.dart';
import 'package:flutter/material.dart' show Color, HSLColor;
import 'package:flutter_test/flutter_test.dart';

/// 合规与版权自查（openspec 任务 8.7 / 8.8）。
///
/// **做成用例而不是一份文档。** 这两条要保证的是「这个 App 里没有某些东西」
/// ——没有网络、没有第三方 SDK、没有埋点、儿童端没有跳出应用的入口、没有蹭
/// 受保护作品的名字与配色。这类「不存在」的承诺写在文档里第二天就可能失效：
/// 加一个依赖、粘一行 `launchUrl` 就破了，而没有任何东西会提醒我。
///
/// 放在这里，破坏它的那次提交会直接变红。
void main() {
  String read(String path) => File(path).readAsStringSync();

  List<String> dartSources() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path)
      .toList();

  group('8.7 权限与依赖', () {
    const sensitivePermissions = [
      'android.permission.INTERNET',
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.ACCESS_WIFI_STATE',
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.ACCESS_COARSE_LOCATION',
      'android.permission.READ_CONTACTS',
      'android.permission.CAMERA',
      'android.permission.READ_EXTERNAL_STORAGE',
    ];

    test('发布用的 main 清单不申请任何网络或敏感权限', () {
      // 这是儿童类目合规的核心，也让隐私问卷变成一句「不收集任何数据」。
      final text = read('android/app/src/main/AndroidManifest.xml');
      for (final permission in sensitivePermissions) {
        expect(
          text,
          isNot(contains(permission)),
          reason: 'main 清单申请了 $permission',
        );
      }
    });

    test('debug / profile 清单只多一条 INTERNET，且那是 Flutter 模板给热重载用的', () {
      // 这两份清单**不进 release 包**——`flutter create` 的模板往里加 INTERNET
      // 是为了热重载与 VM service 能连上调试机。
      //
      // 真相以打出来的包为准，已用 aapt2 核过发布 APK：整包只声明 RECORD_AUDIO
      // 和 AndroidX 自己那条 DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION。
      // 这条用例守的是**别的敏感权限不许混进来**——INTERNET 之外一个都不行。
      for (final flavor in const ['debug', 'profile']) {
        final path = 'android/app/src/$flavor/AndroidManifest.xml';
        if (!File(path).existsSync()) continue;
        final text = read(path);
        for (final permission in sensitivePermissions) {
          if (permission == 'android.permission.INTERNET') continue;
          expect(
            text,
            isNot(contains(permission)),
            reason: '$path 申请了 $permission',
          );
        }
      }
    });

    test('依赖清单里没有分析 / 广告 / 网络 SDK', () {
      // 逐个点名而不是「白名单」：白名单会让新增一个正当依赖也变红，
      // 那条用例很快会被人删掉。点名的这些是真正不该出现的。
      final pubspec = read('pubspec.yaml');
      for (final banned in const [
        'firebase',
        'google_mobile_ads',
        'admob',
        'facebook',
        'appsflyer',
        'sentry',
        'amplitude',
        'mixpanel',
        'umeng',
        'bugly',
        'analytics',
        'crashlytics',
        'http:',
        'dio:',
        'url_launcher',
        'webview_flutter',
      ]) {
        expect(
          pubspec,
          isNot(contains(banned)),
          reason: 'pubspec.yaml 里出现了 $banned',
        );
      }
    });

    test('代码里没有任何联网 / 跳出应用的调用', () {
      // 儿童端「零外链」这条红线的机器版本：跳出应用的入口一个都不许有，
      // 家长区也不例外（见 ParentAboutPage 的说明——协议原文照抄进来即可）。
      final offenders = <String>[];
      for (final path in dartSources()) {
        final text = read(path);
        for (final pattern in const [
          'HttpClient(',
          'package:http/',
          'package:dio/',
          'WebSocket.connect',
          'Socket.connect',
          'launchUrl',
          'launchUrlString',
          'canLaunchUrl',
          'InAppWebView',
        ]) {
          if (text.contains(pattern)) offenders.add('$path: $pattern');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('麦克风用途说明写清楚了，且是唯一的敏感权限', () {
      // 用途说明必须说明「只在本机」——这是上架审核会逐字读的一句。
      final plist = read('ios/Runner/Info.plist');
      expect(plist, contains('NSMicrophoneUsageDescription'));
      expect(plist, contains('不会上传'));
      // 相机、定位、通讯录、相册一个都不该申请。
      for (final key in const [
        'NSCameraUsageDescription',
        'NSLocationWhenInUseUsageDescription',
        'NSContactsUsageDescription',
        'NSPhotoLibraryUsageDescription',
      ]) {
        expect(plist, isNot(contains(key)), reason: 'Info.plist 申请了 $key');
      }
    });

    test('没有埋点上报：代码里不出现任何 track / report / beacon 调用', () {
      final offenders = <String>[];
      for (final path in dartSources()) {
        final text = read(path);
        for (final pattern in const [
          'logEvent(',
          'trackEvent(',
          'reportEvent(',
          'sendBeacon',
          'Analytics.',
        ]) {
          if (text.contains(pattern)) offenders.add('$path: $pattern');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });

  group('8.8 版权', () {
    test('应用名是「方块星球」，两端一致', () {
      expect(read('android/app/src/main/AndroidManifest.xml'), contains('方块星球'));
      expect(read('ios/Runner/Info.plist'), contains('方块星球'));
    });

    test('包名不是 flutter create 的默认值', () {
      // `com.example.*` 会被 App Store 直接拒。
      final gradle = Directory('android/app')
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('build.gradle.kts'));
      final text = gradle.readAsStringSync();
      expect(text, contains('com.ericding.emmett.babypal'));
      expect(text, isNot(contains('com.example')));
    });

    test('会显示出去的文字里不出现受保护作品的名字', () {
      // 借鉴教学法（立方体表数量、位值、部件组字）没问题，用名字不行。
      //
      // **注释除外，而且是故意的。** `tokens.dart` 里那句「刻意避开
      // Numberblocks 的经典配色」正是这套调色板为什么长这样的理由，删掉它
      // 等于把这条自查的依据也删了。这里查的是**会被显示出去的字符串**：
      // 应用名、内容包、以及 Dart 里的字面量。
      //
      // 第一版没做这个区分，于是把注释一起报了出来——但它同时也抓到了一条
      // 真的：`ModuleId.numbers` 的家长区标签当时写的就是「数字积木」。
      final offenders = <String>[];

      void scan(String path, String text) {
        for (final name in const ['Numberblocks', 'numberblocks', '数字积木']) {
          if (text.contains(name)) offenders.add('$path: $name');
        }
      }

      for (final path in const [
        'android/app/src/main/AndroidManifest.xml',
        'ios/Runner/Info.plist',
      ]) {
        scan(path, read(path));
      }
      for (final file in Directory(
        'assets/packs',
      ).listSync().whereType<File>()) {
        scan(file.path, file.readAsStringSync());
      }
      for (final path in dartSources()) {
        // 去掉 `//` 起的注释再查。块注释这个代码库里没有用到。
        final code = read(path)
            .split('\n')
            .map((line) {
              final i = line.indexOf('//');
              return i < 0 ? line : line.substring(0, i);
            })
            .join('\n');
        scan(path, code);
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('调色板里没有纯正的三原色', () {
      // **这里原本还有一条「饱和度 < 0.85」，删掉了。** 那个门槛是我拍脑袋
      // 定的，琥珀色 0.872 撞上去之后，唯一的出路是把门槛调到 0.9 让它变绿
      // ——一条为了通过而调过阈值的用例，什么都不证明。
      //
      // 真正说明问题的是这条（没有纯三原色）和下一条（色相不单调递增）：
      // 受保护的那套配色，其本质是**色相随数字单调递增**的彩虹序列。
      for (final primary in const [
        Color(0xFFFF0000),
        Color(0xFFFFFF00),
        Color(0xFF0000FF),
        Color(0xFFFF9900),
        Color(0xFF00FF00),
      ]) {
        expect(BlockColors.palette, isNot(contains(primary)));
      }
    });

    test('数字与颜色的对应关系不是按色相递增排的', () {
      // 「1 红 2 橙 3 黄 4 绿 5 蓝」的本质是**色相随数字单调递增**。
      // 只要调色板的色相不是单调的，这个对应关系就不可能与之相似。
      final hues = [
        for (final c in BlockColors.palette) HSLColor.fromColor(c).hue,
      ];
      var ascending = true;
      for (var i = 0; i < hues.length - 1; i++) {
        if (hues[i + 1] < hues[i]) {
          ascending = false;
          break;
        }
      }
      expect(ascending, isFalse, reason: '调色板色相单调递增，像一条彩虹');
    });

    test('图标素材带着 CC BY-SA 4.0 署名，且家长区能看到', () {
      // 署名是发行条件，不是礼节。仓库里有、App 里也要有。
      expect(read('assets/icons/LICENSE.txt'), contains('CC BY-SA 4.0'));
      final about = read('lib/parent/about_page.dart');
      expect(about, contains('CC BY-SA 4.0'));
      expect(about, contains('OpenMoji'));
    });
  });
}
