#!/usr/bin/env python3
"""Minimal legacy DPMS setprop test via libdrm (same ioctl KWin uses)."""
import ctypes, sys, os

DRM_MODE_OBJECT_CONNECTOR = 0xc0c0c0c0
DRM_MODE_DPMS_ON = 0
DRM_MODE_DPMS_OFF = 3
DRM_PROP_NAME_LEN = 32


class drmModeRes(ctypes.Structure):
    _fields_ = [
        ("count_fbs", ctypes.c_int), ("fbs", ctypes.POINTER(ctypes.c_uint32)),
        ("count_crtcs", ctypes.c_int), ("crtcs", ctypes.POINTER(ctypes.c_uint32)),
        ("count_connectors", ctypes.c_int), ("connectors", ctypes.POINTER(ctypes.c_uint32)),
        ("count_encoders", ctypes.c_int), ("encoders", ctypes.POINTER(ctypes.c_uint32)),
        ("min_width", ctypes.c_uint32), ("max_width", ctypes.c_uint32),
        ("min_height", ctypes.c_uint32), ("max_height", ctypes.c_uint32),
    ]


class drm_mode_modeinfo(ctypes.Structure):
    _fields_ = [
        ("clock", ctypes.c_uint32),
        ("hdisplay", ctypes.c_uint16), ("hsync_start", ctypes.c_uint16),
        ("hsync_end", ctypes.c_uint16), ("htotal", ctypes.c_uint16),
        ("hskew", ctypes.c_uint16), ("vdisplay", ctypes.c_uint16),
        ("vsync_start", ctypes.c_uint16), ("vsync_end", ctypes.c_uint16),
        ("vtotal", ctypes.c_uint16), ("vscan", ctypes.c_uint16),
        ("vrefresh", ctypes.c_uint32), ("flags", ctypes.c_uint32),
        ("type", ctypes.c_uint32), ("name", ctypes.c_char * 32),
    ]


class drmModeConnector(ctypes.Structure):
    _fields_ = [
        ("connector_id", ctypes.c_uint32),
        ("encoder_id", ctypes.c_uint32),
        ("connector_type", ctypes.c_uint32),
        ("connector_type_id", ctypes.c_uint32),
        ("connection", ctypes.c_uint32),
        ("mmWidth", ctypes.c_uint32), ("mmHeight", ctypes.c_uint32),
        ("subpixel", ctypes.c_uint32),
        ("count_modes", ctypes.c_uint32),
        ("modes", ctypes.POINTER(drm_mode_modeinfo)),
        ("count_props", ctypes.c_uint32),
        ("props", ctypes.POINTER(ctypes.c_uint32)),
        ("prop_values", ctypes.POINTER(ctypes.c_uint64)),
        ("count_encoders", ctypes.c_uint32),
        ("encoders", ctypes.POINTER(ctypes.c_uint32)),
    ]


class drmModePropertyRes(ctypes.Structure):
    _fields_ = [
        ("prop_id", ctypes.c_uint32),
        ("flags", ctypes.c_uint32),
        ("name", ctypes.c_char * DRM_PROP_NAME_LEN),
        ("count_values", ctypes.c_uint32),
        ("count_enums", ctypes.c_uint32),
        ("count_blobs", ctypes.c_uint32),
        ("values", ctypes.POINTER(ctypes.c_uint64)),
        ("enums", ctypes.c_void_p),
        ("blob_ids", ctypes.POINTER(ctypes.c_uint32)),
    ]


class drmModeObjectProperties(ctypes.Structure):
    _fields_ = [
        ("count_props", ctypes.c_uint32),
        ("props", ctypes.POINTER(ctypes.c_uint32)),
        ("prop_values", ctypes.POINTER(ctypes.c_uint64)),
    ]


libdrm = ctypes.CDLL("libdrm.so.2", use_errno=True)
libdrm.drmModeGetResources.restype = ctypes.POINTER(drmModeRes)
libdrm.drmModeFreeResources.argtypes = [ctypes.POINTER(drmModeRes)]
libdrm.drmModeGetConnector.restype = ctypes.POINTER(drmModeConnector)
libdrm.drmModeGetConnector.argtypes = [ctypes.c_int, ctypes.c_uint32]
libdrm.drmModeFreeConnector.argtypes = [ctypes.POINTER(drmModeConnector)]
libdrm.drmModeObjectGetProperties.restype = ctypes.POINTER(drmModeObjectProperties)
libdrm.drmModeObjectGetProperties.argtypes = [ctypes.c_int, ctypes.c_uint32, ctypes.c_uint32]
libdrm.drmModeFreeObjectProperties.argtypes = [ctypes.POINTER(drmModeObjectProperties)]
libdrm.drmModeGetProperty.restype = ctypes.POINTER(drmModePropertyRes)
libdrm.drmModeGetProperty.argtypes = [ctypes.c_int, ctypes.c_uint32]
libdrm.drmModeFreeProperty.argtypes = [ctypes.POINTER(drmModePropertyRes)]
libdrm.drmModeObjectSetProperty.restype = ctypes.c_int
libdrm.drmModeObjectSetProperty.argtypes = [
    ctypes.c_int, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint64]


