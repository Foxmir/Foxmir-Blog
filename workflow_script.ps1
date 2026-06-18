param(
    [string]$ProjectPath = 'D:\Quarto\Foxmir_blog',
    [string]$LogPath = 'C:\Users\李勇\OneDrive\Markdown\1-Work\Blog\ERROR.md',
    [string]$CommitMessage = 'Update blog content',
    [switch]$NoPush
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$script:FailureLogged = $false

if ([System.IO.Path]::GetFileName($LogPath).Equals('LOG.md', [System.StringComparison]::OrdinalIgnoreCase)) {
    $logDirectory = if (-not [string]::IsNullOrWhiteSpace($env:BLOG_SOURCE) -and (Test-Path -LiteralPath $env:BLOG_SOURCE)) {
        $env:BLOG_SOURCE
    } else {
        Split-Path -Parent $LogPath
    }
    $LogPath = Join-Path $logDirectory 'ERROR.md'
}

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

        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $message = $_.Exception.Message
            if (-not [string]::IsNullOrWhiteSpace($message)) {
                $trimmedMessage = $message.TrimEnd()
                if ($trimmedMessage -ne 'System.Management.Automation.RemoteException') {
                    $trimmedMessage
                }
            }

            $text = $_.ToString().TrimEnd()
            if (-not [string]::IsNullOrWhiteSpace($text) -and $text -ne 'System.Management.Automation.RemoteException') {
                $text
            }
            return
        }

        $_.ToString().TrimEnd()
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
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
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Get-FileLinesIfExists {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    return @([System.IO.File]::ReadAllLines($Path))
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

function Invoke-RobocopyCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $output = @()
    $failed = $false
    $exitCode = 0

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    try {
        $output = & robocopy $Source $Destination /MIR /NFL /NDL /NJH /NJS /NP 2>&1
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) {
            $exitCode = 0
        }
        $failed = ($exitCode -ge 8)
    } catch {
        $failed = $true
        $exitCode = if ($LASTEXITCODE) { $LASTEXITCODE } else { 16 }
        $output = @($output) + $_
    }

    return [pscustomobject]@{
        Failed = $failed
        ExitCode = $exitCode
        Lines = @(Convert-OutputLines -Output $output)
    }
}

function Invoke-SourceSyncCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $excludedFiles = @('publish.bat', 'ERROR.md')
    $sourceErrorLogPath = Join-Path $Source 'ERROR.md'
    $sourceLegacyErrorLogPath = Join-Path $Source 'LOG.md'
    $sourceLegacyWeeklyLogPath = Join-Path $Source 'WEEKLYLOG.md'
    if ((-not (Test-Path -LiteralPath $sourceErrorLogPath)) -and
        (Test-Path -LiteralPath $sourceLegacyErrorLogPath) -and
        (Test-Path -LiteralPath $sourceLegacyWeeklyLogPath)) {
        $excludedFiles += 'LOG.md'
    }

    $arguments = @(
        $Source,
        $Destination,
        '*.md',
        '*.png',
        '*.jpg',
        '*.jpeg',
        '*.gif',
        '*.webp',
        '/MIR',
        '/XF'
    ) + $excludedFiles + @(
        '/XD',
        '.git',
        '.obsidian',
        '/NJH',
        '/NJS',
        '/NDL',
        '/NC',
        '/NS',
        '/NP'
    )

    return Invoke-ProcessCapture -FilePath 'robocopy' -ArgumentList $arguments -FailurePredicate {
        param($exitCode, $lines)
        return ($exitCode -ge 8)
    }
}

function ConvertTo-ProcessArgumentString {
    param([AllowEmptyCollection()][string[]]$ArgumentList = @())

    $encodedArgs = foreach ($argument in $ArgumentList) {
        if ($null -eq $argument) {
            '""'
            continue
        }

        if ($argument.Length -eq 0) {
            '""'
            continue
        }

        if ($argument -match '[\s"]') {
            '"' + ($argument -replace '"', '\"') + '"'
        } else {
            $argument
        }
    }

    return [string]::Join(' ', $encodedArgs)
}

