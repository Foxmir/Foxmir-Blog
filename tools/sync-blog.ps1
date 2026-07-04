$ErrorActionPreference = 'Stop'

$project = $env:BLOG_PROJECT
$publish = $env:BLOG_PUBLISH
$blogSource = $env:BLOG_SOURCE
$siteUrl = 'https://foxmir.github.io/Foxmir-Blog/'
$googleAnalyticsId = 'G-VQW94RHSBY'
$excludedRootPageNames = @('HOME', 'ERROR')

if ([string]::IsNullOrWhiteSpace($project)) {
    $project = 'D:\Quarto\Foxmir_blog'
}
if ([string]::IsNullOrWhiteSpace($publish)) {
    $publish = Join-Path $project 'publish'
}

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

function Get-YamlDateLine {
    param([Parameter(Mandatory = $true)][datetime]$Date)

    return ('date: {0}' -f (ConvertTo-YamlSingleQuoted -Value $Date.ToString('yyyy-MM-dd')))
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

function Get-RootMarkdownContent {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$BaseName
    )

    $candidate = Get-ChildItem -LiteralPath $Directory -File |
        Where-Object {
            $_.BaseName.Equals($BaseName, [System.StringComparison]::OrdinalIgnoreCase) -and
            $_.Extension.Equals('.md', [System.StringComparison]::OrdinalIgnoreCase)
        } |
        Select-Object -First 1

    if ($null -eq $candidate) {
        return @()
    }

    return Get-MarkdownBodyLines -Path $candidate.FullName
}

