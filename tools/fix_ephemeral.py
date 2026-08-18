# -*- coding: utf-8 -*-
"""修复 windows/flutter/ephemeral/cpp_client_wrapper 文件缺失。

Flutter 3.47 在 Windows 上偶发：flutter_assemble 没有把引擎的
cpp_client_wrapper 完整复制到项目，导致 C1083 编译错误
（找不到 core_implementations.cc 等文件）。

用法：构建报 C1083 时先跑一次
    python tools/fix_ephemeral.py
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLUTTER = r'C:\flutter'  # SDK 路径（如安装位置不同请修改）
SRC = os.path.join(FLUTTER, 'bin', 'cache', 'artifacts', 'engine',
                   'windows-x64', 'cpp_client_wrapper')
DST = os.path.join(ROOT, 'windows', 'flutter', 'ephemeral', 'cpp_client_wrapper')

if not os.path.isdir(SRC):
    print('未找到 SDK 的 cpp_client_wrapper，请检查 FLUTTER 路径：' + SRC)
    sys.exit(1)

os.makedirs(DST, exist_ok=True)
copied = 0
for name in os.listdir(SRC):
    s = os.path.join(SRC, name)
    d = os.path.join(DST, name)
    if os.path.isfile(s) and not os.path.exists(d):
        shutil.copy2(s, d)
        copied += 1
print('完成：补充了 %d 个缺失文件' % copied if copied else '文件已完整，无需修复')
