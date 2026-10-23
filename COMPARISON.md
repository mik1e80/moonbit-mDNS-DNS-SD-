# 生态对比与新增价值

本项目不声称是首个 MoonBit mDNS 实现。

| 项目 | 已知交集 | 本项目计划补充 |
| --- | --- | --- |
| moonbit-community/rtc.mbt 的 mdns | `.local` 主机 A/AAAA 查询与缓存 | PTR/SRV/TXT 服务聚合、连续状态与来源范围 |
| jinshengmeng46/moon-dns-stub | DNS wire 和普通 Native resolver | mDNS 查询调度、缓存高位语义和 DNS-SD 生命周期 |
| moonbitlang/async | Native UDP 与组播能力 | 传输适配与系统元数据，协议仍由本项目核心处理 |
| python-zeroconf / Avahi | 独立 DNS-SD 实现 | 作为互通对端，不隐藏调用它们代替库逻辑 |

这些是选题边界，不代表本项目已经实现相应能力。固定源码版本、许可和复用结论记录于 M0 依赖决策。
