GUI 中“Test Actions”区域的每个按钮，统一先经过 `D2DWorkbench.execute()` 包装，负责更新 Status、捕获异常和显示 Passed/Failed：

[gui/D2DWorkbench.m:380](E:/Desktop_use/D2D_Modelization/gui/D2DWorkbench.m:380)

| GUI 按钮            | GUI 回调函数         | 实际调用文件/函数                             | 说明                                                         |
| ------------------- | -------------------- | --------------------------------------------- | ------------------------------------------------------------ |
| **Loss Sweep**      | `runSweep('loss')`   | `gui/D2DWorkbench.m` 内部 `runSweep()`        | 使用当前配置，逐点修改 `c.channel.lossNyq_dB`，然后调用 `D2DPHY.run()`。结果写入 `results/gui_loss_sweep.csv`。 |
| **CTLE Sweep**      | `runSweep('ctle')`   | `gui/D2DWorkbench.m` 内部 `runSweep()`        | 逐点修改 `c.rxPma.lane.ctleBoost_dB`，调用 `D2DPHY.run()`。结果写入 `results/gui_ctle_sweep.csv`。 |
| **RJ Sweep**        | `runSweep('rj')`     | `gui/D2DWorkbench.m` 内部 `runSweep()`        | 逐点修改 `c.link.rjUI_rms`，调用 `D2DPHY.run()`。结果写入 `results/gui_rj_sweep.csv`。 |
| **CDR Sweep**       | `runSweep('cdr')`    | `gui/D2DWorkbench.m` 内部 `runSweep()`        | 设置 `clockMode='cdr'`，逐点修改 `c.link.cdrBw`，调用 `D2DPHY.run()`，同时计算 PLL residual phase RMS。结果写入 `results/gui_cdr_sweep.csv`。 |
| **FFE + CTLE Scan** | `runEqScan()`        | `gui/D2DWorkbench.m` 内部 `runEqScan()`       | GUI 自己实现 FFE pre/post/main 与 CTLE boost 的三重扫描，调用 `D2DPHY.run()`。结果写入 `results/gui_eq_sweep.csv`。 |
| **Behavior Suite**  | `runBehaviorSuite()` | `test/behavior_tests.m` 的 `behavior_tests()` | 执行 Loss、CTLE、RJ、CDR 四类行为趋势测试，生成 `behavior_loss.csv`、`behavior_ctle.csv`、`behavior_rj.csv`、`behavior_cdr.csv` 和 `behavior_results.mat`。 |
| **Standard T1-T9**  | `runRegression()`    | `test/run_all_tests.m` 的 `run_all_tests()`   | 执行完整 T1 到 T9 回归，并生成 `summary.csv`、`manifest.json`、`junit.xml`、`regression.mat` 等结果。 |
| **Run x8 Link**     | `runLink()`          | `src/composite/D2DPHY.m` 的 `run()`           | 不是 Test Actions 中的回归测试，而是运行一次完整的 8-lane PHY 链路，并更新 Metrics 和白盒波形。 |

GUI 按钮定义位置在：

[gui/D2DWorkbench.m:83-89](E:/Desktop_use/D2D_Modelization/gui/D2DWorkbench.m:83)

**Run x8 Link 的实际链路调用顺序**

`D2DPHY.run()` 位于：

[src/composite/D2DPHY.m:25](E:/Desktop_use/D2D_Modelization/src/composite/D2DPHY.m:25)

内部流程是：

```text
RawPcs.run()
    -> TxPma.run()
        -> TxLane / Ffe / Serializer / Driver
    -> Channel.run() x8
    -> RxPma.run()
        -> RxLane / Afe / Term / Ctle / Slicer / Deserializer / Pll
    -> RawPcs.check()
    -> 返回 BER、错误数、测量比特数和 rxBits
```

具体代码为：

- `rawPcs.run()`：生成测试数据和参考比特
- `txPma.run(syms)`：执行 x8 TX lane
- `channel(j).run(tx{j})`：逐 lane 通过通道
- `rxPma.run(ch, referenceBits)`：执行 x8 RX lane
- `rawPcs.check(rx, skipUI)`：统计 BER 和错误数

**T1-T9 中各项测试对应关系**

[T1-T9 主入口](E:/Desktop_use/D2D_Modelization/test/run_all_tests.m:1)

| 测试   | 实际函数/文件                            | 测试内容                                                     |
| ------ | ---------------------------------------- | ------------------------------------------------------------ |
| **T1** | `run_all_tests.m` 第 7-18 行             | 多种 baud、NRZ/PAM4、channel loss 组合，调用 `eyeHeight()` 和 `plotEye()` 检查眼高并生成眼图。 |
| **T2** | `behavior_tests.m` 的 `behavior_tests()` | 检查 channel loss 增加时 BER 上升。                          |
| **T3** | `run_all_tests.m` 第 24-38 行            | 手动进行 phase/offset 扫描，调用 `dspSample()`、`dspSlice()`，生成 bathtub 曲线。 |
| **T4** | `sweep_eq.m` 的 `sweep_eq()`             | 执行 FFE pre/post 与 CTLE boost 扫描，并调用 `ffeEqDb()` 检查 FFE dB 计算。 |
| **T5** | `behavior_tests.m` 的 `behavior_tests()` | 检查 CTLE boost 对 BER 和 eye height 的改善。                |
| **T6** | `run_all_tests.m` 第 47-57 行            | 测试 PRBS7、PRBS15、PRBS31、PRQS10 surrogate，并验证错误注入数量准确。 |
| **T7** | `run_all_tests.m` 第 59-65 行            | 相同 baud 条件下比较 NRZ 与 PAM4 BER。                       |
| **T8** | `behavior_tests.m` 的 `behavior_tests()` | 检查 CDR bandwidth 的 BER 最优点和 residual phase 最优点是否位于扫描区间内部。 |
| **T9** | `run_all_tests.m` 第 71-82 行            | 检查 x8 shallow loopback、serial lane loopback 和 two-endpoint die-to-die loopback。 |

需要注意两点：

1. **GUI 的 FFE + CTLE Scan 不直接调用 `test/sweep_eq.m`**，而是在 `D2DWorkbench.runEqScan()` 中实现了一套 GUI 专用扫描逻辑。
2. `test/test_dsp.m`、`test/test_leaf_classes.m`、`test/test_hierarchy.m` 目前不是 GUI 的独立按钮调用目标；它们属于独立的底层验收脚本。GUI 中的 **Standard T1-T9** 调用的是 `run_all_tests()`，而不是这三个脚本。
