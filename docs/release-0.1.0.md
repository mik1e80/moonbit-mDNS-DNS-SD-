# MoonDiscover 0.1.0

MoonDiscover 是 MoonBit DNS-SD 浏览与解析库。应用按服务类型发现实例，再取得主机、端口、TXT 与地址，持续接收服务变化事件。

首版包含纯 MoonBit 报文/模型、范围隔离缓存、生命周期引擎、QM 查询调度与 resolve、Native IPv4 组播入口、browse/resolve/doctor/replay CLI、录制回放、HTTP 连接和浏览器离线示例。

Windows 已完成独立 python-zeroconf 进程发布、动态端口 HTTP 使用、TXT 更新、goodbye、取消释放和回放一致性验证。0.1.0 标签当时的 Linux 证据为编译；后续新增验证不回填为该版本发布前的证据。

Mooncakes：`mik1e80/dnssd@0.1.0`。公开根包：`mik1e80/dnssd`；Native 包：`mik1e80/dnssd/src/native`。

源码标签固定在 `2b922d6ac0db5c6261aea917545776dfc488b1ec`。附带的 module ZIP 与 Mooncakes 发布归档相同，SHA256 为 `817c7abe72ca359cfac067e751db30a4f17c4fef8c76fa02b77dcd31f668a71b`。独立工程安装及 116 个文件一致性检查通过。

当前首版不包含服务发布者、IPv6 组播、子类型、NSEC 负缓存、多包 Known-Answer 或完整 SRV 权重选择；单播接收明确排除。完整支持范围与证据见仓库 `docs/SCOPE.md`、`docs/verification.md`。
