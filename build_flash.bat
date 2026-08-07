@echo off
chcp 65001
echo ======================================================
echo  鸿蒙开发板 命令行编译 + 安装
echo  Mode: CLI build (DevEco node + hvigor)
echo ======================================================

cd /d "%~dp0"

:: 【必改】PackageHap 需要 java；使用 DevEco 自带 JBR（路径勿含空格）
set "JAVA_HOME=D:\DevEcoStudio\jbr"
set "PATH=%JAVA_HOME%\bin;D:\DevEcoStudio\tools\node;%PATH%"

:: 【必改】HAP 输出路径（相对工程根目录；常见为 products\phone 或 product\phone，以首次编译产物为准）
set "HAP_PATH=entry\build\default\outputs\default\browser-default-signed.hap"

:: ===================== 步骤1：清理旧包 =====================
echo.
echo [1] 清理旧 HAP 包...
if exist "%HAP_PATH%" (
    del /f /q "%HAP_PATH%"
    echo 已清理旧包
)

:: ===================== 步骤2：命令行编译 =====================
echo.
echo ========== 开始编译（纯命令行） ==========
D:\DevEcoStudio\tools\node\node.exe D:\DevEcoStudio\tools\hvigor\bin\hvigorw.js --mode module -p product=default assembleHap --no-daemon

if %errorlevel% neq 0 (
    echo.
    echo 编译失败！
    pause
    exit /b 1
)

if not exist "%HAP_PATH%" (
    echo.
    echo HAP 包未生成！
    pause
    exit /b 1
)

echo.
echo 编译成功！

:: ===================== 步骤3：确认安装 =====================
echo.
echo ========== 输入 Y 确认安装到开发板 ==========
set /p confirm=请输入 Y 确认:
if /i not "%confirm%"=="Y" (
    echo 已取消安装
    pause
    exit /b 0
)

:: ===================== 步骤4：烧录开发板 =====================
echo.
echo ========== 开始安装 ==========
hdc install -r "%CD%\%HAP_PATH%"
hdc shell reboot

echo.
echo ========== 全部完成！ ==========
pause
