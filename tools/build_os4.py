#!/usr/bin/env python3
"""Build HyperOS 4 (Xiaomi Pad 8 / yupei) system, system_ext, product EROFS images
for Lenovo TB710FU, reusing the HyperOS 3 port's vendor/odm/dlkm.

Inputs  : $TB_OS4_DIR/{x_system,x_system_ext,x_product,x_mi_ext,img/*.img}
          (OS4 OTA extracted; 4.0.5 was work/hyperos4_yupei, 4.0.11 is work/hyperos4_411)
          $TB_WORK/port/{x_system_a,x_product_a,system_a.img}   the working HyperOS 3 port (extracted)
          $TB_WORK/patches/miui-services-tb710fu[-411].jar     version-specific colour patch
          $TB_WORK/overlay/*.apk                     overlays built from hyperos/overlay (signed by you)
          hyperos/ in this repository                keylayout, displayconfig, sepolicy_compat.cil
Outputs : $TB_WORK/build_os4/out/{system,system_ext,product}.img

TB710FU-specific behaviour:
  * keeps ro.sf.lcd_density=440 (do not drop it)
  * drops OS3 wmhp / set_res.sh (3198 wedge), keeps lwky cover + smart charge
  * stock refresh-rate list, software face unlock, VoiceAssist whitelist, stock 40px corner padding
  * colours: swaps the flute HAL's ADAPT/STANDARD semantics; the matching prebuilt
    miui-services odex/vdex is removed so ART cannot run the old code
  * settings that build.prop cannot express are written by tb710fu_bootfix.sh
    (font 100% and stock back-gesture width; refresh rate and dynamic island stay stock)

TB_WORK defaults to ./work next to tools/.  TB_SKIP_STAGE=1 reuses an existing
stage tree; TB_KEEP_BASE/TB_KEEP_STAGE disable the disk cleanups (the base
images are deleted after their EROFS metadata is cached).  TB_CLEAN_PORT_TREES=1
opts into deleting the extracted OS3 port trees after staging (off by default,
because they are the source for future rebuilds).
"""
import glob, json, os, re, shutil, subprocess, sys, tarfile, io, stat
sys.path.insert(0, os.path.dirname(__file__))
from erofs_meta import Erofs

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
H = os.path.abspath(os.environ.get('TB_WORK', os.path.join(REPO, 'work')))
# Extracted OS4 base.  OS4.0.11 uses work/hyperos4_411; OS4.0.5 used
# work/hyperos4_yupei.  Keep both layouts usable: TB_OS4_DIR wins.
Y = os.path.abspath(os.environ.get('TB_OS4_DIR') or f'{H}/hyperos4_411')
PORT = f'{H}/port'
B = f'{H}/build_os4'
STAGE = f'{B}/stage'
OUT = f'{B}/out'
LOG = []


def log(*a):
    s = ' '.join(str(x) for x in a)
    LOG.append(s)
    print(s, flush=True)


def meta_of(img, cache):
    # Include size+mtime in the cache name: switching the OS4 base or port image
    # must not silently reuse uid/gid/mode/SELinux labels from the old image.
    st = os.stat(img)
    p = f'{B}/meta_{cache}_{st.st_size}_{int(st.st_mtime)}.json'
    if not os.path.exists(p):
        json.dump(Erofs(img).walk(), open(p, 'w'))
    return json.load(open(p))


def _cp(src, dst, recursive):
    # macOS clonefile (cp -c) preserves xattrs/SELinux labels and is fast; fall
    # back to cp -a on Linux (or when the filesystem rejects clonefile).
    if sys.platform == 'darwin':
        primary = ['cp', '-cR' if recursive else '-c', '-P', src, dst]
        fallback = ['cp', '-a', src, dst]
    else:
        primary = ['cp', '-a', src, dst]
        fallback = None
    try:
        subprocess.run(primary, check=True)
    except subprocess.CalledProcessError:
        if fallback is None:
            raise
        subprocess.run(fallback, check=True)


def clone_tree(src, dst):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    _cp(src, dst, True)


