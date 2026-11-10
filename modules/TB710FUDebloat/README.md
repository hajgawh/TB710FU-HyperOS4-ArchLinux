# TB710FUDebloat v1.5.2 — OS4 超级精简冻结

- 模块 ID：`tb710fu_os4_debloat`
- 版本：v1.5.2 / versionCode 8
- 目标设备：TB710FU，Android 侧 HyperOS `OS4.0.11.0.XPZCNXM`（piano / 25091RP04C）
- 实测基线：总 PSS 3.23 GB，MemAvailable 3.45 GB，ZRAM 换出 1.07 GB
- 日志：`/data/adb/tb710fu_os4_debloat/debloat.log`

三级精简：①按真机 PSS 实测冻结 30 个不用的系统包；②组件级冻结 6 个反诈组件；③iptables 在 DNS
层黑洞 4 个反诈上报域名。**只写模块，不主动冻结**：安装本身不生效，是否冻结由重启或手动执行决定。

## 1. 作用与边界

- 包级冻结只处理 `lists/packages.txt` 列出的 30 个包，其他包一律不碰；`PROTECTED` 名单再硬拦一层。
- 组件级冻结只处理 `lists/components.txt` 列出的 6 个组件；安全中心包级不冻。
- DNS 黑洞只拦 `lists/netblock.txt` 列出的 4 个域名的解析。
- 不写 system、不改 APK、不动 `/data` 里的应用数据；全部基于 `pm disable-user` /
  `pm disable 组件` / `pm uninstall --user 0` / `iptables`，均可逆。
- **这是唯一会改变用户应用状态的模块，安装前必须得到用户明确同意。**

## 2. 包级冻结清单（`lists/packages.txt`）

> PSS 为 2026-11-07 真机 `dumpsys meminfo` 实测（快照时刻未运行的包标“—”）。全部运行时合计约
> 1.11–1.27 GB，占当时总 PSS（3.23 GB）的约 34%。

### A. 小爱 / AI 认知（8 包，实测约 781 MB）

| 包名 | 作用 | 实测 PSS | 冻结影响 |
|---|---|---|---|
| com.miui.voiceassist | 超级小爱主进程（含 :core 子进程，370 MB private dirty） | ~676 MB（470+206） | 长按/语音唤醒小爱失效 |
| com.xiaomi.aicr | AI 认知/感知服务（cognition+perception 两进程），供小爱、负一屏、相册语义搜索调用 | ~105 MB | 相册 AI 搜图、相机 AI 识别退化（Aperture 不受影响） |
| com.miui.voiceassistProxy | 小爱代理入口（/product/data-app 注入） | — | 小爱入口彻底失效 |
| com.miui.voicetrigger | 语音唤醒（唤醒词监听） | — | “小爱同学”唤醒词不可用 |
| com.miui.audiomonitor | 音频监听（语音唤醒配套；也是「应用通话录音」功能宿主） | — | 应用通话录音失效 |
| com.miui.contentcatcher | 内容捕手（屏幕内容识别） | — | 长按识屏/内容提取失效 |
| com.xiaomi.aiasst.vision | AI 视觉服务（AiasstVision） | — | 视觉 AI 能力停用 |
| com.xiaomi.mibrain.speech | 小米大脑语音引擎 | — | 语音语义能力停用 |

### B. 账号 / 云 / 互联（10 包，实测约 212 MB）

前提：本机**未登录任何小米账号（Accounts: 0）**、无 SIM，此档基本空转。

| 包名 | 作用 | 实测 PSS | 冻结影响 |
|---|---|---|---|
| com.milink.service | 米联/妙享（:audio 进程） | ~68 MB | 妙享中心、音频流转失效 |
| com.miui.mishare.connectivity | 小米互传 | ~53 MB | 互传不可用（日常用 KDE Connect） |
| com.xiaomi.finddevice | 查找设备（MIUI core，**实际走按用户卸载**，见下） | ~42 MB | 远程定位/丢失模式不可用 |
| com.xiaomi.mi_connect_service | 妙享互联底层（设备发现/组网） | ~30 MB | 跨设备连接失效 |
| com.miui.cloudservice | 云服务 | ~20 MB | 小米云同步不可用 |
| com.miui.cloudbackup | 云备份 | — | 云备份不可用 |
| com.miui.micloudsync | 云同步引擎 | — | 相册/联系人等同步停止 |
| com.xiaomi.mirror | 投屏（妙播） | — | 投屏到电视不可用 |
| com.xiaomi.continuity.sdkapp | 互联 SDK（跨设备连续互通） | — | 应用接力类能力失效 |
| com.miui.vsimcore | 虚拟 SIM | — | 本机无 SIM，无感 |