function Invoke-ProcessCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [AllowEmptyCollection()][string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = $ProjectPath,
        [scriptblock]$FailurePredicate
    )

    $stdoutPath = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N') + '.stdout.log')
    $stderrPath = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N') + '.stderr.log')

    try {
        $argumentText = ConvertTo-ProcessArgumentString -ArgumentList $ArgumentList
        $process = Start-Process -FilePath $FilePath `
            -ArgumentList $argumentText `
            -WorkingDirectory $WorkingDirectory `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $lines = Convert-OutputLines -Output @(
            (Get-FileLinesIfExists -Path $stdoutPath)
            (Get-FileLinesIfExists -Path $stderrPath)
        )
        $exitCode = if ($null -eq $process.ExitCode) { 0 } else { $process.ExitCode }
        $failed = if ($FailurePredicate) {
            & $FailurePredicate $exitCode $lines
        } else {
            $exitCode -ne 0
        }

        return [pscustomobject]@{
            Failed = [bool]$failed
            ExitCode = $exitCode
            Lines = @($lines)
        }
    } finally {
        Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-TcpPortOpen {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMilliseconds = 700
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $asyncResult = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
            return $false
        }
        $client.EndConnect($asyncResult)
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Get-GitProxyArguments {
    $explicitProxy = $env:BLOG_GIT_PROXY
    $proxyCandidates = @()
    if (-not [string]::IsNullOrWhiteSpace($explicitProxy)) {
        $proxyCandidates += $explicitProxy.Trim()
    }
    $proxyCandidates += @(
        'http://127.0.0.1:17890',
        'socks5h://127.0.0.1:12333',
        'http://127.0.0.1:7890',
        'socks5h://127.0.0.1:7891',
        'socks5h://127.0.0.1:10808',
        'http://127.0.0.1:10809'
    )

    foreach ($proxy in ($proxyCandidates | Select-Object -Unique)) {
        if ($proxy -notmatch '^(?<scheme>https?|socks5h?)://(?<host>[^:/]+):(?<port>\d+)$') {
            continue
        }

        $hostName = $Matches['host']
        $port = [int]$Matches['port']
        if (-not (Test-TcpPortOpen -HostName $hostName -Port $port)) {
            continue
        }

        $probeArgs = @(
            '-c', ('http.proxy=' + $proxy),
            '-c', ('https.proxy=' + $proxy),
            'ls-remote',
            '--heads',
            'origin',
            'main'
        )
        $probeResult = Invoke-ProcessCapture -FilePath 'git' -ArgumentList $probeArgs
        if (-not $probeResult.Failed) {
            Write-Host ('[网络] GitHub 将通过本地代理 ' + $proxy + ' 访问。') -ForegroundColor DarkGray
            return @(
                '-c', ('http.proxy=' + $proxy),
                '-c', ('https.proxy=' + $proxy)
            )
        }
    }

    Write-Host '[网络] 未检测到可用 GitHub 本地代理，Git 将尝试直连。' -ForegroundColor Yellow
    return @()
}

function Get-LocalAheadCount {
    $aheadResult = Invoke-ProcessCapture -FilePath 'git' -ArgumentList @(
        'rev-list',
        '--left-right',
        '--count',
        'origin/main...HEAD'
    )
    if ($aheadResult.Failed -or $aheadResult.Lines.Count -eq 0) {
        return 0
    }

    $parts = ($aheadResult.Lines[0] -split '\s+') | Where-Object { $_ -ne '' }
    if ($parts.Count -lt 2) {
        return 0
    }

    return [int]$parts[1]
}

function Get-ChineseReason {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [AllowNull()][string[]]$Lines
    )

    $text = ([string]::Join("`n", ($Lines | ForEach-Object { $_ })))
    switch -Regex ($text) {
        'Recv failure|Connection was reset|Failed to connect|Connection reset' { return 'GitHub 推送连接被重置，通常是网络、代理、防火墙或 GitHub HTTPS 连接不稳定。已完成本地同步、渲染和提交时，可稍后再次点击发布重试推送。' }
        'Connection timed out|timed out' { return 'Git 推送超时，通常是网络、代理、DNS 或 GitHub 连接异常。' }
        'Authentication failed|could not read Username|repository not found|Permission denied' { return 'Git 推送认证失败，请检查账号凭据、令牌或远程仓库权限。' }
        'Could not resolve host' { return '网络解析失败，Git 无法解析 GitHub 地址。' }
        'os error 32|另一个程序正在使用此文件|The process cannot access the file because it is being used by another process' { return '文件被其他进程占用，常见原因是本地预览、资源管理器或终端仍占着输出目录。' }
        'Access to the path.*denied|拒绝访问' { return '文件访问被拒绝，请检查权限、只读状态或同步盘占用。' }
        'Could not find a part of the path|Cannot find path|找不到路径' { return '所需路径不存在，说明输入目录、输出目录或中间产物缺失。' }
        'Attachment resolution failed' { return 'Obsidian 引用的附件解析失败。' }
        'Missing attachments' { return '存在缺失附件，发布已中止。' }
        'Conflicting attachments' { return '存在同名附件冲突，无法确定应引用哪一个文件。' }
        'index\.html not found|index.html 未生成' { return '站点首页未生成，说明渲染结果不完整。' }
        default { return ($Stage + '失败，请查看详情输出。') }
    }
}

