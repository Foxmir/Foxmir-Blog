$ErrorActionPreference = 'Stop'

$project = $env:BLOG_PROJECT
$publish = $env:BLOG_PUBLISH
$blogSource = $env:BLOG_SOURCE
$siteUrlEn = 'https://foxmir.github.io/Foxmir-Blog/'
$siteUrlZh = 'https://foxmir.github.io/Foxmir-Blog/zh/'
$googleAnalyticsId = 'G-VQW94RHSBY'
# LOG 页已停用。留这两个名字只是为了万一 LOG.md 又被拷进来，也不会被当成单页渲染出去。
$excludedRootPageNames = @('HOME', 'ERROR', 'LOG', 'WEEKLYLOG')

if ([string]::IsNullOrWhiteSpace($project)) {
    # 没设 BLOG_PROJECT 时就按脚本自己所在的位置往上退一级，不写死路径
    $project = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($publish)) {
    $publish = Join-Path $project 'publish'
}

$buildRoot = Join-Path $project 'build'
$tempBuildRoot = Join-Path $project '.quarto-build-temp'

$vaultRoot = $null
if (-not [string]::IsNullOrWhiteSpace($blogSource) -and (Test-Path -LiteralPath $blogSource)) {
    $blogParent = Split-Path -Parent $blogSource
    if (-not [string]::IsNullOrWhiteSpace($blogParent)) {
        $vaultRoot = Split-Path -Parent $blogParent
    }
}

$pictureRoot = $null
if (-not [string]::IsNullOrWhiteSpace($vaultRoot) -and (Test-Path -LiteralPath $vaultRoot)) {
    $pictureRoot = Get-ChildItem -LiteralPath $vaultRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Sys.Picture.folder*' } |
        Select-Object -First 1 -ExpandProperty FullName
}

$defaultAttachmentSearchRoots = @()
if (-not [string]::IsNullOrWhiteSpace($vaultRoot)) {
    $defaultAttachmentSearchRoots += Join-Path $vaultRoot 'Z-Database\Z-1-Work'
    if (-not [string]::IsNullOrWhiteSpace($pictureRoot)) {
        $defaultAttachmentSearchRoots += $pictureRoot
    }
    $defaultAttachmentSearchRoots += $vaultRoot
}

$attachmentSearchRoots = if ([string]::IsNullOrWhiteSpace($env:BLOG_ATTACHMENT_SEARCH_ROOTS)) {
    $defaultAttachmentSearchRoots
} else {
    $env:BLOG_ATTACHMENT_SEARCH_ROOTS -split '\|'
}
$attachmentSearchRoots = @(
    $attachmentSearchRoots |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -Unique
)
$attachmentRootIndexCache = @{}
$attachmentResolutionCache = @{}
$missingAttachmentRefs = @{}
$conflictingAttachmentRefs = @{}
$copiedAttachmentTargets = @{}

function ConvertTo-Slug {
    param([Parameter(Mandatory = $true)][string]$Name)

    $slug = $Name.ToLowerInvariant() -replace '[^a-z0-9_-]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $md5 = [Security.Cryptography.MD5]::Create()
        $bytes = [Text.Encoding]::UTF8.GetBytes($Name)
        $hash = ($md5.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
        $slug = 'category-' + $hash.Substring(0, 8)
    }
    return $slug
}