### C. 负一屏 / 推送 / 快应用（6 包，实测约 230 MB）

| 包名 | 作用 | 实测 PSS | 冻结影响 |
|---|---|---|---|
| com.xiaomi.xmsf | 小米推送（主 + :services + :kit7 三进程） | ~152 MB | 小米系 App 推送收不到（米家/商城/游戏中心） |
| com.miui.personalassistant | 负一屏 / 智能助理 | ~72 MB | 桌面左滑负一屏失效 |
| com.xiaomi.xmsfkeeper | 推送保活器 | ~8 MB | 随 xmsf 冻结（禁用后曾有 ~7.5 MB 残留进程，重启应消失） |
| com.miui.hybrid | 快应用框架 | — | 快应用入口失效 |
| com.xiaomi.minigame | 小游戏中心 | — | 小游戏不可用 |
| com.xiaomi.gamecenter.sdk.service | 游戏中心 SDK | — | 小米渠道游戏登录失效（本机游戏不走此渠道） |

### D. 广告 / 统计 / 诊断（6 包，实测约 50 MB）

| 包名 | 作用 | 实测 PSS | 冻结影响 |
|---|---|---|---|
| com.miui.powerinsight | 耗电分析/电池健康 | ~22 MB | 设置内耗电统计页降级 |
| com.miui.analytics | OneTrack 统计上报 | ~15 MB | 遥测停止（预期） |
| com.miui.systemAdSolution | 系统广告 SDK | — | 系统广告消失（预期） |
| com.xiaomi.ab | AB 实验/云控 | — | 云控实验停止 |
| com.miui.misightservice | MiSight 体验计划/诊断 | — | 诊断上报停止 |
| com.miui.bugreport | 用户反馈/日志收集 | — | 反馈通道失效 |

### 特殊路径与保留项

- **com.xiaomi.finddevice**：MIUI core package，`pm disable-user` 被系统拒绝（SecurityException），
  `freeze.sh` 自动降级 `pm uninstall -k --user 0`（APK 在 /product 未动、数据保留），`status.sh` 显示
  `UNINSTALLED`；恢复 = `pm install-existing` + `pm enable`。
- **明确保留**：人脸解锁（com.miui.face）、joyose（游戏性能数据，《异环》在用）、metoknlp（网络定位，
  天气在用）、时区 provider、所有预装第三方 App。
- **包级不碰**：system_server / systemui / surfaceflinger / 桌面 / 壁纸 / **安全中心（包级，反诈走
  组件级）** / 安装器 / 蓝牙 / telephony / 输入法；脚本内 `PROTECTED` 名单硬拦。

## 3. 组件级冻结清单（`lists/components.txt`）

反诈能力全部长在 securitycenter（uid 1000，MIUI core，包级禁用被拦且会废掉管家）内部，所以走
**组件级 `pm disable 包/类`**——实测 MIUI 放行（只有包级才拦）：

| 组件 | 说明 | 级别 |
|---|---|---|
| `…xsof.frauddetection.service.MiFraudDetectionService` | 反诈常驻服务：监听截图/电话态/SIM/飞行模式/网络，写 fraud_detection_data.db，4 域名上报入口 | 必冻 |
| `…com.miui.antifraud.AntiFraudReceiver` | 反诈广播入口（PHONE_STATE / SCAN_RISKY_URL） | 必冻 |
| `…antifraud.PayActivityMonitorService` | 支付页监控（本机无 telephony，天然不触发） | 可选 |
| `…frauddetection.provider.FraudDetectionProvider` | 反诈数据外部查询接口 | 可选 |
| `…xsof.MiSafetyDetectService` | 安全检测（冻结后“安全检测”入口失效） | 可选 |
| `com.miui.guardprovider/…aiguard.AiGuardService` | AI 静默录屏服务（本机 4 前置本就不满足，双保险） | 可选 |

`…electricrisk.AiGuardPosterActivity`（反诈宣传页 UI）**不列入清单**：安全中心自己会禁用它
（本机无通话能力），且 `pm enable` 后会被系统改回 disabled，冻它没有意义。

实测（2026-11-07）：禁用后 kill `securitycenter.remote` 模拟重启——进程干净重启、fraud 服务不再拉起、
无崩溃、其余管家服务正常、DB 停止写入。完整依据见工作区 `os4-audit/OS4-反诈监控体系调研报告.md`。

## 4. 网络层兜底（`lists/netblock.txt`）

`iptables -m string --hex-string` 匹配 DNS 查询包（udp/tcp 53，v4+v6）的 QNAME 并 REJECT：

```
flash.sec.miui.com | fraud-detection.engine.miui.com | eps.caict.ac.cn | gateway-papa.cloud.weizhi.com
```

