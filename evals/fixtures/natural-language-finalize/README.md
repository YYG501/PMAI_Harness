# Session Eval Fixture

这是一个脱敏、可重置的 PMAI 消费仓快照，用于验证自然语言定稿能在完整初始化和
`iterating` build 合同下完成 finalize。夹具保留真实消费仓的入口、Proposal、产品基线、
模块三件套、`project.yml`、实现代码和测试；历史审计、用户路径和外部服务均已移除。

Runner 只能在这个隔离工作区内执行。预期唯一业务文档变化是根目录
`PRODUCT-STATE.md`；模块规格与决定文件是保护路径，不能被 finalize 改写。
