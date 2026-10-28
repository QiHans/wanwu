@echo off
setlocal enabledelayedexpansion

:: ============================================
::  Wanwu Platform - Windows Launcher
::  Usage: start.bat          Start all
::         start.bat stop     Stop all
::         start.bat status   Show status
::         start.bat help     Show help
:: ============================================

set "PROJECT_DIR=%~dp0"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
cd /d "%PROJECT_DIR%"

set "TOOLS_DIR=%USERPROFILE%\tools"
set "MYSQL_DIR=%TOOLS_DIR%\mysql\bin"
set "REDIS_DIR=%TOOLS_DIR%\redis"
set "MINIO_DIR=%TOOLS_DIR%\minio"
set "ES_DIR=%TOOLS_DIR%\elasticsearch\bin"
set "DATA_DIR=%PROJECT_DIR%\project\data"
set "LOG_DIR=%PROJECT_DIR%\project\logs"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

if /i "%~1"=="stop"    goto :STOP
if /i "%~1"=="frontend" goto :FRONTEND
if /i "%~1"=="middleware" goto :MIDDLEWARE
if /i "%~1"=="backend"  goto :BACKEND
if /i "%~1"=="status"  goto :STATUS
if /i "%~1"=="help"    goto :HELP
if /i "%~1"=="-h"      goto :HELP
if /i "%~1"=="--help"  goto :HELP

:: ==========================================
:: Main entry: start everything in order
:: ==========================================
:START_ALL
echo ============================================
echo   Wanwu Platform - Starting All Services
echo ============================================
echo.

:: 本机开发：把生产版 config.yaml（服务名:端口）替换成本地 dev 版（localhost:端口）
call :FIX_DEV_CONFIG

call :START_MIDDLEWARE
if errorlevel 1 (
    echo.
    echo [ERROR] 中间件启动失败, 终止.
    goto :EOF
)

call :START_BACKEND

call :START_FRONTEND

echo.
echo ============================================
echo   Frontend : http://localhost:8080/aibase/
echo   API      : http://localhost:8088/v1/
echo   Account  : admin / Wanwu123456
echo ============================================
echo.
echo   start.bat stop    - Stop all services
echo   start.bat status  - Show status
echo.
goto :EOF

:: ==========================================
:: Start middleware (MySQL/Redis/MinIO/ES) with health check
:: ==========================================
:MIDDLEWARE
call :START_MIDDLEWARE
goto :EOF

:START_MIDDLEWARE
echo [1/4] Starting middleware...
echo.

:: ---- Redis (最快, 先启动) ----
echo   Redis...
start "wanwu-redis" /min "%REDIS_DIR%\redis-server.exe" --port 6379

:: ---- MySQL ----
echo   MySQL...
if not exist "%DATA_DIR%\mysql" mkdir "%DATA_DIR%\mysql"
start "wanwu-mysql" /min "%MYSQL_DIR%\mysqld.exe" --datadir="%DATA_DIR%\mysql" --port=3306 --console

:: ---- MinIO (必须设置账号密码) ----
echo   MinIO...
if not exist "%DATA_DIR%\minio" mkdir "%DATA_DIR%\minio"
set "MINIO_ROOT_USER=root"
set "MINIO_ROOT_PASSWORD=Wanwu123456"
start "wanwu-minio" /min "%MINIO_DIR%\minio.exe" server "%DATA_DIR%\minio" --address ":9000" --console-address ":9001"

:: ---- Elasticsearch (可选, 不影响登录) ----
echo   Elasticsearch...
start "wanwu-elastic" /min "%ES_DIR%\elasticsearch.bat"

:: ---- 健康检查 ----
echo.
echo   Waiting for middleware to be ready...

set "REDIS_READY="
set "MYSQL_READY="
set "MINIO_READY="
set /a RETRY=0
set /a MAX_RETRY=60