- QNAME 是长度前缀线格式，必须用 hex（清单内已附 `域名|hex`）；换域名用文件头注释里的 python 方法
  重新生成，注意标签长度字节数错一位就拦不住。
- **限制**：只拦“域名解析”；已缓存 IP 的连接、DoH 自带解析不受影响（组件冻结才是主控）。
- 副作用：flash.sec.miui.com 是安全中心共享域，病毒库更新/网址检测/游戏云配置会同时失效。
- iptables 规则重启即失：`service.sh` 按 `net_state`（默认 on）每次开机重建；
  `bin/netblackhole.sh on|off|status` 可独立控制。

## 5. 文件与状态

```text
TB710FUDebloat/
├── module.prop
├── service.sh            # 开机 boot_completed 后应用冻结；按 net_state 重建 DNS 黑洞
├── action.sh             # KernelSU“操作”按钮：冻结 <-> 恢复 切换
├── uninstall.sh          # 卸载模块时自动恢复全部包/组件并关闭 DNS 黑洞
├── lists/
│   ├── packages.txt      # 包冻结清单（只处理这里列出的包）
│   ├── components.txt    # 组件冻结清单（反诈 6 组件）
│   └── netblock.txt      # DNS 黑洞清单（域名|线格式hex）
└── bin/
    ├── common.sh         # 常量/日志/pm 封装/保护名单
    ├── freeze.sh         # 冻结包+组件+开黑洞；支持 --dry-run
    ├── restore.sh        # 恢复包+组件+关黑洞
    ├── netblackhole.sh   # DNS 黑洞 on|off|status（iptables 自定义链）
    └── status.sh         # 只读查看包/组件/网络兜底状态
```

状态文件：

- `/data/adb/tb710fu_os4_debloat/state`：`frozen` / `restored`，默认 `frozen`；
- `/data/adb/tb710fu_os4_debloat/uninstalled.txt`：走按用户卸载的包，restore 时自动 `install-existing`；
- `/data/adb/tb710fu_os4_debloat/net_state`：`on` / `off`，默认 `on`；restore 写 `off`；
- `/data/adb/tb710fu_os4_debloat/debloat.log`：操作日志；
- `/data/adb/tb710fu_os4_debloat/suspended.txt`：仅用于清理旧 suspend 记录，restore 会清空。

## 6. 安装 / 启用

```bash
# 方式一：KSU Next 模块页 -> 从本地安装，选择 TB710FUDebloat.zip
# 方式二：
adb push TB710FUDebloat.zip /data/local/tmp/
adb shell su -c 'ksud module install /data/local/tmp/TB710FUDebloat.zip'
```

安装后**不会立即生效**。生效有两条路：

1. 重启设备：`service.sh` 在 boot_completed 后执行冻结并重建 DNS 黑洞；
2. 手动执行（不重启）：

   ```bash
   adb shell su -c 'sh /data/adb/modules/tb710fu_os4_debloat/bin/freeze.sh'
   ```

执行前建议先 dry-run 看一遍：

```bash
adb shell su -c 'sh /data/adb/modules/tb710fu_os4_debloat/bin/freeze.sh --dry-run'
```

## 7. 验收

```bash
# 包/组件/网络状态（只读）
adb shell su -c 'sh /data/adb/modules/tb710fu_os4_debloat/bin/status.sh'

# 操作日志
adb shell su -c 'tail -n 60 /data/adb/tb710fu_os4_debloat/debloat.log'

# DNS 黑洞规则
adb shell su -c 'sh /data/adb/modules/tb710fu_os4_debloat/bin/netblackhole.sh status'

# 抽查：被冻结的包应出现在 -d 列表；finddevice 应显示 UNINSTALLED
adb shell 'pm list packages -d --user 0 | grep -E "voiceassist|xmsf|cloudservice"'
adb shell 'pm list packages -u --user 0 | grep finddevice'
```

`status.sh` 中 `FROZEN` = `pm disable-user` 生效，`UNINSTALLED` = finddevice 按用户卸载，
`enabled` = 未冻结，`not-installed` = ROM 里没有这个包。

## 8. 恢复 / 卸载

```bash
# 1) KernelSU 模块页点“操作”按钮（切换 frozen <-> restored）
# 2) 命令行
adb shell su -c 'sh /data/adb/modules/tb710fu_os4_debloat/bin/restore.sh'
# 3) 卸载模块：uninstall.sh 自动恢复
adb shell su -c 'ksud module uninstall tb710fu_os4_debloat'
```

`restore.sh` 会：恢复清单内 29 个被 disable 的包 + finddevice 的 `install-existing` + `pm enable`
6 个反诈组件 + 关闭 DNS 黑洞，并把 state 写成 `restored`（**重启后也不会再冻结**）。想重新冻结就点
一次 action 按钮或手动跑 `freeze.sh`。

