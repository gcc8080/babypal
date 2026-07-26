## ADDED Requirements

### Requirement: 家长门

所有家长功能入口 SHALL 由家长门保护：长按 3 秒进入，再答对一道两位数乘法题方可通过。儿童端 MUST NOT 存在绕过家长门访问设置的路径。

#### Scenario: 通过家长门
- **WHEN** 用户长按入口 3 秒并答对乘法题
- **THEN** 进入家长区

#### Scenario: 长按时间不足
- **WHEN** 用户长按入口不足 3 秒即松手
- **THEN** 不进入验证环节，停留在儿童端

#### Scenario: 答错乘法题
- **WHEN** 用户答错乘法题
- **THEN** 返回儿童端，并在重试时更换题目

### Requirement: 逐条录音覆盖

家长区 SHALL 提供按语音键逐条录音的能力，录音写入应用文档目录的 `voice_overrides/`，MUST 在录制完成后立即生效。家长 MUST 能试听、重录与删除某条覆盖；删除后 MUST 回落到打包的 TTS 资源。

#### Scenario: 录制并立即生效
- **WHEN** 家长录制「爸爸」的语音并保存，随后返回儿童端触发该词
- **THEN** 播放的是刚录制的真人语音，无需重启应用

#### Scenario: 删除覆盖
- **WHEN** 家长删除「爸爸」的录音覆盖
- **THEN** 该词回落为打包的 TTS 语音

#### Scenario: 无麦克风权限
- **WHEN** 麦克风权限被拒绝
- **THEN** 录音入口给出说明并保持不可用，应用其余功能 MUST 全部正常

### Requirement: 基于墙钟的每日时长上限

家长区 SHALL 提供每日游玩时长上限设置，默认 15 分钟。计时 MUST 基于墙钟时间戳并在应用生命周期切换点累加持久化，MUST NOT 依赖前台定时器。切后台再切回 MUST NOT 重置已用额度。

#### Scenario: 切后台不重置
- **WHEN** 孩子已玩 10 分钟后把应用切到后台，5 分钟后切回
- **THEN** 已用额度仍为 10 分钟（后台时间不计入），继续计时而非从零开始

#### Scenario: 杀进程重启不重置
- **WHEN** 孩子已玩 10 分钟后应用被杀死并重新启动
- **THEN** 当日已用额度仍为 10 分钟

#### Scenario: 达到上限
- **WHEN** 当日已用时长达到设定上限
- **THEN** 积木进入「困了」状态并播放温柔谢幕动画，MUST NOT 硬锁屏或弹出强制对话框

#### Scenario: 跨日重置
- **WHEN** 进入新的自然日
- **THEN** 已用额度归零

### Requirement: 学习看板

家长区 SHALL 展示今日游玩内容与掌握程度较弱的条目。看板 MUST 只使用本机存档数据，MUST NOT 产生任何网络请求。

#### Scenario: 查看今日记录
- **WHEN** 家长打开看板
- **THEN** 展示今日玩过的模块与时长，以及练习次数偏少或错误偏多的条目

### Requirement: 设置项

家长区 SHALL 提供中英模式开关与各内容模块的启用开关。设置 MUST 立即生效并持久化。

#### Scenario: 关闭模块
- **WHEN** 家长关闭汉字模块
- **THEN** 儿童端首页不再显示该模块入口

#### Scenario: 设置持久化
- **WHEN** 应用重启
- **THEN** 上次的设置保持不变

### Requirement: 素材署名

家长区 SHALL 提供素材署名页，列明 OpenMoji 图标的 CC BY-SA 4.0 署名信息与协议链接，仓库 MUST 在图标目录保留 LICENSE 文件。

#### Scenario: 查看署名
- **WHEN** 家长打开署名页
- **THEN** 展示 OpenMoji 的署名与 CC BY-SA 4.0 协议说明
