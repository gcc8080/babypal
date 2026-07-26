> 阶段依赖：P0 → P1 →（P2 → P3、P2 → P4、P5）→ P6。P1 是全项目地基，五个内容模块全部构建其上；P4 的部件加法直接复用 P2 的合体交互，不重复实现。第 3 组内容流水线与 P1 起并行，不占关键路径。
>
> 工期告急时的砍单顺序：家长看板 → 反义词跷跷板 → 大小写配对 → 百格板。绝不砍：积木引擎手感、生日彩蛋、家人相册。

## 1. P0 脚手架（约 3 天）

- [x] 1.1 把 `.fvmrc` 的 flutter 从 `3.27.4` 改为 `3.44.8`，本机执行 `fvm install` 并确认 `fvm flutter --version` 输出 Dart 3.12.2
- [x] 1.2 在仓库根执行 `flutter create --platforms=android,ios --org <reverse-domain> .`，保留既有 `openspec/`、`.github/`、`.fvmrc` 不被覆盖
- [x] 1.3 从 `.gitignore` 删除 `pubspec.lock` 一行（本项目是应用不是 library，锁文件须入库）
- [x] 1.4 在 `pubspec.yaml` 加入依赖：`flutter_riverpod ^3.3.2`、`flutter_soloud ^4.0.13`、`record ^7.1.1`、`shared_preferences ^2.5.5`、`path_provider ^2.1.6`、`wakelock_plus ^1.7.0`、`flutter_svg ^2.3.0`，执行 `fvm flutter pub get` 并提交 `pubspec.lock`
- [x] 1.5 确认平台最低版本无需显式配置：实测 Flutter 3.44.8 默认 minSdk **24** / iOS **13.0**，已高于全部依赖要求（`record_android` 23、`flutter_soloud` 21、`record_ios` 12.0、`flutter_soloud` iOS 13.0）。`build.gradle.kts` 保持 `minSdk = flutter.minSdkVersion` 不写死数字
- [x] 1.6 三处声明横屏锁定：`lib/main.dart` 的 `SystemChrome.setPreferredOrientations`、`AndroidManifest.xml` 的 `android:screenOrientation="sensorLandscape"`、iOS `Info.plist` 的 `UISupportedInterfaceOrientations` 只留横屏两项
- [x] 1.7 在 `Info.plist` 加 `NSMicrophoneUsageDescription`，文案说明仅用于家长录音与生日吹蜡烛；确认 `AndroidManifest.xml` 与 `Info.plist` 均**不含**任何网络权限声明
- [x] 1.8 建立 `lib/core/design/tokens.dart`：设计基准短边 360dp、缩放因子 `shortestSide / 360`、可拖拽积木与按钮下限 90dp、放置区下限 60dp、吸附半径系数 1.5、原创配色表
- [x] 1.9 在 `lib/main.dart` 接入 `wakelock_plus` 前台常亮并在退到后台时解除
- [x] 1.10 新建 `.github/workflows/ci.yml`（仓库当前无任何 workflow）：ubuntu job 固定 Flutter 3.44.8 跑 `flutter analyze`、`flutter test`、`flutter build apk --debug`；macos job 跑 `flutter build ios --no-codesign`
- [x] 1.11 选定生日交付用的 Android 真机（有多台时优先屏幕较大的一台），开启开发者选项与 USB 调试，跑通 `fvm flutter run -d <android>` 与 `fvm flutter install --release` 两条链路

> 实测设备：**MI 8 SE**（Android 9 / API 28 / arm64）。可用区域 2029×1080 物理像素，dpr 2.75 → 横屏逻辑尺寸约 **738 × 393 dp**，短边 393dp，`BlockScale = 1.09`。两条链路均已跑通，release APK 49.2 MB，启动无崩溃。
>
> **已确认以此机作为交付与调试设备。** 该机为 5.88 寸小屏，与 D12「有多台时优先屏幕较大的一台」的建议不符——这是**已知取舍**，非疏漏。相应地，后续设计与验收一律按 393dp 短边把关：积木必须在此尺寸下仍然好抓（抓取目标 ≥90dp、放置区 ≥60dp），一屏可容纳的积木数量按此估算。日后若换大屏平板只会更宽松，不会失效。
>
> 构建环境问题与修复：NDK 28.2 搭配 Android SDK 自带的 CMake 3.22.1 在 macOS 上不传 `--target=` 三元组给 clang，导致其误选 Mach-O 链接器 `ld64.lld`（报 `unknown argument '--build-id=sha1'`），`flutter_soloud` 原生编译失败。已在 `android/build.gradle.kts` 中仅对 macOS 覆盖 CMake 版本为 4.0.2。
- [ ] 1.12 确认 iOS 侧能力保留：本机 `fvm flutter run -d <ios-simulator>` 可跑，CI 的 `flutter build ios --no-codesign` 通过。iOS **不做真机验收**，回归职责全部由 CI 承担
- [x] 1.13 确认代码中不存在 Android 专有分支，保留日后取得开发者账号后直接上 iOS 真机的能力

