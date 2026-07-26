import 'package:baby_pal/core/progress/progress_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可控的假墙钟，用来精确构造「切后台 / 跨日 / 系统时间回拨」等场景。
class FakeClock {
  FakeClock(this._now);
  DateTime _now;

  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
  void set(DateTime t) => _now = t;
}

void main() {
  late FakeClock clock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = FakeClock(DateTime(2026, 7, 26, 9, 0));
  });

  Future<ProgressStore> newStore() async {
    final prefs = await SharedPreferences.getInstance();
    final store = ProgressStore(prefs, clock: clock.call);
    store.load();
    return store;
  }

  group('墙钟计时', () {
    test('会话结束时按墙钟差值累加', () async {
      final store = await newStore();
      store.beginSession();
      clock.advance(const Duration(minutes: 10));
      await store.endSession();

      expect(store.todayPlayed, const Duration(minutes: 10));
    });

    test('会话进行中 todayPlayed 实时反映已过时间', () async {
      final store = await newStore();
      store.beginSession();
      clock.advance(const Duration(minutes: 3));

      expect(store.todayPlayed, const Duration(minutes: 3));
      // 尚未落盘，但 UI 能看到。
      expect(store.snapshot.playedSeconds, 0);
    });

    test('切后台再切回不重置额度，后台时间不计入', () async {
      final store = await newStore();
      store.beginSession();
      clock.advance(const Duration(minutes: 10));
      await store.endSession(); // 切后台

      clock.advance(const Duration(minutes: 5)); // 后台待了 5 分钟

      store.beginSession(); // 切回前台
      expect(
        store.todayPlayed,
        const Duration(minutes: 10),
        reason: '后台的 5 分钟不计入',
      );

      clock.advance(const Duration(minutes: 2));
      await store.endSession();
      expect(store.todayPlayed, const Duration(minutes: 12));
    });

    test('杀进程重启不重置——已落盘额度可从存档恢复', () async {
      final store = await newStore();
      store.beginSession();
      clock.advance(const Duration(minutes: 10));
      await store.endSession();

      // 模拟进程被杀后重新打开：新建 store 从 prefs 读取。
      final revived = await newStore();
      expect(revived.todayPlayed, const Duration(minutes: 10));
    });

    test('flush 在不结束会话的前提下落盘，并重开计时窗口', () async {
      final store = await newStore();
      store.beginSession();
      clock.advance(const Duration(minutes: 4));
      await store.flush();

      expect(store.snapshot.playedSeconds, 240, reason: '已落盘');
      expect(store.todayPlayed, const Duration(minutes: 4), reason: '不重复计算');

      clock.advance(const Duration(minutes: 3));
      expect(store.todayPlayed, const Duration(minutes: 7));
    });

    test('系统时间被回拨时忽略该段，不产生负数时长', () async {
      final store = await newStore();
      store.beginSession();
      clock.advance(const Duration(minutes: -5));
      await store.endSession();

      expect(store.todayPlayed, Duration.zero);
    });

    test('未开始会话时结束是安全的空操作', () async {
      final store = await newStore();
      await store.endSession();
      expect(store.todayPlayed, Duration.zero);
    });
  });

  group('跨日重置', () {
    test('进入新的自然日 → 当日额度归零', () async {
      final store = await newStore();
      store.beginSession();
      clock.advance(const Duration(minutes: 10));
      await store.endSession();
      expect(store.todayPlayed, const Duration(minutes: 10));

      // 第二天重新打开。
      clock.set(DateTime(2026, 7, 27, 8, 0));
      final nextDay = await newStore();
      expect(nextDay.todayPlayed, Duration.zero);
    });

    test('跨日不清除条目统计——那是长期数据', () async {
      final store = await newStore();
      await store.recordAttempt('zh.hanzi.mu', success: true);

      clock.set(DateTime(2026, 7, 27, 8, 0));
      final nextDay = await newStore();
      expect(nextDay.statFor('zh.hanzi.mu').attempts, 1);
      expect(nextDay.todayPlayed, Duration.zero);
    });

    test('跨日清除模块时长', () async {
      final store = await newStore();
      store.beginSession();
      clock.advance(const Duration(minutes: 6));
      await store.endSession(module: 'numbers');
      expect(store.snapshot.moduleSeconds['numbers'], 360);

      clock.set(DateTime(2026, 7, 27, 8, 0));
      final nextDay = await newStore();
      expect(nextDay.snapshot.moduleSeconds, isEmpty);
    });
  });

  group('每日上限', () {
    test('默认 15 分钟', () async {
      final store = await newStore();
      expect(store.dailyLimit, const Duration(minutes: 15));
    });

    test('达到上限时 isLimitReached 为真', () async {
      final store = await newStore();
      store.beginSession();
      clock.advance(const Duration(minutes: 14));
      expect(store.isLimitReached, isFalse);
      expect(store.remaining, const Duration(minutes: 1));

      clock.advance(const Duration(minutes: 1));
      expect(store.isLimitReached, isTrue);
      expect(store.remaining, Duration.zero);
    });

    test('上限可修改并持久化', () async {
      final store = await newStore();
      await store.setDailyLimit(const Duration(minutes: 25));

      final revived = await newStore();
      expect(revived.dailyLimit, const Duration(minutes: 25));
    });

    test('超出上限后 remaining 不为负', () async {
      final store = await newStore();
      store.beginSession();
      clock.advance(const Duration(minutes: 30));
      expect(store.remaining, Duration.zero);
    });
  });

  group('条目统计', () {
    test('累加次数与正确数', () async {
      final store = await newStore();
      await store.recordAttempt('a', success: true);
      await store.recordAttempt('a', success: false);
      await store.recordAttempt('a', success: true);

      final stat = store.statFor('a');
      expect(stat.attempts, 3);
      expect(stat.successes, 2);
      expect(stat.accuracy, closeTo(2 / 3, 1e-9));
    });

    test('没练过的条目 accuracy 为 null 而非 0', () async {
      final store = await newStore();
      expect(store.statFor('never').accuracy, isNull);
      expect(store.statFor('never').attempts, 0);
    });

    test('weakestItems 只挑练过的，按正确率升序', () async {
      final store = await newStore();
      // a: 1/2 = 0.5
      await store.recordAttempt('a', success: true);
      await store.recordAttempt('a', success: false);
      // b: 2/2 = 1.0
      await store.recordAttempt('b', success: true);
      await store.recordAttempt('b', success: true);
      // c: 0/2 = 0.0
      await store.recordAttempt('c', success: false);
      await store.recordAttempt('c', success: false);
      // d 从未练过，不应出现

      expect(store.weakestItems(), ['c', 'a', 'b']);
      expect(store.weakestItems(limit: 2), ['c', 'a']);
      expect(store.weakestItems(), isNot(contains('d')));
    });

    test('正确率相同时练得少的排前面', () async {
      final store = await newStore();
      await store.recordAttempt('few', success: true);
      for (var i = 0; i < 5; i++) {
        await store.recordAttempt('many', success: true);
      }
      expect(store.weakestItems(), ['few', 'many']);
    });

    test('统计可持久化', () async {
      final store = await newStore();
      await store.recordAttempt('zh.hanzi.mu', success: true);

      final revived = await newStore();
      expect(revived.statFor('zh.hanzi.mu').attempts, 1);
      expect(revived.statFor('zh.hanzi.mu').successes, 1);
    });
  });

  group('存档健壮性', () {
    test('存档损坏时重置而不是崩溃', () async {
      SharedPreferences.setMockInitialValues({
        ProgressStore.storageKey: '{ 这不是 json',
      });
      final store = await newStore();
      expect(store.todayPlayed, Duration.zero);
      expect(store.dailyLimit, const Duration(minutes: 15));
    });

    test('存档字段类型错误时按缺省值降级', () async {
      SharedPreferences.setMockInitialValues({
        ProgressStore.storageKey: '{"day":123,"played":"abc","items":"nope"}',
      });
      final store = await newStore();
      expect(store.todayPlayed, Duration.zero);
      expect(store.snapshot.items, isEmpty);
    });

    test('reset 清空全部数据', () async {
      final store = await newStore();
      await store.recordAttempt('a', success: true);
      store.beginSession();
      clock.advance(const Duration(minutes: 5));
      await store.endSession();

      await store.reset();
      expect(store.todayPlayed, Duration.zero);
      expect(store.snapshot.items, isEmpty);
    });
  });
}
