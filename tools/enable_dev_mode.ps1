# 启用 Windows 开发人员模式（Flutter 插件构建需要符号链接支持）
# 会弹出 UAC 提权确认框，点击"是"即可
Start-Process reg -ArgumentList @(
    'add',
    'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock',
    '/t', 'REG_DWORD',
    '/f',
    '/v', 'AllowDevelopmentWithoutDevLicense',
    '/d', '1'
) -Verb RunAs -Wait
Write-Output 'DEV_MODE_OK'
