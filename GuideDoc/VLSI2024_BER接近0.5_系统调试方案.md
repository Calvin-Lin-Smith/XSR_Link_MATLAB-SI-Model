# VLSI2024 XSR BER≈0.5 解决实施方案

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:systematic-debugging` for evidence and `superpowers:test-driven-development` for each fix. Execute in order with Luna workers. Per user request, no independent review is required; every task must provide RED/GREEN evidence and a commit.

**Goal:** 从 canonical TX DAC 源头修复 BER≈0.49，将整个 VLSI2024 x8 link 迁移到唯一的 Gray-coded PAM4 contract，并使四电平、CDR lock、checker 对齐、训练目标和 regression PASS 使用同一条可信证据链。

**Architecture:** 工程内部只保留 `00→-3、01→-1、11→+1、10→+3` 这一套 Gray PAM4 contract。TX DAC 不再把逻辑 outer level 从 `±3` 压成 `±1`；物理 swing 与逻辑幅度分开记录。通道/AFE 可以产生连续失真波形，但在 sampler/CDR 判决前必须显式恢复到 PAM4 logical units；随后补偿 checker 的整数 UI lag，拒绝缺少四电平或尾部失锁的 CDR 状态，再让 CTLE/FFE 训练使用四电平目标。

**Tech Stack:** MATLAB R2024b；现有 `D2DPHY` 分层、assert tests、CSV/MAT artifacts；不增加第三方依赖。

**Spec:** `../../20260926_Paper_Reappear&Power-On/VLSI2024_XSR_SerDes_建模逐步实施方案.md`；论文 `../../20260926_Paper_Reappear&Power-On/Paper4Reappear/A_0.9pj_b_9.8-113Gb_s_XSR_SerDes_with_6-tap_TX_FFE_and_AC_coupling_RX_in_3nm_FinFet_Technology.pdf`。

## Global Constraints

- 所有逻辑 PAM4 映射固定为 Gray code：`00→-3、01→-1、11→+1、10→+3`，对应 levels `[-3,-1,1,3]` 和 thresholds `[-2,0,2]`。
- 不保留 natural-binary PAM4 配置开关或 legacy 旁路；所有 profile、GUI、Simulink、tests 和 artifacts 同步迁移，避免两套映射共存。
- analog waveform 可以缩放/失真，但进入 sampler/CDR 判决前必须显式恢复到 logical PAM4 units。
- `levelShiftCodes` 是 DAC/control code，不是 PAM4 symbol 或 threshold。
- CDR/PI 不得读取 TX reference bits；reference 只允许 checker 做同步和 BER。
- legacy `typical`/`ideal`、零参数 `run_all_tests()` 和 T1-T9 必须保持兼容。
- 有限样本只报告 empirical BER/UCB，不声称复现论文极低 BER。
- 每个任务一次只验证/修复一个根因；P0 电平契约完成前不调 CTLE/FFE/CDR 参数。

## 已确认根因

当前 canonical 结果不是 bit mapping 或 lane 串接错误，而是以下问题叠加：

1. **主因：幅度/阈值单位矛盾。** Driver 将 PAM4 outer level 压到约 `±1`，AFE samples 约为 `[-1.1,1.1]`，而 `Slicer`/`dspBbCdr` 仍用 logical thresholds `[-2,0,2]`。结果 decision trace 只有 `-1/+1`，outer levels 完全消失。
2. **主因：无效状态也能 lock/PASS。** 当前 lock 只看 transition、phase residual 和 PI span；二电平数据仍能 lock。`baseline_cdr_pi` 也没有 BER 或四电平门槛。
3. **测量问题：checker 没有 integer UI alignment。** 8 dB waveform 的最佳诊断 lag 约为 `+1 UI`；只修 lag 不能根治，但不修会继续把正确 symbol 与错误 PRBS 位置比较。
4. **次因：AC pre/post 使眼质量进一步下降。** AC off 在正确 phase/lag/threshold 下可显著改善，说明当前 corner/leveling 组合过强。
5. **训练目标错误。** 当前 objective 只计算“已经出现的 levels”；只有 `-1/+1` 时不会受罚，CTLE training 会优化成二电平眼。

当前 natural-binary TX/RX LUT 彼此一致，因此它不是现有 BER≈0.49 的直接原因；但用户已要求全链路迁移到 Gray mapping。PRBS、Serializer 和 lane routing 不重写，PAM4 mapper/slicer/CDR/checker 的映射与相关 tests/artifacts 必须整体迁移。

## 不可违反的 PAM4 契约

```text
bit pairs: 00   01   11   10
symbols:   -3   -1   +1   +3
thresholds:    -2    0    +2
```

- `dspMap`、`dspSlice`、`Slicer`、`dspBbCdr`、checker、training objective、Simulink 和 artifacts 全部使用这套 Gray contract。
- 相邻 level 的 bit pair Hamming distance 必须始终为 1；测试必须直接验证 `00↔01↔11↔10`。
- analog waveform 可以被缩放/滤波，但进入判决前必须通过显式 leveling 转回 logical units。
- `targetSwing` 是物理/行为 swing metadata，不得把逻辑 alphabet 改成 `[-1,-1/3,1/3,1]`。
- `levelShiftCodes` 是 DAC/control code，不是 PAM4 symbol 或 threshold。
- 禁止把全局 thresholds 直接改成当前诊断最优的 `[-0.4,0,0.4]`；那只是证明 scale mismatch 的实验。
- CDR 不得使用 TX reference bits；reference 只允许 checker 做同步与 BER。

## 解决顺序

```text
Fix 1: 统一 PAM4 contract 与 Driver 内部幅度
  -> Fix 2: RX blind leveling，恢复四个 logical levels
  -> Fix 3: checker integer UI alignment
  -> Fix 4: 有效 CDR lock + 四电平 training objective
  -> Fix 5: 收敛 AC corner并强化 regression
