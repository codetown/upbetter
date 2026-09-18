# 第三方组件声明 / Third-Party Notices

Upbetter 本身以 [MIT 协议](LICENSE) 发布。但它依赖并分发若干第三方组件，
这些组件各自遵循其原始许可证。本文件列出这些组件及其许可证条款。

> Upbetter itself is released under the [MIT License](LICENSE). It depends on and
> distributes third-party components that are covered by their own licenses,
> listed below.

---

## 一、随应用分发的运行时（首次启动时下载）

这些文件不属于本仓库，由应用在首次运行时从 Real-ESRGAN 官方发行版下载并安装到
`%APPDATA%\Upbetter\runtime` 与 `models` 目录。

### Real-ESRGAN

- **用途**：超分辨率模型权重与 `realesrgan-ncnn-vulkan` 推理引擎可执行文件
- **来源**：https://github.com/xinntao/Real-ESRGAN
- **版本**：v0.2.5.0（发行包 `realesrgan-ncnn-vulkan-20220424-windows.zip`）
- **许可证**：BSD 3-Clause
- **版权**：Copyright (c) 2021, Xintao Wang

包含的模型权重：

| 文件 | 说明 |
| --- | --- |
| `realesrgan-x4plus.param` / `.bin` | Real-ESRGAN x4plus 通用模型 |
| `realesrgan-x4plus-anime.param` / `.bin` | Real-ESRGAN x4plus 动漫模型 |
| `realesr-animevideov3-x2/x3/x4.param` / `.bin` | AnimeVideo v3 系列模型 |

### ncnn

- **用途**：`realesrgan-ncnn-vulkan.exe` 内嵌的高性能神经网络推理框架
- **来源**：https://github.com/Tencent/ncnn
- **许可证**：BSD 3-Clause
- **版权**：Copyright (c) 2017, Tencent Inc.

### Vulkan 相关组件

推理引擎在运行时通过系统显卡驱动调用 Vulkan API。Vulkan 是 Khronos Group 的商标，
其头文件与加载器遵循 Apache License 2.0。应用本身不分发这些组件。

---

## 二、编译进应用的 Dart / Flutter 依赖

以下依赖的源代码会被编译进最终产物。

| 组件 | 许可证 | 版权 |
| --- | --- | --- |
| [window_manager](https://pub.dev/packages/window_manager) | MIT | Copyright (c) 2022-present LiJianying |
| [archive](https://pub.dev/packages/archive) | MIT | Copyright (c) 2013-2021 Brendan Duncan |
| [desktop_drop](https://pub.dev/packages/desktop_drop) | Apache-2.0 | Copyright (c) 2021 LinXunFeng |
| [material_symbols_icons](https://pub.dev/packages/material_symbols_icons) | Apache-2.0 | Copyright 2024 Tim Mahlberg |
| [file_selector](https://pub.dev/packages/file_selector) | BSD-3-Clause | Copyright 2013 The Flutter Authors |
| [path_provider](https://pub.dev/packages/path_provider) | BSD-3-Clause | Copyright 2013 The Flutter Authors |
| [path](https://pub.dev/packages/path) | BSD-3-Clause | Copyright 2014, the Dart project authors |
| [crypto](https://pub.dev/packages/crypto) | BSD-3-Clause | Copyright 2015, the Dart project authors |
| [ffi](https://pub.dev/packages/ffi) | BSD-3-Clause | Copyright 2019, the Dart project authors |

### 图标字体

界面使用的图标来自 Google 的 **Material Symbols**，遵循
[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)。

### Flutter 引擎

应用链接了 Flutter 引擎，遵循 **BSD 3-Clause**，
Copyright 2014 The Flutter Authors。见 https://flutter.dev/

---

## 三、许可证全文

### MIT License

适用于：window_manager、archive

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### BSD 3-Clause License

适用于：Real-ESRGAN、ncnn、file_selector、path_provider、path、crypto、ffi、Flutter 引擎

```
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the copyright holder nor the names of its
      contributors may be used to endorse or promote products derived from
      this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

### Apache License 2.0

适用于：desktop_drop、material_symbols_icons、Material Symbols 图标字体

许可证全文见 https://www.apache.org/licenses/LICENSE-2.0

```
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

---

## 四、关于商标

- "Real-ESRGAN" 属于其 respective 作者
- "Vulkan" 是 Khronos Group Inc. 的商标
- "Windows" 是 Microsoft Corporation 的商标
- "Flutter" 是 Google LLC 的商标

Upbetter 与上述项目不存在隶属或背书关系。
