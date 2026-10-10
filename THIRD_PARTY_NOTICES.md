# 来源、版本与许可证

本项目是 GPL-3.0 软件。保留根目录 LICENSE 的完整 GPL 文本。改动日期 2026-10-09 至 2026-10-10。

| 来源 | 固定提交 | 复用／参考范围 | 许可证 |
|---|---|---|---|
| [OPPO Pods for macOS](https://github.com/ssigpoy/OPPO-Pods-for-macOS) | `64c869ab550c9b107561c6209872a77cda6d9dd5` | 原生 SwiftUI 项目、IOBluetooth/RFCOMM 基础、协议模型及打包脚本、图标与型号元数据 | GPL-3.0，Copyright (C) 原项目贡献者 |
| [EncoFree4Menu](https://github.com/wang29a/EncoFree4Menu) | `380b920605038dff51b9d0d73f57110c1969a75c` | Free4 普通版模式映射、操作确认、档位记忆交叉核对 | GPL-3.0-or-later |
| [QuickBuds](https://github.com/spizganed/QuickBuds) | `6a341e9edadb40e97f2d9d204ce06629542a82e6` | 变长帧、能力位图、手势、EQ、连接设备、个性化协议与设备请求应答参考 | GPL-3.0-or-later |

关键改动：限制为普通版单型号；修复长报文长度；移除乐观更新；加入ACK与关联回读、重连与生命周期、未知／过期状态；中文界面重组；P1功能实现；P2只读探测及经实机回读验证的开关；脱敏日志；独立协议测试；应用名称和Bundle ID分离。

JADX、Android蓝牙HCI日志与Wireshark是协议校准工具（APK分析参考官方JADX 1.5.6），不是最终应用依赖。本项目未打包官方APK或厂商固件，未提取或上传用户账号数据。
