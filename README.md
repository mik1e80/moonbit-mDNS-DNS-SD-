# MoonDiscover

MoonBit DNS-SD 服务发现库，模块名 `mik1e80/dnssd`，Apache-2.0 许可。

通过 `_http._tcp.local.` 等类型发现实例、主机、端口、二进制 TXT 与地址，持续报告解析、更新、暂不可用和移除。纯 MoonBit 核心负责报文、缓存、聚合、查询调度和确定性回放；Native IPv4 适配层负责指定接口上的实际组播收发。

当前为发布前版本。Windows 已完成同机独立 `python-zeroconf` 进程发布、MoonBit 主动发现、使用发现的动态端口请求 HTTP、TXT 更新、goodbye 移除、异步取消释放和录制回放的闭环。[实网证据](docs/evidence/windows-live-20261024.json)对应源提交 `f2baff7`。Linux 目前只有 Native 编译证据；尚无第二设备、Linux 实网或 Mooncakes 已发布包消费证据。

## 快速开始

Windows 需要 Visual Studio C++ 工具和 Windows SDK。项目使用固定工具链，不替换全局 MoonBit：

```powershell
.\scripts\bootstrap.ps1
.\scripts\moon.ps1 run examples/encode_query --target js
.\scripts\moon.ps1 build cmd/moondiscover --target native
```

离线示例通过公开根包编码并解码 QM PTR 查询。CLI 的 Windows 构建位置是 `_build/native/debug/build/cmd/moondiscover/moondiscover.exe`。把下面地址换成当前活动网卡的 IPv4 地址：

```powershell
$cli = '.\_build\native\debug\build\cmd\moondiscover\moondiscover.exe'
& $cli doctor --interface 192.168.1.10
& $cli browse --interface 192.168.1.10 --service _http._tcp.local. --duration-ms 5000
& $cli resolve --interface 192.168.1.10 --instance 'Demo._http._tcp.local.' --duration-ms 5000
& $cli browse --interface 192.168.1.10 --service _http._tcp.local. --duration-ms 5000 --record trace.jsonl
& $cli replay --file trace.jsonl
```

CLI 向 stdout 实时输出 JSONL。`doctor` 检查接口与共享绑定，不证明网络响应可达；browse 的空结果只表示观察窗口内未发现。resolve 未在窗口内完成时返回非零。录制保存原始报文、输入时间和随机种子；分享前需检查其中是否包含其他局域网服务。

## 库入口与示例

根包 `mik1e80/dnssd` 暴露 `DnsName`、`TxtRecord`、`Engine`、`Replay` 和报文/事件模型，不依赖系统网络。调用者给 `Engine` 注入范围标识、单调毫秒时间和输入报文，再取事件、快照与待发查询。

Native 包 `mik1e80/dnssd/src/native` 的 `Browser` 连接系统 socket 和时钟，提供 `browse`、`resolve`、`cancel`、`poll`、异步 `run` 与幂等 `close`。`run` 在取消和退出时关闭浏览器。

- [离线公开 API 示例](examples/encode_query/main.mbt)：编码与解码查询。
- [连续事件示例](examples/watch_events/main.mbt)：通过异步 stdout 输出服务事件。
- [HTTP 连接示例](examples/http_connect/main.mbt)：按 TXT demo token 选择受控服务，使用发现的地址和动态端口请求演示端点。
- [可离线回放的实网样本](fixtures/live-20261024.jsonl)：从录制中筛出本项目合成服务的报文，保留时钟与命令帧。
- [浏览器离线回放](examples/browser_replay/README.md)：本地粘贴或加载 JSONL，查看同一 MoonBit 核心产生的事件与待发查询。

## 当前边界

实时传输限定为显式选择接口的 IPv4 QM 组播，接纳源端口 5353、目标 `224.0.0.251`、所选入站接口的响应。单播接收已明确排除。可解码 AAAA，不代表支持 IPv6 组播。

缓存支持 TTL、goodbye 的一秒宽限、cache-flush 的近期分包保护和范围隔离；查询支持初始抖动、指数退避、TTL 刷新和有界单包 Known-Answer。最新同批中的多个冲突 SRV/TXT 会保留未完成状态，尚无完整 SRV 优先级/权重选择。未实现发布者、自动重命名、服务子类型、NSEC 负缓存、跨子网、接口自动切换或多包 Known-Answer。

## 文档与验证

- [范围与支持矩阵](docs/SCOPE.md)、[协议矩阵](docs/protocol-matrix.md)、[当前进度](docs/progress.md)
- [验证证据与复现](docs/verification.md)、[开发与轻量测试](docs/development.md)
- [名称/TXT/事件模型](docs/model.md)、[参赛说明](docs/submission.md)、[变更记录](CHANGELOG.md)
- [生态对比](COMPARISON.md)、[原始实施计划（历史）](docs/implementation-plan-20261023.md)

按有实际成果的步骤提交并推送 GitHub。验证采用针对当前改动的少量断言与短时冒烟，不在每一步全量运行所有后端。测试范围与平台结论见验证文档。
