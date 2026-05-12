param(
    [string]$ProjectPath = 'D:\Quarto\Foxmir_blog',
    [string]$LogPath = 'C:\Users\李勇\OneDrive\Markdown\1-Work\Blog\LOG.md',
    [string]$CommitMessage = 'Update blog content'
)

$ErrorActionPreference = 'Stop'

function Write-StageHeader {
    param(
        [Parameter(Mandatory = $true)][int]$Step,
        [Parameter(Mandatory = $true)][int]$Total,
        [Parameter(Mandatory = $true)][string]$Title
    )

    $line = ('#' * 24) + (' [阶段 {0}/{1}] {2} ' -f $Step, $Total, $Title) + ('#' * 24)
    Write-Host "`n$line" -ForegroundColor Cyan
}

function Convert-OutputLines {
    param([AllowNull()][object[]]$Output)

    return @($Output | ForEach-Object {
        if ($null -eq $_) { return }
        $_.ToString().TrimEnd()
    } | Where-Object { $_ -ne '' })
}

function Get-TailLines {
    param(
        [AllowNull()][string[]]$Lines,
        [int]$Count = 10
    )

    if ($null -eq $Lines -or $Lines.Count -eq 0) {
        return @('（无输出）')
    }

    return @($Lines | Select-Object -Last $Count)
}

function Write-Utf8Text {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Add-LogEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Summary,
        [AllowNull()][string[]]$Details
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $detailLines = @($Details | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $entryLines = @(
        '============================================================',
        ('时间: ' + $timestamp),
        ('标题: ' + $Title),
        ('结论: ' + $Summary)
    )

    if ($detailLines.Count -gt 0) {
        $entryLines += '详情:'
        $entryLines += @($detailLines | ForEach-Object { '  ' + $_ })
    }

    $entryLines += @(
        '============================================================',
        ''
    )

    $newEntry = [string]::Join([Environment]::NewLine, $entryLines)
    $existingContent = if (Test-Path -LiteralPath $LogPath) {
        [System.IO.File]::ReadAllText($LogPath)
    } else {
        ''
    }

    if ([string]::IsNullOrWhiteSpace($existingContent)) {
        Write-Utf8Text -Path $LogPath -Content ($newEntry + [Environment]::NewLine)
        return
    }

    $mergedContent = $newEntry + [Environment]::NewLine + $existingContent.TrimStart("`r", "`n")
    Write-Utf8Text -Path $LogPath -Content $mergedContent
}

function Get-ChineseReason {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [AllowNull()][string[]]$Lines
    )

    $text = ([string]::Join("`n", ($Lines | ForEach-Object { $_ })))
    switch -Regex ($text) {
        'Connection timed out|timed out' { return 'Git 推送超时，通常是网络、代理、DNS 或 GitHub 连接异常。' }
        'Authentication failed|could not read Username|repository not found|Permission denied' { return 'Git 推送认证失败，请检查账号凭据、令牌或远程仓库权限。' }
        'Could not resolve host' { return '网络解析失败，Git 无法解析 GitHub 地址。' }
        'os error 32|另一个程序正在使用此文件' { return '渲染输出目录被其他进程占用，通常是本地预览服务或文件句柄未释放。' }
        'Attachment resolution failed' { return 'Obsidian 引用的附件解析失败。' }
        'Missing attachments' { return '存在缺失附件，发布已中止。' }
        'Conflicting attachments' { return '存在同名附件冲突，无法确定应引用哪一个文件。' }
        'index\.html not found|index.html 未生成' { return '站点首页未生成，说明渲染结果不完整。' }
        default { return ($Stage + '失败，请查看详情输出。') }
    }
}

function Fail-Workflow {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [AllowNull()][string[]]$Lines
    )

    $tailLines = Get-TailLines -Lines $Lines -Count 20
    $reason = Get-ChineseReason -Stage $Title -Lines $tailLines
    Write-Host ('[失败] ' + $reason) -ForegroundColor Red
    Add-LogEntry -Title $Title -Summary $reason -Details $tailLines
    throw $reason
}

