import 'dart:convert';
import 'dart:io';

import 'package:baby_pal/modules/hanzi/hanzi_shapes.dart';
import 'package:flutter_test/flutter_test.dart';

/// 象形图形的数据校验。
///
/// 这些是**手写的坐标**，而手写坐标出错的表现是屏幕上一次莫名其妙的动画——
/// 某一笔突然抽一下、或者干脆看不出在变什么。那种错误在真机上很难指认，
/// 在这里却只是一个数字对不上。
void main() {
  group('每个字的两套笔画都能逐点插值', () {
    for (final entry in kPictographs.entries) {
      test('${entry.key}：笔数与每笔的点数都对得上', () {
        final shape = entry.value;
        expect(
          shape.isInterpolatable,
          isTrue,
          reason:
              '${entry.key} 的图与字对不上：'
              '图 ${shape.picture.map((s) => s.length).toList()}，'
              '字 ${shape.glyph.map((s) => s.length).toList()}',
        );
      });

      test('${entry.key}：坐标都在 0..1 之内', () {
        // 越界的点会被画到方框外面去，在别的元素上留下一道线。
        for (final strokes in [entry.value.picture, entry.value.glyph]) {
          for (final stroke in strokes) {
            for (final p in stroke) {
              expect(p.dx, inInclusiveRange(0.0, 1.0), reason: entry.key);
              expect(p.dy, inInclusiveRange(0.0, 1.0), reason: entry.key);
            }
          }
        }
      });

      test('${entry.key}：图与字确实不一样——否则这个字根本没在变', () {
        // 两套笔画完全相同意味着复制粘贴时忘了改，动画会是一动不动的两秒。
        expect(entry.value.picture, isNot(equals(entry.value.glyph)));
      });
    }
  });

  group('闭合外框（日 与 田）', () {
    /// 有向面积。符号即绕行方向：同号才是同一个方向。
    double signedArea(List<Offset> ring) {
      var sum = 0.0;
      for (var i = 0; i < ring.length - 1; i++) {
        sum += ring[i].dx * ring[i + 1].dy - ring[i + 1].dx * ring[i].dy;
      }
      return sum / 2;
    }

    test('图与字的外框绕行方向相同——反了会拧成一团', () {
      for (final key in ['sun', 'field']) {
        final shape = kPictographs[key]!;
        expect(
          signedArea(shape.picture[0]) * signedArea(shape.glyph[0]),
          greaterThan(0),
          reason: '$key 的两个外框绕行方向相反',
        );
      }
    });

    test('外框首尾闭合', () {
      for (final key in ['sun', 'field']) {
        final shape = kPictographs[key]!;
        for (final ring in [shape.picture[0], shape.glyph[0]]) {
          expect(ring.first, ring.last, reason: '$key 的外框没闭合');
        }
      }
    });

    test('四个角都真的落在采样点上——沿周长等距取点会削掉梯形的角', () {
      // 「田」的图是一块斜着看的地，四条边不一样长。按周长等距取点时采样点
      // 落不到拐角上，角就被切成斜面，看起来不像一块地。
      const corners = [
        Offset(0.30, 0.22),
        Offset(0.70, 0.22),
        Offset(0.92, 0.86),
        Offset(0.08, 0.86),
      ];
      final ring = kPictographs['field']!.picture[0];
      for (final corner in corners) {
        expect(
          ring.any((p) => (p - corner).distance < 1e-9),
          isTrue,
          reason: '拐角 $corner 不在采样点里',
        );
      }
    });
  });

  group('插值', () {
    test('t=0 是图，t=1 是字', () {
      final shape = kPictographs['tree']!;
      expect(shape.at(0), equals(shape.picture));
      expect(shape.at(1), equals(shape.glyph));
    });

    test('中间时刻落在两者之间', () {
      final shape = kPictographs['mountain']!;
      final mid = shape.at(0.5);
      final a = shape.picture[2][1]; // 中峰的顶点
      final b = shape.glyph[2][1]; // 中竖的顶端
      expect(mid[2][1].dx, closeTo((a.dx + b.dx) / 2, 1e-9));
      expect(mid[2][1].dy, closeTo((a.dy + b.dy) / 2, 1e-9));
    });

    test('超出 0..1 的 t 被夹住，不会画出画面外', () {
      final shape = kPictographs['sun']!;
      expect(shape.at(-3), equals(shape.picture));
      expect(shape.at(9), equals(shape.glyph));
    });
  });

  group('与内容包对得上', () {
    test('hanzi.json 里每个象形字的 imageKey 都有图形', () {
      final raw =
          jsonDecode(File('assets/packs/hanzi.json').readAsStringSync())
              as Map<String, dynamic>;
      final missing = <String>[];
      for (final item in raw['hanzi'] as List) {
        final map = item as Map<String, dynamic>;
        if (map['type'] != 'pictograph') continue;
        if (pictographOf(map['imageKey'] as String?) == null) {
          missing.add('${map['char']} → ${map['imageKey']}');
        }
      }
      expect(missing, isEmpty, reason: '这些象形字没有图形数据，玩法会退化成「直接显示字」：$missing');
    });

    test('查不到的 imageKey 返回 null 而不是抛异常', () {
      // 明年新增象形字时会走到这条路：没配图形只该少一段动画，不该崩。
      expect(pictographOf('no-such-shape'), isNull);
      expect(pictographOf(null), isNull);
    });
  });
}
