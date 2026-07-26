## ADDED Requirements

### Requirement: 字母名与音素分别播报

字母模块 SHALL 对每个字母分别播报字母名与音素，两者 MUST 是可区分的两次播报，MUST NOT 合并为一次。

#### Scenario: 点击字母积木
- **WHEN** 用户点击字母 A 的积木
- **THEN** 先播报字母名「ay」，再播报音素「/æ/」

### Requirement: A is for Apple 交互版

模块 SHALL 保留 `A is for Apple` 的格式但使其可交互：选中字母后飞入多张以该字母开头的名词图片。这些图片 MUST 全部为正确答案，点击任意一张 MUST 触发庆祝，MUST NOT 存在错误选项。

#### Scenario: 图片飞入
- **WHEN** 用户选中字母 A
- **THEN** Apple、Ant、Alligator 三张图飞入并各自播报名称

#### Scenario: 点击任意图片
- **WHEN** 用户点击其中任意一张图
- **THEN** 播报该词并庆祝，三张图行为一致

### Requirement: 字母轮廓填充

模块 SHALL 提供用小方块填入字母轮廓模板的玩法。填充 MUST 使用引擎的吸附能力，且 MUST 支持拖拽与点选双通道。

#### Scenario: 填入轮廓
- **WHEN** 用户把小方块拖到字母 L 轮廓内的空位附近
- **THEN** 方块吸附到该位置

#### Scenario: 轮廓填满
- **WHEN** 字母轮廓的全部空位被填满
- **THEN** 字母整体点亮，播报字母名并庆祝

### Requirement: 大小写配对

模块 SHALL 提供大小写字母配对玩法。配错时 MUST NOT 出现错误标记，而是演示正确配对。

#### Scenario: 正确配对
- **WHEN** 用户把小写 a 拖到大写 A 上
- **THEN** 两者合并并庆祝

#### Scenario: 错误配对
- **WHEN** 用户把小写 b 拖到大写 A 上
- **THEN** 系统演示 A 与 a 的正确配对，然后允许重试，无红叉、无扣分

### Requirement: 拼自己的名字

模块 SHALL 提供以孩子姓名字母为目标的拼字关卡，作为字母模块的终关。目标名字 MUST 来自可配置数据，MUST NOT 硬编码在代码中。

#### Scenario: 拼出名字
- **WHEN** 用户按顺序拼出配置的名字字母
- **THEN** 名字整体点亮，播报名字并播放特别庆祝

#### Scenario: 字母顺序错误
- **WHEN** 用户放置的字母不符合目标顺序
- **THEN** 该字母吸附到其正确位置或返回起点，并演示正确顺序，MUST NOT 呈现失败状态
