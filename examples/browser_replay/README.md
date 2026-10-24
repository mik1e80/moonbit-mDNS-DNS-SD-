# 浏览器离线回放

这个示例把公开根包的 `Replay` 编译为 JavaScript，在本机浏览器中处理粘贴或加载的 JSONL。它不会扫描局域网、打开 socket、发送 outbound 查询或上传输入。

在仓库根目录构建（先按根 README 安装固定工具链）：

```powershell
.\scripts\build-replay.ps1
python -m http.server 8000 --bind 127.0.0.1 --directory .tools/browser-replay
```

打开 `http://127.0.0.1:8000`。也可直接打开生成目录中的 `index.html`；页面不使用 fetch、CDN 或 npm 依赖。`加载 JSONL` 可选择仓库的 `fixtures/live-20261024.jsonl`，或粘贴 CLI `--record` 产生的文件内容。内置小例子只展示订阅、待发查询与取消。

`config` 首帧恢复录制的完整 UInt32 seed；没有 config 时固定使用 1。每次点击都创建新引擎；重复运行相同输入，事件和待发查询保持一致。事件与 outbound 分列展示，点击条目可查看完整 JSON。损坏命令会显示原文件行号，损坏 DNS 报文按核心规则产生诊断。

示例输入限制为 8 MiB/10000 帧，单行和时间规则沿用 Replay；为控制页面内存，输出上限为 20000 条。较大的录制应使用 CLI。所有输出使用文本节点显示，服务名和 TXT 不作为 HTML 执行。

轻量检查只加载编译结果并调用相同回调，不需要浏览器或网络：

```powershell
node examples/browser_replay/smoke.cjs
```

它检查实际 fixture 的端口解析、重复运行一致、筛选后实网 fixture 的服务事件与公开证据相同、outbound 输出、完整 UInt32 config seed 恢复和错误行号，不运行全量测试。
