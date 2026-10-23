# M0 依赖决策（2026-10-23）

## 固定输入

- 本机 moon 0.1.20260920 (914d7da)、moonc v0.10.14+7d59c7ec9。
  实际安装 0.22.5 后发现旧 moon 不识别 `max_concurrent_tests`，因此在项目 `.tools` 固定新版 moon 0.1.20261023 / moonc v0.10.17+d971670cd，已实际编译通过；全局工具链未变。归档散列见 `toolchain.json`。
- 安装包 moonbitlang/async 0.22.5，Apache-2.0。上游核对提交 `021e5c1fbb782485eb6086d6c8c74009ca75b1d6`。发布包与该提交不能未经比对直接认定相同。
- moon-dns-stub 核对提交 `d68d543f41b8f4b383df3efec2d50ef3b9590b0c`，版本 0.1.0，Apache-2.0。
- RTC 核对提交 `0d823a5d5da14eae526b37b9dae905f1e3bc72ff`。

## Codec 选择

先核对 [现有包配置](https://github.com/jinshengmeng46/moon-dns-stub/blob/d68d543f41b8f4b383df3efec2d50ef3b9590b0c/src/moon.pkg)、[名称实现](https://github.com/jinshengmeng46/moon-dns-stub/blob/d68d543f41b8f4b383df3efec2d50ef3b9590b0c/src/name.mbt) 和 [RDATA](https://github.com/jinshengmeng46/moon-dns-stub/blob/d68d543f41b8f4b383df3efec2d50ef3b9590b0c/src/rdata.mbt)。

该包将 codec 和 async resolver 放在同一 Native 包；直接依赖会限制本项目核心后端。名称 API 使用转义后的 octet String，可以通过逐 UTF-8 字节转义适配中文与标签内点，并非完全不支持这些输入。TXT 也可逐字节适配，而不是直接传任意 Unicode String。

可行选项是提炼独立 codec 包，但这需要维护外部模块的一组相关文件，且尚无已发布的可移植子包。本版选择自行实现 DNS-SD 所需的有限 wire 子集，不复制现有实现，不另立通用 DNS 项目。仅覆盖名称、问题、PTR/SRV/TXT/A/AAAA，以及有界跳过未知 RR；后续使用独立实现和反例校对。未来出现可移植发布包时重新评估。

## 网络依赖风险

实际安装的 async 0.22.5 中：

- `UdpServer::multicast` 支持共享组播监听，但 `sendto` 会明确拒绝通过该 socket 发包。
- 普通 `UdpServer` 支持发送，但构造 API 没有供调用方配置复用端口的参数。
- `recvfrom` 返回报文长度和来源地址，不返回入站接口、目标地址或 IP TTL。

因此不能仅靠调用普通 API 就声称完成 5353 共存、收发与来源范围。先用 `cmd/transport_spike` 实际验证；随后选择最小 Native socket 扩展。扩展只负责系统调用和元数据，协议与缓存保留在 MoonBit。

参考：[固定 UDP 源码](https://github.com/moonbitlang/async/blob/021e5c1fbb782485eb6086d6c8c74009ca75b1d6/src/socket/udp.mbt)。