def copy_in(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    _cp(src, dst, os.path.isdir(src) and not os.path.islink(src))


def edit_device_features(path):
    """Apply the OS3 port's still-relevant device_features changes to yupei.xml.

    Deliberately does NOT copy the OS3 piano.xml wholesale: OS4.0.11 has a
    different feature set (e.g. it dropped support_virtual_call).  Only the
    changes that are still meaningful for TB710FU are applied.
    """
    t = open(path).read()

    # Refresh rate: leave yupei's stock fpsList (120/90/60) and
    # support_max_fps=144.  The Settings UI therefore shows "最高 144"
    # while most apps settle at 120, which is the intended stock behaviour.

    # TEE face HAL is absent on Lenovo firmware; PearlBiometric takes the
    # non-TEE path when this is false.  Region CN -> ALL for the same reason
    # the OS3 port changed it.
    t = t.replace('<bool name="support_tee_face_unlock">true</bool>',
                  '<bool name="support_tee_face_unlock">false</bool>')
    t = re.sub(r'(<string-array name="support_face_unlock_region_dom">\s*<item>)CN(</item>)',
               r'\1ALL\2', t)

    add = []
    if 'support_mi_keyboard' not in t:
        add.append('    <string name="support_mi_keyboard">piano</string>')
    if 'support_video_dfps' not in t:
        add.append('    <bool name="support_video_dfps">true</bool>')
    if 'remove_screen_off_hold_on' not in t:
        add.append('    <bool name="remove_screen_off_hold_on">false</bool>')
    if add:
        t = t.replace('</features>', '\n'.join(add) + '\n</features>')
    open(path, 'w').write(t)
    log(f'[product] device_features: fpsList left at stock, tee_face=false, region=ALL'
        f'{", +" + str(len(add)) + " compat keys" if add else ""}')


# ---------------------------------------------------------------- staging
def stage():
    os.makedirs(STAGE, exist_ok=True)
    for p in ('system', 'system_ext', 'product'):
        clone_tree(f'{Y}/x_{p}', f'{STAGE}/{p}')
    S, P = f'{STAGE}/system/system', f'{STAGE}/product'
    extra = {'system': {}, 'system_ext': {}, 'product': {}}   # rel path -> meta source

    # 1) mi_ext merged into product / system (as the HyperOS 3 port did)
    mi = f'{Y}/x_mi_ext'
    for root, dirs, files in os.walk(f'{mi}/product'):
        for n in files + [d for d in dirs if os.path.islink(os.path.join(root, d))]:
            src = os.path.join(root, n)
            rel = os.path.relpath(src, f'{mi}/product')
            dst = f'{P}/{rel}'
            if os.path.lexists(dst) and not os.path.isdir(dst):
                os.remove(dst)
            copy_in(src, dst)
            extra['product'][rel] = ('mi_ext', f'product/{rel}')
    for root, dirs, files in os.walk(f'{mi}/product'):
        for d in dirs:
            rel = os.path.relpath(os.path.join(root, d), f'{mi}/product')
            extra['product'].setdefault(rel, ('mi_ext', f'product/{rel}'))
    copy_in(f'{mi}/system/etc/permissions/privapp-permissions-system-miext.xml',
            f'{S}/etc/permissions/privapp-permissions-system-miext.xml')
    extra['system']['system/etc/permissions/privapp-permissions-system-miext.xml'] = \
        ('mi_ext', 'system/etc/permissions/privapp-permissions-system-miext.xml')

    # 2) product/pangu/system -> system (as the port did; drop TMS NFC jars)
    pg = f'{P}/pangu/system'
    for rel in ('app/Joyose', 'app/Joyose/Joyose.apk', 'etc/ota_skip_apps',
                'etc/permissions/privapp-permissions-pangu.xml',
                'etc/permissions/signature-permission-pangu.xml',
                'etc/permissions/security', 'etc/permissions/security/verity_key'):
        src = f'{pg}/{rel}'
        if os.path.isdir(src):
            os.makedirs(f'{S}/{rel}', exist_ok=True)
        else:
            copy_in(src, f'{S}/{rel}')
        extra['system'][f'system/{rel}'] = ('product', f'pangu/system/{rel}')
    shutil.rmtree(f'{P}/pangu')

    # 3) porter's lwky runtime tweaks from the working HyperOS 3 port
    #    TB710FU 4.0.11 build: wmhp ("perfect landscape" window rules) and set_res.sh
    #    (2000x3198 wedge) are dropped -- both harmful at 440 density. Charging
    #    (lwky_smart_charge_hyper), cover (lwky_cover) and their init triggers stay.
    PS = f'{PORT}/x_system_a/system'
    lwky_rc_src = open(f'{PS}/etc/init/init.lwky.rc').read()
    blocks, cur = [], []
    for line in lwky_rc_src.splitlines():
        if line.startswith(('service ', 'on ')) and cur:
            blocks.append(cur); cur = [line]
        else:
            cur.append(line)
    blocks.append(cur)
    keep = []
    for b in blocks:
        head = b[0] if b else ''
        if head.startswith('service lwky_wmhp') or head.startswith('service set_resolution'):
            continue
        b = [l for l in b if l.strip() not in ('start lwky_wmhp', 'start set_resolution')]
        if head.startswith('on ') and not any(l.strip() for l in b[1:]):
            continue
        keep.append(b)
    open(f'{S}/etc/init/init.lwky.rc', 'w').write('\n'.join('\n'.join(b) for b in keep) + '\n')
    # The OS3 bridge set game_mode=4 + game_edge=4 for "high sampling".
    # Two problems: (1) game_edge 4 is outside the Lenovo HAL's 0..3 range
    # (getCornerInhibition clamps to 3), and (2) game_mode 4 (firmware 0x79/0x03)
    # keeps palm rejection.  game_mode 2 is the vendor's "game mode / remove palm
    # reject" (0x79/0x04) and is what actually frees the right-edge back gesture;
    # 4 was only lwky's unverified high-sampling guess.  Keep game_edge 0 and use
    # game_mode 2.  The stock ZUI game-assistant UI that would expose these
    # choices is absent from this port.
    rc_path = f'{S}/etc/init/init.lwky.rc'
    rc_text = open(rc_path).read()
    rc_text = rc_text.replace('write /proc/game_edge 4', 'write /proc/game_edge 0')
    rc_text = rc_text.replace('write /proc/game_mode 4', 'write /proc/game_mode 2')
    open(rc_path, 'w').write(rc_text)
    extra['system']['system/etc/init/init.lwky.rc'] = ('port', 'system/etc/init/init.lwky.rc')
    copy_in(f'{PS}/lwky', f'{S}/lwky')
    for root, dirs, files in os.walk(f'{PS}/lwky'):
        for n in dirs + files:
            rel = 'system/' + os.path.relpath(os.path.join(root, n), PS)
            extra['system'][rel] = ('port', rel)
    extra['system']['system/lwky'] = ('port', 'system/lwky')
    for junk in ('wmhp.sh', 'set_res.sh', 'wmhp'):
        p = f'{S}/lwky/{junk}'
        if os.path.lexists(p):
            shutil.rmtree(p) if os.path.isdir(p) and not os.path.islink(p) else os.remove(p)
    log('[system] lwky: kept cover/smart_charge, dropped wmhp + set_res')

    # 3a) Runtime Settings rows that cannot be expressed in build.prop.  The OS3
    #     port needed a SystemUI PropObserver for these; an init oneshot running
    #     in the shell domain can write the Settings provider directly (verified
    #     with `adb shell settings put` on the 4.0.5 device).  It runs after
    #     boot_completed, so SystemUI/Settings have already created their rows.
    bootfix = f'{STAGE}/system/system/etc/tb710fu_bootfix.sh'
    os.makedirs(os.path.dirname(bootfix), exist_ok=True)
    open(bootfix, 'w').write('''#!/system/bin/sh
# TB710FU runtime defaults (Settings provider rows; build.prop cannot set these)
sleep 5

# --- font size: OS4 default 100% ---
# The 4.0.5 port left font_scale=0.85 in /data. OS4's font page clamps that to
# 90%, and its 100% entry early-returns because Configuration.uiMode already
# maps to 1, so the row must be written directly. Write it on every boot (the
# user asked for 100% at every startup) and retry once if the Settings provider
# was not ready yet. device_font_scale is the companion row real OS4 ships.
settings put system font_scale 1.0
settings put system device_font_scale 1.0
settings put system ui_mode_scale 1
sleep 2
fs=$(settings get system font_scale)
case "$fs" in
  1|1.0) ;;
  *)
    sleep 5
    settings put system font_scale 1.0
    settings put system device_font_scale 1.0
    settings put system ui_mode_scale 1
    ;;
esac

# Restore the stock back-gesture edge width (framework default scale 1.0).
# Older TB710FU packages wrote 1.5; delete those persistent Secure values so a
# no-wipe update does not keep the wider hot area.
settings delete secure back_gesture_inset_scale_left >/dev/null 2>&1
settings delete secure back_gesture_inset_scale_right >/dev/null 2>&1

# NTP server: pool.ntp.org is flaky in CN; the hardware RTC cannot hold time
# (pm8xxx rtc node has no allow-set-time in this kernel), so auto-time depends
# entirely on NTP right after every boot. Point it at aliyun.
settings put global ntp_server ntp.aliyun.com

log -t tb710fu_bootfix "font_scale=$(settings get system font_scale) device_font_scale=$(settings get system device_font_scale) ui_mode_scale=$(settings get system ui_mode_scale)"
# Refresh rate and dynamic island: intentionally untouched; keep 4.0.11 stock
# (support_max_fps=144, fpsList=120/90/60; no support_dynamic_island* writes).
exit 0
''')
    rc = 'system/etc/init/tb710fu_bootfix.rc'
    open(f'{STAGE}/system/{rc}', 'w').write('''service tb710fu_bootfix /system/bin/sh /system/etc/tb710fu_bootfix.sh
    class late_start
    user root
    group root system
    seclabel u:r:shell:s0
    oneshot
    disabled

on property:sys.boot_completed=1
    start tb710fu_bootfix
''')
    extra['system']['system/etc/tb710fu_bootfix.sh'] = ('sibling', 'system/etc/init/apexd.rc')
    extra['system'][rc] = ('sibling', 'system/etc/init/apexd.rc')
    log('[system] + tb710fu_bootfix (font 100% + back-gesture inset; refresh/island stock)')

    # 3a-2) Novatek edge inhibition follows /proc/panel_direction (0..3 =
    #       Surface.ROTATION_0..270).  Stock ZUI's EdgeInhibitionInputPolicy sets
    #       it from the display rotation; HyperOS never does, so it stays at the
    #       power-on default 0 ("Vertical").  At ROTATION_90 that puts the
    #       controller's palm-rejection bands on the wrong edges, and swipe-back
    #       dies around the middle of the right edge.  The tablet's normal
    #       orientation is landscape (ROTATION_90), so write 3.  The driver's
    #       SET mapping is 3 -> EDGE_REJECT_RIGHT_UP (0xBC, rotate 90); its proc
    #       SHOW labels for 1/3 are inverted, so do not trust the text output.
    #       init is the only domain the vendor policy allows to write this
    #       generic proc node; the driver keeps the state across suspend and
    #       re-sends it on resume, so one successful boot-time write is enough.
    #       boot_completed is a retry for the case where the touch driver probes
    #       after "on boot".
    rc = 'system/etc/init/tb710fu_paneldir.rc'
    open(f'{STAGE}/system/{rc}', 'w').write('''on boot
    write /proc/panel_direction 3

on property:sys.boot_completed=1
    write /proc/panel_direction 3
''')
    extra['system'][rc] = ('sibling', 'system/etc/init/apexd.rc')
    log('[system] + tb710fu_paneldir (touch edge inhibition -> 90 degrees)')

    # 3b) miui-services.jar color-mode patch: this flute-derived vendor HAL swaps the
    #     ADAPT(0)/STANDARD(2) picture-mode meanings, so yuanse looked oversaturated.
    #     The patch is version-specific (the class is recompiled per OS4 OTA), so pick
    #     the jar built for this base and drop the matching prebuilt odex/vdex.
    base_tag = os.path.basename(Y).replace('hyperos4_', '')
    candidates = [f'{H}/patches/miui-services-tb710fu-{base_tag}.jar',
                  f'{H}/patches/miui-services-tb710fu.jar']
    patched = os.environ.get('TB_MIUI_SERVICES_PATCH') or next(
        (p for p in candidates if os.path.exists(p)), None)
    if patched and os.path.exists(patched):
        shutil.copyfile(patched, f'{STAGE}/system_ext/framework/miui-services.jar')
        # The prebuilt oat is keyed to the original jar's checksum.  Leaving it in
        # place makes ART either reject the jar or run it interpreted until the next
        # dexopt, so remove only this jar's artifacts and let the system rebuild.
        for pat in (f'{STAGE}/system_ext/framework/oat/*/miui-services.art',
                    f'{STAGE}/system_ext/framework/oat/*/miui-services.odex',
                    f'{STAGE}/system_ext/framework/oat/*/miui-services.vdex',
                    f'{STAGE}/system_ext/framework/oat/*/miui-services.*.fsv_meta',
                    f'{STAGE}/system_ext/framework/miui-services.jar.fsv_meta',
                    f'{STAGE}/system_ext/framework/miui-services.jar.prof',
                    f'{STAGE}/system_ext/framework/miui-services.jar.prof.fsv_meta'):
            for p in glob.glob(pat):
                os.remove(p)
        log(f'[system_ext] miui-services.jar color-mode swap applied ({os.path.basename(patched)})')

    # 3c) SystemUI DevicesOverlay: stock yupei sets rounded_corner_content_padding=40px.
    #     Keep the stock 40px by default now. The old OS3/piano-tuned 10px is only
    #     applied when TB_CORNER_PADDING=10 is set for an experiment. When patching
    #     is requested, edit resources.arsc in place so the Xiaomi certificate and
    #     the APK Signing Block survive (system-partition APKs use skipVerify).
    dov = f'{P}/overlay/DevicesOverlay.apk'
    if os.environ.get('TB_CORNER_PADDING', '40') == '10' and os.path.exists(dov) and base_tag.startswith('411'):
        tmp = dov + '.tb710fu'
        subprocess.run([sys.executable, f'{REPO}/tools/patch_apk_res.py', dov, tmp,
                        '--dimen', 'rounded_corner_content_padding=10',
                        '--entry-id', '0x5c'], check=True)
        os.replace(tmp, dov)
        log('[product] DevicesOverlay: rounded_corner_content_padding 40px -> 10px (TB_CORNER_PADDING=10)')
    else:
        log('[product] DevicesOverlay: stock 40px kept (default)')

    # 3d) VoiceAssist offline-wakeup device whitelist.  The OS3 port patched this
    #     asset, not the code; do the same in place so the Xiaomi signature stays.
    vap = f'{P}/priv-app/VoiceAssistAndroidT/VoiceAssistAndroidT.apk'
    if os.path.exists(vap):
        tmp = vap + '.tb710fu'
        subprocess.run([sys.executable, f'{REPO}/tools/patch_voice_wakeup.py', vap, tmp], check=True)
        os.replace(tmp, vap)
        log('[product] VoiceAssist: + piano/yupei/TB710FU wakeup whitelist')

    # 3e) Camera: MiuiCamera cannot save on this port.  Its JPEG path goes
    #     through Xiaomi's Mialgo/campostproc post-processing service
    #     (vendor.xiaomi.hardware.campostproc, /vendor/lib64/libmialgoengine.so),
    #     which is only in the Xiaomi piano/yupei vendor.  The frozen Lenovo
    #     QTI vendor has no such service; the app hits a 12 s capture timeout
    #     and saves the 1440x1080 preview with Exif smallPicture=true.
    #     Standard Camera2 is healthy (Aperture captures 4160x3120), so ship
    #     Aperture as the camera app and drop MiuiCamera.  Aperture's APK is
    #     built with debuggable=false so Android 17 does not show the 16 KB
    #     page-size warning; it is re-signed because the manifest changed.
    cam_dir = f'{P}/priv-app/MiuiCamera'
    if os.path.isdir(cam_dir):
        shutil.rmtree(cam_dir)
        log('[product] MiuiCamera removed (Xiaomi campostproc vendor service absent)')
    ap_dir = f'{P}/app/Aperture'
    os.makedirs(ap_dir, exist_ok=True)
    copy_in(f'{REPO}/hyperos/camera/Aperture.apk', f'{ap_dir}/Aperture.apk')
    dp_dir = f'{P}/etc/default-permissions'
    os.makedirs(dp_dir, exist_ok=True)
    copy_in(f'{REPO}/hyperos/camera/default-permissions-aperture.xml',
            f'{dp_dir}/aperture.xml')
    extra['product']['app/Aperture'] = ('product', 'app/MIUIXiaomiAccount')
    extra['product']['app/Aperture/Aperture.apk'] = \
        ('product', 'app/MIUIXiaomiAccount/MIUIXiaomiAccount.apk')
    extra['product']['etc/default-permissions/aperture.xml'] = ('sibling', 'etc/build.prop')
    log('[product] Aperture installed as the only camera app (full-res Camera2 JPEG)')

    # 3f) CameraParallelService stub.  HyperOS 4 gallery is Rust: its photo page
    #     (ExternalPhotoPageActivity, also the target of the standard
    #     com.android.camera.action.REVIEW that GCam's thumbnail tap fires)
    #     unwraps a query against the authority
    #     com.xiaomi.camera.parallelservice.provider.SpecialTypesProvider.
    #     That provider is declared inside MiuiCamera (removed in 3e), so the
    #     gallery abort()s on launch and "view photo" dies in both cameras.
    #     Ship a minimal no-op provider with the same authority; an empty
    #     result is the correct answer for a port with no MiuiCamera special
    #     media (live photos etc.).
    ps_dir = f'{P}/app/CameraParallelServiceStub'
    os.makedirs(ps_dir, exist_ok=True)
    copy_in(f'{REPO}/hyperos/camera/CameraParallelServiceStub.apk',
            f'{ps_dir}/CameraParallelServiceStub.apk')
    extra['product']['app/CameraParallelServiceStub'] = ('product', 'app/Aperture')
    extra['product']['app/CameraParallelServiceStub/CameraParallelServiceStub.apk'] = \
        ('product', 'app/Aperture/Aperture.apk')
    log('[product] CameraParallelServiceStub installed (gallery SpecialTypesProvider)')

    # 4) Lenovo Tab Pen Plus button key layout
    kl = 'system/usr/keylayout/Vendor_17ef_Product_617f.kl'
    copy_in(f'{REPO}/hyperos/keylayout/Vendor_17ef_Product_617f.kl', f'{STAGE}/system/{kl}')
    extra['system'][kl] = ('sibling', 'system/usr/keylayout/Generic.kl')

    # 5) USB NCM tethering overlay (usb0 interface)
    ov = 'overlay/TB710FUTetheringOverlay.apk'
    copy_in(f'{H}/overlay/TB710FUTetheringOverlay.apk', f'{P}/{ov}')
    extra['product'][ov] = ('sibling', 'overlay/NcmTetheringResCommon_Sys.apk')
    # EthernetTracker's default regex (usb|eth)\d+ grabs usb0 and its IpClient wipes the tether IPv4
    ov = 'overlay/TB710FUConnectivityOverlay.apk'
    copy_in(f'{H}/overlay/TB710FUConnectivityOverlay.apk', f'{P}/{ov}')
    extra['product'][ov] = ('sibling', 'overlay/NcmTetheringResCommon_Sys.apk')

    # 6) device features: odm reports ro.product.device=piano
    copy_in(f'{P}/etc/device_features/yupei.xml', f'{P}/etc/device_features/piano.xml')
    extra['product']['etc/device_features/piano.xml'] = ('product', 'etc/device_features/yupei.xml')
    edit_device_features(f'{P}/etc/device_features/piano.xml')

    # 6b) face unlock: yupei declares TEE face (needs Xiaomi's face HAL, absent on TB710FU -> enrollment fails).
    # Use the software 2D face unlock the HyperOS 3 port ships (PearlBiometric = com.miui.face, signed with the
    # same Xiaomi platform key as OS4); MiuiFaceManager takes the non-TEE path when support_tee_face_unlock=false.
    # oat/ is left out (compiled against the HyperOS 3 boot image). Meta (owner/mode/selinux) borrowed from app/MIUIXiaomiAccount.
    copy_in(f'{PORT}/x_product_a/app/PearlBiometric/PearlBiometric.apk', f'{P}/app/PearlBiometric/PearlBiometric.apk')
    extra['product']['app/PearlBiometric'] = ('product', 'app/MIUIXiaomiAccount')
    extra['product']['app/PearlBiometric/PearlBiometric.apk'] = ('product', 'app/MIUIXiaomiAccount/MIUIXiaomiAccount.apk')
    log('[product] face unlock: + app/PearlBiometric, support_tee_face_unlock=false')

    # 6c) Per-display brightness + HBM (strong-light) config.  DisplayDeviceConfig
    #     looks for display_id_<physicalDisplayId>.xml under /product/etc/
    #     displayconfig first; the Pad 8 files are keyed to other display IDs, so
    #     the framework silently fell back to the global config, which has no
    #     highBrightnessMode data.  Result: the manual slider could drive the
    #     Lenovo panel to its 782-nit maximum everywhere, and HBM was never used.
    #     This file uses the panel's own brightness curve (from Lenovo's vendor
    #     display config) and the Pad 8 sunlight policy: normal max at brightness
    #     0.4509 (~516 nits, verified on device: raw backlight 1846/4095), HBM
    #     allowed above 10000 lux up to the panel maximum.  The port file is the
    #     fallback if the stable display ID ever changes.
    disp_src = f'{REPO}/hyperos/displayconfig/display_id_4630946395913993603.xml'
    disp_meta = 'etc/displayconfig/display_id_4630946969883713683.xml'
    for name in ('display_id_4630946395913993603.xml', 'display_port_131.xml'):
        rel = f'etc/displayconfig/{name}'
        copy_in(disp_src, f'{P}/{rel}')
        extra['product'][rel] = ('product', disp_meta)
    log('[product] displayconfig: normal max 0.4509 (~516 nits), HBM >=10000 lux')

    # 7) SELinux: re-declare types the Android 17 platform policy dropped but the API-34 vendor policy uses
    with open(f'{P}/etc/selinux/product_sepolicy.cil', 'a') as f:
        f.write('\n' + open(f'{REPO}/hyperos/sepolicy_compat.cil').read())

    # vendor has no media_profiles_vendor.xml -> zygote aborts in MediaProfiles (port comments it out too)
    bp = f'{S}/build.prop'
    t = open(bp).read()
    t = t.replace('\nmedia.settings.xml=/vendor/etc/media_profiles_vendor.xml', '\n#media.settings.xml=/vendor/etc/media_profiles_vendor.xml')
    open(bp, 'w').write(t)

    # 7b) Find Device: KEEP priv-app/MIUIFindDeviceCN. Its fid signing needs Xiaomi's TEE TA (cardapp, via mtd/
    # MTService), absent on Lenovo firmware, so it can never work -- but without the app com.xiaomi.account crashes
    # on re-auth (FindDeviceStatusManager "Can't bind service"). The failing status check is bypassed via the DEV
    # incremental set in edit_product_prop() (step 8). Do not turn on Find Device on the tablet.
    # TB_NO_FINDDEVICE=1: drop it for a first setup after a data wipe -- with the app present the setup wizard
    # demands an activation check that can never pass ("cloudsp_fid 参数不能为空", 10/20). Skip the Xiaomi account in
    # the wizard, then flash the normal product (with Find Device) and log in from Settings.
    if os.environ.get('TB_NO_FINDDEVICE'):
        shutil.rmtree(f'{P}/priv-app/MIUIFindDeviceCN', ignore_errors=True)
        log('[product] TB_NO_FINDDEVICE: - priv-app/MIUIFindDeviceCN')

    # debug variant (TB_DEBUG=1): adb without authorization from early boot, for logcat during hangs
    if os.environ.get('TB_DEBUG'):
        # the framework drops adb from the USB config after boot; put it back (vendor rc is sys.usb.config driven)
        rc = 'system/etc/init/tb710fu_adb.rc'
        open(f'{STAGE}/system/{rc}', 'w').write(
            'on property:sys.boot_completed=1 && property:sys.usb.config=mtp\n'
            '    setprop sys.usb.config mtp,adb\n\n'
            'on property:sys.boot_completed=1 && property:sys.usb.config=none\n'
            '    setprop sys.usb.config adb\n')
        extra['system'][rc] = ('sibling', 'system/etc/init/apexd.rc')
        bp = f'{S}/build.prop'
        t = open(bp).read()
        t = t.replace('ro.adb.secure=1', 'ro.adb.secure=0').replace('ro.debuggable=0', 'ro.debuggable=1')
        t += '\n# TB710FU debug build\npersist.sys.usb.config=adb\npersist.service.adb.enable=1\n'
        open(bp, 'w').write(t)
        log('[system] DEBUG build.prop: ro.debuggable=1 ro.adb.secure=0 persist.sys.usb.config=adb')
        # vendor/build.prop sets ro.adb.secure=1 and is loaded after system; product is loaded last
        open(f'{P}/etc/build.prop', 'a').write('\n# TB710FU debug build\nro.adb.secure=0\nro.debuggable=1\n')
        # /adb_keys -> /product/etc/security/adb_keys : trust an explicit build-host key.
        # Never default to the builder's personal key silently: a TB_DEBUG image is a
        # personal debug artifact and must not be redistributed.
        ak = f'{P}/etc/security/adb_keys'
        os.makedirs(os.path.dirname(ak), exist_ok=True)
        key = os.environ.get('TB_ADB_KEY') or os.path.expanduser('~/.android/adbkey.pub')
        if not os.path.exists(key):
            raise SystemExit(f'TB_DEBUG requires an adb public key: set TB_ADB_KEY=<path> '
                             f'(tried {key})')
        old = open(ak).read() if os.path.exists(ak) else ''
        open(ak, 'w').write(old + open(key).read())
        extra['product'].setdefault('etc/security/adb_keys', ('sibling', 'etc/build.prop'))
        log(f'[product] DEBUG: ro.adb.secure=0, adb_keys added from {key}')
        log('[product] WARNING: TB_DEBUG image trusts the build host adb key; do not distribute')

    # 8) product build.prop
    edit_product_prop(f'{P}/etc/build.prop', f'{mi}/etc/build.prop')
    json.dump(extra, open(f'{B}/extra_meta.json', 'w'), indent=1)
    return extra


def edit_product_prop(path, miext_prop):
    lines = open(path).read().splitlines()
    drop = {'ro.product.build.no_bionic_page_size_macro'}   # keep ro.sf.lcd_density=440 (yupei native)
    set_ = {
        'ro.product.cpu.pagesize.max': '4096',
        # Refresh rate: leave stock support_max_fps=144 and the 120/90/60 list untouched.
        # OS3 lwky switches (executors live in init.lwky.rc).  These were a
        # Magisk/KSU module in the 4.0.5 build; baking them in makes a clean
        # first boot behave the same.
        'persist.sys.stylus.enable': '1',
        'persist.sys.device_case_enabled': '1',
        'persist.sys.high_touch_sampling_rate.enable': '1',
        'persist.sys.gesture_wakeup': '2',
        'persist.sys.pc_mode': '0',
        # Memory extension: 4.0.11 ships xring_extm + dm_opt but dropped the
        # legacy key that some MIUI components still read.
        'persist.miui.extm.enable': '1',
        # Bluetooth HID host (keyboard/mouse) must stay on; 4.0.11 already has
        # host=true, but the device profile is also needed by some stacks.
        'bluetooth.profile.hid.host.enabled': 'true',
        'bluetooth.profile.hid.device.enabled': 'true',
    }
    # ".DEV" suffix -> miui.os.Build.IS_STABLE_VERSION=false -> Xiaomi Account's isIgnoreExceptionBuild() ignores the
    # Find Device status check error ("查找Pad检查状态出错"), which always fails without Xiaomi's TEE (see step 7b).
    # Replaces every occurrence (product build.prop defines it twice; product is loaded last, so it wins).
    override = {'ro.build.version.incremental': lambda v: v if v.endswith('.DEV') else v + '.DEV'}
    out = []
    seen = set()
    for l in lines:
        k = l.split('=', 1)[0] if '=' in l and not l.startswith('#') else None
        if k in drop:
            out.append('# removed for TB710FU: ' + l)
            continue
        if k in override:
            out.append(f'{k}={override[k](l.split("=", 1)[1])}')
            continue
        if k in set_:
            out.append(f'{k}={set_[k]}')
            seen.add(k)
            continue
        out.append(l)
    for k, v in set_.items():
        if k not in seen:
            out.append(f'{k}={v}')
    out.append('')
    out.append('# ---- merged from mi_ext/etc/build.prop ----')
    for l in open(miext_prop).read().splitlines():
        if not l or l.startswith('#'):
            continue
        k = l.split('=', 1)[0]
        if k in ('ro.vendor.build.ab_ota_partitions',):
            continue
        if k == 'ro.product.mod_device':
            l = 'ro.product.mod_device=piano'
        out.append(l)
    out += ['', '# ---- Lenovo TB710FU port ----',
            'lwky.hyper.brand=Lenovo', 'lwky.hyper.device=TB710FU', 'lwky.hyper.manufacturer=LENOVO',
            'lwky.hyper.marketname=联想小新平板 Pro GT', 'lwky.hyper.model=TB710FU',
            'lwky.hyper.vendor.brand=Lenovo', 'lwky.hyper.vendor.device=TB710FU',
            'lwky.hyper.vendor.manufacturer=LENOVO', 'lwky.hyper.vendor.model=TB710FU',
            'lwky.hyper.vendor.name=TB710FU',
            'ro.product.marketname=联想小新平板Pro GT',
            # Keep every product-source marketname Lenovo-branded.  The generic
            # ro.product.marketname is what Settings shows; the per-source copies
            # stop ro.product.odm.marketname ("Xiaomi Pad 8 Pro") leaking into
            # apps that read the source-specific key.  ro.product.model stays
            # piano (25091RP04C) on purpose: the store channel keys on it.
            'ro.product.product.marketname=联想小新平板Pro GT',
            'ro.product.odm.marketname=联想小新平板Pro GT',
            'ro.product.vendor.marketname=联想小新平板Pro GT',
            'ro.product.system.marketname=联想小新平板Pro GT',
            'ro.product.system_ext.marketname=联想小新平板Pro GT',
            # mslg version gate: OS4 launchers require >= 26.01.01 while the
            # frozen OS3 ODM rootfs is 25.09.04.  The SetRes module deploys the
            # real rootfs; baking the prop makes the gate pass even if the
            # module's resetprop runs late.
            'ro.vendor.mslg.rootfs.version=rootfs-26.01.01.tgz',
            # OS3 hardware switches are handled by set_ above so an existing
            # yupei line is replaced instead of duplicated.
            # Advanced textures (高级材质): gates read by miuix HyperMaterialUtils / Settings
            'persist.sys.background_blur_supported=true',
            'persist.sys.background_blur_supported_overlay=false',
            'persist.sys.bionic_material_supported=true',
            'persist.sys.advanced_visual_release=6',
            # AirPlay receiver colours: Skia/Vulkan TextureView YUV->RGB is BT.601-limited (Step 15); was a Magisk module
            'debug.hwui.renderer=skiagl',
            'persist.vendor.battery.health=true', 'persist.vendor.battery.health.optimise=true',
            'persist.vendor.night.charge=true', 'persist.vendor.smartchg=30',
            'persist.vendor.smart.battMntor.V2=true', 'persist.vendor.hightemp.notice=true',
            '']
    open(path, 'w').write('\n'.join(out))


# ---------------------------------------------------------------- tar + mkfs
def default_meta(rel, is_dir, parent):
    m = dict(parent) if parent else dict(uid=0, gid=0, xattrs={})
    m['mode'] = (0o040755 if is_dir else 0o100644)
    m['xattrs'] = {k: v for k, v in m.get('xattrs', {}).items() if k == 'security.selinux'}
    return m


def build_tar(part, extra, metas):
    base = metas[f'y_{part}']
    srcmap = {'mi_ext': metas['y_mi_ext'], 'product': metas['y_product'], 'port': metas['port_system']}
    root = f'{STAGE}/{part}'
    tpath = f'{B}/{part}.tar'
    t = tarfile.open(tpath, 'w', format=tarfile.PAX_FORMAT, encoding='utf-8', errors='surrogateescape')
    missing = 0
    entries = ['.']
    for r, dirs, files in os.walk(root):
        dirs.sort(); files.sort()
        for n in dirs + files:
            entries.append(os.path.relpath(os.path.join(r, n), root))
    for rel in entries:
        full = os.path.join(root, rel)
        st = os.lstat(full)
        m = None
        if rel in extra.get(part, {}):
            kind, src = extra[part][rel]
            if kind == 'sibling':
                m = dict(base.get(src) or {})
                m['mode'] = 0o100644
            elif kind == 'mi_ext' and stat.S_ISDIR(st.st_mode) and rel in base:
                m = base[rel]          # keep product's own directory metadata
            else:
                m = srcmap[kind].get(src)
        if m is None:
            m = base.get(rel)
        if m is None:
            parent = base.get(os.path.dirname(rel) or '.')
            m = default_meta(rel, stat.S_ISDIR(st.st_mode), parent)
            missing += 1
            if missing <= 30:
                log(f'  [{part}] no meta, default for {rel}')
        ti = tarfile.TarInfo('./' + rel if rel != '.' else '.')
        ti.uid, ti.gid = m['uid'], m['gid']
        ti.mode = m['mode'] & 0o7777
        ti.mtime = 1230768000
        ti.pax_headers = {f'SCHILY.xattr.{k}': bytes.fromhex(v).decode('utf-8', 'surrogateescape')
                          for k, v in m.get('xattrs', {}).items()}
        if stat.S_ISLNK(st.st_mode):
            ti.type = tarfile.SYMTYPE
            ti.linkname = os.readlink(full)
            t.addfile(ti)
        elif stat.S_ISDIR(st.st_mode):
            ti.type = tarfile.DIRTYPE
            t.addfile(ti)
        else:
            ti.type = tarfile.REGTYPE
            ti.size = st.st_size
            with open(full, 'rb') as fh:
                t.addfile(ti, fh)
    t.close()
    log(f'[{part}] tar entries={len(entries)} defaulted={missing}')
    return tpath


def mkfs(part, tpath):
    os.makedirs(OUT, exist_ok=True)
    img = f'{OUT}/{part}.img'
    if os.path.exists(img):
        os.remove(img)
    subprocess.run(['mkfs.erofs', '-b4096', '-zlz4hc,9', '-T1230768000', '--tar=f', img, tpath],
                   check=True, stdout=subprocess.DEVNULL)
    log(f'[{part}] image {os.path.getsize(img)/1e9:.3f} GB')
    os.remove(tpath)
    return img


def main():
    parts = sys.argv[1:] or ['system', 'system_ext', 'product']
    metas = {f'y_{p}': meta_of(f'{Y}/img/{p}.img', f'y_{p}') for p in ('system', 'system_ext', 'product', 'mi_ext')}
    metas['port_system'] = meta_of(f'{PORT}/system_a.img', 'port_system')
    # The EROFS metadata is now cached in build_os4/meta_*.json; the multi-GB
    # base images are no longer needed by this build.  Keep the extracted trees
    # (they are the editable source) unless TB_KEEP_BASE is set.
    if not os.environ.get('TB_KEEP_BASE'):
        for p in ('system', 'system_ext', 'product', 'mi_ext'):
            img = f'{Y}/img/{p}.img'
            if os.path.exists(img):
                os.remove(img)
                log(f'[cleanup] removed {img}')
    if os.environ.get('TB_SKIP_STAGE'):
        extra = json.load(open(f'{B}/extra_meta.json'))
        log('[stage] TB_SKIP_STAGE set, reusing staging trees')
    else:
        extra = stage()
        if os.environ.get('TB_CLEAN_PORT_TREES'):
            # lwky/PearlBiometric have been copied into the stage; only do this
            # when disk is tight -- the trees are the source for future rebuilds.
            for d in (f'{PORT}/x_system_a', f'{PORT}/x_product_a'):
                if os.path.isdir(d):
                    shutil.rmtree(d)
                    log(f'[cleanup] removed {d}')
    for p in parts:
        mkfs(p, build_tar(p, extra, metas))
        if not os.environ.get('TB_KEEP_STAGE'):
            shutil.rmtree(f'{STAGE}/{p}', ignore_errors=True)
    open(f'{B}/build.log', 'w').write('\n'.join(LOG))


if __name__ == '__main__':
    main()
