## ADDED Requirements

### Requirement: 音频格式统一为 WAV

系统中所有音频资源与运行时录音 MUST 为 WAV 格式（22.05 kHz、单声道、16-bit）。系统 MUST NOT 使用 AAC/M4A（播放引擎不支持）或 opus（在 iOS 上为 CAF 容器，跨平台不可读）。音频文件扩展名 MUST 定义为单一常量，以便日后整体切换格式。

#### Scenario: 家长录音编码
- **WHEN** 家长录制一条语音覆盖
- **THEN** 录音以 `AudioEncoder.wav` 写入，且可被播放引擎直接加载

#### Scenario: TTS 资源加载
- **WHEN** 应用加载打包的 TTS 语音资源
- **THEN** 资源为 WAV 格式并能被播放引擎解码播放

### Requirement: 音效池支持并发短音效

音频总线 SHALL 维护音效池，支持多个短音效同时播放而不互相打断、不产生可感知延迟。

#### Scenario: 并发音效
- **WHEN** 1 秒内触发 10 次积木点击音效
- **THEN** 10 次音效全部播放，无丢失、无截断、无排队延迟

#### Scenario: 音效与语音同时发生
- **WHEN** 一次操作同时触发音效和语音播报
- **THEN** 两者同时播放，音效不被语音打断

### Requirement: 语音队列

音频总线 SHALL 以队列方式播放语音，同一时刻 MUST 只有一条语音在播。新语音入队时，系统 MUST 能按调用方指定的策略选择「排队」或「打断当前并清空队列」。

#### Scenario: 语音顺序播放
- **WHEN** 连续请求播报「三」「加」「二」
- **THEN** 三条语音依次播放，不重叠

#### Scenario: 切换模块打断语音
- **WHEN** 语音播放过程中用户离开当前模块
- **THEN** 当前语音停止，队列清空

### Requirement: 语音覆盖层解析

语音解析器 SHALL 按固定优先级解析语音键：先检查应用文档目录下的 `voice_overrides/<key>.wav`，存在则使用；否则回落到打包资源 `assets/audio/<key>.wav`。家长录制的覆盖 MUST 在录制完成后立即生效，MUST NOT 要求重新打包或重启应用。

#### Scenario: 存在家长录音覆盖
- **WHEN** `voice_overrides/zh.hanzi.mu.wav` 存在
- **THEN** 播报「木」时使用该文件

#### Scenario: 不存在覆盖
- **WHEN** `voice_overrides/zh.hanzi.mu.wav` 不存在
- **THEN** 播报「木」时使用 `assets/audio/zh.hanzi.mu.wav`

#### Scenario: 录完立即生效
- **WHEN** 家长刚录制完某条语音并返回儿童端
- **THEN** 下一次播报该键时即为新录制的声音，无需重启应用

#### Scenario: 覆盖文件损坏
- **WHEN** 覆盖文件存在但无法解码或读取失败
- **THEN** 系统回落播放打包资源，MUST NOT 表现为静默无声

### Requirement: 语音键命名与内容包一致

每条语音 SHALL 由内容包中的 `voiceKey` 唯一标识。构建工具 MUST 能从内容包枚举出全部语音键并据此生成音频清单，使资源缺失可被离线检出。

#### Scenario: 检出缺失语音
- **WHEN** 内容包中某条目的 `voiceKey` 在音频清单中无对应文件
- **THEN** 构建工具报告该缺失键，且应用运行时对该键回落为静默并记录，MUST NOT 崩溃
