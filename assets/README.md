# assets/

这里是本项目自己的**源码/小文件**，不含任何官方/第三方二进制。

- `overlay-src/`：两个 NCM RRO 的 apktool 源码
  - `src_tether` → `TB710FUTetheringOverlay.apk`
  - `src_eth` → `TB710FUConnectivityOverlay.apk`
  - 用 `tools/build_overlays.sh` 构建并用本地测试密钥签名；输出到 `work/overlay/`。
- 笔键位与 SELinux 兼容在 `../hyperos/`：
  - `hyperos/keylayout/Vendor_17ef_Product_617f.kl`
  - `hyperos/sepolicy_compat.cil`

> 这些 RRO 是 system product 分区预装 APK，扫描时走 AOSP `skipVerify`，所以自签即可。
> 不要把这里的测试密钥用于其他 APK；仓库不包含 `tb710fu.jks`（由脚本现场生成）。
