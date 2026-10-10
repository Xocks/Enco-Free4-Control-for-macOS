# 提示音内容／音色 · Prompt content and timbre

提示音音量和内容替换是两个独立功能。现有提示音方案读取通过验证；内容／音色写入暂缓。

## 已找到的接口

- `0121 → 8121`查询方案ID、有效性、CRC32、选中状态及可选名称。
- 官方Android实现中的`ToneFileVertifyInformation`记录ID、文件大小、CRC32及UTF-8名称；元信息设置为`0417`。
- 官方实现下载按型号区分的`.bin`提示音资源包，并使用SHA-256校验；预览音频是不同资源。
- `deviceType=4`对应提示音资源传输，复用升级传输框架，不能当作普通feature开关或直接发送WAV／MP3。

## 暂缓原因与恢复条件

缺少普通版可校准的官方资源包样本和完整传输记录；容器、编码、分包确认、断线恢复及恢复原提示音尚未验证。未发送资源写入命令，未执行固件刷写。不能据此判定设备不支持任意内容替换。

先获取对应型号官方资源包及哈希，离线解析；再用合法获取的Android HCI记录和Wireshark核对元信息、传输与完成事件。先验证官方资源包和恢复流程，再判断自定义音频是否可转换。APK和抓包不随仓库分发。

English: reading existing prompt presets works. Replacing prompt content/timbre is deferred until the official resource format, transfer protocol and restoration path are verified. Changing prompt volume does not implement content replacement.
