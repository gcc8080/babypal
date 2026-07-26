## ADDED Requirements

### Requirement: 内容包与代码分离

全部学习内容 SHALL 以 JSON 内容包形式存放于 `assets/packs/`，由加载器在启动时解析。新增学习内容 MUST 只需新增或修改内容包文件，MUST NOT 需要修改 Dart 代码。

#### Scenario: 新增内容包
- **WHEN** 向 `assets/packs/` 添加一个符合 schema 的新汉字内容包并在 `pubspec.yaml` 声明
- **THEN** 应用启动后该包内容可用，无需任何代码改动

### Requirement: schemaVersion 兼容策略

每个内容包 MUST 包含 `schemaVersion` 整数字段。加载器 SHALL 接受不高于当前支持版本的内容包；遇到高于当前支持版本的内容包时 MUST 跳过该包并继续加载其余内容包，MUST NOT 崩溃。

#### Scenario: 版本受支持
- **WHEN** 内容包 `schemaVersion` 为 1 且当前支持版本为 1
- **THEN** 内容包正常解析

#### Scenario: 版本过高
- **WHEN** 内容包 `schemaVersion` 为 99 且当前支持版本为 1
- **THEN** 该包被跳过并记录原因，其余内容包正常加载，应用可用

#### Scenario: 缺少 schemaVersion
- **WHEN** 内容包缺少 `schemaVersion` 字段
- **THEN** 该包被视为非法并跳过，其余内容包正常加载

### Requirement: 内容模型

加载器 SHALL 支持四类内容模型：`NumberItem`、`LetterItem`、`HanziItem`、`NounItem`。每类条目 MUST 携带其 `voiceKey`。汉字条目 MUST 区分 `pictograph`（象形）与 `compound`（合体），`compound` 类型 MUST 声明其组成部件 `parts`。

#### Scenario: 解析象形汉字
- **WHEN** 解析 `{"char":"木","pinyin":"mù","type":"pictograph","imageKey":"tree","voiceKey":"zh.hanzi.mu"}`
- **THEN** 得到一个 `HanziItem`，类型为象形，携带图片键与语音键

#### Scenario: 解析合体汉字
- **WHEN** 解析 `{"char":"林","pinyin":"lín","type":"compound","parts":["木","木"],"voiceKey":"zh.hanzi.lin"}`
- **THEN** 得到一个 `HanziItem`，类型为合体，部件为两个「木」

#### Scenario: 解析反义词对
- **WHEN** 汉字内容包中含 `"antonyms": [["大","小"],["多","少"]]`
- **THEN** 得到两组反义词配对数据

### Requirement: 非法条目的局部降级

加载器 SHALL 在遇到单个非法条目时跳过该条目并继续解析同一内容包中的其余条目，MUST NOT 因一条数据错误而丢弃整个内容包。

#### Scenario: 单条目字段缺失
- **WHEN** 某汉字条目缺少 `voiceKey`
- **THEN** 该条目被跳过并记录，同包内其余条目正常可用

#### Scenario: 合体字引用了不存在的部件
- **WHEN** 某 `compound` 条目的 `parts` 引用了内容包中不存在的字
- **THEN** 该条目被跳过并记录，MUST NOT 在运行时产生空引用