def err(msg):
    e = ctypes.get_errno()
    print(f"{msg}: errno={e} ({os.strerror(e)})")
    sys.exit(1)


def kwin_master_fds():
    """Duplicate DRM fds from kwin_wayland via pidfd_getfd (same drm_file => master)."""
    import glob
    libc = ctypes.CDLL("libc.so.6", use_errno=True)
    libc.syscall.restype = ctypes.c_int
    out = []
    pids = []
    for p in glob.glob("/proc/[0-9]*/comm"):
        try:
            if open(p).read().strip() == "kwin_wayland":
                pids.append(int(p.split("/")[2]))
        except OSError:
            pass
    for pid in pids:
        pidfd = libc.syscall(434, pid, 0)  # pidfd_open
        if pidfd < 0:
            e = ctypes.get_errno()
            print(f"pidfd_open({pid}) failed: {os.strerror(e)}")
            continue
        for path in glob.glob(f"/proc/{pid}/fd/*"):
            try:
                if os.readlink(path) != "/dev/dri/card1":
                    continue
                fdnum = int(path.rsplit("/", 1)[1])
                fd = libc.syscall(438, pidfd, fdnum, 0)  # pidfd_getfd
                if fd >= 0:
                    out.append((pid, fdnum, fd))
            except OSError:
                pass
        os.close(pidfd)
    return out


def find_dpms(fd, conn_id):
    props = libdrm.drmModeObjectGetProperties(fd, conn_id, DRM_MODE_OBJECT_CONNECTOR)
    if not props:
        return None, None
    op = props.contents
    dpms_id = cur = None
    for i in range(op.count_props):
        pid = op.props[i]
        prop = libdrm.drmModeGetProperty(fd, pid)
        if not prop:
            continue
        name = prop.contents.name.decode(errors="replace")
        if name == "DPMS":
            dpms_id = pid
            cur = op.prop_values[i]
        libdrm.drmModeFreeProperty(prop)
    libdrm.drmModeFreeObjectProperties(props)
    return dpms_id, cur


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "/dev/dri/card1"
    action = sys.argv[2] if len(sys.argv) > 2 else "info"
    fd = os.open(path, os.O_RDWR | os.O_CLOEXEC)
    res = libdrm.drmModeGetResources(fd)
    if not res:
        err("drmModeGetResources")
    r = res.contents

    target = None
    for i in range(r.count_connectors):
        cid = r.connectors[i]
        conn = libdrm.drmModeGetConnector(fd, cid)
        if not conn:
            continue
        c = conn.contents
        print(f"connector id={cid} type={c.connector_type} type_id={c.connector_type_id} "
              f"connection={c.connection} encoder_id={c.encoder_id} props={c.count_props}")
        if c.connector_type == 16 and target is None:  # DRM_MODE_CONNECTOR_DSI
            target = cid
        libdrm.drmModeFreeConnector(conn)
    libdrm.drmModeFreeResources(res)

    if target is None:
        print("no DSI connector found")
        sys.exit(1)
    conn_id = target
    print(f"card={path} using connector_id={conn_id}")

    props = libdrm.drmModeObjectGetProperties(fd, conn_id, DRM_MODE_OBJECT_CONNECTOR)
    if not props:
        err("drmModeObjectGetProperties")
    op = props.contents
    dpms_id = None
    cur = None
    for i in range(op.count_props):
        pid = op.props[i]
        prop = libdrm.drmModeGetProperty(fd, pid)
        if not prop:
            continue
        name = prop.contents.name.decode(errors="replace")
        if name == "DPMS":
            dpms_id = pid
            cur = op.prop_values[i]
            print(f"DPMS prop_id={pid} value={cur}")
        libdrm.drmModeFreeProperty(prop)
    libdrm.drmModeFreeObjectProperties(props)

    if dpms_id is None:
        print("DPMS property not found")
        sys.exit(1)
    if action == "info":
        return

    val = DRM_MODE_DPMS_OFF if action == "off" else DRM_MODE_DPMS_ON
    ctypes.set_errno(0)
    ret = libdrm.drmModeObjectSetProperty(fd, conn_id, DRM_MODE_OBJECT_CONNECTOR, dpms_id, val)
    if ret == 0:
        print(f"set DPMS {action} OK via own fd (was {cur})")
        return
    print(f"own fd: ret={ret} errno={ctypes.get_errno()} ({os.strerror(ctypes.get_errno())})")
    if ctypes.get_errno() != 13:
        sys.exit(1)

    # Fall back to kwin's master drm_file
    for pid, fdnum, kfd in kwin_master_fds():
        did, _ = find_dpms(kfd, conn_id)
        if did is None:
            os.close(kfd)
            continue
        ctypes.set_errno(0)
        ret = libdrm.drmModeObjectSetProperty(kfd, conn_id, DRM_MODE_OBJECT_CONNECTOR, did, val)
        e = ctypes.get_errno()
        print(f"kwin pid={pid} fd={fdnum}: ret={ret} errno={e} ({os.strerror(e) if ret else 'ok'})")
        os.close(kfd)
        if ret == 0:
            print(f"set DPMS {action} OK via kwin master fd")
            return
    print("no usable master fd")
    sys.exit(1)


if __name__ == "__main__":
    main()
