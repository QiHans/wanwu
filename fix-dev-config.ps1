# ============================================
#  Wanwu Platform - 本机开发配置修正脚本
#  把生产版 config.yaml（服务名:端口）替换为本地 dev 版（localhost:端口）
#  由 start.bat 调用，也可手动执行：
#    powershell -ExecutionPolicy Bypass -File fix-dev-config.ps1
# ============================================

$ErrorActionPreference = "Continue"

# 所有微服务的 config.yaml
$configFiles = Get-ChildItem -Path 'configs\microservice' -Recurse -Filter 'config.yaml' | ForEach-Object { $_.FullName }

if ($configFiles.Count -eq 0) {
    Write-Host "[WARN] 未找到任何 config.yaml" -ForegroundColor Yellow
    exit 0
}

foreach ($configFile in $configFiles) {
    $txt = [System.IO.File]::ReadAllText($configFile)

    # --- 微服务 host: 服务名 -> localhost ---
    $txt = $txt -replace 'bff-service:6668', 'localhost:8088'
    $txt = $txt -replace 'iam-service:8888', 'localhost:8888'
    $txt = $txt -replace 'mcp-service:9898', 'localhost:9898'
    $txt = $txt -replace 'app-service:9988', 'localhost:9988'
    $txt = $txt -replace 'operate-service:9797', 'localhost:9797'
    $txt = $txt -replace 'channel-service:9990', 'localhost:9990'
    $txt = $txt -replace 'assistant-service:8890', 'localhost:8890'
    $txt = $txt -replace 'agent-service:8990', 'localhost:8990'
    $txt = $txt -replace 'knowledge-service:8889', 'localhost:8889'
    $txt = $txt -replace 'model-service:8989', 'localhost:8989'
    $txt = $txt -replace 'rag-service:9640', 'localhost:9640'
    $txt = $txt -replace 'workflow-wanwu:8999', 'localhost:8999'
    $txt = $txt -replace 'rag-wanwu:8681', 'localhost:8681'
    $txt = $txt -replace 'rag-wanwu:10891', 'localhost:10891'
    $txt = $txt -replace 'rag-wanwu:15000', 'localhost:15000'

    # --- 中间件 ---
    $txt = $txt -replace 'elastic-wanwu:9200', 'localhost:9200'
    $txt = $txt -replace 'minio-wanwu:9000', 'localhost:9000'
    $txt = $txt -replace 'https://localhost:9200', 'http://localhost:9200'

    # --- Redis 密码（本机 redis 无密码，清空）---
    $txt = $txt -replace "(`r`nredis:`r`n  host: localhost`r`n  port: 6379`r`n  username:`r`n  password:) Wanwu123456", '${1}'

    # --- BFF 专用：server 段、jwt、rsa ---
    if ($configFile -match 'bff-service') {
        $txt = $txt -replace "`r`n  host: bff-service`r`n", "`r`n  host: localhost`r`n"
        $txt = $txt -replace "`r`n  port: 6668`r`n", "`r`n  port: 8088`r`n"
        $txt = $txt -replace 'web_base_url: http://localhost:8081', 'web_base_url: http://localhost:8080'
        $txt = $txt -replace 'api_base_url: http://localhost:6668', 'api_base_url: http://localhost:8088'
        $txt = $txt -replace 'app_open_base_url: http://localhost:6668', 'app_open_base_url: http://localhost:8088'
        $txt = $txt -replace 'callback_url: http://bff-service:6668', 'callback_url: http://localhost:8088'
        $txt = $txt -replace '/app/tmp/rsa', 'project/rsa'
        $txt = $txt -replace "`r`n  signing-key:`r`n", "`r`n  signing-key: `"`"`r`n"
    }

    [System.IO.File]::WriteAllText($configFile, $txt)
    Write-Host "[INFO] Fixed: $configFile" -ForegroundColor Green
}

Write-Host "[INFO] All configs fixed for local dev" -ForegroundColor Green
