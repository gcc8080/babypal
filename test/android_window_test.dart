import 'dart:io';

import 'package:baby_pal/core/design/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

/// Android 窗口本身的配置。
///
/// 这些东西**在 Dart 里一行都看不到**，但它们决定了用户第一眼看见什么：
/// 窗口铺不铺满屏幕、Flutter 还没画到的地方是什么颜色。两条都在真机上
/// 咬过一次，所以钉在这里。
void main() {
  String read(String path) => File(path).readAsStringSync();

  const stylesFiles = [
    'android/app/src/main/res/values/styles.xml',
    'android/app/src/main/res/values-night/styles.xml',
    'android/app/src/main/res/values-v28/styles.xml',
    'android/app/src/main/res/values-night-v28/styles.xml',
  ];

  group('刘海屏', () {
    test('API 28 起两个主题都声明 shortEdges', () {
      // 横屏锁定 + 系统默认策略 = 刘海那侧永远留一条黑边（真机 MI 8 SE）。
      //
      // 两个主题都要设：只设 NormalTheme 的话，启动那一瞬间窗口还是让开的，
      // 第一帧画出来时画面会跳一下宽度。
      for (final path in stylesFiles.where((p) => p.contains('-v28'))) {
        final text = read(path);
        expect(
          RegExp(
            r'windowLayoutInDisplayCutoutMode">shortEdges<',
          ).allMatches(text).length,
          2,
          reason: '$path 里两个主题没有都声明 shortEdges',
        );
      }
    });

    test('深色模式那份单独存在——并列限定符拿不到 values-v28', () {
      // `values-night/` 与 `values-v28/` 是**并列**的限定符，深色模式下系统
      // 选中的是前者，拿不到后者里的刘海设置。少了这个文件，家长在夜里
      // 打开就又会看见那条边。
      expect(
        File('android/app/src/main/res/values-night-v28/styles.xml').existsSync(),
        isTrue,
      );
    });

    test('清单里有 MIUI 那条 notch.config', () {
      // 标准属性在原生 Android 上够用，小米额外要求这条，而交付机是 MI 8 SE。
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('notch.config'));
      // 只写 landscape 无效，必须两个都给。
      expect(manifest, contains('portrait|landscape'));
    });
  });

  group('窗口底色', () {
    /// `values/colors.xml` 里的 `sky_background`，转成 0xAARRGGBB。
    int androidSkyColor() {
      final match = RegExp(
        r'<color name="sky_background">#([0-9A-Fa-f]{8})</color>',
      ).firstMatch(read('android/app/src/main/res/values/colors.xml'));
      expect(match, isNotNull, reason: 'colors.xml 里找不到 sky_background');
      return int.parse(match!.group(1)!, radix: 16);
    }

    test('与 BlockColors.skyBackground 一模一样', () {
      // 窗口底色就是「Flutter 还没画到的地方」露出来的颜色：冷启动闪屏、
      // 窗口尺寸变化的那一两帧、以及刘海那一条。两边一旦对不上，那些地方
      // 就会露出一条和天空不同的颜色——真机上就是这么冒出一条白边的。
      expect(androidSkyColor(), BlockColors.skyBackground.toARGB32());
    });

    test('四份主题的 NormalTheme 都用天色，不用模板默认值', () {
      // 模板给的是 `?android:colorBackground`：`Theme.Light` 下是白，
      // `Theme.Black` 下是黑。这个 App 的界面没有深色版本，永远是那片米色
      // 的天，窗口底色就该跟着它——否则深色模式下露出来的是一条黑边。
      for (final path in stylesFiles) {
        final text = read(path);
        expect(
          text,
          contains('<item name="android:windowBackground">@color/sky_background</item>'),
          reason: '$path 的 NormalTheme 没用天色',
        );
        expect(
          text,
          isNot(contains('?android:colorBackground')),
          reason: '$path 还留着模板默认的窗口底色',
        );
      }
    });

    test('冷启动闪屏也是天色，不是白屏一闪', () {
      // 白屏闪一下再跳到米色的天，在一个给三岁孩子看的 App 上很刺眼。
      for (final path in const [
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      ]) {
        final text = read(path);
        expect(text, contains('@color/sky_background'), reason: path);
        expect(text, isNot(contains('@android:color/white')), reason: path);
        expect(text, isNot(contains('?android:colorBackground')), reason: path);
      }
    });
  });
}
