@echo off
:: 切换CMD编码为UTF-8，解决中文输出/输入乱码
chcp 65001 >nul
:: 清屏，让输出更整洁
cls



:: ====================== 脚本配置区（可根据需要调整） ======================
:: 钉钉启动后等待加载的时间（秒），低端手机可适当增加（如8-10）
set "load_delay=10"
:: 企业微信Webhook地址（用于发送通知）
set "webhook_url=https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=your_key"
:: 配置最大随机延迟时间（分钟），如5表示0-5分钟随机延迟
:: 防止每天同一时间打卡
set "max_random_delay_min=5"
:: 是否删除本地截图文件（true/false），默认true
set "delete_local_image=true"
:: =========================================================================


echo ======================
echo ADB启动钉钉脚本
echo ======================



:: =========================================================================
:: 判断当天是否为工作日，不是工作日直接退出
echo 正在检查今天是否为工作日...

:: 获取当前日期（格式：YYYY-MM-DD）
for /f "tokens=*" %%i in ('powershell -Command "Get-Date -Format \"yyyy-MM-dd\""') do set "today_date=%%i"
echo 当前日期：%today_date%

:: 调用公益接口（无需API Key），判断今天是否为工作日
set "api_url=https://timor.tech/api/holiday/info/%today_date%"
echo 正在查询工作日信息...

:: 使用PowerShell调用API并解析JSON
set "workday_type="
echo 正在调用API：%api_url%
for /f "tokens=* delims=" %%i in ('powershell -NoProfile -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $ErrorActionPreference = 'Stop'; try { $apiUrl = '%api_url%'; $response = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 10; if ($response.code -eq 0) { Write-Output $response.type.type } else { Write-Output 'ERROR' } } catch { Write-Output 'ERROR' }" 2^>nul') do set "workday_type=%%i"

:: 调试信息：显示获取到的值
if not defined workday_type (
    echo ❌ 错误：未获取到工作日类型，自动终止流程！
    :: 发送企业微信通知
    call :send_text_message "❌ 错误：未获取到工作日类型，自动终止打卡流程！"
    exit
) else (
    echo 获取到工作日类型：%workday_type%
)

:: 判断是否为工作日（type.type=0为工作日，其它为休息日）
if "%workday_type%"=="0" (
    echo ✅ 今天是工作日，继续执行打卡流程...
    echo.
) else if "%workday_type%"=="ERROR" (
    echo ⚠️ 无法获取工作日信息，默认继续执行打卡流程...
    echo.
) else (
    :: 获取节假日名称用于显示
    set "holiday_name="
    for /f "tokens=*" %%i in ('powershell -NoProfile -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; try { $apiUrl = '%api_url%'; $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop; if ($response.code -eq 0) { Write-Output $response.type.name } else { Write-Output '未知' } } catch { Write-Output '未知' }"') do set "holiday_name=%%i"
    if not defined holiday_name set "holiday_name=未知"
    echo ❌ 今天是休息日（%holiday_name%），无需打卡，脚本退出！
    echo 等待3秒后退出...
    call :countdown 3
    exit
)


:: =========================================================================
:: 随机延迟时间执行
:: 计算随机延迟秒数（0~max_random_delay_min*60之间的随机数）
set /a "max_random_delay_sec=%max_random_delay_min%*60"
set /a "random_delay=%RANDOM% %% (%max_random_delay_sec% + 1)"
:: 输出倒计时
echo 即将随机延迟 %random_delay% 秒...
echo.
call :countdown %random_delay%
echo 延迟完成！
echo.
:: =========================================================================



:: =========================================================================
:: 检查ADB设备是否连接
echo 正在检查安卓设备连接状态...
adb devices >nul 2>&1
:: 判断ADB命令是否执行成功（设备未连接时errorlevel=1）
if errorlevel 1 (
    echo ❌ 错误：未检测到ADB环境或设备未连接！
    echo 请确认：
    echo 1. ADB已配置环境变量或脚本中使用ADB绝对路径
    echo 2. 手机已开启USB调试并通过USB/无线连接电脑
    :: 发送企业微信通知
    call :send_text_message "❌ ADB设备检查失败错误：未检测到ADB环境或设备未连接！请确认：1. ADB已配置环境变量或脚本中使用ADB绝对路径2. 手机已开启USB调试并通过USB/无线连接电脑"
    pause
    exit
)

