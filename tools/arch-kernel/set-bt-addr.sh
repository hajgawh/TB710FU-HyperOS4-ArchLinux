#!/bin/sh
# 兼容旧文档的薄包装；真正的实现在 set-bt-addr.py（Python 3）。
exec "$(dirname "$0")/set-bt-addr.py" "$@"