## 2. P1 积木引擎与地基（约 1 周，本阶段做扎实，后面五个模块全靠它）

- [x] 2.1 `lib/core/block/block_model.dart`：`BlockBody` 数据模型（id、尺寸、颜色、表情、所属群组）
- [x] 2.2 `lib/core/block/snap_grid.dart`：网格吸附纯逻辑——最近合法格位判定、1.5 倍宽容半径、多候选取最近、已占用格位跳到最近空闲格位
- [x] 2.3 `test/core/block/snap_grid_test.dart`：覆盖半径内、半径外、多候选、已占用、边界共 5 类场景
- [x] 2.4 `lib/core/block/block_face.dart`：`CustomPainter` 程序化画脸——待机眨眼、开心、惊讶三种表情，零素材
- [x] 2.5 `lib/core/block/block_widget.dart`：单块渲染 + 手势 + 挤压回弹；保证每一次触摸都触发动画与音效（音效通过 `onSquash` 回调预留，待 2.9 音频总线接入）
- [x] 2.6 `lib/core/block/block_board.dart` 拖拽通道：拖拽、落位吸附、手指移出屏幕边缘按释放处理、多指同时拖拽互不干扰
- [x] 2.7 `lib/core/block/block_board.dart` **点选通道**：点积木进入选中态（含选中态视觉）→ 点目标位飞入落子；再点积木或点空白取消选中。此为全局不变量，五个模块不得只实现拖拽通道
- [x] 2.8 `lib/core/block/block_board.dart` 合体、分裂与群组整体拖动，三者均带过程动画

> 实现说明：状态与规则拆到 `lib/core/block/block_board_controller.dart`，`block_board.dart` 只负责渲染与指针事件。这样合体/分裂/群组/吸附落位可以用纯逻辑单测覆盖（`test/core/block/block_board_controller_test.dart`，15 个用例直接对应规格场景），不需要 pump 组件树。
- [x] 2.9 `lib/core/audio/audio_bus.dart`：`flutter_soloud` 封装——音效池（并发短音效）+ 语音队列（同一时刻一条，支持排队/打断两种策略）
- [x] 2.10 `lib/core/audio/voice_resolver.dart`：文档目录 `voice_overrides/<key>.wav` 优先，回落 `assets/audio/<key>.wav`；覆盖文件损坏时必须回落而非静默。扩展名抽为单一常量
- [x] 2.11 `test/core/audio/voice_resolver_test.dart`：有覆盖、无覆盖、覆盖文件损坏三种优先级场景
- [x] 2.12 `lib/core/content/models.dart` 与 `pack_loader.dart`：四类内容模型 + `schemaVersion` 校验（过高则跳过整包）+ 单条目非法时局部跳过而不丢弃整包
- [x] 2.13 `test/core/content/pack_loader_test.dart`：版本受支持、版本过高、缺 schemaVersion、单条目字段缺失、合体字引用不存在的部件
- [x] 2.14 `assets/packs/numbers.json` 首个内容包，跑通「内容包 → 加载器 → 积木」全链路

> 实现说明：
> - `parse()` 是**同步纯函数**（输入 JSON 字符串，不碰 IO 与 AssetBundle），因此两级降级路径全部可直接单测。
> - 汉字**分两趟解析**：先收集全部合法条目，再校验合体字的 `parts` 是否都在包内。一趟扫描会把「部件定义在合体字之后」误判为缺失（已有用例覆盖）。
> - `ContentPack.skipped` 保留被跳过条目及原因而非静默丢弃——否则一个拼错的字段会让某个字安静地从 App 里消失。
> - `numbers.json` 逐条列出 0–100 共 101 条而非在代码里生成：`allVoiceKeys` 必须能枚举出全部 202 个中英语音键，否则 `tool/gen_audio.dart` 无从得知要合成哪些音频。
> - 全链路验证 `test/core/content/numbers_pack_pipeline_test.dart` 直接读真实 asset 文件，验到「十条逐行落满 10×10 百格板」。
- [x] 2.15 `lib/core/progress/`：`shared_preferences` + JSON 存档读写
- [x] 2.16 `lib/modules/home/`：方块星球首页，纯图形入口、零文字