:: 检查设备是否在线（排除offline/unauthorized状态）
for /f "tokens=2" %%i in ('adb devices ^| findstr "device"') do (
    if "%%i"=="device" (
        set "device_online=1"
    )
)
if not defined device_online (
    echo ❌ 错误：设备未授权（unauthorized）或离线（offline）！
    echo 请在手机上确认USB调试授权，或重新插拔数据线。
    :: 发送企业微信通知
    call :send_text_message "❌ ADB设备检查失败错误：设备未授权（unauthorized）或离线（offline）！请在手机上确认USB调试授权，或重新插拔数据线。"
    pause
    exit
)
echo ✅ 设备连接正常！


:: =========================================================================
:: 检查屏幕是否点亮
echo 正在检查屏幕是否点亮...
:: 检查屏幕状态（mScreenOn=true表示屏幕点亮，mScreenOn=false表示屏幕未点亮）
for /f "tokens=*" %%i in ('adb shell "dumpsys deviceidle | grep mScreenOn"') do set "screen_status=%%i"
echo 屏幕状态：%screen_status%
:: 检查是否包含 mScreenOn=false（屏幕未点亮）
echo %screen_status% | findstr /C:"mScreenOn=false" >nul 2>&1
if not errorlevel 1 (
    echo 屏幕未点亮，正在点亮屏幕...
    :: 发送电源键唤醒屏幕
    adb shell input keyevent 26
    :: 等待屏幕点亮（等待2秒）
    echo 等待屏幕点亮（2秒）...
    call :countdown 2
) else (
    :: 检查是否包含 mScreenOn=true（屏幕已点亮）
    echo %screen_status% | findstr /C:"mScreenOn=true" >nul 2>&1
    if not errorlevel 1 (
        echo ✅ 屏幕已点亮
    ) else (
        echo ⚠️ 无法确定屏幕状态，尝试点亮屏幕...
        adb shell input keyevent 26
        echo 等待屏幕点亮（2秒）...
        call :countdown 2
    )
)


:: =========================================================================
:: 强制停止钉钉（可选，避免钉钉后台运行导致启动异常）
echo 正在清理钉钉后台进程...
adb shell am force-stop com.alibaba.android.rimet >nul 2>&1

:: 启动钉钉应用（核心命令）
echo 正在启动钉钉应用...
:: 钉钉的正确包名+启动Activity（关键！不可随意修改）
adb shell am start -n com.alibaba.android.rimet/com.alibaba.android.rimet.biz.LaunchHomeActivity

:: 判断启动命令是否执行成功
if errorlevel 1 (                           
    echo ❌ 错误：钉钉启动失败！
    echo 可能原因：钉钉包名/Activity路径错误，或手机未安装钉钉。
    :: 发送企业微信通知
    call :send_text_message "❌ 错误：钉钉启动失败！可能原因：钉钉包名/Activity路径错误，或手机未安装钉钉。"
    pause
    exit
)

:: 等待钉钉加载完成
echo 钉钉已启动，正在等待应用加载（%load_delay%秒）...
call :countdown %load_delay%



:: =========================================================================
:: 打卡流程
:: 进入到钉钉考勤打卡页面
echo 正在进入到钉钉考勤打卡页面...

echo 点击工作台...
adb shell input tap 468 2041

echo 等待应用加载（%load_delay%秒）...
call :countdown %load_delay%

echo 点击考勤打卡...
adb shell input tap 145 885

echo 等待应用加载（%load_delay%秒）...
call :countdown %load_delay%

echo 点击打卡按钮...
adb shell input tap 548 1317

echo 等待应用加载（%load_delay%秒）...
call :countdown %load_delay%


:: =========================================================================
:: 设置截图保存目录为脚本所在目录下的screenshot文件夹
set "screenshot_dir=%~dp0screenshot"

:: 确保截图保存目录存在，如果不存在则创建
if not exist "%screenshot_dir%" (
    echo 截图目录不存在，正在创建：%screenshot_dir%
    mkdir "%screenshot_dir%"
)

