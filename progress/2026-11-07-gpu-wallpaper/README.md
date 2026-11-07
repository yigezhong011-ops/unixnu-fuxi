# 2026-11-07：壁纸和 GPU（Metal）进度

小米 13（fuxi，SM8550），iPadOS 17.7.11（21H461），`t50` 内核加二进制补丁。所有测试用 `fastboot boot` 临时启动，今天没有刷机。

测试由 USB 手势脚本 `scripts/ctl-run.ps1` 自动执行，结果靠截图和串口判断。除非特别说明，每项结果只跑过 1 次。

## 结论

**Metal 还没修好。** 壁纸库的一个主要问题找到了原因，并有了修法；“你好”全黑和卡顿还没解决。

| 项目 | 结果 |
|---|---|
| 桌面、设置、普通壁纸 | 能显示 |
| “团结”（Kaleidoscope） | 放行后，来回滚动几次，三个缩略图都画出来了 |
| “团结”点进编辑页 | 放行后能实时显示（第三个格子，新旧插件都测过） |
| “彩虹”（Pride）点进编辑页 | 放行 + 旧插件：霓虹线条完整。放行 + 新插件：全黑 |
| “彩虹”缩略图 | 放行 + 旧插件：黑底加时钟，还不对 |
| “你好”（Hello）点进编辑页 | 放行 + 旧插件：全黑，**未解决** |
| 卡顿 | **未解决**，原因不明 |

## 找到的原因

壁纸库里的海报扩展打开 GPU 时被沙盒拒绝：

```
Sandbox: KaleidoscopePoster(N) deny(1) iokit-open-user-client AGXDeviceUserClient
```

内核的放行名单 `NativeSandboxGrantProcess` 里没有这三个进程。

## 修法

`scripts/patch-t50-grant.py` 把名单加长，内核只改 62 字节：

```
backboardd,iconservicesagent,WidgetRenderer_Default,PosterBoard,AegirPoster,WeatherPoster,PhotosPosterProvider
+ KaleidoscopePoster,PridePosterExtension,HelloPosterExtension
```

没有修改槽位数量，仍是 7 个。名单比槽位多，抢槽位的情况还没有查。

## 11-05 的新插件不要用

`AdrenoMetal 7e0d3d2` 加 `8c1ea13`、`5a50581` 和翻译器补丁 `0025` 的版本：

- 同样的放行和操作，“彩虹”全黑，旧插件正常。
- 空格子它修不了，原因在沙盒。
- 它想修的 `pro24MainFragment`、`lightsMeshFragment` 被拒，今天的负载没有碰到，修复效果未证实。
- 新插件有 2 次、旧插件 0 次出现长按锁屏打不开切换页。次数太少，不能下结论。

## 日用候选镜像

`t50-daily-g7grant`（sha256 前 16 位 `a50b0187ea382c4e`）：旧插件、放行名单、修好的 X 上限。**没有刷入。** 临时启动 1 次：自动解锁，点击屏幕右侧打开备忘录（修复前点不到 240 pt 以右），上划回桌面，USB 叫回 fastboot。

## 排除的说法

- **没联网导致格子空白：** 用户提出的问题。这三个壁纸的日志里没看到网络错误，但筛选不算彻底。没联网确实影响 Apple 账号服务，约 3600 次 `failed to load the bag`。
- **`Image cannot be created from URL`：** 看过的几条来自天气壁纸，且不在最新日志段。
- **`OutOfMemory`：** 累计日志有约 1400 条，今天两轮 A/B 没有新增。来源不明。

## 测试方法的修正

- **回落检测：** 日用镜像现在也回复 TAP，探测失效，曾把回落当成测试结果。现在还检查第一个启动参数是不是 `sheng-autoreset`。
- **开机时间：** 同一镜像有一次到 130 秒界面还没起来。新增 `ready` 步骤，等屏幕有内容再操作。
- **有人碰屏幕：** `hid` 比手势多出几百个报告时，那一轮不算自动结果。
- **统一日志：** 回 fastboot 前最后一次开机的日志只留下约 8 万行开机段，海报的报错经常没有落盘，所以读不到“你好”的具体错误。
- **“设置”只点中屏幕坐标：** 编辑页的“取消”在 y≈25。

## 下一步

1. 查“你好”和“彩虹”缩略图为什么是黑的。要先解决日志落盘。
2. 查放行后 GPU 槽位够不够。
3. 查卡顿。
4. 用户同意后，把候选镜像刷入 boot_b。

## 文件

`scripts/` 里是今天用到的补丁和脚本。镜像、内核、密钥、Data 备份都没有上传。