function ConvertTo-YamlSingleQuoted {
    param([AllowNull()][string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function ConvertTo-YamlPlainPath {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ($Value -replace '\\', '/')
}

function Get-YamlTitleLine {
    param([Parameter(Mandatory = $true)][string]$Title)

    return ('title: {0}' -f (ConvertTo-YamlSingleQuoted -Value $Title))
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $content = [string]::Join([Environment]::NewLine, $Lines) + [Environment]::NewLine
    if ((Test-Path -LiteralPath $Path) -and ([System.IO.File]::ReadAllText($Path) -eq $content)) {
        return $false
    }

    $tempPath = $Path + '.tmp'
    $encoding = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText($tempPath, $content, $encoding)
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
    return $true
}

function Get-FileContentLines {
    param([Parameter(Mandatory = $true)][string]$Path)

    $content = [System.IO.File]::ReadAllText($Path)
    return [regex]::Split($content, "`r`n|`n")
}

function Get-MarkdownBodyLines {
    param([Parameter(Mandatory = $true)][string]$Path)

    $lines = Get-FileContentLines -Path $Path
    if ($lines.Length -ge 1 -and $lines[0] -eq '---') {
        for ($index = 1; $index -lt $lines.Length; $index++) {
            if ($lines[$index] -eq '---') {
                if ($index + 1 -lt $lines.Length) {
                    return @($lines[($index + 1)..($lines.Length - 1)])
                }

                return @()
            }
        }
    }

    return $lines
}

function ConvertTo-DisplayTitle {
    param([Parameter(Mandatory = $true)][string]$Name)

    $specialTitles = @{
        'ABOUT' = 'About'
    }
    $upperName = $Name.ToUpperInvariant()
    if ($specialTitles.ContainsKey($upperName)) {
        return $specialTitles[$upperName]
    }

    $words = [regex]::Matches($Name, '[A-Z]+(?=[A-Z][a-z]|\d|$)|[A-Z]?[a-z]+|\d+') |
        ForEach-Object { $_.Value }
    if (@($words).Count -eq 0) {
        return $Name
    }

    return (@($words | ForEach-Object {
        if ($_.Length -le 1) {
            $_.ToUpperInvariant()
        } else {
            $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1).ToLowerInvariant()
        }
    }) -join ' ')
}

function Get-RootPageVariantSuffixes {
    # 首页、关于这类单页的中文版，文件名在原文件名后面加 _zh / -zh / .zh
    return @('_zh', '-zh', '.zh')
}

function Get-RootPageCanonicalName {
    param([Parameter(Mandatory = $true)][string]$BaseName)

    foreach ($suffix in (Get-RootPageVariantSuffixes)) {
        if ($BaseName.Length -gt $suffix.Length -and $BaseName.ToLowerInvariant().EndsWith($suffix)) {
            return $BaseName.Substring(0, $BaseName.Length - $suffix.Length)
        }
    }

    return $BaseName
}

function Get-RootPages {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $rootMarkdownFiles = @(
        Get-ChildItem -LiteralPath $Directory -File -Filter '*.md' -ErrorAction SilentlyContinue |
            Where-Object {
                $canonical = Get-RootPageCanonicalName -BaseName $_.BaseName
                $canonical -eq $_.BaseName -and
                $excludedRootPageNames -notcontains $canonical.ToUpperInvariant()
            }
    )

    return @(
        $rootMarkdownFiles |
            ForEach-Object {
                $canonicalBaseName = $_.BaseName
                [pscustomobject]@{
                    BaseName = $canonicalBaseName
                    Slug = ConvertTo-Slug $canonicalBaseName
                    Title = ConvertTo-DisplayTitle -Name $canonicalBaseName
                    SortKey = switch ($canonicalBaseName.ToUpperInvariant()) {
                        'ABOUT' { '000-about' }
                        default { '100-' + $canonicalBaseName.ToLowerInvariant() }
                    }
                }
            } |
            Sort-Object SortKey, BaseName
    )
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)
    $baseUri = New-Object System.Uri($baseFullPath)
    $targetUri = New-Object System.Uri($targetFullPath)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)

    return ([System.Uri]::UnescapeDataString($relativeUri.ToString()) -replace '/', '\')
}

function Get-MarkdownAssetDirectory {
    param([Parameter(Mandatory = $true)][string]$MarkdownPath)

    $noteDirectory = Split-Path -Parent $MarkdownPath
    $noteRelativeDirectory = Get-RelativePath -BasePath $publish -TargetPath $noteDirectory
    $assetPath = Join-Path $publish '_attachments'

    if (-not [string]::IsNullOrWhiteSpace($noteRelativeDirectory) -and $noteRelativeDirectory -ne '.') {
        foreach ($segment in (($noteRelativeDirectory -replace '\\', '/').Split('/') | Where-Object { $_ -ne '' })) {
            $assetPath = Join-Path $assetPath (ConvertTo-Slug $segment)
        }
    } else {
        $assetPath = Join-Path $assetPath 'root'
    }

    $assetPath = Join-Path $assetPath (ConvertTo-Slug ([System.IO.Path]::GetFileNameWithoutExtension($MarkdownPath)))
    return $assetPath
}

function ConvertTo-MarkdownLinkPath {
    param(
        [Parameter(Mandatory = $true)][string]$BaseDirectory,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $relativePath = Get-RelativePath -BasePath $BaseDirectory -TargetPath $TargetPath
    return ($relativePath -replace '\\', '/')
}

function Resolve-AttachmentSource {
    param([Parameter(Mandatory = $true)][string]$ReferenceName)

    $cacheKey = $ReferenceName.ToLowerInvariant()
    if ($attachmentResolutionCache.ContainsKey($cacheKey)) {
        return $attachmentResolutionCache[$cacheKey]
    }

    # 变量名不能叫 $matches：PowerShell 里 $matches 和自动变量 $Matches 是同一个名字，
    # 上面 Where-Object 一旦执行过 -match，这个变量就会被换成 Hashtable。
    #
    # 附件由内到外找：先在内层目录找，找着就停；内层没有，才去外层找。
    # 搜外层时跳过已经找过的内层目录，同一个文件只会进候选一次。
    $candidates = New-Object System.Collections.ArrayList
    $searchedRoots = New-Object System.Collections.ArrayList
    foreach ($root in $attachmentSearchRoots) {
        if (-not $attachmentRootIndexCache.ContainsKey($root)) {
            $attachmentRootIndexCache[$root] = @(
                Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '\.(png|jpe?g|gif|webp|svg|pdf|csv)$' }
            )
        }
        foreach ($file in $attachmentRootIndexCache[$root]) {
            $insideSearchedRoot = $false
            foreach ($searchedRoot in $searchedRoots) {
                if ($file.FullName.StartsWith(($searchedRoot + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) {
                    $insideSearchedRoot = $true
                    break
                }
            }
            if ($insideSearchedRoot) {
                continue
            }
            if ($file.Name.Equals($ReferenceName, [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$candidates.Add($file.FullName)
            }
        }
        [void]$searchedRoots.Add($root)
        if ($candidates.Count -gt 0) {
            break
        }
    }

    $resolved = if ($candidates.Count -eq 0) {
        [pscustomobject]@{ Status = 'Missing'; Path = $null; Candidates = @() }
    } elseif ($candidates.Count -eq 1) {
        [pscustomobject]@{ Status = 'Resolved'; Path = $candidates[0]; Candidates = @() }
    } else {
        $exact = @($candidates | Where-Object { [System.IO.Path]::GetFileName($_) -ceq $ReferenceName })
        if ($exact.Count -eq 1) {
            [pscustomobject]@{ Status = 'Resolved'; Path = $exact[0]; Candidates = @() }
        } else {
            [pscustomobject]@{ Status = 'Conflict'; Path = $null; Candidates = $candidates.ToArray() }
        }
    }

    $attachmentResolutionCache[$cacheKey] = $resolved
    return $resolved
}

function Convert-ObsidianLinksInMarkdown {
    param([Parameter(Mandatory = $true)][string]$Path)

    $content = [System.IO.File]::ReadAllText($Path)
    $markdownDirectory = Split-Path -Parent $Path
    $assetDirectory = Get-MarkdownAssetDirectory -MarkdownPath $Path
    $pattern = [regex]'(?is)(?<embed>!?)\[\[(?<target>[^\]#|]+)(?:#[^\]|]+)?(?:\|(?<alias>[^\]]+))?\]\]'

    $updatedContent = $pattern.Replace($content, {
        param($match)

        $target = $match.Groups['target'].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($target)) {
            return $match.Value
        }

        $alias = $match.Groups['alias'].Value.Trim()
        $referenceName = [System.IO.Path]::GetFileName($target)
        $extension = [System.IO.Path]::GetExtension($referenceName)

        if ([string]::IsNullOrWhiteSpace($extension)) {
            return $match.Value
        }

        $resolved = Resolve-AttachmentSource -ReferenceName $referenceName
        $referenceKey = $Path + '|' + $referenceName

        if ($resolved.Status -eq 'Missing') {
            if (-not $missingAttachmentRefs.ContainsKey($referenceKey)) {
                $missingAttachmentRefs[$referenceKey] = [pscustomobject]@{
                    MarkdownPath = $Path
                    ReferenceName = $referenceName
                }
            }
            return $match.Value
        }

        if ($resolved.Status -eq 'Conflict') {
            if (-not $conflictingAttachmentRefs.ContainsKey($referenceKey)) {
                $conflictingAttachmentRefs[$referenceKey] = [pscustomobject]@{
                    MarkdownPath = $Path
                    ReferenceName = $referenceName
                    Candidates = $resolved.Candidates
                }
            }
            return $match.Value
        }

        $destinationPath = Join-Path $assetDirectory $referenceName
        if (-not (Test-Path -LiteralPath $assetDirectory)) {
            New-Item -ItemType Directory -Path $assetDirectory -Force | Out-Null
        }

        $shouldCopyAttachment = $true
        if (Test-Path -LiteralPath $destinationPath) {
            $sourceInfo = Get-Item -LiteralPath $resolved.Path
            $destinationInfo = Get-Item -LiteralPath $destinationPath
            $shouldCopyAttachment = ($sourceInfo.Length -ne $destinationInfo.Length) -or ($sourceInfo.LastWriteTimeUtc -ne $destinationInfo.LastWriteTimeUtc)
        }

        if ($shouldCopyAttachment) {
            Copy-Item -LiteralPath $resolved.Path -Destination $destinationPath -Force
            $copiedAttachmentTargets[$destinationPath] = $true
        }

        $relativeLinkPath = ConvertTo-MarkdownLinkPath -BaseDirectory $markdownDirectory -TargetPath $destinationPath
        $isImageEmbed = $match.Groups['embed'].Value -eq '!' -and $extension -match '^(?i)\.(png|jpe?g|gif|webp|svg)$'
        $label = if ([string]::IsNullOrWhiteSpace($alias)) {
            if ($isImageEmbed) {
                [System.IO.Path]::GetFileNameWithoutExtension($referenceName)
            } else {
                $referenceName
            }
        } else {
            $alias
        }

        if ($isImageEmbed) {
            return '![' + $label + '](' + $relativeLinkPath + ')'
        }

        return '[' + $label + '](' + $relativeLinkPath + ')'
    })

    if ($updatedContent -ne $content) {
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, $updatedContent, $encoding)
    }
}

function Get-ArticleOutputPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    return (('publish/' + (($RelativePath -replace '\\', '/')) -replace '(?i)\.md$', '.html'))
}

function Get-SiteRelativeHref {
    param(
        [Parameter(Mandatory = $true)][string]$FromPagePath,
        [Parameter(Mandatory = $true)][string]$ToPagePath
    )

    # 两个路径都是合并后 docs 里的位置，比如 publish/Bits/X.html 和 zh/publish/Bits/Y.html
    $segments = @(($FromPagePath -replace '\\', '/') -split '/' | Where-Object { $_ -ne '' })
    $depth = $segments.Count - 1
    return ((('../' * $depth) -join '') + ($ToPagePath -replace '\\', '/'))
}

function Get-LanguageSwitchHref {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('en', 'zh')][string]$Language,
        [Parameter(Mandatory = $true)][string]$OwnSitePath,
        [Parameter(Mandatory = $true)][string]$TargetSitePath
    )

    if ($Language -eq 'zh') {
        return (Get-SiteRelativeHref -FromPagePath ('zh/' + $OwnSitePath) -ToPagePath $TargetSitePath)
    }

    return (Get-SiteRelativeHref -FromPagePath $OwnSitePath -ToPagePath ('zh/' + $TargetSitePath))
}

