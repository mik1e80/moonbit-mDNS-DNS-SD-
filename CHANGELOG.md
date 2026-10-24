# 变更记录

## 0.1.0 — 发布准备中

### 已实现

- 纯 MoonBit 名称/TXT 模型、有限 DNS-SD wire 解码与 QM 查询编码，公开根包 API。
- 带 scope 的有界 TTL 缓存、goodbye/flush 宽限、PTR/SRV/TXT/地址聚合、部分状态与生命周期事件。
- 注入时钟和随机种子的 QM 抖动/退避/刷新、单包 Known-Answer、指定实例 resolve 超时与取消。
- 指定 IPv4 接口的 Native 组播适配、共享 5353 绑定、入站元数据、异步 Browser 和取消释放。
- browse/resolve/doctor/replay CLI、实时 JSONL、保存原始报文/时钟/种子的录制及确定性回放。
- 公开 API 示例、动态发现端口的受控 HTTP 示例、Windows 独立 zeroconf 进程互通证据、固定工具链与轻量 CI。

### 已修复

- Native CLI 使用异步 stdout 逐行及时输出事件。
- 唯一记录更新按报文到达序号处理，避免同毫秒 TXT 更新产生暂不可用。
- 空闲定时 tick 不再重复重建服务状态，快照仍提供当前剩余 TTL。
- mDNS 名称上限支持 255 字节加根终止字节，并保持可逆文本表示。
- 同一 tick 内不同服务失效时，事件按各自相关记录保留 goodbye/TTL/flush 原因。
- 超长或截断的 UDP 报文被丢弃，浏览器继续处理后续合法响应；真实 socket 故障继续报错。

### 当前限制

实时传输为 IPv4 QM 组播，单播排除；Linux 仅编译，无第二设备证据。没有发布者、IPv6 组播、子类型、NSEC 负缓存、多包 Known-Answer 或完整 SRV 优先级/权重选择。Mooncakes 发布与已发布包消费结果尚待记录。
