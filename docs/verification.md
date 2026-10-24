# 当前验证证据

状态日期：2026-10-24。验证采用按改动分批的轻量用例和受控短时实验，不在每一步全量运行所有后端。

## 纯核心与实际 CLI

截至录制实现 `f2baff7`，JS 有 29 个 `smoke:*` 用例：根 API 1、模型 5、wire 5、缓存 4、引擎/查询/resolve 11、回放 3。覆盖乱序、重复、范围隔离、goodbye/flush 宽限、到期、队列溢出、抖动/退避、剩余 TTL Known-Answer、resolve 超时、同毫秒更新和回放种子。部分引擎用例另外在 Wasm、Native 运行通过；没有全量运行所有后端。

`tests/interop/cli_smoke.py` 对实际 Windows CLI 二进制离线验证相同输入的两次回放、fixture 端口解析、TTL 到期的 unavailable/removed、移除后的 TTL=0/complete=false、非法参数退出、help/version 和完整 UInt32 种子恢复。构建通过不等于实网通过。

后续另补三项定向回归，验证同一 tick 中不同服务的移除原因和范围隔离；同时失效的 goodbye 与自然 TTL 到期不会互相覆盖。公开实网 fixture 的两次回放及完整服务事件对照也已纳入离线 CLI 冒烟。

提交前执行 `moon info` 和 `moon fmt`，检查公开 `.mbti`；复现命令见 [开发文档](development.md)。原始 zeroconf 报文来源见 [fixtures](../fixtures/README.md)。

浏览器示例的编译回调另有 Node 轻量检查，真实录制的六个服务事件与公开报告逐项一致。真实浏览器还检查了内置查询示例和实际报文产生的 seen/resolved/unavailable/removed 列表；页面仅展示待发查询，不发送网络请求。

## Windows 实网闭环

公开报告：[windows-live-20261024.json](evidence/windows-live-20261024.json)。源提交为 `f2baff7786e6199bfae105a2f81de62313b30672`，实验开始时工作树干净。环境为 Windows 11、Python 3.12.14、python-zeroconf 0.148.0；发布者是同一台机器上的独立 Python 进程。

8 项检查全部通过：

1. MoonBit 主动发现独立实现发布的合成服务。
2. HTTP 示例使用发现的动态端口请求 `/moondiscover-demo` 并验证返回 token。
3. CLI 实时输出 TXT 属性更新事件。
4. 观察 goodbye 后服务移除。
5. browse、HTTP、doctor、cancel 进程均成功退出。
6. 异步取消关闭 Browser，随后可重开 socket。
7. 录制文件两次离线回放产生相同结果。
8. 回放的该服务事件序列与实网观察一致（比较时只移除观测时间字段）。

导出的 [live-20261024.jsonl](../fixtures/live-20261024.jsonl) 经过合成服务名称白名单检查，保留配置、时钟和命令帧。该次录制只有本项目合成服务的报文，实际排除数为 0；导出样本与原 trace 的 SHA256 相同，均在报告中记录。分享其他录制仍须逐次检查。报告中的 TTL/端口/IP 是该次实验观测值。

最初的 [M0 传输报告](transport-spike.md) 保留了单播未收到、整体退出码 1 的历史结果。当前 Browser 明确限定 IPv4 QM 组播，后续闭环成功不将该历史失败改成通过。

另有约两秒的[超长报文回归](evidence/windows-oversized-20261024.json)：发送 9001/16000 字节组播后，浏览器继续解析随后的自建合法响应并正常完成观察窗口。报告记录修复尚未提交时的工作树状态与二进制 SHA256，代码已保存为 `7b9ad71`。此测试验证传输鲁棒性，独立实现互通仍以前述 zeroconf 实验为证据。

## GitHub CI

[轻量工作流](../.github/workflows/ci.yml) 在 Linux 运行核心 JS 冒烟并编译 Native 探针、CLI、HTTP/事件示例和取消验证程序；Windows 编译这些入口并运行离线 CLI 冒烟。普通 runner 不进行局域网实验。

提交 `f2baff7` 的 [39989994807](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/39989994807) 两项检查成功。该链接证明对应提交的检查成功；后续变动以各自 Actions 记录为准。

## 结论的范围

Windows 证据是同机独立进程互通，没有第二设备、Avahi 或 Linux 实网证据。Linux Native 只有 CI 编译证据。没有完整 RFC 审计、所有平台全量测试或长时间压力验证。

Mooncakes 发布与已发布包的仓库外消费尚待记录。源码工作区外的本地消费与注册表发布包消费是两种不同证据，前者不能代替后者。
