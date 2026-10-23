# 当前验证证据

## 轻量测试

按改动分批运行，累计 9 个 JS 冒烟用例：模型 3、手工 wire 用例 4、独立实现报文 1、公开根 API 1。没有在每个步骤全量运行所有后端。

示例实际输出：`QM PTR query: _http._tcp.local. (34 bytes)`。

`moon info`、`moon fmt` 已执行；Native 两个探针已在本机构建并运行。

## GitHub CI

首轮成功运行：[39977741559](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/39977741559)，提交 `acc75c66373436b4e694f2df89883835e534cd97`。

- portable-smoke：固定工具链、9 个 JS 冒烟、Linux Native 编译均成功。
- windows-native-build：固定项目工具链和 Windows Native 编译成功。

此链接只证明该提交的检查成功；后续提交的结果以各自 Actions 记录为准。普通 CI 没有运行真实局域网互通。

## 真实网络

见 [传输报告](transport-spike.md) 和原始 JSON；组播通过，单播未收到，总体实验退出码 1。

## 未验证/未交付

尚未发布 Mooncakes 包；没有仓库外已发布包消费证据；没有完整服务发现、状态变化或 HTTP 连接闭环。首版完整验收矩阵仍待后续阶段。