:: 截屏保存为PNG格式到电脑目录
echo 正在截屏保存为PNG格式到电脑目录...
:: 生成当前时间戳作为文件名（格式：YYYY-MM-DD_HH-MM-SS）
for /f "tokens=*" %%i in ('powershell -Command "Get-Date -Format \"yyyy-MM-dd_HH-mm-ss\""') do set "timestamp=%%i"
set "screenshot_name=%timestamp%.png"
adb shell screencap -p /sdcard/Pictures/%screenshot_name%
adb pull /sdcard/Pictures/%screenshot_name% %screenshot_dir%
adb shell rm /sdcard/Pictures/%screenshot_name%

:: 将保存的截图发送给企业微信群
echo 正在发送截图到企业微信群...
set "screenshot_path=%screenshot_dir%\%screenshot_name%"

:: 检查截图文件是否存在
if not exist "%screenshot_path%" (
    echo ❌ 错误：截图文件不存在：%screenshot_path%
    goto :end_send
)

:: =========================================================================
:: 发送钉钉消息打卡成功
echo 发送钉钉消息打卡成功...
call :send_text_message "✅打卡截图凭证："

echo 等待1秒...
call :countdown 1

:: 使用函数发送图片到企业微信
call :send_image_message "%screenshot_path%"

:end_send


:: =========================================================================
:: 打卡成功后，关闭钉钉应用
echo 打卡成功后，返回桌面...
@REM adb shell am force-stop com.alibaba.android.rimet
adb shell input keyevent 3

:: 等待3秒...
echo 等待3秒...
call :countdown 3

:: 关闭手机屏幕
echo 关闭手机屏幕...
adb shell input keyevent 26

:: =========================================================================
:: 结束任务
echo 任务结束...
echo =========================================================================

goto :eof

:: ====================== 发送消息函数 ======================
:: 函数：发送文本消息到企业微信
:: 参数：第一个参数为消息内容
:send_text_message
setlocal
set "message_content=%~1"
echo 正在发送消息到企业微信群...
powershell -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $webhookUrl = '%webhook_url%'; $content = '%message_content%'; $body = @{ msgtype = 'text'; text = @{ content = $content } } | ConvertTo-Json -Depth 10; $utf8 = New-Object System.Text.UTF8Encoding $false; $bodyBytes = $utf8.GetBytes($body); try { Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $bodyBytes -ContentType 'application/json; charset=utf-8' | Out-Null } catch { }"
endlocal
exit /b

:: 函数：发送图片消息到企业微信
:: 参数：第一个参数为图片文件路径
:send_image_message
setlocal
set "image_path=%~1"
if not exist "%image_path%" (
    echo ❌ 错误：图片文件不存在：%image_path%
    endlocal
    exit /b
)
echo 正在发送图片到企业微信群...
powershell -Command "$filePath = '%image_path%'; $webhookUrl = '%webhook_url%'; $deleteLocalImage = '%delete_local_image%'; if (-not (Test-Path $filePath)) { Write-Host '❌ 错误：截图文件不存在'; exit; }; $fileBytes = [System.IO.File]::ReadAllBytes($filePath); $base64 = [System.Convert]::ToBase64String($fileBytes); $md5 = (Get-FileHash -Path $filePath -Algorithm MD5).Hash.ToLower(); $body = @{ msgtype = 'image'; image = @{ base64 = $base64; md5 = $md5 } } | ConvertTo-Json -Depth 10; try { $response = Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $body -ContentType 'application/json'; if ($response.errcode -eq 0) { Write-Host '✅ 截图已成功发送到企业微信群！'; if ($deleteLocalImage -eq 'true') { Remove-Item -Path $filePath -Force; Write-Host '✅ 本地截图文件已清理' } else { Write-Host '✅ 本地截图文件已保留' } } else { Write-Host '❌ 发送失败：' $response.errmsg } } catch { Write-Host '❌ 发送失败：' $_.Exception.Message }"
endlocal
exit /b
:: =========================================================================

:: ====================== 倒计时函数 ======================
:: 函数：显示倒计时
:: 参数：第一个参数为倒计时秒数
:countdown
setlocal enabledelayedexpansion
set /a "countdown=%~1"
if !countdown! LEQ 0 (
    endlocal
    exit /b
)
:countdown_loop
echo 倒计时：!countdown! 秒...
timeout /t 1 /nobreak >nul
set /a "countdown-=1"
if !countdown! GTR 0 goto :countdown_loop
endlocal
exit /b
:: =========================================================================