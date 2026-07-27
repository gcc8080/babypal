// OpenMoji 图标抽取工具。
//
// 读 assets/packs/*.json 里名词条目的 `iconKey`（Unicode 码点），从 OpenMoji
// 仓库逐个抓取彩色 SVG 到 assets/icons/，并写入署名与许可证文件。
//
// **只抓用得上的那几十个，不整包下载**：OpenMoji 完整彩色 SVG 集约 4000 个
// 文件、上百 MB，而这个 App 只用到内容包里点名的那些。子集随内容包增长而
// 增长——加一条名词、跑一次这个工具，就够了。
//
// 用法：
//   dart run tool/fetch_openmoji.dart            # 只抓缺失的
//   dart run tool/fetch_openmoji.dart --force    # 全部重抓
//   dart run tool/fetch_openmoji.dart --dry-run  # 只列出将要抓什么
//
// 与 gen_audio.dart 一样刻意不复用 pack_loader.dart：那个文件 import 了
// package:flutter/services.dart，纯 Dart VM 跑不起来。

import 'dart:convert';
import 'dart:io';

/// OpenMoji 彩色 SVG 的原始文件地址。
///
/// 固定在某个 tag 而不是 master：master 会随上游改动，某天重跑这个工具可能
/// 抓到换了画风的图，而孩子对「那只猫」的样子是有记忆的。
const String openMojiRef = '15.1.0';
const String svgBase =
    'https://raw.githubusercontent.com/hfg-gmuend/openmoji/$openMojiRef/color/svg';

const String packsDir = 'assets/packs';
const String iconsDir = 'assets/icons';

/// OpenMoji 的文件名**不含 FE0F 变体选择符**：`2708 FE0F`（✈️）在仓库里是
/// `2708.svg`。内容包按人手写的习惯可能带上，这里统一剥掉。
String normalizeCodepoint(String raw) {
  final parts = raw
      .toUpperCase()
      .split(RegExp(r'[-_\s]+'))
      .where((p) => p.isNotEmpty)
      .toList();

  // 键帽（0️⃣ 1️⃣ #️⃣ …）是唯一**必须留着 FE0F** 的一类：OpenMoji 那边的文件名
  // 就叫 `0030-FE0F-20E3.svg`，剥掉之后 `0030-20E3.svg` 是 404。
  //
  // 其余序列则相反，必须剥掉：✈️ 的码点是 `2708 FE0F`，文件却叫 `2708.svg`。
  //
  // 两条规则冲突，只能按是不是键帽分开处理。分辨方法是看结尾的 U+20E3
  // COMBINING ENCLOSING KEYCAP——有它就是键帽，没有就不是。
  final isKeycap = parts.isNotEmpty && parts.last == '20E3';
  if (isKeycap) return parts.join('-');

  return parts.where((p) => p != 'FE0F').join('-');
}

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final dryRun = args.contains('--dry-run');

  final packs =
      Directory(packsDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  // 码点 → 引用它的名词 id，抓失败时能直接说出是哪条内容出的问题。
  final wanted = <String, List<String>>{};
  for (final pack in packs) {
    final Object? decoded;
    try {
      decoded = jsonDecode(pack.readAsStringSync());
    } on FormatException catch (e) {
      stderr.writeln('${pack.path}: JSON 解析失败，已跳过 ($e)');
      continue;
    }
    if (decoded is! Map<String, dynamic>) continue;
    final nouns = decoded['nouns'];
    if (nouns is! List) continue;
    for (final item in nouns.whereType<Map<String, dynamic>>()) {
      final icon = item['iconKey'];
      final id = item['id'];
      if (icon is! String || icon.isEmpty) continue;
      wanted
          .putIfAbsent(normalizeCodepoint(icon), () => [])
          .add(id is String ? id : '?');
    }
  }

  if (wanted.isEmpty) {
    stderr.writeln('$packsDir 下没有任何名词条目，无事可做。');
    exit(1);
  }

  final codes = wanted.keys.toList()..sort();
  stdout.writeln('内容包引用图标 ${codes.length} 个（OpenMoji $openMojiRef）。');

  if (dryRun) {
    for (final code in codes) {
      stdout.writeln('  $code  ← ${wanted[code]!.join(", ")}');
    }
    stdout.writeln('\n--dry-run，未下载任何文件。');
    return;
  }

  await Directory(iconsDir).create(recursive: true);

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  var fetched = 0;
  var skipped = 0;
  final missing = <String>[];

  for (final code in codes) {
    final out = File('$iconsDir/$code.svg');
    if (!force && out.existsSync() && out.lengthSync() > 0) {
      skipped++;
      continue;
    }
    final body = await _get(client, '$svgBase/$code.svg');
    if (body == null) {
      missing.add('$code  ← ${wanted[code]!.join(", ")}');
      continue;
    }
    out.writeAsBytesSync(body);
    fetched++;
    if (fetched % 20 == 0) stdout.writeln('  已抓取 $fetched 个…');
  }
  client.close();

  _writeLicense(codes);

  final totalBytes = Directory(iconsDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.svg'))
      .fold<int>(0, (sum, f) => sum + f.lengthSync());

  stdout.writeln('');
  stdout.writeln('新抓取 $fetched 个，已存在跳过 $skipped 个。');
  stdout.writeln('图标总体积 ${(totalBytes / 1024).toStringAsFixed(0)} KB');

  if (missing.isNotEmpty) {
    // 缺图不是「图标少一个」这么轻——名词是「A is for Apple」里飞进来的那张
    // 图，缺了就是那个字母少一张卡片。必须让它在构建期就吵起来。
    stderr.writeln('');
    stderr.writeln('❌ ${missing.length} 个码点在 OpenMoji $openMojiRef 里不存在：');
    for (final m in missing) {
      stderr.writeln('    $m');
    }
    stderr.writeln('改内容包里的 iconKey，或换一个名词。');
    exit(1);
  }
}

Future<List<int>?> _get(HttpClient client, String url) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode == 404) {
        await res.drain<void>();
        return null; // 真的没有，重试没意义。
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        continue;
      }
      final chunks = <int>[];
      await for (final chunk in res) {
        chunks.addAll(chunk);
      }
      return chunks;
    } on Exception {
      // 网络抖动，退避后重试。
      await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
  }
  return null;
}

/// 写许可证与署名文件。
///
/// CC BY-SA 4.0 要求署名，且这是**发行条件而不是礼节**——家长区的素材署名页
/// （任务 7.11）直接读这里的信息。清单里列出实际用到的码点，是为了让「我们
/// 到底用了人家哪些东西」这件事在仓库里是可查的。
void _writeLicense(List<String> codes) {
  File('$iconsDir/LICENSE.txt').writeAsStringSync('''
OpenMoji — the open-source emoji and icon project
https://openmoji.org/

版本 / Version: $openMojiRef
许可 / License: Creative Commons Attribution-ShareAlike 4.0 International
                (CC BY-SA 4.0)
https://creativecommons.org/licenses/by-sa/4.0/

本目录下的 ${codes.length} 个 SVG 文件由 OpenMoji 项目设计，按 CC BY-SA 4.0
使用。未作修改。

All emojis in this directory are designed by OpenMoji – the open-source emoji
and icon project. License: CC BY-SA 4.0. No modifications were made.

本目录由 tool/fetch_openmoji.dart 生成，请勿手工编辑。
''');

  File('$iconsDir/MANIFEST.txt').writeAsStringSync(
    '# tool/fetch_openmoji.dart 生成，OpenMoji $openMojiRef\n'
    '${codes.join('\n')}\n',
  );
}
