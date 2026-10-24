# 轻量开发与复现

固定版本与散列见 `toolchain.json`：moon `0.1.20261023`、moonc `v0.10.17+d971670cd`、async `0.22.5`。旧的 2026-09 工具链不能读取此 async 版本的配置。不要修改已安装依赖源码来掩盖不兼容。

## 工具链与最小检查

Windows 已安装 Visual Studio C++ 工具和 Windows SDK 时：

```powershell
.\scripts\bootstrap.ps1
.\scripts\moon.ps1 run examples/encode_query --target js
.\scripts\moon.ps1 test src/engine --target js --frozen --filter 'smoke:*'
.\scripts\moon.ps1 build cmd/moondiscover examples/http_connect examples/watch_events tests/native_cancel --target native
python tests/interop/cli_smoke.py
```

bootstrap 将官方固定工具链装在项目 `.tools/moon`，校验归档散列并构建 core bundle；不会升级全局工具链。工具链和依赖已安装时，可用 `bootstrap.ps1 -Offline`。

按改动选择相关包或具体测试文件。需要复现当前 CI 核心范围时运行：

```powershell
.\scripts\moon.ps1 test dnssd_test.mbt src/model src/wire src/cache src/engine src/replay --target js --frozen --filter 'smoke:*'
```

提交前运行 `scripts/moon.ps1 info --frozen` 和 `scripts/moon.ps1 fmt`，检查生成接口差异。不以重复全量测试增加提交步骤。

## 离线回放

先构建 CLI，再运行实际二进制：

```powershell
$cli = '.\_build\native\debug\build\cmd\moondiscover\moondiscover.exe'
& $cli replay --file fixtures/replay-basic.jsonl --seed 7
& $cli replay --file fixtures/live-20261024.jsonl
```

有 `config` 首帧时自动恢复录制的 UInt32 随机种子；显式 `--seed` 必须与配置一致。相同帧/时间/种子应产生相同 JSON 事件和待发报文。文件上限 8 MiB/10000 帧，时间需为不递减的精确 JSON 整数。

## 受控 Windows 实网实验

`tests/interop/live_smoke.py` 创建独立 zeroconf 发布者与动态端口 HTTP 服务，运行 Native CLI/HTTP/取消程序，修改 TXT、发送 goodbye、保存录制并离线回放。先完成 Native 构建，选择当前活动物理网卡的 IPv4 地址：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r tests/interop/requirements.txt
.\.venv\Scripts\python.exe tests/interop/live_smoke.py --interface 192.168.1.10 --output .tools/live-local.json
```

测试前确认该地址属于活动接口；VPN/隧道地址可能不具备预期组播可达性。宿主机需允许组播收发；受限 sandbox 内无响应不能当作协议验证通过。脚本清理它创建的进程与服务，不需要停止其他占用 5353 的应用。

CLI 手工录制为 `browse` 或 `resolve` 添加 `--record path.jsonl`，正常退出后写入配置、输入命令、时钟和接收原始报文。录制也可能包含同接口其他服务的报文，提交前只导出受控服务相关内容，并分别记录原始与导出散列。

## 后端与证据

根包是无 socket 的纯核心；真实网络入口为 `mik1e80/dnssd/src/native`。CI 使用固定版本做 JS 核心冒烟、Windows/Linux Native 编译，Windows 另运行离线二进制契约测试。CI 不运行真实局域网实验。

平台结论依 [验证记录](verification.md)；Linux 编译成功不能代替 Linux 实网互通。原始实施计划不作为“所有能力已完成”的证明。