:WAIT_LOOP
set /a RETRY+=1
if !RETRY! gtr !MAX_RETRY! (
    echo.
    echo [ERROR] 中间件在 !MAX_RETRY! 次尝试后仍未就绪:
    if not defined REDIS_READY  echo   - Redis  :6379 未就绪
    if not defined MYSQL_READY  echo   - MySQL  :3306 未就绪
    if not defined MINIO_READY  echo   - MinIO  :9000 未就绪
    echo   请检查 project\logs 下的日志排查原因.
    exit /b 1
)

if not defined REDIS_READY (
    netstat -ano 2>nul | findstr /C:":6379 " >nul && set "REDIS_READY=1"
)
if not defined MYSQL_READY (
    netstat -ano 2>nul | findstr /C:":3306 " >nul && set "MYSQL_READY=1"
)
if not defined MINIO_READY (
    netstat -ano 2>nul | findstr /C:":9000 " >nul && set "MINIO_READY=1"
)

if defined REDIS_READY if defined MYSQL_READY if defined MINIO_READY goto :MW_DONE

timeout /t 2 /nobreak >nul
goto :WAIT_LOOP

:MW_DONE
echo.
echo   [OK] 中间件就绪: Redis ^(6379^) MySQL ^(3306^) MinIO ^(9000^)
echo.
exit /b 0

:: ==========================================
:: Start Go backend microservices
:: ==========================================
:BACKEND
call :START_BACKEND
goto :EOF

:START_BACKEND
echo [2/4] Starting Go microservices...
echo.

set "CFG_ROOT=%PROJECT_DIR%\configs\microservice"
set "BIN_DIR=%PROJECT_DIR%\bin"

:: service_name:exe_args (noarg = 硬编码配置, 无需 -config)
set "SVC_LIST=iam-service: model-service:noarg mcp-service: app-service: operate-service: channel-service: assistant-service: agent-service:noarg knowledge-service:noarg"

for %%i in (%SVC_LIST%) do (
    for /f "tokens=1,2 delims=:" %%a in ("%%i") do (
        set "svc=%%a"
        set "arg=%%b"
        echo   !svc!...
        if "!arg!"=="noarg" (
            start "wanwu-!svc!" /min "!BIN_DIR!\!svc!.exe"
        ) else (
            start "wanwu-!svc!" /min "!BIN_DIR!\!svc!.exe" -config "!CFG_ROOT!\!svc!\configs\config.yaml"
        )
        timeout /t 2 /nobreak >nul
    )
)

echo.
echo   Waiting for microservices to be ready...

set /a SRETRY=0
set /a SMAX=30

:SVC_WAIT_LOOP
set /a SRETRY+=1
if !SRETRY! gtr !SMAX! goto :SVC_DONE

netstat -ano 2>nul | findstr /C:":8888 " >nul && goto :SVC_DONE

timeout /t 2 /nobreak >nul
goto :SVC_WAIT_LOOP

:SVC_DONE
echo   [OK] microservices started
echo.

:: ==========================================
echo [3/4] Starting BFF API Gateway...
echo.
start "wanwu-bff-service" /min "%BIN_DIR%\bff-service.exe" -config "%CFG_ROOT%\bff-service\configs\config.yaml"

echo   Waiting for BFF (8088)...
set /a BRETRY=0
set /a BMAX=30

:BFF_WAIT_LOOP
set /a BRETRY+=1
if !BRETRY! gtr !BMAX! goto :BFF_DONE

netstat -ano 2>nul | findstr /C:":8088 " >nul && goto :BFF_DONE

timeout /t 2 /nobreak >nul
goto :BFF_WAIT_LOOP

:BFF_DONE
echo   [OK] BFF started
echo.
exit /b 0

:: ==========================================
:START_FRONTEND
echo [4/4] Starting frontend...
echo.
cd /d "%PROJECT_DIR%\web"
start "wanwu-frontend" /min cmd /c "npx vue-cli-service serve --port 8080"
cd /d "%PROJECT_DIR%"
exit /b 0

:: ==========================================
:FRONTEND
echo Starting frontend...
cd /d "%PROJECT_DIR%\web"
start "wanwu-frontend" /min cmd /c "npx vue-cli-service serve --port 8080"
cd /d "%PROJECT_DIR%"
echo http://localhost:8080/aibase/
goto :EOF

