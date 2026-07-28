allprojects {
    repositories {
        maven("https://maven.aliyun.com/repository/public")
        maven("https://maven.aliyun.com/repository/google")
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// ── 给插件子工程补上 kotlin-android（AGP 9 + builtInKotlin=false 的坑）──────
//
// package:jni 1.0.1 起，它的 android/build.gradle 会判断 AGP 主版本：AGP ≥ 9 时
// 不再 `apply plugin: 'kotlin-android'`，改为指望 AGP 自带的 built-in Kotlin 去
// 注册顶层 `kotlin {}` 扩展。而本项目的 android/gradle.properties 保留了 Flutter
// 模板写入的 `android.builtInKotlin=false`，于是两头落空——jni 脚本末尾那句
// `kotlin { compilerOptions { ... } }` 直接报
// `Could not find method kotlin() ... on project ':jni'`，构建在配置阶段就挂。
//
// settings.gradle.kts 里的 `id("org.jetbrains.kotlin.android") ... apply false`
// 只把 KGP 放上 classpath，不会作用到 flutter-plugin-loader 动态加进来的插件子
// 工程，所以要在这里手动 apply。
//
// 用 withPlugin 而非 afterEvaluate：回调在子工程执行 `apply plugin:
// 'com.android.library'` 的那一刻同步触发，早于同一脚本后面的 kotlin {} 块——
// afterEvaluate 太晚，脚本那时已经报错了。
//
// 跳过 :app：它的 Kotlin 由 Flutter Gradle Plugin 负责，重复 apply 徒增变数。
// 已有 kotlin 扩展的子工程也跳过，避免和自带 KGP 的插件打架。
// 注意 `target` 这个别名：withPlugin 的 lambda receiver 是 AppliedPlugin，它自己
// 就有 name/getName()，直接写 `name` 拿到的是插件名而非工程名。显式绑定免得踩坑。
subprojects {
    val target = this
    if (target.name != "app") {
        target.pluginManager.withPlugin("com.android.library") {
            if (target.extensions.findByName("kotlin") == null) {
                runCatching { target.pluginManager.apply("org.jetbrains.kotlin.android") }
                    .onFailure {
                        target.logger.warn(
                            "[baby_pal] ${target.name}: 补 kotlin-android 失败 -> ${it.message}",
                        )
                    }
            }
        }
    }
}

// ── 绕开 NDK 28 + CMake 3.22.1 在 macOS 上的工具链缺陷 ──────────────────
//
// AGP 默认使用 Android SDK 自带的 CMake 3.22.1。它与 NDK 28.2 搭配时不会把
// `--target=<triple>` 传给 clang，clang 于是退回选用宿主机的 Mach-O 链接器
// ld64.lld，报 `unknown argument '--build-id=sha1'`，flutter_soloud 的原生
// 编译直接失败。已实测 CMake 4.0.2 可正常完成配置。
//
// 只在 macOS 覆盖：ld64 是 Mach-O 链接器，Linux CI 走不到这条路径，保持默认
// 工具链以免 CI 还要额外下载 CMake。若日后 CI 的原生构建出问题，先看这里。
//
// 用反射而非 AGP 类型：本项目用 AGP 9，`BaseExtension` 等旧类型已不可靠。
// 注意：本块必须注册在下面的 `evaluationDependsOn(":app")` **之前**，否则部分
// 子项目已完成求值，再调 afterEvaluate 会抛 "project is already evaluated"。
// 即便如此仍用 state.executed 兜底——插件子项目由 flutter-plugin-loader 动态
// 加入，求值时机不完全可控。
val cmakeVersionOverride = "4.0.2"
if (System.getProperty("os.name").orEmpty().startsWith("Mac")) {
    subprojects {
        fun applyCmakeOverride() {
            val androidExt = extensions.findByName("android") ?: return
            runCatching {
                val nativeBuild = androidExt.javaClass
                    .getMethod("getExternalNativeBuild").invoke(androidExt)
                val cmake = nativeBuild.javaClass
                    .getMethod("getCmake").invoke(nativeBuild)
                cmake.javaClass
                    .getMethod("setVersion", String::class.java)
                    .invoke(cmake, cmakeVersionOverride)
                logger.lifecycle(
                    "[baby_pal] ${project.name}: CMake 固定为 $cmakeVersionOverride",
                )
            }.onFailure {
                logger.warn(
                    "[baby_pal] ${project.name}: CMake 版本覆盖失败 -> ${it.message}",
                )
            }
        }

        if (state.executed) applyCmakeOverride() else afterEvaluate { applyCmakeOverride() }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
