# MoonDiscover

MoonBit DNS-SD 服务发现库，拟发布模块 `mik1e80/dnssd`。

状态：M0 风险验证与 M1 基础实现进行中。已实现名称/TXT 模型、有限 wire 解码和 QM 查询编码；Windows 本机独立发布者组播收发、基础解析与接口元数据已有证据。尚未完成缓存、服务聚合和连续发现，也未发布 Mooncakes 包。版本字段 `0.1.0` 是目标版本。

目标是通过 `_http._tcp.local.` 等服务类型，获得实例、主机、端口、TXT、地址，并持续报告变化。纯协议核心与网络入口分离，首版实时网络面向 Native；浏览器只做后期离线回放。

## 使用场景

- 本地开发：发现 HTTP 服务，使用发现的实际端口请求演示端点。
- 桌面伴随程序：观察实例出现、属性更新、撤销和记录到期。
- 局域网盘点：按指定服务类型观察，并导出有来源范围的结果。

## 文档

- [完整实施计划](docs/implementation-plan-20261023.md)
- [当前进度及下一步](docs/progress.md)
- [首版范围](docs/SCOPE.md)
- [生态对比](COMPARISON.md)
- [开发环境与轻量测试](docs/development.md)
- [真实传输验证与限制](docs/transport-spike.md)
- [协议实现矩阵](docs/protocol-matrix.md)

## 当前可运行入口

Windows 安装 C++ 工具和 Windows SDK 后：

```powershell
.\scripts\bootstrap.ps1
.\scripts\moon.ps1 run examples/encode_query --target js
.\scripts\moon.ps1 test dnssd_test.mbt src/model src/wire --target js --filter 'smoke:*'
```

示例使用公开根包 API 编码并解码 `_http._tcp.local.` 的 QM PTR 查询；它不启动浏览器或扫描局域网。实网探针及独立发布者复现方式见传输验证文档。

首轮 [GitHub 轻量 CI 已通过](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/39977741559)：9 个核心冒烟测试、Windows/Linux Native 编译。其结果不代表 Linux 实网互通或完整 RFC 支持。

## 开发约定

采用有实际成果的小步提交，每个 commit 对应可复查的行为或文档决策。轻量验证只覆盖当前变更，不在每一步全量运行全部后端和互通矩阵。完整验收证据另按里程碑记录。

许可证：Apache-2.0。第三方代码或样本引入前记录来源和许可。