:: ==========================================
:STOP
echo Stopping all Wanwu services...
set "TITLES=wanwu-mysql wanwu-redis wanwu-minio wanwu-elastic wanwu-iam-service wanwu-model-service wanwu-mcp-service wanwu-app-service wanwu-operate-service wanwu-channel-service wanwu-assistant-service wanwu-agent-service wanwu-knowledge-service wanwu-bff-service wanwu-frontend"
for %%t in (%TITLES%) do (
    taskkill /FI "WINDOWTITLE eq %%t" /F >nul 2>&1
)
:: 兜底: 按进程名再杀一遍 (防止窗口标题不匹配)
taskkill /F /IM mysqld.exe >nul 2>&1
taskkill /F /IM redis-server.exe >nul 2>&1
taskkill /F /IM minio.exe >nul 2>&1
echo Done.
goto :EOF

:: ==========================================
:STATUS
echo ========== Wanwu Services ==========
echo.
netstat -ano 2>nul | findstr /C:":3306 " >nul && echo   [OK] MySQL    :3306    || echo   [--] MySQL    :3306
netstat -ano 2>nul | findstr /C:":6379 " >nul && echo   [OK] Redis    :6379    || echo   [--] Redis    :6379
netstat -ano 2>nul | findstr /C:":9000 " >nul && echo   [OK] MinIO    :9000    || echo   [--] MinIO    :9000
netstat -ano 2>nul | findstr /C:":9200 " >nul && echo   [OK] ES       :9200    || echo   [--] ES       :9200
netstat -ano 2>nul | findstr /C:":8888 " >nul && echo   [OK] IAM      :8888    || echo   [--] IAM      :8888
netstat -ano 2>nul | findstr /C:":8989 " >nul && echo   [OK] Model    :8989    || echo   [--] Model    :8989
netstat -ano 2>nul | findstr /C:":9898 " >nul && echo   [OK] MCP      :9898    || echo   [--] MCP      :9898
netstat -ano 2>nul | findstr /C:":8889 " >nul && echo   [OK] Knowledge:8889    || echo   [--] Knowledge:8889
netstat -ano 2>nul | findstr /C:":9988 " >nul && echo   [OK] App      :9988    || echo   [--] App      :9988
netstat -ano 2>nul | findstr /C:":9797 " >nul && echo   [OK] Operate  :9797    || echo   [--] Operate  :9797
netstat -ano 2>nul | findstr /C:":9990 " >nul && echo   [OK] Channel  :9990    || echo   [--] Channel  :9990
netstat -ano 2>nul | findstr /C:":8890 " >nul && echo   [OK] Assistant:8890    || echo   [--] Assistant:8890
netstat -ano 2>nul | findstr /C:":8990 " >nul && echo   [OK] Agent    :8990    || echo   [--] Agent    :8990
netstat -ano 2>nul | findstr /C:":8088 " >nul && echo   [OK] BFF      :8088    || echo   [--] BFF      :8088
netstat -ano 2>nul | findstr /C:":8080 " >nul && echo   [OK] Frontend :8080    || echo   [--] Frontend :8080
echo.
goto :EOF

:: ==========================================
:: 本机开发：把生产版 config.yaml 替换成本地 dev 版
:: 生产版: bff-service:6668, 服务名, 带密码等
::   替换为 dev 版: localhost:8088, localhost, 无密码等
:: ==========================================
:FIX_DEV_CONFIG
echo   Fixing config for local dev...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\fix-dev-config.ps1" >nul 2>&1
echo   Config fixed for local dev
goto :EOF

:: ==========================================
:HELP
echo Wanwu Platform - Windows Launcher
echo.
echo Usage: start.bat [command]
echo.
echo Commands:
echo   (none)      Start all services (middleware + backend + frontend)
echo   stop        Stop all services
echo   status      Show service status
echo   middleware  Start middleware only (MySQL/Redis/MinIO/ES)
echo   backend     Start Go backend + BFF only
echo   frontend    Start frontend dev server only
echo   help        Show this help
echo.
goto :EOF