> 实现说明：
> - `ProgressStore` 的时长统计基于**墙钟差值**，在生命周期切换点累加落盘（D7）。另提供 `flush()` 供长时间连续游玩时定期落盘——**计时依据仍是墙钟，定时器只负责触发落盘，不参与计数**，这样进程被强杀最多只丢一个落盘间隔。已覆盖切后台、杀进程、跨日、系统时间回拨四类场景。
> - `weakestItems()` 只挑**练过的**条目：没练过属于「还没教」而非「没掌握」，混在一起会让家长看板变成一份无用的长名单。同理 `accuracy` 在没练过时返回 null 而非 0。
> - 首页入口改用原始 `Listener` 而非 `GestureDetector`：`onTapDown` 要等手势竞技场裁决，而外层横向滚动识别器会参与竞争，导致**按下要等一下才有形变**，违反「触摸必有回应」红线。测试专门锁住这条。
> - 触控下限用**绝对 90dp**，不乘缩放因子——dp 已是密度无关单位，90dp 对应手指物理尺寸；小屏上再乘 0.85 会变成 76dp，恰好击穿这条红线要守的东西。缩放只能放大入口。
>
> 顺带修复：`BlockFace` 的眨眼调度原用 `Future.delayed`，其 Timer 无法取消，组件销毁后仍会挂最多 6 秒。拼搭台上积木频繁增删会攒下一堆悬空定时器。已改为可取消的 `Timer` 并在 `dispose` 中取消。
- [ ] 2.17 真机手感验收：连续快速点击 10 个积木音效不丢不卡；手指移出边缘不崩；两指同时拖拽正常；手机与平板横屏与缩放均正确

## 3. 内容流水线（与 P1 起并行，不占关键路径）

- [ ] 3.1 `tool/gen_audio.dart`：读内容包枚举 `voiceKey` → 调本机 TTS → 输出 **WAV（22.05 kHz 单声道 16-bit）** + manifest。macOS 命令形如 `say -v Tingting --file-format=WAVE --data-format=LEI16@22050 -o out.wav`，英文用 `-v Samantha`
- [ ] 3.2 跑 `gen_audio.dart` 产出约 400 条 TTS 音频（约 26 MB），在 `pubspec.yaml` 声明资源目录
- [ ] 3.3 `tool/fetch_openmoji.dart`：按内容包里的 emoji 码点抽取 OpenMoji SVG 子集（约 150 个），输出到 `assets/icons/`
- [ ] 3.4 在 `assets/icons/` 放置 OpenMoji 的 LICENSE 文件（CC BY-SA 4.0），记录署名信息供家长区署名页使用
- [ ] 3.5 校验：内容包中每个 `voiceKey` 在音频 manifest 中都有对应文件，缺失项列出清单

## 4. P2 数字 + 加法（约 1.5 周）

- [ ] 4.1 `lib/modules/numbers/`：十条与单块积木，位值拆解玩法（23 = 2 十条 + 3 单块），支持 10 个单块合体为 1 个十条
- [ ] 4.2 `test/modules/numbers/place_value_test.dart`：位值拆解纯逻辑（23 → 2 tens + 3 ones，整十数，边界值）
- [ ] 4.3 百格板：10×10 网格作展示面与落点区域，孩子拖动的是 ≥90dp 的十条或单块，**不得要求点中单格**；每填满一行放烟花
- [ ] 4.4 `lib/modules/addition/`：合体求和，两组积木拼接合体并播报算式
- [ ] 4.5 反向分解：对总数积木执行分裂，生成两个加数并播报「五可以分成二和三」
- [ ] 4.6 `test/modules/addition/decompose_test.dart`：分解枚举（5 → `1+4,2+3,3+2,4+1`）与边界（1 → 空集）
- [ ] 4.7 等式槽 `[?][+][?][=][?]`，槽位同时支持拖拽与点选双通道
- [ ] 4.8 答案不符预期时用积木演示正确结果后允许重试，无红叉、无扣分、无倒计时
- [ ] 4.9 中英双声道播报：同一算式依次中英播报，共用同一套内容与关卡

## 5. P3 字母（约 1 周）

- [ ] 5.1 `assets/packs/letters.json` 与 `nouns.json`：26 字母的字母名、音素、对应名词与 emoji 码点
- [ ] 5.2 `lib/modules/letters/`：点击字母积木先播报字母名、再播报音素，两次可区分的播报
- [ ] 5.3 A is for Apple 交互版：选中字母后飞入多张名词图，**全部为正确答案**，点哪张都庆祝
- [ ] 5.4 字母轮廓填充：小方块填入字母模板，复用引擎吸附与双通道
- [ ] 5.5 大小写配对；配错时演示正确配对而非标记错误
- [ ] 5.6 拼自己的名字终关，目标名字来自可配置数据而非硬编码

## 6. P4 汉字（约 1 周）

