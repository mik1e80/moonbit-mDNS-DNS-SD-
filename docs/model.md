# 名称和 TXT 模型

公开包：`mik1e80/dnssd/src/model`。

- `DnsName::from_utf8_labels` 接收已经划分好的标签。实例名 `中文.服务` 是一个标签，不能先按点拆分。
- `from_labels` 和 `labels` 保留任意原始字节；数组在 API 边界复制。标签长 1..63 字节，完整名称最多 255 wire 字节；空标签数组表示根。
- `same_name` / `canonical_key` 只折叠 ASCII 大小写，并保留标签长度边界。展示使用绝对转义形式，原始 UTF-8 可以从 `labels()` 取回。
- `TxtRecord` 保留条目顺序、二进制值、无值与空值。每条最多 255 字节，总 RDATA 最多 65535 字节。
- `lookup` 区分 Missing、Flag、Value；键按 ASCII 不区分大小写，重复键第一项胜出。无效键保留在原始条目中但不参与查询。

轻量验证：`scripts/moon.ps1 test src/model --target js --frozen --filter 'smoke:*'`，3 个测试覆盖中文标签内点、二进制/空值/重复键、损坏与超长输入。
