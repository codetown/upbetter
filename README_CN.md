# Upbetter

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D4.svg)](#环境要求)
[![Flutter 3.47](https://img.shields.io/badge/Flutter-3.47-02569B.svg)](https://flutter.dev)
[![Engine: Real-ESRGAN](https://img.shields.io/badge/engine-Real--ESRGAN%20ncnn%20Vulkan-7C6BFF.svg)](https://github.com/xinntao/Real-ESRGAN)

**简体中文** · [English](README.md)

> 极致高性能的 AI 图像超分辨率桌面工具 —— [Upscayl](https://github.com/upscayl/upscayl) 的平替实现

基于 Flutter 3.47 构建，使用 Real-ESRGAN ncnn Vulkan 作为推理后端，
在本地显卡上完成 2×/3×/4× 放大。**图片不离开你的电脑**，首次安装引擎后即可完全离线运行。

---

## 目录

- [核心特性](#核心特性)
- [性能设计](#性能设计)
- [环境要求](#环境要求)
- [构建与运行](#构建与运行)
- [操作步骤](#操作步骤)
- [键盘快捷键](#键盘快捷键)
- [命令行用法](#命令行用法)
- [目录结构](#目录结构)
- [测试](#测试)
- [常见问题](#常见问题)
- [已知限制](#已知限制)
- [参与贡献](#参与贡献)
- [许可证](#许可证)

---

## 核心特性

| 能力 | 说明 |
| --- | --- |
| GPU 加速推理 | Real-ESRGAN ncnn Vulkan，走显卡计算，比 CPU 快数十倍 |
| 批量队列 | 拖入整个文件夹自动排队，支持拖拽调整处理顺序 |
| 前后对比 | 分割线滑块对比「AI 放大」与「直接插值」，差异一目了然 |
| 三个内置模型 | 照片写实 / 动漫插画 / 极速通用 |
| 自定义模型 | 把社区模型（`.param` + `.bin`）丢进模型目录即可被自动识别 |
| 命名模板 | `{name}_{scale}` 这类模板驱动输出文件名，带实时预览 |
| 完全离线 | 推理过程零网络请求，图片不上传 |
| 绿色便携 | 把 `runtime/` 放在 exe 旁边即可整个应用打包分发 |

## 性能设计

这一节说明为什么它比「一张图一次命令」的朴素做法更快。

### 1. 批次合并：模型只加载一次

推理引擎每次冷启动都要重新读取权重并上传显存。实测（Intel UHD 核显，x4plus 模型）：

| 场景 | 耗时 |
| --- | --- |
| 单张图（含冷启动） | 9.9 s |
| 4 张图一次批量 | 33.6 s |
| → 推算的固定开销 | **约 2 s / 次进程** |
| → 推算的单张边际耗时 | 约 7.9 s |

因此引擎会把**执行参数相同**的任务合并成一次进程调用，用目录模式一次跑完。
处理 N 张图时，模型加载从 N 次降到「批次数」次。

暂存输入时优先使用 **NTFS 硬链接**（通过 FFI 调用 `CreateHardLinkW`）：
对上百 MB 的原图是零拷贝、零额外磁盘占用；跨卷等失败场景自动退化为复制。

> 真实运行日志：
>
> ```bash
> 批次 batch_1789679122175673：2 个文件（硬链接 2 个）
> 启动推理：realesrgan-ncnn-vulkan.exe -i .../in -o .../out -n realesrgan-x4plus -s 4 -f jpg -v
> 批次 batch_1789679122175673 完成，已写出 2 个文件
> ```
>
> 两个文件 → 一次进程调用。

### 2. 进度不依赖推理进程

实测发现：引擎在 `-t 0`（自动分块）模式下**几乎不输出进度行**——
它只在分块边界打印百分比，而自动分块往往一次覆盖整张图。

```bash
-t 64（显式分块）：196 个进度步进
-t 0 （自动）    ：0 个
```

自动分块能让引擎选择装得进显存的最大分块，速度最快。所以我们**保留自动分块**，
改为在客户端按实测吞吐量做时间插值，并用真实回报值作为下限钳制——
进度条始终平滑推进，又不会出现「先冲到 90% 再卡住」的假象。

吞吐量按「模型 + 倍率 + GPU」记录并跨会话保存，
因此第二次启动的最初几秒就能给出准确的剩余时间。

### 3. 分级解码预览

打开一张 8000×6000 的照片时，全尺寸解码要分配近 200 MB 内存；
4× 放大后更是 32000×24000，远超 GPU 纹理上限。

预览采用两级策略：

1. 先用 `ImmutableBuffer.fromFilePath` 按目标尺寸解码一张长边 2048 的预览图 —— 秒开；
2. 当用户放大到接近 1:1、能看出画质差异时，才在后台解码高分辨率版本并平滑替换。

队列缩略图同理，通过 `cacheWidth` 让**解码器在解码阶段**就缩到 92 px，
而不是先解全尺寸位图再缩放。

### 4. 精确到行的界面重建

不引入状态管理框架，而是用 `ValueNotifier` / `ListenableBuilder` 组织重建范围：
每个任务的进度是独立的 `ValueNotifier`，一个任务的进度跳动只重建那一行，
不会引起整个列表重排。

### 5. 队列顺序即处理顺序

批次分组是全局的，因此「选包含队首任务的批次」与「选最大的批次」
产生的批次数完全一样（模型加载次数相同），但前者尊重用户的排序。
唯一的中止信号用递增代数（`_abortGeneration`）而非布尔标志，
避免并行度大于 1 或批次间隙期漏掉停止信号。

---

## 环境要求

| 项目 | 要求 |
| --- | --- |
| 操作系统 | Windows 10 1809+ / Windows 11 |
| 显卡 | 支持 Vulkan 的 GPU（Intel / AMD / NVIDIA 核显与独显均可） |
| 运行时 | [Visual C++ 2015-2022 运行库](https://aka.ms/vs/17/release/vc_redist.x64.exe)（多数系统已内置） |
| 构建 | Flutter 3.47+、Visual Studio 2022/2026 生成工具（含「使用 C++ 的桌面开发」） |

> 没有独立显卡也能用，但速度会明显慢。标题栏会显示识别到的 Vulkan 设备。

---

## 构建与运行

```bash
# 1. 获取依赖
flutter pub get

# 2. 开发模式运行
flutter run -d windows

# 3. 发布构建（产物在 build\windows\x64\runner\Release\）
flutter build windows --release
```

首次运行会自动下载推理引擎（约 43 MB，来自 Real-ESRGAN 官方发行版），
下载完成后做 SHA-256 校验再解压。

### 开发辅助脚本

```bash
# 提前下载引擎到 .devtools/runtime，便于离线开发和跑集成测试
dart run tool/fetch_runtime.dart

# 校验图像头解析是否正确
dart run tool/probe_check.dart <图片路径...>
```

---

## 操作步骤

### 一、首次启动：安装推理引擎

1. 启动 `upbetter.exe`，会看到欢迎页。
2. 点击 **「下载并安装引擎」**。进度条会显示下载百分比、已下载字节数与实时速度。
   - 下载源优先直连 GitHub，失败时自动切换到内置镜像，每个来源重试 2 次且支持断点续传。
   - 所有来源都必须通过 SHA-256 校验，镜像即使被劫持也无法装上被篡改的引擎。
3. 下载完成后自动解压模型权重，随后进入主界面。

**如果下载失败**，错误页提供三条出路：

| 方式 | 操作 |
| --- | --- |
| 走代理 | 设置系统代理（`HTTP_PROXY` / `HTTPS_PROXY`）后点「重试」 |
| 自定义镜像 | 在输入框填入可信的下载地址（例如公司内网镜像），再点「重试」 |
| 使用已有引擎 | 点「已有引擎？手动指定目录」，选择包含 `realesrgan-ncnn-vulkan.exe` 的文件夹 |

> 也可以把引擎目录命名为 `runtime/` 放在 exe 同级目录，应用会优先使用它（绿色便携模式）。

---

### 二、导入图片

三种方式，任选其一：

| 方式 | 操作 |
| --- | --- |
| 拖放 | 把文件或**整个文件夹**拖到窗口任意位置，出现提示遮罩后松手 |
| 按钮 | 左侧队列面板右上角的 **「+」** 添加文件，**文件夹图标**添加目录 |
| 空状态 | 队列为空时，中间的「选择图片 / 或选择文件夹」按钮 |

- 支持的格式：PNG / JPEG / WebP / BMP / GIF / TGA / PPM / PGM
- 拖入文件夹会**递归**收集其中所有图片
- 读取图像信息是并发进行的（16 路），只读文件头不解码，几百个文件也是瞬间完成
- 无法识别的文件会被跳过，并在提示中告诉你跳过数量

---

### 三、选择放大模型

在右侧面板顶部的「放大模型」区点选。卡片上标注了体积与适用场景：

| 模型 | 体积 | 适用 |
| --- | --- | --- |
| **Real-ESRGAN 通用** | 32.9 MB | 真实照片、风景、人像，细节重建能力最强 |
| **Real-ESRGAN 动漫** | 8.6 MB | 二次元线稿与平涂，线条干净锐利 |
| **AnimeVideo v3** | 1.2 MB | 体积最小、速度最快，适合批量预览与视频帧 |

**使用自定义模型**：把社区模型的 `.param` 与 `.bin` 文件放进模型目录
（`%APPDATA%\Upbetter\models`），重启应用后会自动出现在列表里。
`.param` 的文件名（去掉扩展名）就是模型名。

---

### 四、选择放大倍率

在「放大倍率」区选择 **2× / 3× / 4×**：

- **4× 是模型的原生倍率**，画质最佳。
- 选择低于原生倍率时，引擎会先按原生倍率推理再降采样，画质仍明显优于直接插值，
  界面会明确提示当前是否处于原生倍率。
- 选中某个队列项时，下方会实时显示它的**输出尺寸**。

---

### 五、配置输出

#### **输出格式**

| 选项 | 说明 |
| --- | --- |
| 原格式 | 保持输入格式（JPEG 进 → JPEG 出） |
| PNG | 无损，体积大 |
| JPEG | 有损，体积小 |
| WebP | 现代化格式，兼顾体积与质量 |

#### **保存位置**

| 选项 | 说明 |
| --- | --- |
| 原目录 | 与源文件放在一起 |
| 子文件夹 | 在源文件目录下创建指定名称的子文件夹 |
| 指定目录 | 输出到固定文件夹，下方列出最近用过的目录供一键切换 |

### **命名规则**

支持以下占位符，输入框下方有实时预览：

| 占位符 | 含义 | 示例 |
| --- | --- | --- |
| `{name}` | 原文件名（不含扩展名） | `DSC_0421` |
| `{scale}` | 放大倍率 | `4x` |
| `{model}` | 模型名 | `realesrgan-x4plus` |
| `{date}` | 日期 | `20260918` |
| `{time}` | 时间 | `143052` |
| `{w}` / `{h}` | 输出宽 / 高 | `1600` |

默认模板是 `{name}_upbetter`，输出 `DSC_0421_upbetter.png`。

#### **覆盖同名文件**

- 关闭（默认）：自动追加 `(1)`、`(2)` 序号，绝不覆盖已有文件
- 开启：直接替换同名文件

---

### 六、开始处理

1. 点击右下角的 **「开始放大 · N 个文件」** 按钮（或按 `Ctrl+Enter`）。
   按钮上方会显示基于历史实测数据的**预计耗时**；首次使用某组参数时会诚实显示
   「首次运行后可知」，而不是给一个可能差十倍的数字。
2. 处理过程中可以看到：
   - 标题栏：当前文件名的活动指示器
   - 队列行：每个文件的独立进度条与百分比
   - 右侧面板：总体进度、实时吞吐量（MP/s）、剩余时间
   - 底部状态栏：吞吐量、已完成数量

### **停止与取消的区别**

| 操作 | 效果 |
| --- | --- |
| 点「停止」/ 按 `Esc` | 中止当前批次，**未处理的任务回到队列**，再次点开始即可续跑 |
| 队列行悬停时的 ⓧ | 只取消这一个任务（状态变为「已取消」，不会产出文件） |
| 右键 → 从队列移除 | 把任务彻底移出队列 |

> 已经完成的任务永远保留结果，停止不会让它们白做。

---

### 七、查看对比结果

处理完成后，中间预览区会自动切换为**对比视图**：

| 对比模式 | 说明 |
| --- | --- |
| **对比** | 分割线左侧是原图（直接插值放大），右侧是 AI 放大结果，拖动分割线查看差异 |
| **原图** | 只看原图 |
| **结果** | 只看放大结果 |

#### **画布操作**

| 操作 | 效果 |
| --- | --- |
| 滚轮 | 以鼠标指针为锚点缩放 |
| 拖拽 | 平移画布 |
| 双击 | 在「适应窗口」与「实际像素 1:1」之间切换 |
| 按住 `空格` | 临时切到原图，松开恢复（修图工具里最顺手的对比手势） |

工具栏另外提供 **缩小 / 放大 / 适应窗口 / 1:1** 四个按钮，
以及一个在资源管理器中定位结果文件的快捷入口。

> 「适应窗口」不会把小图放大超过 100% —— 这个工具是用来判断画质的，
> 把图拉伸到填满窗口只会让人看到插值出来的假细节。

---

### 八、高级选项（可选）

展开右侧面板底部的「高级选项」：

| 选项 | 说明 |
| --- | --- |
| **计算设备** | 多显卡时选择用哪一块；未识别到设备时可点「检测 GPU」 |
| **显存分块** | 默认「自动」，由引擎选择装得进显存的最大分块（最快）。遇到显存不足再手动调小 |
| **TTA 增强模式** | 8 倍计算量换取极微小的质量提升，默认关闭 |
| **并行任务数** | 默认 1。同一块显卡上并行收益有限但显存占用成倍，仅在队列里参数各不相同时才值得调高 |
| **处理时阻止休眠** | 避免长时间批处理被系统睡眠打断 |
| **完成后提示音** | 有文件成功处理完毕时提醒 |
| **完成后打开输出目录** | 自动在资源管理器中定位结果 |

---

### 九、批量处理技巧

1. **先调整参数，再拖入文件** —— 参数会作用于所有待处理任务，已完成的保持原样。
2. **同参数的文件会被自动合并成一次推理** —— 想获得最大吞吐，就让一批文件用相同的模型与倍率。
3. **用拖拽调整顺序** —— 悬停时行左侧出现拖拽手柄，处理顺序严格遵循队列顺序。
4. **中途改主意** —— 直接改右侧参数，所有未开始的任务会立刻同步新参数。
5. **失败重试** —— 队列右上角「⋮」菜单里有「重试失败项」，只重新排队失败和已取消的任务。

---

### 十、界面个性化

底部状态栏右侧：

| 按钮 | 功能 |
| --- | --- |
| 调色板 | 选择强调色（6 种预设，全局主色与渐变都会跟着变） |
| 对比度 / 太阳 / 月亮 | 在「跟随系统 → 深色 → 浅色」之间循环 |
| 文档图标 | 打开运行日志面板，排查失败原因的第一手资料 |

窗口的位置、尺寸与最大化状态会在退出时保存，下次启动原样还原。

---

## 键盘快捷键

| 快捷键 | 功能 |
| --- | --- |
| `Ctrl` + `O` | 添加文件 |
| `Ctrl` + `Shift` + `O` | 添加文件夹 |
| `Ctrl` + `Enter` | 开始处理 / 停止处理 |
| `Esc` | 停止处理；未运行时取消当前选中 |
| `Delete` | 从队列移除当前选中的任务 |
| `空格`（按住） | 预览区临时显示原图 |
| 双击画布 | 适应窗口 ⇄ 1:1 切换 |

---

## 命令行用法

可以直接配合系统的「打开方式」或脚本调用：

```bash
# 导入文件/文件夹并启动界面
upbetter.exe "D:\photos\a.jpg" "D:\photos\b.png"

# 显式指定，可重复
upbetter.exe --add "D:\photos" --add "E:\shot.png"

# 导入后立即开始处理（自动化场景）
upbetter.exe --add "D:\photos" --run
```

| 参数 | 含义 |
| --- | --- |
| `<路径>` | 位置参数，直接作为待导入的文件或文件夹 |
| `--add` / `-a` `<路径>` | 同上，显式写法，可重复 |
| `--run` / `-r` | 导入完成后立即开始处理 |

---

## 目录结构

```bash
lib/
├── main.dart                        程序入口：路径解析、窗口创建、命令行参数
└── src/
    ├── core/                        不依赖 UI 的核心层
    │   ├── app_paths.dart           目录布局（支持便携模式）
    │   ├── models.dart              领域模型：模型清单、放大参数、任务
    │   ├── settings.dart            设置持久化（防抖写盘）
    │   ├── engine/
    │   │   ├── upscale_engine.dart  调度核心：批次分组、进程驱动、进度插值、取消
    │   │   └── output_path.dart     命名模板与输出路径解析
    │   ├── image/
    │   │   └── image_probe.dart     只读文件头的图像尺寸探测
    │   ├── runtime/
    │   │   ├── runtime_manager.dart 引擎安装、模型发现、GPU 枚举
    │   │   └── downloader.dart      断点续传下载 + SHA-256 校验
    │   └── util/                    日志、格式化、硬链接、电源、提示音
    └── ui/
        ├── app.dart                 AppScope 注入与主题装配
        ├── theme/                   设计令牌与 Material 3 主题
        ├── shell/title_bar.dart     自绘标题栏
        ├── pages/                   安装引导页、主工作区
        ├── panels/                  队列 / 预览 / 对比画布 / 参数 / 状态栏 / 日志
        ├── widgets/primitives.dart  基础组件库
        └── util/                    文件对话框、系统外壳调用

assets/
├── icon.png                         应用图标源文件（1254×1254，图标生成器的输入）
└── icon_256.png                     界面内展示用的 256px 版本

tool/                                开发辅助脚本（不参与打包）
├── generate_icon.dart               由 assets/icon.png 生成多尺寸 app_icon.ico
├── fetch_runtime.dart               预下载推理引擎，供离线开发与集成测试使用
├── probe_check.dart                 校验图像头解析
├── capture_window.ps1               截取应用窗口，用于人工核对界面改动
└── extract_exe_icon.ps1             从 exe 提取指定尺寸图标，核对图标是否真的打进去了

test/                                单元测试 + 真实驱动推理进程的端到端测试
```

### 应用图标

图标走的是 Windows 原生路径，最终由资源编译器写进 exe：

```bash
assets/icon.png
  └─ dart run tool/generate_icon.dart
       └─ windows/runner/resources/app_icon.ico   （16/24/32/48/64/128/256 七档尺寸）
            └─ windows/runner/Runner.rc           （IDI_APP_ICON）
                 └─ upbetter.exe                  （任务栏、标题栏、资源管理器）
```

改图标只需替换 `assets/icon.png` 后执行：

```bash
dart run tool/generate_icon.dart     # 重新生成 ICO
flutter build windows --release      # 重新编译进 exe
```

> 为什么不用 `flutter_launcher_icons`：它给 Windows 只生成**单尺寸**（256×256）的 ICO，
> Windows 只好自己把 256px 缩到 16/24/32px，带细线条或文字的图标会糊掉。
> ICO 格式本身支持在一个文件里放多张图，因此这里自己生成全套尺寸，
> 让系统在每种显示场景下都能取到原生分辨率。`tool/generate_icon.dart` 里有详细说明。

### 数据目录

```bash
%APPDATA%\Upbetter\
├── runtime\        推理引擎可执行文件与依赖库
├── models\         模型权重（可自行放入自定义模型）
├── cache\          下载缓存与批次暂存目录（自动清理）
├── logs\           运行日志
└── settings.json   设置、窗口状态、实测吞吐量
```

### 关键设计约定

- **`core/` 不依赖 `ui/`**：核心层可以在没有 Flutter 界面的情况下被测试。
- **参数在队列项上是快照**：已完成的任务永远保留它当时使用的参数，
  界面改参数只同步给未开始的任务。
- **中止用代数而非布尔**：`_abortGeneration` 递增计数，
  避免并行度大于 1 或批次间隙期漏掉停止信号。

---

## 测试

```bash
# 全部测试
flutter test

# 静态分析
flutter analyze

# 仅队列编排逻辑（快，无需引擎）
flutter test test/engine_queue_test.dart

# 真实驱动推理进程的端到端测试（需要 .devtools/runtime）
flutter test test/engine_integration_test.dart

# 启用联网测试（下载并安装引擎，约 43 MB）
UPBETTER_NETWORK_TESTS=1 flutter test test/runtime_install_test.dart
```

测试覆盖：

| 文件 | 覆盖内容 |
| --- | --- |
| `widget_test.dart` | 图像头解析（PNG/JPEG）、GPU 设备行解析、命名模板、格式化、参数序列化 |
| `engine_queue_test.dart` | 入队去重、拖拽排序、取消语义、参数同步、清理、耗时预估 |
| `engine_integration_test.dart` | **真实调用推理引擎**：单图产物尺寸、批次合并（3 文件 → 1 次进程）、处理顺序、取消、暂存目录清理 |
| `runtime_install_test.dart` | 发行包解压筛选规则、引擎发现、模型完整性、SHA-256、真实下载安装 |

---

## 常见问题

**Q：提示「未检测到 GPU」怎么办？**
先确认显卡驱动已安装（Vulkan 运行时随驱动一起装）。可以展开「高级选项」点「检测 GPU」重新探测。
即使没有 Vulkan 设备，引擎也会回退到 CPU 推理，只是会慢很多。

**Q：下载引擎一直失败？**
多数是网络无法访问 GitHub。三种解法：设置系统代理后重试；在错误页填入可信镜像地址；
或者从别的渠道拿到引擎目录后用「已有引擎？手动指定目录」。

**Q：处理大图时报显存不足？**
展开「高级选项」，把「显存分块」从「自动」调小（先试 256，再试 128/64）。
分块越小显存占用越低，但速度会下降。

**Q：为什么输出文件比输入大很多？**
PNG 是无损格式。想控制体积就把「输出格式」改成 JPEG 或 WebP。

**Q：能保留 EXIF 信息吗？**
目前不能，输出文件不含原始 EXIF。这是已知限制。

**Q：同时打开两个窗口会怎样？**
目前没有单实例互斥，会各自独立运行。注意不要让两个实例同时处理同一批文件。

**Q：想用自己的模型？**
把 `.param` 和 `.bin` 放进模型目录，重启应用即可在模型列表里看到。
`.param` 文件名（去掉扩展名）就是传给引擎的模型名。

---

## 已知限制

- 没有单实例互斥，重复启动会打开多个窗口
- 输出不保留 EXIF / ICC 色彩配置
- 只支持 Windows 桌面端（核心层是跨平台的，但窗口与文件关联逻辑是 Windows 专用）
- 不支持视频逐帧处理
- 并行任务数大于 1 时单张速度不会提升，只对参数各异的混合队列有意义

---

## 参与贡献

欢迎提交 Issue 与 Pull Request。

### 开发流程

```bash
flutter pub get
dart run tool/fetch_runtime.dart     # 拉取引擎，集成测试需要它
flutter analyze                      # 提交前请确保零问题
flutter test                         # 提交前请确保全绿
```

### 提交前检查清单

- [ ] `flutter analyze` 无 error / warning / info
- [ ] `flutter test` 全部通过（联网测试可跳过）
- [ ] 新增的核心逻辑附带测试；涉及推理链路的改动请补端到端测试
- [ ] 用 `tool/capture_window.ps1` 截图核对界面改动

### 代码约定

- **`lib/src/core/` 不得依赖 `lib/src/ui/`** —— 核心层要能在无 Flutter 界面的环境下被测试
- 注释解释**为什么**，而不是复述代码在做什么
- 面向用户的新行为要写进 README 的操作步骤
- 界面文案与注释使用中文

### 提交信息

使用 `类型: 简述` 的格式，类型建议 `feat` / `fix` / `perf` / `refactor` / `docs` / `test` / `chore`。

---

## 许可证

本项目以 **MIT 协议**发布，见 [LICENSE](LICENSE)。

```bash
Copyright (c) 2026 Upbetter contributors
```

### 第三方组件

本项目依赖并分发若干第三方组件，各自遵循其原始许可证：

| 组件 | 许可证 |
| --- | --- |
| [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN)（模型权重与推理引擎） | BSD 3-Clause |
| [ncnn](https://github.com/Tencent/ncnn) | BSD 3-Clause |
| [window_manager](https://pub.dev/packages/window_manager)、[archive](https://pub.dev/packages/archive) | MIT |
| [desktop_drop](https://pub.dev/packages/desktop_drop)、[material_symbols_icons](https://pub.dev/packages/material_symbols_icons) | Apache 2.0 |
| [file_selector](https://pub.dev/packages/file_selector)、[path_provider](https://pub.dev/packages/path_provider)、[path](https://pub.dev/packages/path)、[crypto](https://pub.dev/packages/crypto)、[ffi](https://pub.dev/packages/ffi) | BSD 3-Clause |

完整的版权声明与许可证全文见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

> 注意：应用首次启动时会从 Real-ESRGAN 官方发行版下载推理引擎与模型权重到本地。
> 这些文件同样受 BSD 3-Clause 约束，其版权归原作者所有。

---

## 技术栈与致谢

- [Flutter](https://flutter.dev/) 3.47 · Dart 3.13
- [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) — 超分模型与 ncnn Vulkan 推理引擎
- [window_manager](https://pub.dev/packages/window_manager) · [desktop_drop](https://pub.dev/packages/desktop_drop) · [file_selector](https://pub.dev/packages/file_selector) · [archive](https://pub.dev/packages/archive) · [material_symbols_icons](https://pub.dev/packages/material_symbols_icons)
- 界面风格参考了 [Upscayl](https://github.com/upscayl/upscayl) 的产品形态

引擎发行包锁定版本 `v0.2.5.0 (20220424)`，SHA-256：
`abc02804e17982a3be33675e4d471e91ea374e65b70167abc09e31acb412802d`