- [ ] 6.1 `assets/packs/hanzi.json`：象形字（山田土木日月水火）、合体字（木+木=林、日+月=明、人+木=休）、`antonyms` 反义词对
- [ ] 6.2 `lib/modules/hanzi/`：象形动画——图片渐变为字形，可重播
- [ ] 6.3 部件加法：**直接复用 P2 的合体交互**，手势、吸附与反馈必须与加法模块完全一致；非法组合时部件返回原位，不标记错误
- [ ] 6.4 反义词跷跷板，配对数据取自内容包 `antonyms`
- [ ] 6.5 验证内容可扩展性：新增一个汉字内容包，确认新字在部件加法中直接可用且零代码改动
- [ ] 6.6 开始录制约 40 条真人语音（家人称谓、孩子名字、鼓励语、生日彩蛋台词），写入 `voice_overrides/` 验证即刻生效

## 7. P5 沙盒 + 家长端（约 1 周）

- [ ] 7.1 `lib/modules/sandbox/`：空白拼搭台，跨内容域混搭，无关卡、无对错、无计分
- [ ] 7.2 沙盒自发组合识别：自己摆出 `7+8=15` 或两个「木」时播报并庆祝；未构成组合时保持安静，不提示不催促
- [ ] 7.3 沙盒作品在离开与重进模块之间保留，并提供带动画的清空操作
- [ ] 7.4 30 层堆叠性能验证：拖拽与动画不掉帧
- [ ] 7.5 `lib/parent/gate.dart`：长按 3 秒 + 两位数乘法家长门，挡住全部设置入口；长按不足或答错则返回儿童端
- [ ] 7.6 `lib/parent/recorder.dart`：逐条录音覆盖，`AudioEncoder.wav` 写入 `voice_overrides/`，支持试听、重录、删除；删除后回落 TTS；无麦克风权限时入口禁用且不影响其余功能
- [ ] 7.7 时长上限：`WidgetsBindingObserver` + 墙钟时间戳持久化累加，**不用 `Timer`**；切后台、杀进程重启均不重置；跨自然日归零
- [ ] 7.8 达上限时积木「困了」+ 温柔谢幕动画，不硬锁屏、不弹强制对话框
- [ ] 7.9 `lib/parent/settings.dart`：中英模式开关、各模块启用开关，立即生效并持久化
- [ ] 7.10 `lib/parent/dashboard.dart`：今日玩了什么 / 哪些内容还生疏，仅用本机存档，零网络请求
- [ ] 7.11 家长区素材署名页（OpenMoji CC BY-SA 4.0）、隐私政策页（不收集不上传任何数据）、Android 屏幕固定与 iOS 引导式访问的使用引导

## 8. P6 生日彩蛋 + 打磨（约 3–5 天）

- [ ] 8.1 `lib/birthday/`：首启一次性播放 + 固定入口可重播；播放中触摸可跳过且不卡在中间状态
- [ ] 8.2 拼名字动画：姓名字母逐个飞入，姓名来自可配置数据
- [ ] 8.3 蜡烛环节：三块积木合体为 3 点燃三根蜡烛，复用引擎合体交互
- [ ] 8.4 吹气检测：`record.startStream(AudioEncoder.pcm16bits)` 在 Dart 侧算 RMS，**不写临时文件**；环境噪音不误触发
- [ ] 8.5 吹气降级路径：无麦克风权限或长时间无输入时改为点击熄灭，彩蛋必须完整可玩
- [ ] 8.6 家人相册：真实照片 + 家人真人语音走覆盖层，未录制时回落 TTS；照片未配置时优雅跳过该环节
- [ ] 8.7 全端合规自查：权限清单无网络声明、无第三方 SDK、无埋点；儿童端无任何跳出应用的入口
- [ ] 8.8 版权自查：应用名与角色名不含「Numberblocks / 数字积木」，角色造型与数字—颜色对应关系为原创
- [ ] 8.9 **Android 真机**手感终调：挤压回弹时长、音效延迟、吸附宽容度——这三项是 3 岁儿童唯一在意的东西。必须在 **release 构建**上调（debug 构建性能偏低，会误导判断）
- [ ] 8.10 交付前完整回归：`fvm flutter analyze` 无告警、`fvm flutter test` 全绿、CI 的 iOS 免签名构建通过、Android 真机装上 release APK 并跑完全部模块与彩蛋
- [ ] 8.11 生日前在 Android 设备上留存上一个可用的 release APK 作为回滚版本

## 9. 真实验收（让他玩，只看三个指标）

- [ ] 9.1 他**不需要你解释**就知道该干什么
- [ ] 9.2 他**主动重复**玩同一个模块
- [ ] 9.3 15 分钟结束时他**抗拒停止**，但谢幕动画能让他接受
- [ ] 9.4 任一指标不达标时：优先打磨手感而非增删功能
