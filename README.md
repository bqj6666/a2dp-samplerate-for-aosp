# a2dp-samplerate for AOSP

让蓝牙 A2DP 输出采样率跟随音源，消除被强制重采样到 48000 带来的音质劣化。
## 注意：该模块不对蓝牙编解码器进行修改，需要其他软件辅助更改，搭配此模块进行使用。

作者：**bqj6666**

---

## 平台支持（重要，请先阅读）

| 平台 | 支持情况 |
|---|---|
| **Qualcomm（高通）** | **唯一受支持的平台** |
| **MediaTek（联发科）** | **不支持。请勿安装。** |
| 其他（Exynos、Tensor、麒麟等） | 不支持 |

本模块的实现针对 **Qualcomm BSP 的音频策略配置结构**（A2DP 输出设备被声明在
`primary` / `default` 音频模块内）。MediaTek 及其他平台的配置文件结构、模块划分、
命名约定均不相同，本模块对其**没有任何适配**。

模块内置平台预检：若目标配置中找不到符合预期结构的 A2DP 声明，补丁产出与原文件
无差异，模块会直接跳过，不会写入任何内容。因此误装到非 Qualcomm 设备上通常不会
造成破坏，但也**不会生效**——请不要把它当作跨平台方案使用。

---

## 这个模块解决什么问题

在 Qualcomm BSP 派生的音频策略配置里，A2DP 输出设备被声明在 **primary / default 音频模块**内：

```xml
<module name="default">
    <devicePort tagName="bt_a2dp_out" ... role="sink">
        <profile samplingRates="48000" .../>
    </devicePort>
    <route type="mix" sink="bt_a2dp_out" sources="low_latency_out,deep_buffer_out,..."/>
</module>
```

而这些模块的**所有**输出（`deep_buffer_out` / `low_latency_out` 等）采样率都固定为 **48000**。
A2DP 因此被挂到只支持 48000 的输出上，于是：

```
44.1kHz 音源 -> AudioFlinger mixer 48000 -> (LDAC) 96000
                    ^ 这里发生强制重采样
```

**AOSP 的原意并非如此。** 官方 `bluetooth_audio_policy_configuration.xml` 把 A2DP 放在
**独立的 bluetooth 模块**里，采样率是完整的：

```xml
<module name="bluetooth" halVersion="2.0">
    <mixPort name="a2dp output" role="source"/>          <!-- 无 profile = 动态率 -->
    <devicePort tagName="BT A2DP Out" ... role="sink">
        <profile samplingRates="44100,48000,88200,96000" .../>
```

本模块在开机时读取**你设备自带的**配置，删掉非 bluetooth 模块里的 A2DP 输出声明，
使 A2DP 回落到 bluetooth 模块的动态输出。之后 AudioFlinger 会按音源采样率开输出，
蓝牙 codec 同步跟随：

| 播放内容 | AudioFlinger 输出 | 蓝牙 codec |
|---|---|---|
| 44.1 kHz | 44100 | 44100 |
| 48 kHz | 48000 | 48000 |

**不打包任何厂商文件**——配置在设备上运行时生成，因此可跨机型通用。

---

## 采样率支持范围

模块本身**不定义采样率上限**——它只是解除 `primary` / `default` 模块对 A2DP 的占用。
实际能力由**设备 bluetooth 模块的声明**与**蓝牙编解码器（codec）的能力**共同决定，
多数 Qualcomm 设备两者上限都是 96000。

以已验证设备（LDAC 耳机）实测：

| 音源采样率 | AudioFlinger 输出 | 蓝牙 codec | 是否发生重采样 |
|---|---|---|---|
| 44100 | 44100 | 44100 | 否 |
| 48000 | 48000 | 48000 | 否 |
| 88200 | 96000 | 96000 | 是（见下方说明） |
| 96000 | 96000 | 96000 | 否 |
| 192000 | 96000 | 96000 | 是（必然降采样） |

结论：

- **96 kHz 可原生直通**：设备声明与 LDAC codec 上限均为 96000，实测 AudioFlinger 与 codec
  同步在 96000，无重采样。
- **192 kHz 无法直通**：超出设备声明（最高 96000）与 LDAC 上限，192k 音源会被降采样到 96k。
  这是硬件与 codec 的硬上限，模块无法突破。
- **88.2 kHz 取决于耳机**：设备侧声明支持 88200，但需耳机 codec 同样协商 88.2k；
  若耳机不提供该档位，会落到 96000，此时发生一次重采样。
- 需要 192 kHz 及以上原生输出，只能走 **USB DAC / 有线耳机**（`direct_pcm_out`），
  蓝牙 A2DP 无法达到。

---

## 适配条件

### 支持

| 条件 | 说明 |
|---|---|
| **Qualcomm 平台** | 必须。见上方「平台支持」 |
| Android 14+ **AIDL 音频 HAL** | 必须存在 `IModule/bluetooth` 或 `IBluetoothAudioProviderFactory`（模块会读 `/vendor/etc/vintf` 自动确认） |
| A2DP 声明位于 `primary` / `default` 等非 bluetooth 模块 | 两种命名风格都识别：`bt_a2dp_out` / `BT A2DP Out` |
| 任意带 mount 能力的 root | KernelSU + SUSFS（首选）或 Magisk / KernelSU 无 SUSFS（自动回退 bind mount） |