function Test-TransientGitPushFailure {
    param([AllowNull()][string[]]$Lines)

    $text = [string]::Join("`n", @($Lines))
    return ($text -match 'Recv failure|Connection was reset|Failed to connect|Connection reset|Connection timed out|timed out|Could not resolve host')
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
    $script:FailureLogged = $true
    throw $reason
}

Write-Host "`n######################## 唯一发布入口：workflow_script.ps1 ########################" -ForegroundColor Green

Push-Location $ProjectPath
try {
    $tempOutputDir = Join-Path $ProjectPath '.quarto-build-temp'
    $docsDir = Join-Path $ProjectPath 'docs'
    $docsIndexPath = Join-Path $docsDir 'index.html'
    $docsNoJekyllPath = Join-Path $docsDir '.nojekyll'
    $sourceBlogDir = $env:BLOG_SOURCE
    $publishDir = if ([string]::IsNullOrWhiteSpace($env:BLOG_PUBLISH)) { Join-Path $ProjectPath 'publish' } else { $env:BLOG_PUBLISH }

    Write-StageHeader -Step 1 -Total 6 -Title '清理环境'
    Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process quarto -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Job -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
    $env:TMP = 'D:\TempJunk'
    $env:TEMP = 'D:\TempJunk'
    Write-Host ('[完成] 已清理 Python/Quarto 进程，TMP=' + $env:TMP) -ForegroundColor DarkGray

    Write-StageHeader -Step 2 -Total 6 -Title '同步 Obsidian 内容'
    if (-not [string]::IsNullOrWhiteSpace($sourceBlogDir) -and (Test-Path -LiteralPath $sourceBlogDir)) {
        $sourceSyncResult = Invoke-SourceSyncCapture -Source $sourceBlogDir -Destination $publishDir
        Get-TailLines -Lines $sourceSyncResult.Lines -Count 12 | ForEach-Object { Write-Host ('  ' + $_) }
        if ($sourceSyncResult.Failed) {
            Fail-Workflow -Title '同步 Obsidian 原始文件' -Lines $sourceSyncResult.Lines
        }
    } else {
        Write-Host '[跳过] 未检测到 BLOG_SOURCE，直接使用项目内 publish 目录。' -ForegroundColor DarkGray
    }

    $syncResult = Invoke-ProcessCapture -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        (Join-Path $ProjectPath 'tools\sync-blog.ps1')
    )
    Get-TailLines -Lines $syncResult.Lines -Count 12 | ForEach-Object { Write-Host ('  ' + $_) }
    if ($syncResult.Failed) {
        Fail-Workflow -Title '同步 Obsidian 内容' -Lines $syncResult.Lines
    }

    Write-StageHeader -Step 3 -Total 6 -Title '渲染 Quarto 站点'
    if (Test-Path -LiteralPath $tempOutputDir) {
        Remove-Item -LiteralPath $tempOutputDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $renderResult = Invoke-ProcessCapture -FilePath 'D:\Quarto\bin\quarto.exe' -ArgumentList @(
        'render',
        '.',
        '--output-dir',
        '.quarto-build-temp'
    )
    Get-TailLines -Lines $renderResult.Lines -Count 12 | ForEach-Object { Write-Host ('  ' + $_) }
    if ($renderResult.Failed) {
        Fail-Workflow -Title '渲染 Quarto 站点' -Lines $renderResult.Lines
    }
    $syncDocsResult = Invoke-RobocopyCapture -Source $tempOutputDir -Destination $docsDir
    Get-TailLines -Lines $syncDocsResult.Lines -Count 12 | ForEach-Object { Write-Host ('  ' + $_) }
    if ($syncDocsResult.Failed) {
        Fail-Workflow -Title '同步渲染产物到 docs' -Lines $syncDocsResult.Lines
    }
    if (-not (Test-Path -LiteralPath $docsIndexPath)) {
        Fail-Workflow -Title '检查渲染结果' -Lines @('index.html 未生成。')
    }
    Write-Utf8Text -Path $docsNoJekyllPath -Content ''
    $indexSize = (Get-Item $docsIndexPath).Length
    Write-Host ('[完成] docs\index.html 已生成，大小: ' + $indexSize + ' 字节；docs\.nojekyll 已恢复。') -ForegroundColor DarkGray
    if (Test-Path -LiteralPath $tempOutputDir) {
        Remove-Item -LiteralPath $tempOutputDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($NoPush) {
        Write-Host '[完成] --no-push 模式：已完成同步、渲染和 docs 更新，跳过 Git 提交与推送。' -ForegroundColor Yellow
        Write-Host "`n######################## 发布流程结束：--no-push，未写入 ERROR ########################" -ForegroundColor Green
        return
    }

    Write-StageHeader -Step 4 -Total 6 -Title '检查 Git 变更'
    $statusResult = Invoke-ProcessCapture -FilePath 'git' -ArgumentList @('status', '--short')
    if ($statusResult.Failed) {
        Fail-Workflow -Title '检查 Git 状态' -Lines $statusResult.Lines
    }
    $localAheadCount = Get-LocalAheadCount
    if ($statusResult.Lines.Count -eq 0 -and $localAheadCount -le 0) {
        Write-Host '[完成] 没有检测到文件变化，本次跳过提交和推送。' -ForegroundColor Yellow
        Write-Host "`n######################## 发布流程结束：无变更，无需写入 ERROR ########################" -ForegroundColor Green
        return
    }
    if ($statusResult.Lines.Count -eq 0) {
        Write-Host ('[继续] 工作区无新变化，但本地还有 ' + $localAheadCount + ' 个提交未推送。') -ForegroundColor Yellow
    } else {
        $statusResult.Lines | ForEach-Object { Write-Host ('  ' + $_) }
    }

    Write-StageHeader -Step 5 -Total 6 -Title '提交 Git 变更'
    if ($statusResult.Lines.Count -gt 0) {
        $addResult = Invoke-ProcessCapture -FilePath 'git' -ArgumentList @('add', '-A')
        if ($addResult.Failed) {
            Fail-Workflow -Title '暂存 Git 变更' -Lines $addResult.Lines
        }
        $commitResult = Invoke-ProcessCapture -FilePath 'git' -ArgumentList @('commit', '-m', $CommitMessage)
        Get-TailLines -Lines $commitResult.Lines -Count 12 | ForEach-Object { Write-Host ('  ' + $_) }
        if ($commitResult.Failed) {
            Fail-Workflow -Title '提交 Git 变更' -Lines $commitResult.Lines
        }
    } else {
        Write-Host '[跳过] 工作区无新变化，直接推送已有本地提交。' -ForegroundColor Yellow
    }

    Write-StageHeader -Step 6 -Total 6 -Title '推送到 GitHub'
    $gitProxyArgs = @(Get-GitProxyArguments)
    $pushResult = $null
    $pushLines = @()
    $maxPushAttempts = 3
    for ($attempt = 1; $attempt -le $maxPushAttempts; $attempt++) {
        Write-Host ('[尝试] Git push {0}/{1}' -f $attempt, $maxPushAttempts) -ForegroundColor DarkGray
        $pushResult = Invoke-ProcessCapture -FilePath 'git' -ArgumentList ($gitProxyArgs + @('push', 'origin', 'main'))
        $pushLines += ('Git push attempt {0}/{1}, exit code {2}' -f $attempt, $maxPushAttempts, $pushResult.ExitCode)
        $pushLines += $pushResult.Lines
        Get-TailLines -Lines $pushResult.Lines -Count 12 | ForEach-Object { Write-Host ('  ' + $_) }

        if (-not $pushResult.Failed) {
            break
        }

        if ($attempt -ge $maxPushAttempts -or -not (Test-TransientGitPushFailure -Lines $pushResult.Lines)) {
            break
        }

        Start-Sleep -Seconds (4 * $attempt)
    }
    if ($pushResult.Failed) {
        Fail-Workflow -Title '推送到 GitHub' -Lines $pushLines
    }

    Write-Host "`n######################## 发布成功：本次未写入 ERROR ########################" -ForegroundColor Green
} catch {
    if (-not $script:FailureLogged) {
        $unexpectedLines = Convert-OutputLines -Output @(
            $_.Exception.Message,
            $_.ScriptStackTrace,
            $_
        )
        $tailLines = Get-TailLines -Lines $unexpectedLines -Count 20
        $reason = Get-ChineseReason -Stage '发布流程' -Lines $tailLines
        Write-Host ('[失败] ' + $reason) -ForegroundColor Red
        Add-LogEntry -Title '发布流程' -Summary $reason -Details $tailLines
        $script:FailureLogged = $true
    }
    throw
} finally {
    Pop-Location
}
