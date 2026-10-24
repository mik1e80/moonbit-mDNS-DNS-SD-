# MoonDiscover 项目说明

仓库：[mik1e80/moonbit-mDNS-DNS-SD-](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-)。模块名：`mik1e80/dnssd`。许可：Apache-2.0。状态：2026-10-24，已发布 0.1.0；不宣称已完成原实施计划的所有平台与 RFC 验收。

## 解决的问题

局域网服务的端口和地址会变化。应用可以通过 `_http._tcp.local.` 等 DNS-SD 类型发现实例，再拿到 SRV、TXT 与地址，跟踪属性变化、goodbye 和缓存到期，而不把端点写死在代码里。

MoonDiscover 用 MoonBit 实现发现所需的报文、缓存、查询与状态引擎。Native 层提供指定 IPv4 接口的真实组播收发，纯核心可在没有局域网和系统 socket 的环境中回放相同输入。

## 可检查的成果

- 原始标签字节与二进制 TXT，保留实例内点、flag/empty、重复键语义。
- 范围隔离的 TTL 缓存、goodbye/cache-flush 宽限、部分与完整服务、连续生命周期事件。
- QM 查询抖动、退避、TTL 刷新、单包 Known-Answer、指定实例解析超时与取消。
- Native Browser、四个 CLI 命令、实时 JSONL、原始报文录制和固定种子确定性回放。
- 使用发现端点的 HTTP 示例，未通过 Python 发现库代替 MoonBit 内部逻辑。
- 按实际功能与修复逐步提交的 Git 历史、固定版本工具链和轻量 CI。

## 演示与证据

从 [README](../README.md) 构建 CLI 后，可用 `replay --file fixtures/live-20261024.jsonl` 离线查看筛选后的真实录制。该样本来自 Windows 上的独立 python-zeroconf 发布进程，服务与 HTTP 端点由测试脚本创建。

[Windows 报告](evidence/windows-live-20261024.json)记录了 8 项通过检查：主动发现、动态端口 HTTP 请求、TXT 更新、goodbye 移除、所有受控进程成功退出、异步取消关闭、录制回放确定性、实网与回放服务事件一致。报告包含源提交、工作树状态、二进制散列和事件时间线。复现脚本为 `tests/interop/live_smoke.py`，轻量测试和来源说明见 [验证文档](verification.md)。

## 支持范围与后续工作

当前 Windows 证据来自同一台机器上的独立进程，尚无第二设备、Avahi 或 Linux 实网结果；Linux Native 已有 CI 编译。实时网络限定 IPv4 QM 组播，单播接收明确排除。未实现发布者、IPv6 组播、服务子类型、NSEC 负缓存、多包 Known-Answer 和完整 SRV 优先级/权重选择。

Mooncakes 0.1.0 已实际发布，[源码标签](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/tree/v0.1.0)对应 `2b922d6`。无 `moon.work` 源码映射的新工程已从注册表安装、运行公开核心 API、编译 Native 并打开/关闭 socket；归档散列及全部 116 个安装文件匹配。详见[发布记录](evidence/release-0.1.0-20261024.json)和[消费记录](evidence/consumer-registry-20261024.json)。