### 仅检测、不处理

| 情况 | 行为 |
|---|---|
| **老 HIDL / 单文件 policy 布局**（A2DP 只在 primary 里有声明，系统不提供独立 bluetooth 模块） | 模块**直接跳过，不做任何改动**。此类设备删掉 primary 里的声明会导致 A2DP 彻底无声，无安全改法 |
| 配置本来就是 AOSP 布局 | 补丁产出与原文件逐字节相同，直接跳过 |
| **MediaTek 及其他平台** | 配置结构不符，补丁无差异，直接跳过。**不被支持** |

### 为什么原厂系统（如 ColorOS）通常没这个问题

原厂可能使用自己定制的 `libaudiopolicymanagerdefault.so`，或在 offload 路径上做了额外处理，
因此原厂下未必复现。刷入 AOSP 派生 ROM 后用的是纯 AOSP 策略库，会严格按 XML 声明选择
48000 输出，问题才暴露出来。**此为推测**（未在保留原厂库的环境下验证）。

---

## 已验证设备

> OnePlus 13T (SM8750) / AVIUM UI 16.2.1 / Android 16

在该设备上实测双向动态生效（44.1 kHz 对应 44100，48 kHz 对应 48000，切换可逆），
无杂音、无断音。

其他 Qualcomm 机型欢迎提交测试结果。

---

## 安装

1. 从 Releases 下载 zip，在 KernelSU / Magisk 里刷入；
2. **重启设备**；
3. 验证（见下）。

模块不依赖任何硬编码路径，会自行探测配置位置。

---

## 验证

```sh
# 应输出 0（primary/default 模块里已无 A2DP 声明）
dumpsys media.audio_policy | awk '/^  [0-9]+\. Handle: [0-9]+; "/ { inmod = ($0 ~ /"(primary|default)"/) }
  inmod && /"bt_a2dp_out"|"bt_a2dp_headphones"|"bt_a2dp_speaker"|"BT A2DP Out"|"BT A2DP Headphones"|"BT A2DP Speaker"/ { n++ }
  END { print n+0 }'
```

连接蓝牙耳机并播放音乐后：

```sh
# AudioFlinger 输出线程的采样率应等于音源采样率
dumpsys media.audio_flinger | grep -E 'Sample rate|BLUETOOTH_A2DP'

# 蓝牙 codec 协商结果应同步
dumpsys bluetooth_manager | grep -o 'codecName:[A-Za-z]*[^}]*mSampleRate:0x[0-9a-f]([0-9|]*)'
```

播放一首 44.1 kHz 与一首 48 kHz 的曲目，上述两处应分别在 44100 / 48000 之间切换。

日志：`/data/adb/a2dp_samplerate.log`

---

## 投递方式

| 优先级 | 方式 | 特点 |
|---|---|---|
| 1 | **SUSFS open_redirect** | kernel 层路径重写，**不产生任何挂载行**，不触发 mount 类检测 |
| 2 | **bind mount** | 设备不支持 SUSFS 时自动回退；通过 `nsenter -t 1 -m` 挂到 init 的 namespace |

投递件位置：`/data/vendor/audio/a2dp-sr/`（`audio:audio`，audio HAL 可读）。
原文件**从不被修改**（`/vendor` 只读），模块只做运行时重定向。

---

## 卸载

在管理器里卸载模块，然后**重启一次**。

SUSFS 的 live open_redirect 只能靠重启彻底清除；模块自带的 `uninstall.sh` 会尽力清理
挂载与投递目录，并建议重启。

若音频异常需要立即停用：创建空文件 `/data/adb/modules/a2dp_samplerate/disable` 后重启
（内核层面不会加载模块）。

---

## 已知限制

- **A2DP 采样率在连接时协商一次**，不会逐曲重协商。多数播放器（如开启自适应采样率后）
  切换不同采样率的曲目会触发重新配置，实测可逆；但这依赖播放器行为。
- **多个应用同时播放不同采样率内容时**，AudioFlinger 只能选定一个采样率，其余内容仍会被
  重采样。这是混音器的固有约束，任何方案都无法消除——独占播放才完全干净。
- 真正 bit-perfect 的独占路径只有 **USB DAC / 有线耳机**（走 `direct_pcm_out`，非本模块职责）。
- 部分 ROM 的蓝牙开关在 `audioserver` 重启后会短暂断开耳机，属正常现象。

---

## 开发

```sh
# 补丁逻辑自测（纯合成 XML，无需设备）
sh tools/test-patch.sh
```

- `tools/patch.awk` —— 补丁核心：仅删除**非 bluetooth 模块**内的 A2DP 输出声明
  （devicePort + route），保留 `bt_a2dp_mic` 等输入设备。
- 两种命名风格（`bt_a2dp_out` / `BT A2DP Out`）均支持。
- 幂等：对已打过补丁的文件再次运行结果不变。

```sh
# 构建可刷写模块 zip（产物在 dist/）
sh tools/build-zip.sh
```

---

## 许可

GPL-3.0