function Invoke-CommandCapture {
    param([Parameter(Mandatory = $true)][scriptblock]$Script)

    $output = @()
    $failed = $false
    $exitCode = 0

    try {
        $output = & $Script 2>&1
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) {
            $exitCode = 0
        }
        $failed = ($exitCode -ne 0)
    } catch {
        $failed = $true
        $exitCode = if ($LASTEXITCODE) { $LASTEXITCODE } else { 1 }
        $output = @($output) + $_
    }

    return [pscustomobject]@{
        Failed = $failed
        ExitCode = $exitCode
        Lines = @(Convert-OutputLines -Output $output)
    }
}

Write-Host "`n######################## 唯一发布入口：workflow_script.ps1 ########################" -ForegroundColor Green

Push-Location $ProjectPath
try {
    Write-StageHeader -Step 1 -Total 6 -Title '清理环境'
    Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process quarto -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Job -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
    $env:TMP = 'D:\TempJunk'
    $env:TEMP = 'D:\TempJunk'
    Write-Host ('[完成] 已清理 Python/Quarto 进程，TMP=' + $env:TMP) -ForegroundColor DarkGray

    Write-StageHeader -Step 2 -Total 6 -Title '同步 Obsidian 内容'
    $syncResult = Invoke-CommandCapture -Script {
        powershell -NoProfile -ExecutionPolicy Bypass -File '.\tools\sync-blog.ps1'
    }
    Get-TailLines -Lines $syncResult.Lines -Count 12 | ForEach-Object { Write-Host ('  ' + $_) }
    if ($syncResult.Failed) {
        Fail-Workflow -Title '同步 Obsidian 内容' -Lines $syncResult.Lines
    }

    Write-StageHeader -Step 3 -Total 6 -Title '渲染 Quarto 站点'
    $renderResult = Invoke-CommandCapture -Script {
        D:\Quarto\bin\quarto.exe render
    }
    Get-TailLines -Lines $renderResult.Lines -Count 12 | ForEach-Object { Write-Host ('  ' + $_) }
    if ($renderResult.Failed) {
        Fail-Workflow -Title '渲染 Quarto 站点' -Lines $renderResult.Lines
    }
    if (-not (Test-Path -LiteralPath '.\docs\index.html')) {
        Fail-Workflow -Title '检查渲染结果' -Lines @('index.html 未生成。')
    }
    Write-Utf8Text -Path '.\docs\.nojekyll' -Content ''
    $indexSize = (Get-Item '.\docs\index.html').Length
    Write-Host ('[完成] docs\index.html 已生成，大小: ' + $indexSize + ' 字节；docs\.nojekyll 已恢复。') -ForegroundColor DarkGray

    Write-StageHeader -Step 4 -Total 6 -Title '检查 Git 变更'
    $statusResult = Invoke-CommandCapture -Script {
        git status --short
    }
    if ($statusResult.Failed) {
        Fail-Workflow -Title '检查 Git 状态' -Lines $statusResult.Lines
    }
    if ($statusResult.Lines.Count -eq 0) {
        Write-Host '[完成] 没有检测到文件变化，本次跳过提交和推送。' -ForegroundColor Yellow
        Write-Host "`n######################## 发布流程结束：无变更，无需写入 LOG ########################" -ForegroundColor Green
        return
    }
    $statusResult.Lines | ForEach-Object { Write-Host ('  ' + $_) }

    Write-StageHeader -Step 5 -Total 6 -Title '提交 Git 变更'
    $addResult = Invoke-CommandCapture -Script {
        git add -A
    }
    if ($addResult.Failed) {
        Fail-Workflow -Title '暂存 Git 变更' -Lines $addResult.Lines
    }
    $commitResult = Invoke-CommandCapture -Script {
        git commit -m $CommitMessage
    }
    Get-TailLines -Lines $commitResult.Lines -Count 12 | ForEach-Object { Write-Host ('  ' + $_) }
    if ($commitResult.Failed) {
        Fail-Workflow -Title '提交 Git 变更' -Lines $commitResult.Lines
    }

    Write-StageHeader -Step 6 -Total 6 -Title '推送到 GitHub'
    $pushResult = Invoke-CommandCapture -Script {
        git push origin main
    }
    Get-TailLines -Lines $pushResult.Lines -Count 12 | ForEach-Object { Write-Host ('  ' + $_) }
    if ($pushResult.Failed) {
        Fail-Workflow -Title '推送到 GitHub' -Lines $pushResult.Lines
    }

    Write-Host "`n######################## 发布成功：本次未写入 LOG ########################" -ForegroundColor Green
} finally {
    Pop-Location
}