function Get-LanguageHeaderLines {
    param(
        [AllowNull()][string]$Href,
        [AllowNull()][string]$Label,
        [AllowNull()][string]$HrefLang
    )

    if ([string]::IsNullOrWhiteSpace($Href)) {
        return @()
    }

    return @(
        'include-in-header:'
        '  text: |'
        ('    <meta name="lang-target" content="' + $Href + '">')
        ('    <meta name="lang-label" content="' + $Label + '">')
        ('    <meta name="lang-hreflang" content="' + $HrefLang + '">')
    )
}

function ConvertTo-NativePath {
    param([Parameter(Mandatory = $true)][string]$Value)

    return ($Value -replace '/', '\')
}

function Get-RootPageSourcePath {
    param(
        [Parameter(Mandatory = $true)][string]$BaseName,
        [Parameter(Mandatory = $true)][string]$Language
    )

    $candidates = if ($Language -eq 'zh') {
        @(Get-RootPageVariantSuffixes | ForEach-Object { $BaseName + $_ + '.md' })
    } else {
        @($BaseName + '.md')
    }

    foreach ($candidate in $candidates) {
        $candidatePath = Join-Path $publish $candidate
        if (Test-Path -LiteralPath $candidatePath) {
            return $candidatePath
        }
    }

    return $null
}

function Get-RootPageBodyLines {
    param(
        [Parameter(Mandatory = $true)][string]$BaseName,
        [Parameter(Mandatory = $true)][string]$Language
    )

    $sourcePath = Get-RootPageSourcePath -BaseName $BaseName -Language $Language
    if ($null -eq $sourcePath) {
        return @()
    }

    return @(Get-MarkdownBodyLines -Path $sourcePath)
}

function Get-HomeBodyLines {
    param([Parameter(Mandatory = $true)][string]$Language)

    return @(Get-RootPageBodyLines -BaseName 'HOME' -Language $Language)
}

function Get-RootPageTitle {
    param(
        [Parameter(Mandatory = $true)][string]$BaseName,
        [Parameter(Mandatory = $true)][string]$Language
    )

    if ($Language -eq 'zh' -and $BaseName.ToUpperInvariant() -eq 'ABOUT') {
        return '关于'
    }

    return (ConvertTo-DisplayTitle -Name $BaseName)
}

function Split-ArticleBodyTitle {
    # 正文第一个非空行是「# 标题」时，它就是文章标题，这一行从正文里去掉。
    # 第一个非空行不是一级标题时，标题退回用文件名。
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$FallbackTitle
    )

    for ($index = 0; $index -lt $Lines.Length; $index++) {
        if ($Lines[$index].Trim() -eq '') { continue }

        $match = [regex]::Match($Lines[$index], '^#\s+(.+?)\s*$')
        if (-not $match.Success) { break }

        $bodyLines = @()
        if ($index + 1 -lt $Lines.Length) {
            $bodyLines = @($Lines[($index + 1)..($Lines.Length - 1)])
        }

        return [pscustomobject]@{
            Title = $match.Groups[1].Value
            Lines = $bodyLines
        }
    }

    return [pscustomobject]@{
        Title = $FallbackTitle
        Lines = $Lines
    }
}

