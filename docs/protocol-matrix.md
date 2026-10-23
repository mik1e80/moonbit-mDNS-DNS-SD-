# 当前协议矩阵

参考：[RFC 6762](https://www.rfc-editor.org/info/rfc6762)、[RFC 6763](https://www.rfc-editor.org/info/rfc6763)、[RFC 8553](https://www.rfc-editor.org/info/rfc8553)。本表是首轮实现记录，不是完整规范审计。

| 事项 | 实现/证据 | 状态与限制 |
| --- | --- | --- |
| 标签与实例内点 | model/name.mbt，model_test | 原始字节、UTF-8 输入、长度边界、ASCII 比较 |
| TXT 键值 | model/txt.mbt，model_test | binary/flag/empty/first duplicate；无效键保留但不查询 |
| 压缩名称 | wire/decode.mbt，wire_test | 后向指针、循环/越界检查、256 步；完整边界矩阵待补 |
| PTR/SRV/TXT/A/AAAA | wire/decode.mbt，真实 zeroconf fixture | 有限解码；AAAA 尚无实网断言，不代表 IPv6 传输 |
| QU 与 cache-flush | Question/Record 各自独立字段 | 编解码分开；cache-flush 的缓存行为未实现 |
| RR TTL | UInt32 原值保留 | 尚未建立到期、刷新与计时逻辑；与 IP TTL 无关 |
| 未知 RR | Unknown(Bytes)，真实 NSEC fixture | 有界跳过；不解释 NSEC，不构成负缓存支持 |
| QM 查询 | qm_query，witness 实网记录 | 单问题组播编码；无抖动、退避与 Known-Answer |
| IP socket | native/socket.c，M0 报告 | IPv4 元数据；只有 Windows 同机实网证据 |
| 缓存接纳、RRSet、goodbye、flush 宽限 | 待 M2 | 未实现 |
| DNS-SD 聚合、事件、部分状态 | 待 M2 | 未实现 |
| 订阅、刷新、退避、取消 | 待 M3 | 未实现 |

首轮工程上限：包 9000 字节、每包问题与记录合计 256、单名称解码 256 步。它们是实现限制，不是 RFC 规定。缓存、查询和事件队列上限将在对应模块建立时另行冻结。
