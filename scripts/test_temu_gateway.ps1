# Test gateway-deliver → Temu OpenAPI router
# Usage:
#   .\scripts\test_temu_gateway.ps1
#   .\scripts\test_temu_gateway.ps1 -GatewayToken "your-token"
#   $env:GATEWAY_TOKEN = "your-token"; .\scripts\test_temu_gateway.ps1

param(
    [string]$Gateway = "https://gateway-deliver.zhuangyanliuhe.workers.dev",
    [string]$Target = "https://openapi-b-us.temu.com/openapi/router",
    [string]$GatewayToken = $env:GATEWAY_TOKEN
)

$ErrorActionPreference = "Stop"
$StatusMark = "___HTTP_STATUS___"

function Write-Step([string]$Title) {
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Invoke-Curl {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CurlArgs,
        [string]$Label
    )

    $allArgs = $CurlArgs + @("-w", "${StatusMark}%{http_code}")
    Write-Host ("CMD: curl.exe {0}" -f ($CurlArgs -join " ")) -ForegroundColor DarkGray
    $raw = & curl.exe @allArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host $raw
        throw "$Label failed (curl exit $LASTEXITCODE)"
    }

    $text = ($raw | Out-String)
    $idx = $text.LastIndexOf($StatusMark)
    if ($idx -lt 0) {
        throw "$Label: missing status marker in curl output"
    }
    $body = $text.Substring(0, $idx).TrimEnd()
    $status = $text.Substring($idx + $StatusMark.Length).Trim()

    Write-Host ("HTTP status: {0}" -f $status)
    $preview = if ($body.Length -gt 800) { $body.Substring(0, 800) + "..." } else { $body }
    Write-Host "Body:"
    Write-Host $preview
    return @{ Status = $status; Body = $body }
}

Write-Step "1) Gateway health"
$health = Invoke-Curl -Label "health" -CurlArgs @("-sS", "$Gateway/health")
if ($health.Status -notmatch "^2") {
    throw "Health check failed"
}

Write-Step "2) Forward POST via X-Forward-To"
$payload = '{"type":"bg.local.openapicall","timestamp":' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + '}'
$fwdArgs = @(
    "-sS",
    "-X", "POST",
    "$Gateway/",
    "-H", "Content-Type: application/json",
    "-H", "Accept: application/json",
    "-H", "X-Forward-To: $Target",
    "--data-raw", $payload
)
if ($GatewayToken) {
    $fwdArgs += @("-H", "Authorization: Bearer $GatewayToken")
}
$fwd = Invoke-Curl -Label "forward-post" -CurlArgs $fwdArgs

Write-Step "3) Forward GET via /proxy/<url>"
$pathArgs = @("-sS", "$Gateway/proxy/$Target")
if ($GatewayToken) {
    $pathArgs += @("-H", "Authorization: Bearer $GatewayToken")
}
$null = Invoke-Curl -Label "forward-path" -CurlArgs $pathArgs

Write-Step "4) Check X-Gateway response header (POST)"
$headerArgs = @(
    "-sS", "-D", "-", "-o", "NUL",
    "-X", "POST",
    "$Gateway/",
    "-H", "Content-Type: application/json",
    "-H", "X-Forward-To: $Target",
    "--data-raw", $payload
)
if ($GatewayToken) {
    $headerArgs += @("-H", "Authorization: Bearer $GatewayToken")
}
Write-Host ("CMD: curl.exe {0}" -f ($headerArgs -join " ")) -ForegroundColor DarkGray
$hdrOut = & curl.exe @headerArgs 2>&1 | Out-String
Write-Host $hdrOut
if ($hdrOut -match "(?im)^X-Gateway:\s*gateway-deliver") {
    Write-Host "X-Gateway header present." -ForegroundColor Green
} else {
    Write-Host "WARN: X-Gateway header not found." -ForegroundColor Yellow
}

Write-Step "Summary"
if ($fwd.Status -eq "502") {
    Write-Host "FAIL: gateway could not reach upstream (502)." -ForegroundColor Red
    Write-Host "If error mentions 'too many values to unpack', redeploy the header-iteration fix first." -ForegroundColor Yellow
    exit 1
}
if ($fwd.Status -eq "401" -and -not $GatewayToken) {
    Write-Host "Gateway requires GATEWAY_TOKEN. Re-run with -GatewayToken or `$env:GATEWAY_TOKEN." -ForegroundColor Yellow
    exit 1
}

Write-Host ("OK: gateway returned upstream HTTP {0} for Temu router." -f $fwd.Status) -ForegroundColor Green
Write-Host "Note: Temu often returns 4xx without valid app_key/sign — that still means proxying works." -ForegroundColor Yellow