function New-SiteArticleFile {
    param(
        [Parameter(Mandatory = $true)][string]$SiteRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][datetime]$Timestamp,
        [Parameter(Mandatory = $true)][string]$Language,
        [AllowNull()][string]$TargetHref,
        [AllowNull()][string]$TargetLabel,
        [AllowNull()][string]$TargetHrefLang
    )

    $sourcePath = Join-Path $publish (ConvertTo-NativePath $RelativePath)
    $targetPath = Join-Path $SiteRoot ('publish\' + (ConvertTo-NativePath $RelativePath))
    $targetDirectory = Split-Path -Parent $targetPath
    if (-not (Test-Path -LiteralPath $targetDirectory)) {
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    }
    Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force

    $fallbackTitle = [System.IO.Path]::GetFileNameWithoutExtension($RelativePath)
    $article = Split-ArticleBodyTitle -Lines @(Get-MarkdownBodyLines -Path $targetPath) -FallbackTitle $fallbackTitle

    $lines = @('---')
    $lines += Get-YamlTitleLine -Title $article.Title
    $lines += ('date: ' + (ConvertTo-YamlSingleQuoted -Value $Timestamp.ToString('yyyy-MM-ddTHH:mm:ss')))
    $lines += ('lang: ' + $Language)
    if (-not [string]::IsNullOrWhiteSpace($TargetHref)) {
        $lines += @(Get-LanguageHeaderLines -Href $TargetHref -Label $TargetLabel -HrefLang $TargetHrefLang)
    }
    $lines += @('---', '')
    $lines += $article.Lines

    Write-Utf8File -Path $targetPath -Lines $lines | Out-Null
}