function ConvertTo-DisplayTitle {
    param([Parameter(Mandatory = $true)][string]$Name)

    $specialTitles = @{
        'ABOUT' = 'About'
        'LOG' = 'LOG'
        'WEEKLYLOG' = 'LOG'
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

function Get-RootPages {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $rootMarkdownFiles = @(
        Get-ChildItem -LiteralPath $Directory -File -Filter '*.md' -ErrorAction SilentlyContinue |
            Where-Object { $excludedRootPageNames -notcontains $_.BaseName.ToUpperInvariant() }
    )

    $hasNewLogPage = @($rootMarkdownFiles | Where-Object {
        $_.BaseName.Equals('LOG', [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0

    return @(
        $rootMarkdownFiles |
            Where-Object {
                if ($hasNewLogPage) {
                    -not $_.BaseName.Equals('WEEKLYLOG', [System.StringComparison]::OrdinalIgnoreCase)
                } else {
                    -not $_.BaseName.Equals('LOG', [System.StringComparison]::OrdinalIgnoreCase)
                }
            } |
            ForEach-Object {
                $canonicalBaseName = if ($_.BaseName.Equals('WEEKLYLOG', [System.StringComparison]::OrdinalIgnoreCase)) {
                    'LOG'
                } else {
                    $_.BaseName
                }
                [pscustomobject]@{
                    SourcePath = $_.FullName
                    SourceBaseName = $_.BaseName
                    BaseName = $canonicalBaseName
                    Slug = ConvertTo-Slug $canonicalBaseName
                    Title = ConvertTo-DisplayTitle -Name $canonicalBaseName
                    BodyLines = @(Get-MarkdownBodyLines -Path $_.FullName)
                    SortKey = switch ($canonicalBaseName.ToUpperInvariant()) {
                        'ABOUT' { '000-about' }
                        'LOG' { '010-log' }
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

    foreach ($root in $attachmentSearchRoots) {
        if (-not $attachmentRootIndexCache.ContainsKey($root)) {
            $index = @{}
            Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $nameKey = $_.Name.ToLowerInvariant()
                    if (-not $index.ContainsKey($nameKey)) {
                        $index[$nameKey] = New-Object System.Collections.Generic.List[string]
                    }

                    $index[$nameKey].Add($_.FullName)
                }
            $attachmentRootIndexCache[$root] = $index
        }

        $rootIndex = $attachmentRootIndexCache[$root]
        $matches = @()
        if ($rootIndex.ContainsKey($cacheKey)) {
            $matches = @($rootIndex[$cacheKey] | Sort-Object)
        }

        if ($matches.Count -eq 1) {
            $result = [pscustomobject]@{
                Status = 'Resolved'
                Path = $matches[0]
                Root = $root
                Candidates = @($matches[0])
            }
            $attachmentResolutionCache[$cacheKey] = $result
            return $result
        }

        if ($matches.Count -gt 1) {
            $result = [pscustomobject]@{
                Status = 'Conflict'
                Path = $null
                Root = $root
                Candidates = @($matches | ForEach-Object { $_.FullName })
            }
            $attachmentResolutionCache[$cacheKey] = $result
            return $result
        }
    }

    $result = [pscustomobject]@{
        Status = 'Missing'
        Path = $null
        Root = $null
        Candidates = @()
    }
    $attachmentResolutionCache[$cacheKey] = $result
    return $result
}

function Convert-ObsidianLinksInMarkdown {
    param([Parameter(Mandatory = $true)][string]$Path)

    $content = [System.IO.File]::ReadAllText($Path)
    $markdownDirectory = Split-Path -Parent $Path
    $assetDirectory = Get-MarkdownAssetDirectory -MarkdownPath $Path
    $pattern = '(?<embed>!?)\[\[(?<target>[^\]#|]+)(?:#[^\]|]+)?(?:\|(?<alias>[^\]]+))?\]\]'

    $updatedContent = [regex]::Replace($content, $pattern, {
        param($match)

        $target = $match.Groups['target'].Value.Trim()
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

function Add-MissingTitleFrontMatter {
    param([Parameter(Mandatory = $true)][string]$Path)

    $lines = Get-FileContentLines -Path $Path
    $titleValue = [System.IO.Path]::GetFileNameWithoutExtension($Path)

    $bodyLines = $lines
    if ($lines.Length -ge 1 -and $lines[0] -eq '---') {
        $yamlEnd = -1
        for ($index = 1; $index -lt $lines.Length; $index++) {
            if ($lines[$index] -eq '---') {
                $yamlEnd = $index
                break
            }
        }

        if ($yamlEnd -gt 0) {
            $bodyLines = if ($yamlEnd + 1 -lt $lines.Length) { @($lines[($yamlEnd + 1)..($lines.Length - 1)]) } else { @() }
        }
    }

    $newLines = @(
        '---',
        (Get-YamlTitleLine -Title $titleValue),
        (Get-YamlDateLine -Date (Get-Item -LiteralPath $Path).LastWriteTime),
        '---',
        ''
    ) + $bodyLines
    Write-Utf8File -Path $Path -Lines $newLines | Out-Null
}

$markdownFiles = @(
    Get-ChildItem $publish -Recurse -File -Include '*.md' |
        Where-Object { $_.DirectoryName -notmatch '[\\/][._]' }
)

$markdownFiles | ForEach-Object {
    Add-MissingTitleFrontMatter -Path $_.FullName
}

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

$rootLogMarkdownPath = Join-Path $publish 'LOG.md'
$rootWeeklyLogMarkdownPath = Join-Path $publish 'WEEKLYLOG.md'
if ((Test-Path -LiteralPath $rootLogMarkdownPath) -and (Test-Path -LiteralPath $rootWeeklyLogMarkdownPath)) {
    Remove-Item -LiteralPath $rootLogMarkdownPath -Force
}

Get-ChildItem -LiteralPath $publish -File -Filter '*.html' -ErrorAction SilentlyContinue |
    Remove-Item -Force
Get-ChildItem -LiteralPath $publish -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '_files$' } |
    Remove-Item -Recurse -Force

$dirs = @(
    Get-ChildItem $publish -Directory |
    Where-Object { $_.Name -notmatch '^[._]' -and $_.Name -notmatch '_files$' } |
    Sort-Object Name
)
$items = @()
$used = @{}
$generatedCategoryPaths = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$generatedRootPagePaths = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$homeContentLines = Get-RootMarkdownContent -Directory $publish -BaseName 'Home'
$rootPages = @(Get-RootPages -Directory $publish)
$hasRootPageInputs = ($rootPages.Count -gt 0)

Get-ChildItem -LiteralPath $publish -File -Filter '*.md' -ErrorAction SilentlyContinue |
    Remove-Item -Force

foreach ($dir in $dirs) {
    $slug = ConvertTo-Slug $dir.Name
    if ($used.ContainsKey($slug)) {
        $slug = $slug + '-' + ($used.Count + 1)
    }
    $used[$slug] = $true

    $postCount = (Get-ChildItem $dir.FullName -File -Filter '*.md' -ErrorAction SilentlyContinue | Measure-Object).Count

    $items += [pscustomobject]@{
        Name = $dir.Name
        Slug = $slug
        PostCount = $postCount
        HasPosts = ($postCount -gt 0)
    }

    $contentsPath = ConvertTo-YamlPlainPath ('publish/' + $dir.Name)
    if ($postCount -gt 0) {
        $page = @(
            '---'
            'title: ' + (ConvertTo-YamlSingleQuoted $dir.Name)
            'page-layout: full'
            'listing:'
            '  id: category-listing'
            '  contents: ' + $contentsPath
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
        $page = @(
            '---'
            'title: ' + (ConvertTo-YamlSingleQuoted $dir.Name)
            'page-layout: full'
            '---'
            ''
            '<!-- AUTO-GENERATED-CATEGORY-PAGE: edit folders/posts in Obsidian, not this file. -->'
            ''
            '::: {.category-empty}'
            'No posts in this category yet.'
            ':::'
        )
    }
    $categoryPagePath = Join-Path $project ($slug + '.qmd')
    $generatedCategoryPaths.Add($categoryPagePath) | Out-Null
    Write-Utf8File -Path $categoryPagePath -Lines $page | Out-Null
}

Get-ChildItem $project -Filter '*.qmd' -File |
    Where-Object {
        $_.FullName -notin $generatedCategoryPaths -and
        ((Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'AUTO-GENERATED-CATEGORY-PAGE')
    } |
    Remove-Item -Force

foreach ($rootPage in $rootPages) {
    $rootPageLines = @(
        '---'
        'title: ' + (ConvertTo-YamlSingleQuoted $rootPage.Title)
        'page-layout: full'
        '---'
        ''
        '<!-- AUTO-GENERATED-ROOT-PAGE: edit root Markdown pages in Obsidian, not this file. -->'
    )

    if ($rootPage.BodyLines.Count -gt 0) {
        $rootPageLines += ''
        if ($rootPage.Slug -eq 'log') {
            $rootPageLines += '::: {.log-timeline}'
            $rootPageLines += $rootPage.BodyLines
            $rootPageLines += ':::'
        } else {
            $rootPageLines += $rootPage.BodyLines
        }
    }

    $rootPagePath = Join-Path $project ($rootPage.Slug + '.qmd')
    $generatedRootPagePaths.Add($rootPagePath) | Out-Null
    Write-Utf8File -Path $rootPagePath -Lines $rootPageLines | Out-Null
}

if ($hasRootPageInputs) {
    Get-ChildItem $project -Filter '*.qmd' -File |
        Where-Object {
            $_.Name -ne 'index.qmd' -and
            $_.FullName -notin $generatedRootPagePaths -and
            ((Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'AUTO-GENERATED-(ROOT|ABOUT)-PAGE')
        } |
        Remove-Item -Force
}

# MAINTAINER NOTE:
# index.qmd is generated by this script on every publish run. Do not make
# lasting homepage layout or UI changes by editing index.qmd alone; they will be
# overwritten the next time the BAT/workflow runs. Update this homepage generator
# and the shared styles.css together, then run the workflow with --no-push before
# asking the user to publish.
$homePage = @(
    '---'
    'title: "Foxmir Blog"'
    'page-layout: full'
    'listing:'
    '  - id: latest-listing'
)

if ($items.Count -gt 0) {
    $homePage += '    contents:'
    foreach ($item in $items) {
        $homePage += '      - ' + (ConvertTo-YamlPlainPath ('publish/' + $item.Name))
    }
} else {
    $homePage += '    contents: []'
}

$homePage += @(
    '    sort: "date desc"'
    '    type: default'
    '    fields: [date, title]'
    '    categories: false'
    '    sort-ui: false'
    '    filter-ui: false'
    '    max-items: 5'
)

foreach ($item in $items) {
    if ($item.HasPosts) {
        $homePage += '  - id: ' + $item.Slug + '-listing'
        $homePage += '    contents: ' + (ConvertTo-YamlPlainPath ('publish/' + $item.Name))
        $homePage += '    sort: "date desc"'
        $homePage += '    type: default'
        $homePage += '    fields: [date, title]'
        $homePage += '    categories: false'
        $homePage += '    sort-ui: false'
        $homePage += '    filter-ui: false'
        $homePage += '    max-items: 1'
    }
}

$homePage += @(
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

if ($homeContentLines.Count -gt 0) {
    $homePage += @(
        ''
        '::: {.home-lines}'
    )
    $homePage += $homeContentLines
    $homePage += ':::'
}

$homePage += @(
    ':::'
    ''
    '::: {.home-section .home-latest-section}'
    '::: {.home-section-label}'
    'Latest'
    ':::'
    ''
    '::: {.home-section-main}'
    ':::{#latest-listing}'
    ':::'
    ':::'
    ':::'
)

if ($items.Count -gt 0) {
    $homeMapOrder = @('bits', 'learn', 'reports', 'articles', 'notes')
    $homeMapItems = @(
        $items |
            Sort-Object @{
                Expression = {
                    $index = [array]::IndexOf($homeMapOrder, $_.Slug)
                    if ($index -lt 0) { [int]::MaxValue } else { $index }
                }
            }, Name
    )

    $homePage += @(
        ''
        '::: {.home-color-divider aria-hidden="true"}'
        ':::'
        ''
        '::: {.home-map}'
    )

    foreach ($item in $homeMapItems) {
        $note = switch ($item.Slug) {
            'articles' { 'Longer arguments when a question needs more room.' }
            'bits' { 'Criteria, definitions, and short technical answers.' }
            'learn' { 'Learning records and design reflections.' }
            'notes' { 'Loose fragments, sketches, and unfinished signals.' }
            'reports' { 'Experiment reports, statistics, and result reading.' }
            default { $item.Name + ' posts and notes.' }
        }

        $homePage += '::: {.map-item .map-item-' + $item.Slug + '}'
        $homePage += '::: {.map-item-head}'
        $homePage += '[' + $item.Name + '](' + $item.Slug + '.qmd)'
        $homePage += ':::'
        $homePage += ''
        $homePage += '::: {.map-item-note}'
        $homePage += $note
        $homePage += ':::'

        if ($item.HasPosts) {
            $homePage += ''
            $homePage += '::: {.map-item-latest}'
            $homePage += ':::{#' + $item.Slug + '-listing}'
            $homePage += ':::'
            $homePage += ':::'
        }

        $homePage += ':::'
        $homePage += ''
    }

    $homePage += ':::'
}

$homePage += ':::'

Write-Utf8File -Path (Join-Path $project 'index.qmd') -Lines $homePage | Out-Null

$config = @(
    'project:'
    '  type: website'
    '  output-dir: docs'
    ''
    'website:'
    '  title: "Foxmir Blog"'
    '  site-url: ' + (ConvertTo-YamlSingleQuoted $siteUrl)
    '  google-analytics: ' + (ConvertTo-YamlSingleQuoted $googleAnalyticsId)
    '  search: false'
    '  navbar:'
    '    logo: assets/foxmir-avatar.png'
)

if ($rootPages.Count -gt 0) {
    $config += '    left:'

    foreach ($rootPage in $rootPages) {
        $config += '      - href: ' + $rootPage.Slug + '.qmd'
        $config += '        text: ' + (ConvertTo-YamlSingleQuoted $rootPage.Title)
    }
}

$config += '    right:'

foreach ($item in $items) {
    $config += '      - href: ' + $item.Slug + '.qmd'
    $config += '        text: ' + (ConvertTo-YamlSingleQuoted $item.Name)
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
    '    include-after-body: outline-sidebar.html'
    '    toc: false'
)

Write-Utf8File -Path (Join-Path $project '_quarto.yml') -Lines $config | Out-Null
Write-Host ('Generated categories: ' + (($items | ForEach-Object { $_.Name }) -join ', '))