```

Fix 1–2 完成前，不调 CTLE、FFE 或 CDR bandwidth。

---

### Task 1: 统一 PAM4 contract 和 Driver logical amplitude

**Files:**

- Create: `src/dsp/dspPam4Contract.m`
- Modify: `src/dsp/dspMap.m`
- Modify: `src/dsp/dspSlice.m`
- Modify: `src/dsp/dspBbCdr.m`
- Modify: `src/leaf/Slicer.m`
- Modify: `src/leaf/Driver.m`
- Modify: `src/config/phyConfig.m`
- Test: `test/test_vlsi2024_pam4_contract.m`

**Required solution:**

1. 新增唯一的 contract helper：

```matlab
function c=dspPam4Contract()
c=struct('levels',[-3 -1 1 3],...
    'thresholds',[-2 0 2],...
    'bitPairs',[0 0;0 1;1 1;1 0],...
    'outerLevel',3);
end
```

2. 删除 `dspMap`、`dspSlice`、`Slicer` 和 `dspBbCdr` 中重复的 PAM4 LUT/threshold literals，统一读取 contract；更新全部 PAM4 expected vectors、T1-T9、GUI/Simulink 和保存 artifacts，不保留 natural-binary 分支。
3. paper Driver 的内部输出保持 PAM4 logical amplitude：swing calibration 把 outer code 恢复到 `±3`，206-level quantization 在 `[-3,3]` 内进行，logical DAC step 为 `6/(206-1)`。
4. 将物理 swing 与逻辑幅度彻底分开：`targetSwing`/physical swing只进入 calibration metadata 和 trained-parameter report；传给 Channel 的 paper waveform使用 logical units。`dacMeta` 同时保存 `logicalOuterLevel=3`、logical step、physical target和gain residual，不能再用physical target作为logical clipping bound。
5. legacy NRZ 和 quantization-off 数学路径保持原行为；旧 natural-binary PAM4 expected values属于有意迁移，必须同步更新而不是保留兼容旁路。

**RED test:**

```matlab
function test_vlsi2024_pam4_contract()
c=dspPam4Contract();
bits=[0 0 0 1 1 1 1 0]';
assert(isequal(dspMap(bits,'PAM4'),c.levels'));
assert(isequal(dspSlice(c.levels','PAM4'),bits));
assert(all(sum(xor(c.bitPairs(1:3,:),c.bitPairs(2:4,:)),2)==1));
cfg=phyConfig('vlsi2024_xsr_typical');
d=Driver('d'); d.configure(cfg.txPma.lane);
y=d.run(c.levels');
assert(max(abs(y))>2.9 && max(abs(y))<=3);
end
```

**GREEN gate:**

- TX logical symbol/Driver output都覆盖四个 canonical levels；
- `00→-3、01→-1、11→+1、10→+3` 在 mapper、Slicer、CDR 和 Simulink round-trip 完全一致；相邻码字只差1 bit；
- `dacMeta.logicalOuterLevel==3`，physical target变化不会把paper logical waveform压回`±1`；
- `unique(decisionTrace)` 不再因为 Driver scale 固定塌成 `[-1,1]`；
- NRZ/legacy non-PAM4 tests保持通过；所有旧PAM4 natural-binary断言已同步迁移到Gray expected values。

**Commit:** `Fix PAM4 logical amplitude contract`

---

### Task 2: 在 sampler/CDR 前加入 blind RX leveling

**Files:**

- Create: `src/dsp/dspPam4Leveling.m`
- Modify: `src/leaf/Slicer.m`
- Modify: `src/dsp/dspBbCdr.m`
- Modify: `src/composite/RxLane.m`
- Modify: `src/config/phyConfig.m`
- Test: `test/test_pam4_leveling.m`

**Required solution:**

1. 输入只使用 RX samples，不使用 TX bits。
2. 用确定性的四 cluster 估计得到 raw centroids、occupancy、offset 和 scale。
3. 将 raw samples 显式转换为 logical decision input：

```text
logicalDecisionInput = (rawSamples - levelingOffset) * levelingScale
```

使四个 centroid 对齐 `[-3,-1,1,3]`，然后仍用 thresholds `[-2,0,2]`。
4. raw waveform、logical input、centroids、scale 和 occupancy 分开保存；不能覆盖原始 probe。
5. 若任何 cluster occupancy 低于门槛或 centroid 顺序塌缩，返回 `levelsValid=false`，不得伪造 outer levels。
6. leveling只改变waveform单位，不改变Gray bit mapping；输出decision仍只能是logical `[-3,-1,1,3]`，随后由共享contract解码为`00/01/11/10`。

**RED test:**

```matlab
levels=repelem([-3;-1;1;3],128);
raw=0.35*levels+0.17;
[logical,meta]=dspPam4Leveling(raw);
assert(meta.levelsValid);
assert(max(abs(meta.logicalCentroids-[-3 -1 1 3]))<0.15);
assert(all(ismember([-3 -1 1 3],unique(meta.decisions)')));
```

Two-level input `repelem([-1;1],256)` 必须返回 `levelsValid=false`。

**GREEN gate:**

- canonical Typical post-lock decision trace出现 `[-3,-1,1,3]`；
- four-level occupancy 每个 level 均大于配置门槛；
- BER 可以暂时仍偏高，但不能再接近“固定丢失 outer bits”的 0.5 状态。

**Commit:** `Add blind PAM4 RX leveling`

---

### Task 3: 在 BER checker 中补偿 integer UI lag

**Files:**

- Modify: `src/composite/RawPcs.m`
- Modify: `src/composite/D2DPHY.m`
- Modify: `test/run_vlsi2024_xsr.m`
- Test: `test/test_checker_ui_alignment.m`

**Required solution:**

1. 保持旧接口 `check(rxBits,skipUI)`；新增可选 paper checker path，搜索 bounded integer UI lag。
2. PAM4 只允许以 2-bit/UI 为单位移动。odd-bit 最优表示 framing 错误，必须报 invalid，不能静默采用。
3. 用 post-lock window 前的一小段 sync bits 选择 lag；冻结 lag 后，在独立 measurement bits 上计算 BER，避免用同一数据选择并评价。
4. 输出 `checkerLagUI`、`syncBits`、`measurementBits`、`alignmentValid`。
5. 该逻辑只存在 checker；改变 reference bits 不得改变 CDR phase/code/lock trace。
6. checker比较的是Gray-decoded RX bits与原始PRBS bits；不得在checker中再次做natural/Gray转换。

**RED test:**

```matlab
ref=dspPrbs([31 28],4096);
rx=[zeros(2,1);ref(1:end-2)];
% paper checker must report checkerLagUI=1 and zero measurement errors
```

**GREEN gate:**

- 当前 8 dB case记录约 `+1 UI` lag或新的实测值；
- lag correction 后 BER明显优于lag=0；
- CDR trace在checker alignment前后完全相同。

**Commit:** `Align paper BER checker by integer UI`

---

### Task 4: 拒绝 PAM4 假锁并修正训练目标

**Files:**

- Modify: `src/dsp/dspBbCdr.m`
- Modify: `src/composite/RxLane.m`
- Modify: `test/run_vlsi2024_xsr.m`
- Test: `test/test_bb_cdr_pam4_valid_lock.m`
- Test: `test/test_adaptation_requires_four_levels.m`

**Required solution — lock:**

- 区分 `everLocked`、`currentlyLocked`、`lockLossCount`；最终 BER 只认 measurement tail 的 `currentlyLocked`。
- PAM4 lock 需要：四 cluster有效、occupancy足够、minimum logical eye margin合格，再叠加 transition/PI stability。
- two-level/constant waveform不得 lock；lock 后 level collapse必须清除 current lock。
- 记录 PI unwrapped code/sample time和cycle slips，避免 `63->0` wrap无记录地重复/跳过 UI。

**Required solution — adaptation:**

替换只看现存 levels 的 objective：

```text
valid = all(fourOccupancies >= minOccupancy)
separation = min(diff(logicalCentroids))
noise = max(withinClusterSigma)
objective = separation / max(noise,eps) - occupancyPenalty
```

缺少任何 canonical level时objective必须invalid/极低。Sampler leveling先于CTLE/FFE candidate评分，每个candidate重新估计四电平。

**GREEN gate:**

- “locked但只有2 levels”测试失败并被拒绝；
- 当前 measurement window 8 lanes全部 `currentlyLocked=true`；
- CTLE=0不能仅靠二电平margin获胜；winning candidate必须four-level valid；
- no-lock仍返回invalid BER/eye。

**Commit:** `Require valid PAM4 levels for CDR and training`

---

### Task 5: 收敛 AC coupling 并强化 canonical regression

**Files:**

- Modify after short sweep: `src/config/phyConfig.m`
- Modify only if formula is wrong: `src/dsp/dspAcCouple.m`
- Modify: `test/run_vlsi2024_regression.m`
- Modify: `src/utils/validate_vlsi2024_artifacts.m`
- Test: `test/test_vlsi2024_ac_solution.m`
- Test: `test/test_regression_rejects_random_ber.m`

**Required solution — AC:**

Fix 1–4 通过后，只运行下面的小矩阵：

```text
cornerRelNyq = [1e-4, 3e-4, 1e-3, 3e-3, 1e-2]
mode = pre-only, post-only, pre+post
```

保持其他参数不变，选择能保留四电平、tail lock和正eye margin的最高可解释corner。论文未公开该值，结果必须标成model-selected assumption。不能以永久关闭AC作为paper default。

**Required solution — regression:**

将 `baseline_cdr_pi` 拆成真实 gates：

```text
pam4_contract_pass
gray_adjacency_pass
tx_dac_logical_scale_pass
four_levels_valid
tail_lock_pass
checker_alignment_pass
ber_sanity_pass
artifact_schema_pass
```

初始 BER sanity ceiling 设为 `<0.25`，用于拒绝随机猜测；这是模型门槛，不是论文 BER。修复稳定后再根据实测结果决定是否收紧到 `<0.05`。

Validator必须保存并检查：mapping=`gray_00_01_11_10`、logical outer level、physical target swing、raw/logical centroids、occupancy、leveling scale、current lock、lock losses、checker lag、errors/bits/BER/UCB。

**Final GREEN gate:**

1. `VLSI Ideal`：BER=0，四电平有效，tail lock有效，lag=0。
2. `VLSI Typical` 1 lane：BER显著低于0.25，四电平有效。
3. canonical x8：8 lane全部four-level valid且tail locked；aggregate BER低于0.25，不再允许0.49仍PASS。
4. 0.5/2/4/6/8/10 dB 保留合理趋势；每行记录有限样本UCB。
5. Gray adjacent-level error测试只产生1 bit error；natural-binary `01↔10` 双bit相邻矛盾在全仓不存在。
6. T1-T9保持9/9；PAM4 expected mapping有意更新为Gray，NRZ/结构行为不回归。

**Commit:** `Close VLSI2024 PAM4 link regression`

---

## 全链路修复完整性矩阵

任何一行未完成，都不能声称当前问题已经解决。

| 边界 | 必须修改/确认 | 防止的矛盾 | 验收证据 |
|---|---|---|---|
| PRBS → mapper | `dspMap`使用Gray contract | TX仍输出natural binary | 四组bit pair精确映射 |
| Mapper → FFE | FFE只处理logical amplitudes，不重编码 | tap后误把幅度当bit code | impulse/round-trip test |
| FFE → TX DAC | paper DAC在`[-3,3]` logical域量化；physical swing单独记录 | canonical TX被压到`±1` | Driver levels、step和metadata |
| DAC → Channel | Channel输入单位明确为logical amplitude | channel loss与physical volts混用 | TX pad probe + unit metadata |
| Channel → AFE | raw连续波形保留，不假装仍是理想四值 | 失真波形被错误标成symbols | raw probe/centroid table |
| AFE → sampler leveling | blind offset/scale恢复logical units | raw `±1`直接比较`±2` | raw/logical centroids和scale |
| level-shift → thresholds | codes与logical thresholds分开 | `+2/0/-2`被当symbol/volt | 独立code、scale、threshold字段 |
| sampler → CDR | CDR decision使用共享Gray contract | Slicer与CDR LUT不一致 | 相同samples产生相同decisions/bits |
| CDR lock | 四电平valid + tail lock + slip统计 | 二电平假锁、历史lockIndex假阳性 | occupancy/currentLock/lossCount |
| RX bits → checker | bounded integer UI同步后冻结lag | PRBS错位造成BER≈0.5 | sync lag与独立measurement BER |
| CTLE/FFE training | 每个candidate重新leveling并要求四电平 | 二电平margin成为最优 | candidate validity/objective trace |
| BER/eye窗口 | first-valid-lock 后加 guard 的统一 x8 窗口；后续 unlock/invalid/slip 使 measurement invalid | pre-lock 样本污染性能或 latest/reacquisition 重选窗口 | measurementStartUI/sample |
| regression | Gray/scale/levels/lock/lag/BER分别设gate | 流程跑通但BER≈0.5仍PASS | 分项summary和negative test |
| artifacts | 旧natural mapping artifacts全部重建 | 新代码配旧CSV/MAT | mapping/version字段 + validator |
| GUI | 不提供mapping切换；显示Gray contract和raw/logical probes | 用户选出第二套映射 | VLSI presets与parameter report |
| Simulink | block统一调用更新后的mapper/slicer/Driver contract | MATLAB修好而Simulink仍natural | temporary model round-trip |
| GuideDoc/README | 示例、参数、结果字段全部改为Gray | 文档继续传播natural mapping | link/keyword self-check |

### 原子迁移规则

Gray mapping不能分两次合入。Task 1的mapper、slicer、CDR LUT、tests、Simulink引用和文档必须在同一批次同时切换；中间状态不生成canonical results。所有旧`results/vlsi2024_xsr`文件在最终full run前视为旧mapping快照，不得与新代码混合解读。

### 端到端负测试

最终至少保留以下会在任一层漏修时失败的测试：

1. 四个Gray code round-trip；
2. 三组相邻level Hamming distance均为1；
3. paper Driver physical target设为1时，logical output outer level仍为3；
4. raw waveform缩放到0.35并加DC offset后，leveling恢复`[-3,-1,1,3]`；
5. two-level collapse不能lock/不能进入BER-valid；
6. known `+1 UI` shift由checker恢复，odd-bit shift被拒绝；
7. adaptation不能选择缺少outer levels的candidate；
8. 保存的canonical BER≥0.25时regression必须失败；
9. GUI/Simulink/CLI对同一Gray vector输出相同bits。

---

## 最小执行批次

### Batch A — 先解决四电平塌缩

- Task 1：统一 `[-3,-1,1,3]` contract和Driver logical amplitude。
- Task 2：blind RX leveling恢复四电平。
- 验收：decision trace必须出现四个canonical levels。
- 验收：全链路Gray mapping唯一，TX DAC不再把logical outer level压到±1。

### Batch B — 让BER统计与lock可信

- Task 3：checker integer UI lag。
- Task 4：tail lock、level-valid lock和四电平training objective。
- 验收：不能再“二电平也lock”，BER明显低于随机。

### Batch C — paper路径收尾

- Task 5：AC corner小矩阵、regression gates、x8 canonical。
- 验收：canonical不再以BER≈0.5通过，T1-T9不回归。

## 明确不做

- 不重写PRBS、Serializer或lane routing；PAM4 LUT按本方案原子迁移到Gray，并删除natural-binary旁路。
- 不用`dspAlign`代替formal CDR。
- 不先调FFE/CTLE参数掩盖level contract错误。
- 不实现S参数、MIMO串扰、晶体管DLL/PI或功耗模型；它们不是当前问题的必要条件。
- 不在每个小改动后跑5分钟full regression；1 lane/8192 bits通过后，Batch C只跑一次canonical full。
