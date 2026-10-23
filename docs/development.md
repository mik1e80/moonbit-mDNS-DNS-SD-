# 轻量开发环境

固定版本与散列见 `toolchain.json`。旧的 2026-09 工具链不能读取 async 0.22.5 的配置；不要通过修改已安装依赖的源码来掩盖不兼容。

Windows 已安装 Visual Studio C++ 工具和 Windows SDK 时：

```powershell
.\scripts\bootstrap.ps1
.\scripts\moon.ps1 test dnssd_test.mbt src/model src/wire --target js --filter 'smoke:*'
.\scripts\moon.ps1 build cmd/native_spike cmd/transport_spike --target native
.\scripts\moon.ps1 run examples/encode_query --target js
```

bootstrap 将固定版 MoonBit 安装到项目 `.tools`，校验官方归档散列，构建必要 core bundle；不会升级全局工具链。离线且依赖已安装时可运行 `bootstrap.ps1 -Offline`。

提交前运行 `scripts/moon.ps1 info` 和 `scripts/moon.ps1 fmt`；检查生成接口差异。CI 只运行当前核心的少量 `smoke:*` 测试和 Windows/Linux Native 编译，不运行真实局域网实验，也不全量跑所有后端。

已执行的网络实验见 `transport-spike.md`；构建通过不等同于该平台真实网络已通过。
