## ADDED Requirements

### Requirement: 儿童端零文字

儿童端界面 SHALL NOT 依赖任何文字来传达指令。所有操作指引 MUST 由语音与动画演示承担。字母与汉字作为**学习内容**呈现不受此限，但 MUST NOT 被用作界面指令。

#### Scenario: 模块入口
- **WHEN** 孩子打开首页
- **THEN** 模块入口以图形呈现，无文字标签

#### Scenario: 新玩法首次进入
- **WHEN** 孩子首次进入某个玩法
- **THEN** 由语音加动画演示该做什么，MUST NOT 出现文字说明

### Requirement: 无挫败设计

儿童端 SHALL NOT 包含倒计时、分数、生命值、红叉或任何失败状态。操作结果不符合预期时，系统 MUST 演示正确结果是什么，然后允许继续尝试。

#### Scenario: 操作结果不符预期
- **WHEN** 孩子把积木放到不构成正确答案的位置
- **THEN** 系统用动画演示正确结果，无负面提示音、无错误标记

#### Scenario: 长时间无操作
- **WHEN** 孩子长时间未操作
- **THEN** 系统最多给出温和的动画提示，MUST NOT 催促或计时惩罚

### Requirement: 全局横屏锁定

应用 SHALL 在 Android 与 iOS 上全局锁定横屏。锁定 MUST 同时在 Flutter 侧、Android manifest 与 iOS Info.plist 三处声明。

#### Scenario: 竖持设备
- **WHEN** 用户把设备竖过来
- **THEN** 界面保持横屏不旋转

#### Scenario: 手机与平板
- **WHEN** 应用分别运行在手机与平板上
- **THEN** 两者均为横屏，布局按短边缩放因子自适应

### Requirement: 误退出防护

应用 SHALL NOT 包含任何跳出应用的链接、外部浏览器入口或分享入口。应用 MUST 在家长区提供 Android 屏幕固定与 iOS 引导式访问的使用引导。

#### Scenario: 儿童端外链
- **WHEN** 审查儿童端全部界面
- **THEN** 不存在任何可跳出应用的入口

#### Scenario: 防误退引导
- **WHEN** 家长打开防误退引导
- **THEN** 展示当前平台对应的屏幕固定或引导式访问设置步骤

### Requirement: 零数据收集

应用 SHALL NOT 申请网络权限、集成第三方 SDK、采集广告标识符或上报任何埋点。应用 MUST 提供一个声明「不收集、不上传任何数据」的隐私政策页。

#### Scenario: 权限清单审查
- **WHEN** 审查 AndroidManifest.xml 与 Info.plist
- **THEN** 不存在网络权限声明；麦克风是唯一的敏感权限，且附有用途说明

#### Scenario: 运行时网络行为
- **WHEN** 应用在无网络环境下完整运行全部功能
- **THEN** 所有功能正常，无任何降级

#### Scenario: 查看隐私政策
- **WHEN** 家长打开隐私政策页
- **THEN** 展示不收集任何数据的声明

### Requirement: 屏幕常亮

应用在前台时 SHALL 保持屏幕常亮，退出前台时 MUST 恢复系统默认息屏行为。

#### Scenario: 长时间观看动画
- **WHEN** 孩子长时间观看动画未触摸屏幕
- **THEN** 屏幕不自动熄灭

#### Scenario: 退出应用
- **WHEN** 应用进入后台
- **THEN** 屏幕常亮解除

### Requirement: 原创造型与配色

应用的角色造型与配色方案 MUST 为原创，MUST NOT 使用受保护作品的角色形象或配色方案，MUST NOT 使用「Numberblocks」或「数字积木」作为应用名称或任何角色名称。教学法本身（立方体表数量、位值、Base-10 blocks、Cuisenaire 数棒）属公共领域，可自由使用。

#### Scenario: 命名审查
- **WHEN** 审查应用名称、角色名称与全部面向用户的文案
- **THEN** 不出现受保护的作品名或角色名

#### Scenario: 配色审查
- **WHEN** 审查数字积木的配色方案
- **THEN** 配色为原创，未复制受保护作品的数字—颜色对应关系
