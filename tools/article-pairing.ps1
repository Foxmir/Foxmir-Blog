# article-pairing.ps1
# 中英文章配对。本文件只放函数，被别的脚本点引用，自己不执行任何动作。
#
# 判断语言：看文章里有没有「的」。中文文章一定有，英文文章一定没有。
# 有汉字却没有「的」的，不猜，报错让人去看。
#
# 配对：看文件名。同一目录下，X_zh.md 和 X.md 就是一对。
# 配对之后做交叉验证：带 _zh 的那篇必须是中文，另一篇必须是英文，对不上就报错。
# 没配成对的单篇，靠语言判定决定进哪个镜像：中文的只进中文站，英文的只进英文站。

function Get-ArticleText {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Get-ArticleLanguage {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = Get-ArticleText -Path $Path

    if ($text.Contains([string][char]0x7684)) {
        return 'zh'
    }

    # 没有「的」但有成片汉字：可能是漏写「的」，也可能是我没想到的写法。
    # 这种情况不猜，报错。
    $han = [regex]'[\u4e00-\u9fff]'
    if ($han.Matches($text).Count -ge 20) {
        return 'unknown'
    }

    return 'en'
}

function Get-ArticleRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$PublishPath,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $relative = $FullPath.Substring($PublishPath.TrimEnd('\', '/').Length)
    return $relative.TrimStart('\', '/').Replace('\', '/')
}

function Get-ArticleEnglishSiblingPath {
    # 文件名是 X_zh.md 时，返回同目录下 X.md 的相对路径；否则返回 $null。
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $directory = ''
    $fileName = $RelativePath
    $slash = $RelativePath.LastIndexOf('/')
    if ($slash -ge 0) {
        $directory = $RelativePath.Substring(0, $slash + 1)
        $fileName = $RelativePath.Substring($slash + 1)
    }

    $stem = $fileName -replace '(?i)\.md$', ''
    if (-not $stem.ToLowerInvariant().EndsWith('_zh')) { return $null }

    return ($directory + $stem.Substring(0, $stem.Length - 3) + '.md')
}

function Get-ArticlePairDocuments {
    param([Parameter(Mandatory = $true)][string]$ProjectPath)

    $publishPath = Join-Path $ProjectPath 'publish'
    if (-not (Test-Path -LiteralPath $publishPath)) { return @() }

    $documents = New-Object System.Collections.ArrayList
    foreach ($file in Get-ChildItem -LiteralPath $publishPath -Recurse -File -Filter '*.md') {
        $relative = Get-ArticleRelativePath -PublishPath $publishPath -FullPath $file.FullName
        $segments = $relative -split '/'

        # publish 根目录下的是首页、关于这类单页，不是文章，不参与配对
        if ($segments.Length -lt 2) { continue }

        $skip = $false
        foreach ($segment in $segments) {
            if ($segment.StartsWith('.') -or $segment.StartsWith('_')) {
                $skip = $true
                break
            }
        }
        if ($skip) { continue }

        [void]$documents.Add([pscustomobject]@{
            RelativePath = $relative
            FullPath     = $file.FullName
            Language     = (Get-ArticleLanguage -Path $file.FullName)
        })
    }

    return @($documents | Sort-Object -Property RelativePath)
}

function Invoke-ArticlePairing {
    param([Parameter(Mandatory = $true)][string]$ProjectPath)

    $errors = New-Object System.Collections.ArrayList

    $documents = @(Get-ArticlePairDocuments -ProjectPath $ProjectPath)
    $byPath = @{}
    foreach ($document in $documents) { $byPath[$document.RelativePath] = $document }

    # 一、按文件名后缀找对：X_zh.md 与同目录的 X.md 是一对
    $pairs = New-Object System.Collections.ArrayList
    $pairedPaths = New-Object System.Collections.ArrayList

    foreach ($document in $documents) {
        if ($pairedPaths -contains $document.RelativePath) { continue }

        $englishPath = Get-ArticleEnglishSiblingPath -RelativePath $document.RelativePath
        if ($null -eq $englishPath) { continue }
        if (-not $byPath.ContainsKey($englishPath)) { continue }
        if ($pairedPaths -contains $englishPath) { continue }

        $english = $byPath[$englishPath]

        # 交叉验证：带 _zh 的是中文，另一篇是英文，两边都要对得上
        $verified = $true
        if ($document.Language -ne 'zh') {
            $verified = $false
            [void]$errors.Add(('文件名带 _zh，但正文不是中文，请检查：{0}' -f $document.RelativePath))
        }
        if ($english.Language -ne 'en') {
            $verified = $false
            [void]$errors.Add(('文件名不带 _zh，但正文不是英文，请检查：{0}' -f $english.RelativePath))
        }
        if (-not $verified) { continue }

        [void]$pairs.Add([pscustomobject]@{ Zh = $document.RelativePath; En = $englishPath })
        [void]$pairedPaths.Add($document.RelativePath)
        [void]$pairedPaths.Add($englishPath)
    }

    # 二、剩下的单篇按语言判定分到两个镜像
    $chineseOnly = New-Object System.Collections.ArrayList
    $englishOnly = New-Object System.Collections.ArrayList

    foreach ($document in $documents) {
        if ($pairedPaths -contains $document.RelativePath) { continue }

        switch ($document.Language) {
            'zh' { [void]$chineseOnly.Add($document.RelativePath) }
            'en' { [void]$englishOnly.Add($document.RelativePath) }
            default {
                [void]$errors.Add(('这篇分不出是中文还是英文，请检查是不是漏了「的」：{0}' -f $document.RelativePath))
            }
        }
    }

    return [pscustomobject]@{
        Pairs       = @($pairs | Sort-Object -Property Zh)
        ChineseOnly = @($chineseOnly | Sort-Object)
        EnglishOnly = @($englishOnly | Sort-Object)
        Errors      = $errors.ToArray()
        Ok          = ($errors.Count -eq 0)
    }
}
