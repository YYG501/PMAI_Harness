# 测试套

验证 INVARIANTS.md 里定义的不变式。每个不变式有至少一个反例测试（故意违反，验证脚本正确拒绝而不是破坏数据）。

## 运行

```bash
# 跑所有测试
bash tests/run-all.sh

# 跑单个脚本的测试
bash tests/test-close-work.sh
bash tests/test-check-branch.sh
bash tests/test-cancel-work.sh
```

## 目录结构

```
tests/
├── README.md                    # 本文件
├── run-all.sh                   # 跑所有测试
├── helpers/
│   ├── assert.sh                # assert_equal, assert_fail 等断言
│   └── fixture.sh               # setup/teardown：创建假项目结构
├── fixtures/
│   └── (运行时临时目录)
├── test-close-work.sh
├── test-check-branch.sh
└── test-cancel-work.sh
```

## 测试约定

- 每个测试函数名以 `test_` 开头
- 每个测试独立创建和清理 fixture（不共享状态）
- 断言失败立即 `exit 1` 并打印失败原因
- 成功测试打印 `✅ <test-name>`
- 失败测试打印 `❌ <test-name>: <reason>`

## 不变式覆盖矩阵

参考 `INVARIANTS.md`。关键不变式（如 I-INIT、I-PD、I-ACC、I-CB、I-CR）均由正例和反例测试覆盖。
