# M0 Native 传输验证：2026-10-23

## 实际结论

Windows 11 本机 IPv4 组播闭环已通过：独立 python-zeroconf 0.148.0 发布 `_http._tcp.local.`，MoonBit 从所选接口的 UDP 5353 主动发出 QM PTR 查询，独立 witness 收到相同查询；MoonBit 收到包含该次唯一 demo 标识的响应，解析出 5 条记录，取得来源、入站接口索引和目标组播地址。

这证明基础收发与 wire 解析，不代表服务聚合、缓存、HTTP 连接和连续生命周期已经完成。

原始记录：[m0-windows-transport-20261023.json](evidence/m0-windows-transport-20261023.json)。传输与实验源码提交：`bcc6cec7eeadc2d6eea03c5b0664f6aa7411e383`；固定工具链见 `../toolchain.json`。该次 native_spike 二进制 SHA256：`646c77e78965ae7c3ea531d8b652e02b9fae9669c2ca2a22fd4ad068088bc85f`。

| 检查 | 结果 |
| --- | --- |
| Native 探针正常退出 | 通过 |
| witness 观察到所选 IP:5353 发出预期查询 | 通过 |
| 收到独立发布者且含本次 demo 的响应 | 通过 |
| 有限 decoder 解析独立响应 | 通过，5 条记录 |
| 入站接口与组播目标地址 | 通过，接口索引 11、224.0.0.251:5353 |
| 两个 Native socket 与独立发布者共用 5353 | 通过 |
| 显式关闭、重复 close、重新绑定 | 通过 |
| 单播包送到本机 IP:5353 | 未观察到；检查为 false |

实验总体退出码 **1**，因为单播检查未通过，未改成全通过。实验关闭了自己创建的发布者和 witness，但未停止其他系统/应用进程。实验后 netstat 仍观察到多个 5353 监听者；单播投递可能受共享端口影响，根因尚未证明。

原始 JSON 的最后一条 limits 写成了“without competing listeners”，这仅指实验创建的监听者，表述不精确；应以本段更正为准。脚本后续已修正文案，没有改写原始测量结果。

## 依赖限制复现

async 0.22.5 组播专用 socket 可以共享监听，但 sendto 明确报“不允许发送”；普通 UdpServer 在共存环境绑定失败。均记录在原始报告。最小 C 扩展因此负责 socket 配置、收发和包元数据，DNS 编解码由 MoonBit 完成。

沙箱内第一次实验能绑定端口，但未观察到网络包；获准在沙箱外执行后组播通过。不是将录制数据当成实网成功。

## 复现命令（Windows）

```powershell
.\scripts\bootstrap.ps1
.\scripts\moon.ps1 build cmd/native_spike cmd/transport_spike --target native
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r tests/interop/requirements.txt
.\.venv\Scripts\python.exe tests/interop/transport_smoke.py --interface <本机IPv4> --output .tools/transport-smoke.json
```

实验约 12 秒，输出中只保留自建服务包。端口 43219 在此阶段仅为 DNS-SD 发布内容，没有启动 HTTP 服务，也未宣称已连接发现端点。当前实验脚本使用 Windows 二进制路径；Linux CI 只编译探针。

## 尚未关闭的风险

- 单播投递、入站 IP TTL 与非本链路接纳策略。
- 跨接口实际注入与过滤验证；接口断开、独占绑定失败的明确错误路径。
- 真正第二设备互通；Linux 实网和 Avahi 互通。
- 同步接收轮询与未来异步取消、任务/句柄审计。

当前只发送 QM 查询，不请求 QU 单播回复。不宣称完整传输层或全平台支持。
