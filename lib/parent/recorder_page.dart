import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_bus.dart';
import '../core/audio/audio_providers.dart';
import '../core/content/content_providers.dart';
import '../core/design/tokens.dart';
import 'parent_shell.dart';
import 'recordables.dart';
import 'voice_recorder.dart';

/// 逐条录音覆盖。
///
/// 见 parent-zone 规格「逐条录音覆盖」：录音写入 `voice_overrides/`，
/// **录完立即生效**，可试听、重录、删除；删除后回落打包的 TTS；
/// 没有麦克风权限时入口不可用但 App 其余部分照常。
///
/// 「立即生效」不需要这一页做任何事——[VoiceResolver] 每次播放都实时查文件，
/// 这一页只需要在写完之后让音频总线丢掉那条的缓存。**没有一张需要同步的表**，
/// 也就没有「录了但没生效」这种状态。
class ParentRecorderPage extends ConsumerStatefulWidget {
  const ParentRecorderPage({super.key, this.backend});

  /// 录音设备。为 null 时用真机实现。
  final VoiceRecorderBackend? backend;

  @override
  ConsumerState<ParentRecorderPage> createState() => _ParentRecorderPageState();
}

class _ParentRecorderPageState extends ConsumerState<ParentRecorderPage> {
  late final VoiceRecorderBackend _backend =
      widget.backend ?? RecordVoiceRecorder();

  late final VoiceOverrides _overrides = VoiceOverrides(
    ref.read(audioBusProvider).resolver,
  );

  /// null = 还没问过；true/false = 问过了。
  ///
  /// 三态是必要的：「还没问」和「被拒了」在界面上完全不同——前者不该显示
  /// 任何警告，后者必须说清楚。
  bool? _permitted;

  /// 正在录哪一条。
  String? _recordingKey;

  Set<String> _recorded = const {};

  AudioBus get _audio => ref.read(audioBusProvider);

  @override
  void initState() {
    super.initState();
    _recorded = _overrides.recordedKeys();
    unawaited(_checkPermission());
  }

  @override
  void dispose() {
    unawaited(_backend.dispose());
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final ok = await _backend.hasPermission();
    if (mounted) setState(() => _permitted = ok);
  }

  Future<void> _toggleRecording(Recordable item) async {
    if (_recordingKey == item.voiceKey) {
      await _stop();
      return;
    }
    if (_recordingKey != null) await _stop();

    final path = _overrides.pathFor(item.voiceKey);
    try {
      await _backend.start(path);
    } on Exception catch (e) {
      debugPrint('录音启动失败 -> $e');
      return;
    }
    if (mounted) setState(() => _recordingKey = item.voiceKey);
  }

  Future<void> _stop() async {
    final key = _recordingKey;
    if (key == null) return;
    await _backend.stop();
    // **写完就让总线忘掉旧的那条。** 少了这一步，孩子听到的仍是缓存里的
    // TTS——表现正是「录了没生效」，而家长会以为是自己录失败了。
    await _audio.invalidateVoice(key);
    if (!mounted) return;
    setState(() {
      _recordingKey = null;
      _recorded = _overrides.recordedKeys();
    });
  }

  Future<void> _preview(Recordable item) async {
    await _audio.speak(item.voiceKey, policy: VoicePolicy.interrupt);
  }

  Future<void> _delete(Recordable item) async {
    _overrides.delete(item.voiceKey);
    await _audio.invalidateVoice(item.voiceKey);
    if (mounted) setState(() => _recorded = _overrides.recordedKeys());
  }

  @override
  Widget build(BuildContext context) {
    final groups = recordableGroups(ref.watch(contentLibraryProvider));
    final permitted = _permitted;

    return ParentShell(
      title: '录我的声音',
      child: ListView(
        children: [
          const ParentNote(
            '每条内容都可以用你自己的声音替换。录完立刻生效，不用重启，'
            '也不用重新安装。删掉录音就回到打包的合成语音。\n\n'
            '先录哪些：他的名字、家人称谓、鼓励语。其余的慢慢来——'
            '没录的一直有合成语音顶着，功能不会缺。',
          ),
          if (permitted == false)
            Container(
              key: const ValueKey('no-permission'),
              margin: const EdgeInsets.symmetric(
                horizontal: BlockMetrics.gap,
                vertical: BlockMetrics.gap / 2,
              ),
              padding: const EdgeInsets.all(BlockMetrics.gap / 2),
              decoration: BoxDecoration(
                color: BlockColors.forIndex(1).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '没有麦克风权限，录音不可用。到系统设置里把麦克风打开就能录。\n'
                'App 的其余部分不受影响，孩子那边一切照常。',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
          for (final group in groups) ...[
            const Divider(height: 1),
            ParentNote('${group.title} · ${group.items.length} 条'),
            for (final item in group.items)
              _RecordableRow(
                key: ValueKey('recordable-${item.voiceKey}'),
                item: item,
                recorded: _recorded.contains(item.voiceKey),
                recording: _recordingKey == item.voiceKey,
                enabled: permitted ?? false,
                onToggleRecord: () => _toggleRecording(item),
                onPreview: () => _preview(item),
                onDelete: () => _delete(item),
              ),
          ],
        ],
      ),
    );
  }
}

class _RecordableRow extends StatelessWidget {
  const _RecordableRow({
    super.key,
    required this.item,
    required this.recorded,
    required this.recording,
    required this.enabled,
    required this.onToggleRecord,
    required this.onPreview,
    required this.onDelete,
  });

  final Recordable item;
  final bool recorded;
  final bool recording;
  final bool enabled;
  final VoidCallback onToggleRecord;
  final VoidCallback onPreview;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(item.label),
      subtitle: Text(
        item.hint,
        style: TextStyle(
          fontSize: 12,
          color: BlockColors.ink.withValues(alpha: 0.6),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('record-${item.voiceKey}'),
            tooltip: recording ? '停止' : (recorded ? '重录' : '录音'),
            icon: Icon(
              recording ? Icons.stop_circle_rounded : Icons.mic_rounded,
              color: recording ? BlockColors.forIndex(1) : null,
            ),
            onPressed: enabled ? onToggleRecord : null,
          ),
          IconButton(
            key: ValueKey('preview-${item.voiceKey}'),
            tooltip: '试听',
            icon: const Icon(Icons.play_arrow_rounded),
            onPressed: onPreview,
          ),
          IconButton(
            key: ValueKey('delete-${item.voiceKey}'),
            tooltip: '删除录音，回到合成语音',
            icon: const Icon(Icons.delete_outline_rounded),
            // 没录过就没什么可删的——**灰掉而不是藏起来**，
            // 位置固定家长才不用每行重新找按钮在哪。
            onPressed: recorded ? onDelete : null,
          ),
        ],
      ),
    );
  }
}