function New-LanguageSite {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('en', 'zh')][string]$Language,
        [Parameter(Mandatory = $true)][string]$SiteRoot,
        [Parameter(Mandatory = $true)][string]$SiteUrl,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Articles,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$RootPages,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Categories,
        [Parameter(Mandatory = $true)][hashtable]$Timestamps,
        [Parameter(Mandatory = $true)][hashtable]$Counterparts
    )

    $ui = if ($Language -eq 'zh') {
        @{
            SiteTitle   = 'Foxmir 博客'
            Latest      = '最新'
            Empty       = '这个分类还没有文章。'
            DefaultNote = ' 的文章和笔记。'
            Notes       = @{
                'articles' = '需要展开讲的长论证。'
                'bits'     = '判定标准、定义，和简短的技术回答。'
                'learn'    = '学习记录和设计反思。'
                'notes'    = '零散想法、草稿，还没成形的信号。'
                'reports'  = '实验报告、统计和结果解读。'
            }
            TargetLabel = 'English'
            TargetCode  = 'en'
        }
    } else {
        @{
            SiteTitle   = 'Foxmir Blog'
            Latest      = 'Latest'
            Empty       = 'No posts in this category yet.'
            DefaultNote = ' posts and notes.'
            Notes       = @{
                'articles' = 'Longer arguments when a question needs more room.'
                'bits'     = 'Criteria, definitions, and short technical answers.'
                'learn'    = 'Learning records and design reflections.'
                'notes'    = 'Loose fragments, sketches, and unfinished signals.'
                'reports'  = 'Experiment reports, statistics, and result reading.'
            }
            TargetLabel = '中文'
            TargetCode  = 'zh-Hans'
        }
    }

    if (Test-Path -LiteralPath $SiteRoot) {
        Remove-Item -LiteralPath $SiteRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $SiteRoot -Force | Out-Null

    # 静态资源：样式、侧栏、语言切换脚本、头像
    foreach ($sharedName in @('styles.css', 'outline-sidebar.html', 'lang-switch.html')) {
        $sharedPath = Join-Path $project $sharedName
        if (Test-Path -LiteralPath $sharedPath) {
            Copy-Item -LiteralPath $sharedPath -Destination (Join-Path $SiteRoot $sharedName) -Force
        }
    }
    $avatarPath = Join-Path $project 'assets\foxmir-avatar.png'
    if (Test-Path -LiteralPath $avatarPath) {
        $avatarTargetDirectory = Join-Path $SiteRoot 'assets'
        if (-not (Test-Path -LiteralPath $avatarTargetDirectory)) {
            New-Item -ItemType Directory -Path $avatarTargetDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $avatarPath -Destination (Join-Path $avatarTargetDirectory 'foxmir-avatar.png') -Force
    }
    $attachmentSource = Join-Path $publish '_attachments'
    if (Test-Path -LiteralPath $attachmentSource) {
        $attachmentTarget = Join-Path $SiteRoot 'publish\_attachments'
        New-Item -ItemType Directory -Path (Split-Path -Parent $attachmentTarget) -Force | Out-Null
        Copy-Item -LiteralPath $attachmentSource -Destination $attachmentTarget -Recurse -Force
    }

    $renderPaths = New-Object System.Collections.ArrayList

    # 首页
    $homeLines = @('---')
    $homeLines += ('title: ' + (ConvertTo-YamlSingleQuoted -Value $ui.SiteTitle))
    $homeLines += 'page-layout: full'
    $homeLines += ('lang: ' + $Language)
    $homeLines += @(Get-LanguageHeaderLines -Href (Get-LanguageSwitchHref -Language $Language -OwnSitePath 'index.html' -TargetSitePath 'index.html') -Label $ui.TargetLabel -HrefLang $ui.TargetCode)
    $homeLines += 'listing:'
    $homeLines += '  - id: latest-listing'
    if ($Articles.Count -gt 0) {
        $homeLines += '    contents:'
        foreach ($article in ($Articles | Sort-Object RelativePath)) {
            $homeLines += '      - ' + (ConvertTo-YamlPlainPath ('publish/' + $article.RelativePath))
        }
    } else {
        $homeLines += '    contents: []'
    }
    $homeLines += @(
        '    sort: "date desc"'
        '    type: default'
        '    fields: [date, title]'
        '    categories: false'
        '    sort-ui: false'
        '    filter-ui: false'
        '    max-items: 5'
        '    feed:'
        '      type: partial'
        '      items: 20'
    )

    foreach ($category in $Categories) {
        $categoryArticles = @($Articles | Where-Object { $_.RelativePath.StartsWith($category.Name + '/') })
        if ($categoryArticles.Count -eq 0) { continue }
        $homeLines += '  - id: ' + $category.Slug + '-listing'
        $homeLines += '    contents:'
        foreach ($article in ($categoryArticles | Sort-Object RelativePath)) {
            $homeLines += '      - ' + (ConvertTo-YamlPlainPath ('publish/' + $article.RelativePath))
        }
        $homeLines += @(
            '    sort: "date desc"'
            '    type: default'
            '    fields: [date, title]'
            '    categories: false'
            '    sort-ui: false'
            '    filter-ui: false'
            '    max-items: 1'
        )
    }

    $homeLines += @(
        '---'
        ''
        '<!-- AUTO-GENERATED-HOMEPAGE: edit folders/posts in Obsidian; edit homepage layout in tools/sync-blog.ps1, not this file. -->'
        ''
        '::: {.home-page}'
        '::: {.home-hero}'
        '::: {.home-title-scene}'
        '# Foxmir'
        ''
        '::: {.home-avatar-note tabindex="0" aria-label="Foxmir"}'
        '::: {.fox-mark aria-hidden="true"}'
        '![](assets/foxmir-avatar.png)'
        ':::'
        ':::'
        ':::'
    )

    $homeBodyLines = @(Get-HomeBodyLines -Language $Language)
    if ($homeBodyLines.Count -gt 0) {
        $homeLines += @('', '::: {.home-lines}', '')
        $homeLines += $homeBodyLines
        $homeLines += @('', '', ':::')
    }

    $homeLines += @(
        ':::'
        ''
        '::: {.home-section .home-latest-section}'
        '::: {.home-section-label}'
        $ui.Latest
        ':::'
        ''
        '::: {.home-section-main}'
        ':::{#latest-listing}'
        ':::'
        ':::'
        ':::'
    )

    if ($Articles.Count -gt 0) {
        $homeMapOrder = @('bits', 'learn', 'reports', 'articles', 'notes')
        $homeMapItems = @(
            $Categories |
                Sort-Object @{
                    Expression = {
                        $index = [array]::IndexOf($homeMapOrder, $_.Slug)
                        if ($index -lt 0) { [int]::MaxValue } else { $index }
                    }
                }, Name
        )

        $homeLines += @(
            ''
            '::: {.home-color-divider aria-hidden="true"}'
            ':::'
            ''
            '::: {.home-map}'
        )

        foreach ($category in $homeMapItems) {
            $note = if ($ui.Notes.ContainsKey($category.Slug)) {
                $ui.Notes[$category.Slug]
            } else {
                $category.Name + $ui.DefaultNote
            }

            $homeLines += '::: {.map-item .map-item-' + $category.Slug + '}'
            $homeLines += '::: {.map-item-head}'
            $homeLines += '[' + $category.Name + '](' + $category.Slug + '.qmd)'
            $homeLines += ':::'
            $homeLines += ''
            $homeLines += '::: {.map-item-note}'
            $homeLines += $note
            $homeLines += ':::'

            $categoryArticles = @($Articles | Where-Object { $_.RelativePath.StartsWith($category.Name + '/') })
            if ($categoryArticles.Count -gt 0) {
                $homeLines += ''
                $homeLines += '::: {.map-item-latest}'
                $homeLines += ':::{#' + $category.Slug + '-listing}'
                $homeLines += ':::'
                $homeLines += ':::'
            }

            $homeLines += ':::'
            $homeLines += ''
        }

        $homeLines += ':::'
    }

    $homeLines += ':::'

    $homePath = Join-Path $SiteRoot 'index.qmd'
    Write-Utf8File -Path $homePath -Lines $homeLines | Out-Null
    [void]$renderPaths.Add('index.qmd')

    # 顶部导航页面（About 等）
    foreach ($rootPage in $RootPages) {
        $title = Get-RootPageTitle -BaseName $rootPage.BaseName -Language $Language
        $pageLines = @('---')
        $pageLines += Get-YamlTitleLine -Title $title
        $pageLines += 'page-layout: full'
        $pageLines += ('lang: ' + $Language)
        $pageLines += @(Get-LanguageHeaderLines -Href (Get-LanguageSwitchHref -Language $Language -OwnSitePath ($rootPage.Slug + '.html') -TargetSitePath ($rootPage.Slug + '.html')) -Label $ui.TargetLabel -HrefLang $ui.TargetCode)
        $pageLines += @(
            '---'
            ''
            '<!-- AUTO-GENERATED-ROOT-PAGE: edit root Markdown pages in Obsidian, not this file. -->'
        )

        $bodyLines = @(Get-RootPageBodyLines -BaseName $rootPage.BaseName -Language $Language)
        if ($bodyLines.Count -gt 0) {
            $pageLines += ''
            $pageLines += $bodyLines
        }

        $pagePath = Join-Path $SiteRoot ($rootPage.Slug + '.qmd')
        Write-Utf8File -Path $pagePath -Lines $pageLines | Out-Null
        [void]$renderPaths.Add($rootPage.Slug + '.qmd')
    }

    # 分类页
    foreach ($category in $Categories) {
        $categoryArticles = @($Articles | Where-Object { $_.RelativePath.StartsWith($category.Name + '/') })
        $pageLines = @('---')
        $pageLines += Get-YamlTitleLine -Title $category.Name
        $pageLines += 'page-layout: full'
        $pageLines += ('lang: ' + $Language)
        $pageLines += @(Get-LanguageHeaderLines -Href (Get-LanguageSwitchHref -Language $Language -OwnSitePath ($category.Slug + '.html') -TargetSitePath ($category.Slug + '.html')) -Label $ui.TargetLabel -HrefLang $ui.TargetCode)

        if ($categoryArticles.Count -gt 0) {
            $pageLines += 'listing:'
            $pageLines += '  id: category-listing'
            $pageLines += '  contents:'
            foreach ($article in ($categoryArticles | Sort-Object RelativePath)) {
                $pageLines += '    - ' + (ConvertTo-YamlPlainPath ('publish/' + $article.RelativePath))
            }
            $pageLines += @(
                '  sort: "date desc"'
                '  type: default'
                '  fields: [date, title]'
                '  categories: false'
                '  sort-ui: false'
                '  filter-ui: false'
                '---'
                ''
                '<!-- AUTO-GENERATED-CATEGORY-PAGE: edit folders/posts in Obsidian, not this file. -->'
                ''
                ':::{#category-listing}'
                ':::'
            )
        } else {
            $pageLines += @(
                '---'
                ''
                '<!-- AUTO-GENERATED-CATEGORY-PAGE: edit folders/posts in Obsidian, not this file. -->'
                ''
                '::: {.category-empty}'
                $ui.Empty
                ':::'
            )
        }

        $pagePath = Join-Path $SiteRoot ($category.Slug + '.qmd')
        Write-Utf8File -Path $pagePath -Lines $pageLines | Out-Null
        [void]$renderPaths.Add($category.Slug + '.qmd')
    }

    # 文章
    foreach ($article in $Articles) {
        $counterpartPath = $Counterparts[$article.RelativePath]
        $targetHref = $null
        if (-not [string]::IsNullOrWhiteSpace($counterpartPath)) {
            $targetHref = Get-LanguageSwitchHref -Language $Language `
                -OwnSitePath (Get-ArticleOutputPath -RelativePath $article.RelativePath) `
                -TargetSitePath (Get-ArticleOutputPath -RelativePath $counterpartPath)
        }

        New-SiteArticleFile -SiteRoot $SiteRoot `
            -RelativePath $article.RelativePath `
            -Timestamp $Timestamps[$article.RelativePath] `
            -Language $Language `
            -TargetHref $targetHref `
            -TargetLabel $ui.TargetLabel `
            -TargetHrefLang $ui.TargetCode

        [void]$renderPaths.Add((ConvertTo-YamlPlainPath ('publish/' + $article.RelativePath)))
    }

    # RSS 页脚
    $rssFooter = @(
        '<div class="rss-footer">'
        '  <hr>'
        '  <hr>'
        ('  <a class="rss-footer__link" href="' + ($SiteUrl.TrimEnd('/') + '/index.xml') + '" title="RSS feed" aria-label="RSS feed"><i class="bi bi-rss"></i></a>')
        '</div>'
    )
    Write-Utf8File -Path (Join-Path $SiteRoot 'rss-footer.html') -Lines $rssFooter | Out-Null

    # _quarto.yml
    $config = @(
        'project:'
        '  type: website'
        ('  output-dir: ' + (ConvertTo-YamlSingleQuoted -Value (Join-Path $tempBuildRoot $Language)))
        '  render:'
    )
    foreach ($renderPath in $renderPaths) {
        $config += '    - ' + (ConvertTo-YamlSingleQuoted -Value $renderPath)
    }
    $config += @(
        ''
        ('lang: ' + $Language)
        'date-format: long'
        ''
        'website:'
        ('  title: ' + (ConvertTo-YamlSingleQuoted -Value $ui.SiteTitle))
        ('  site-url: ' + (ConvertTo-YamlSingleQuoted -Value $SiteUrl))
        ('  google-analytics: ' + (ConvertTo-YamlSingleQuoted -Value $googleAnalyticsId))
        '  search: false'
        '  navbar:'
        '    logo: assets/foxmir-avatar.png'
    )

    if ($RootPages.Count -gt 0) {
        $config += '    left:'
        foreach ($rootPage in $RootPages) {
            $config += '      - href: ' + $rootPage.Slug + '.qmd'
            $config += '        text: ' + (ConvertTo-YamlSingleQuoted -Value (Get-RootPageTitle -BaseName $rootPage.BaseName -Language $Language))
        }
    }

    if ($Categories.Count -gt 0) {
        $config += '    right:'
        foreach ($category in $Categories) {
            $config += '      - href: ' + $category.Slug + '.qmd'
            $config += '        text: ' + (ConvertTo-YamlSingleQuoted -Value $category.Name)
        }
    }

    $config += @(
        ''
        'format:'
        '  html:'
        '    theme:'
        '      light: flatly'
        '      dark: darkly'
        '    respect-user-color-scheme: true'
        '    css: styles.css'
        '    include-after-body:'
        '      - outline-sidebar.html'
        '      - lang-switch.html'
        '      - rss-footer.html'
        '    toc: false'
    )

    Write-Utf8File -Path (Join-Path $SiteRoot '_quarto.yml') -Lines $config | Out-Null
    return $renderPaths.Count
}

# ---------------------------------------------------------------- 正文流程

$markdownFiles = @(
    Get-ChildItem $publish -Recurse -File -Include '*.md' |
        Where-Object { $_.DirectoryName -notmatch '[\\/][._]' }
)

$markdownFiles | ForEach-Object {
    Convert-ObsidianLinksInMarkdown -Path $_.FullName
}

if ($missingAttachmentRefs.Count -gt 0 -or $conflictingAttachmentRefs.Count -gt 0) {
    $errorLines = @('Attachment resolution failed during blog sync.')

    if ($missingAttachmentRefs.Count -gt 0) {
        $errorLines += ''
        $errorLines += 'Missing attachments:'
        $errorLines += @($missingAttachmentRefs.Values | Sort-Object MarkdownPath, ReferenceName | ForEach-Object {
            '- ' + $_.ReferenceName + ' referenced by ' + $_.MarkdownPath
        })
    }

    if ($conflictingAttachmentRefs.Count -gt 0) {
        $errorLines += ''
        $errorLines += 'Conflicting attachments:'
        foreach ($item in ($conflictingAttachmentRefs.Values | Sort-Object MarkdownPath, ReferenceName)) {
            $errorLines += '- ' + $item.ReferenceName + ' referenced by ' + $item.MarkdownPath
            $errorLines += @($item.Candidates | ForEach-Object { '  * ' + $_ })
        }
    }

    throw ([string]::Join([Environment]::NewLine, $errorLines))
}

if ($copiedAttachmentTargets.Count -gt 0) {
    Write-Host ('Resolved attachments: ' + $copiedAttachmentTargets.Count)
}

$rootErrorMarkdownPath = Join-Path $publish 'ERROR.md'
if (Test-Path -LiteralPath $rootErrorMarkdownPath) {
    Remove-Item -LiteralPath $rootErrorMarkdownPath -Force
}

# 中英配对
. (Join-Path $PSScriptRoot 'article-pairing.ps1')
$pairing = Invoke-ArticlePairing -ProjectPath $project

if (-not $pairing.Ok) {
    $pairingErrorLines = @('文章配对失败，下面这些判定不了：')
    $pairingErrorLines += @($pairing.Errors | ForEach-Object { '- ' + $_ })
    throw ([string]::Join([Environment]::NewLine, $pairingErrorLines))
}

$languageByPath = @{}
foreach ($pair in $pairing.Pairs) {
    $languageByPath[$pair.Zh] = 'zh'
    $languageByPath[$pair.En] = 'en'
}
foreach ($relativePath in @($pairing.ChineseOnly)) { $languageByPath[$relativePath] = 'zh' }
foreach ($relativePath in @($pairing.EnglishOnly)) { $languageByPath[$relativePath] = 'en' }

$counterparts = @{}
foreach ($pair in $pairing.Pairs) {
    $counterparts[$pair.Zh] = $pair.En
    $counterparts[$pair.En] = $pair.Zh
}

# 时间戳：配对的上下两篇共用一个时间，保证两边排序完全一样。
# 同一秒撞车时往后挪 1 秒，页面只显示日期，看不出区别。
$units = New-Object System.Collections.ArrayList
foreach ($pair in $pairing.Pairs) {
    $chineseTime = (Get-Item -LiteralPath (Join-Path $publish (ConvertTo-NativePath $pair.Zh))).LastWriteTime
    $englishTime = (Get-Item -LiteralPath (Join-Path $publish (ConvertTo-NativePath $pair.En))).LastWriteTime
    $time = if ($chineseTime -gt $englishTime) { $chineseTime } else { $englishTime }
    [void]$units.Add([pscustomobject]@{ Time = $time; Paths = @($pair.Zh, $pair.En) })
}
foreach ($relativePath in (@($pairing.ChineseOnly) + @($pairing.EnglishOnly))) {
    $time = (Get-Item -LiteralPath (Join-Path $publish (ConvertTo-NativePath $relativePath))).LastWriteTime
    [void]$units.Add([pscustomobject]@{ Time = $time; Paths = @($relativePath) })
}

$timestamps = @{}
$previousTicks = [long](-1)
foreach ($unit in ($units | Sort-Object Time)) {
    $roundedTicks = $unit.Time.Ticks - ($unit.Time.Ticks % [System.TimeSpan]::TicksPerSecond)
    if ($roundedTicks -le $previousTicks) {
        $roundedTicks = $previousTicks + [System.TimeSpan]::TicksPerSecond
    }
    $previousTicks = $roundedTicks
    $assignedTime = New-Object System.DateTime($roundedTicks)
    foreach ($relativePath in $unit.Paths) {
        $timestamps[$relativePath] = $assignedTime
    }
}

# 分类
$categories = @(
    Get-ChildItem $publish -Directory |
        Where-Object { $_.Name -notmatch '^[._]' -and $_.Name -notmatch '_files$' } |
        Sort-Object Name |
        ForEach-Object { [pscustomobject]@{ Name = $_.Name; Slug = (ConvertTo-Slug $_.Name) } }
)
$usedSlugs = @{}
foreach ($category in $categories) {
    if ($usedSlugs.ContainsKey($category.Slug)) {
        $category.Slug = $category.Slug + '-' + ($usedSlugs.Count + 1)
    }
    $usedSlugs[$category.Slug] = $true
}

$rootPages = @(Get-RootPages -Directory $publish)

$englishArticles = New-Object System.Collections.ArrayList
$chineseArticles = New-Object System.Collections.ArrayList
foreach ($relativePath in ($languageByPath.Keys | Sort-Object)) {
    $article = [pscustomobject]@{ RelativePath = $relativePath }
    if ($languageByPath[$relativePath] -eq 'zh') {
        [void]$chineseArticles.Add($article)
    } else {
        [void]$englishArticles.Add($article)
    }
}

$englishSiteRoot = Join-Path $buildRoot 'en'
$chineseSiteRoot = Join-Path $buildRoot 'zh'

[void](New-LanguageSite -Language 'en' -SiteRoot $englishSiteRoot -SiteUrl $siteUrlEn `
    -Articles $englishArticles.ToArray() -RootPages $rootPages -Categories $categories `
    -Timestamps $timestamps -Counterparts $counterparts)

[void](New-LanguageSite -Language 'zh' -SiteRoot $chineseSiteRoot -SiteUrl $siteUrlZh `
    -Articles $chineseArticles.ToArray() -RootPages $rootPages -Categories $categories `
    -Timestamps $timestamps -Counterparts $counterparts)

Write-Host ('配对：{0} 对；中文单篇 {1} 篇；英文单篇 {2} 篇' -f $pairing.Pairs.Count, $chineseArticles.Count, $englishArticles.Count)
Write-Host ('英文站：' + $englishSiteRoot)
Write-Host ('中文站：' + $chineseSiteRoot)