单放行某个反诈组件：`pm enable <包>/<类>`（组件清单在 `lists/components.txt`）。

## 9. 设计要点与不要做

1. **所有 `pm` 调用必须 `</dev/null`。** pm 走 app_process，stdin 指向文件/管道时会必现
   `Failed transaction`；所有入口脚本也 `exec 0</dev/null` 断开 stdin。
2. **停用模块 ≠ 恢复。** KSU 的 disable 标记只是开机不再执行冻结，已经冻结/按用户卸载的应用状态
   还在；要恢复必须跑 `restore.sh`、action 按钮或卸载模块。
3. **finddevice 不要用 suspend。** 它是 MIUI core 包，`pm disable-user` 会被拒；改用
   `pm uninstall -k --user 0`，恢复用 `install-existing`。suspend 的 persistent 进程会被
   system_server 拉回，等于没冻。
4. **安全中心不要包级冻结。** 包级会废掉整个管家且被 MIUI 拦截；只冻 `lists/components.txt` 里的
   组件，包级名单保持 `PROTECTED`。
5. **DNS 黑洞的 hex 必须精确匹配 QNAME。** 标签长度字节错一位就拦不住；它只拦域名解析，已缓存 IP
   和 DoH 不受影响，组件冻结才是主控。
6. **卸载会自动恢复，但 PackageManager 没就绪时不会。** `uninstall.sh` 在 PM 未就绪时会打印警告并
   退出，开机后需手动 `restore.sh`。

## 10. 已知影响

| 冻结项 | 影响 |
|---|---|
| 小爱全家桶 | 长按/语音唤醒小爱失效；相册 AI 搜图、相机 AI 识别可能退化（Aperture 不受影响） |
| 云服务 / 查找设备 | 小米云同步、远程定位不可用（当前未登录账号，本就不可用） |
| 互传 / 妙享 / 投屏 / 米联 | 小米互传、妙享中心、投屏到电视不可用（日常用 KDE Connect） |
| xmsf 推送 | 小米系 App（米家/商城/游戏中心）收不到推送 |
| 负一屏 / 快应用 | 桌面左滑负一屏、快应用入口失效 |
| 广告统计 | 系统广告、统计上报、体验计划停止（预期行为） |
| 反诈 6 组件 | 反诈监听/DB 写入/上报入口停止；“安全检测”入口失效；安全中心其余功能不受影响 |
| DNS 黑洞 | 4 个反诈域名解析失败；flash.sec.miui.com 共享的病毒库更新/网址检测/游戏云配置同时失效 |

## 11. 排错

- 某包显示 `FAIL`：若报错含 `Cannot disable`/`SecurityException`（MIUI 核心包），脚本会自动改走
  `pm uninstall -k --user 0` 兜底并记为 `UNINSTALLED`；再失败才记录 `FAIL`，不影响其他包。
- 某组件显示 `FAIL(comp)`：检查包名/类名拼写（`lists/components.txt`），或该组件被 ROM 更新改名。
- `SKIP not-installed`：ROM 更新后包名变化，属正常跳过。
- 开机日志出现 `PackageManager 未就绪`：`service.sh` 已内置最长 300 s 等待 + 180 s pm 等待；
  仍失败可手动执行 `freeze.sh`。
- DNS 黑洞不生效：先 `status.sh` 看 `net_state` 与规则；再确认该域名没被本地缓存（等 TTL 过期复测）；
  已缓存 IP 的直连不在拦截范围。
- 需要临时放行单个包：`pm enable --user 0 <包名>`；单个组件：`pm enable <包>/<类>`
  （注意重装模块会覆盖清单）。

## 12. 兜底预案（简版，完整版见工作区《兜底与回滚预案.md》）

- 冻结发生在 `sys.boot_completed=1` 之后，且清单内没有 boot-critical 组件/进程：**严格意义的卡
  logo/无限重启不会由本模块造成**。
- 最坏情况是 UI/入口异常，此时无线或 USB adb 仍可用（本机 adb shell 直接是 root）：

  ```bash
  adb shell sh /data/adb/modules/tb710fu_os4_debloat/bin/restore.sh
  ```

- 无线 adb 端口找不到：`adb mdns services`，或直接插 USB。
- 无 adb / UI 全崩：强制重启后，亮屏时**按住音量减 5 秒**进入 KernelSU Next 安全模式（本次启动不
  加载任何模块），进系统后再 `restore.sh`。
- 模块文件丢失时，可用《兜底与回滚预案.md》里的一键恢复命令（29 包 `pm enable` + finddevice
  `install-existing` + 6 组件 `pm enable 包/类`）。
