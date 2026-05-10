$ErrorActionPreference = 'Stop'

$project = $env:BLOG_PROJECT
$publish = $env:BLOG_PUBLISH
$blogSource = $env:BLOG_SOURCE
$siteUrl = 'https://foxmir.github.io/Foxmir-Blog/'
$googleAnalyticsId = 'G-VQW94RHSBY'

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
    $tempPath = $Path + '.tmp'
    $encoding = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText($tempPath, $content, $encoding)
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
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

        Copy-Item -LiteralPath $resolved.Path -Destination $destinationPath -Force
        $copiedAttachmentTargets[$destinationPath] = $true

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
    Write-Utf8File -Path $Path -Lines $newLines
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

Get-ChildItem $project -Filter '*.qmd' -File |
    Where-Object {
        (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'AUTO-GENERATED-CATEGORY-PAGE'
    } |
    Remove-Item -Force

$dirs = @(
    Get-ChildItem $publish -Directory |
    Where-Object { $_.Name -notmatch '^[._]' } |
    Where-Object {
        # Only generate categories that currently contain markdown posts.
        (Get-ChildItem $_.FullName -File -Filter '*.md' -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
    } |
    Sort-Object Name
)
$items = @()
$used = @{}
$homeContentLines = Get-RootMarkdownContent -Directory $publish -BaseName 'Home'
$aboutContentLines = Get-RootMarkdownContent -Directory $publish -BaseName 'About'
$buildId = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')

foreach ($dir in $dirs) {
    $slug = ConvertTo-Slug $dir.Name
    if ($used.ContainsKey($slug)) {
        $slug = $slug + '-' + ($used.Count + 1)
    }
    $used[$slug] = $true

    $items += [pscustomobject]@{
        Name = $dir.Name
        Slug = $slug
    }

    $contentsPath = ConvertTo-YamlPlainPath ('publish/' + $dir.Name)
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
    Write-Utf8File -Path (Join-Path $project ($slug + '.qmd')) -Lines $page
}

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
    $homePage += '  - id: ' + $item.Slug + '-listing'
    $homePage += '    contents: ' + (ConvertTo-YamlPlainPath ('publish/' + $item.Name))
    $homePage += '    sort: "date desc"'
    $homePage += '    type: default'
    $homePage += '    fields: [date, title]'
    $homePage += '    categories: false'
    $homePage += '    sort-ui: false'
    $homePage += '    filter-ui: false'
}

$homePage += @(
    '---'
    ''
    '<!-- AUTO-GENERATED-HOMEPAGE: edit folders/posts in Obsidian, not this file. -->'
    '<!-- BUILD-ID: ' + $buildId + ' -->'
    ''
    '::: {.home-stage}'
    '::: {.home-title}'
)

$homePage += 'FOXMIR'

$homePage += @(
    ':::'
    ':::'
    ''
    '::: {.home-content-layer}'
    '::: {.home-sections-wrap}'
)

if ($homeContentLines.Count -gt 0) {
    $homePage += @(
        ''
        '::: {.home-intro}'
    )
    $homePage += $homeContentLines
    $homePage += @(
        ':::'
        ''
    )
}

$homePage += @(
    ''
    '::: {.home-latest-section}'
    '::: {.home-latest-label}'
    'Latest'
    ':::'
    '::: {.home-latest-main}'
    ':::{#latest-listing}'
    ':::'
    ':::'
    ':::'
)

if ($items.Count -gt 0) {
    $homePage += @(
        ''
        '::: {.home-band-divider}'
        ':::'
        ''
        '::: {.home-band}'
        '::: {.home-band-sticky}'
        '<div class="home-band-track">'
    )
    foreach ($item in $items) {
        $homePage += '<section class="home-band-panel" data-panel="' + $item.Slug + '">'
        $homePage += '  <div class="hbp-label">' + $item.Name + '</div>'
        $homePage += '  <div class="hbp-main">'
        $homePage += ':::{#' + $item.Slug + '-listing}'
        $homePage += ':::'
        $homePage += '  </div>'
        $homePage += '</section>'
    }
    $homePage += @(
        '</div>'
        ':::'
        ':::'
    )
}

$homePage += @(
    ''
    ':::'
    ':::'
    ''
    '```{=html}'
    '<style>'
    'body:has(.home-stage) #title-block-header { display:none; }'
    'body:has(.home-stage) #quarto-content { max-width:min(1200px,calc(100vw - 3rem)); padding-top:0; }'
    'body:has(.home-stage) main.content { padding-top:0; }'
    'body:has(.home-stage) { overflow-x:hidden; }'
    ''
    '.home-stage {'
    '  position:fixed; inset:0; z-index:1;'
    '  display:grid; align-content:center; justify-items:center;'
    '  min-height:100vh;'
    '  padding:5rem 2rem 14rem;'
    '  text-align:center;'
    '  pointer-events:none;'
    '}'
    '.home-title {'
    '  margin:0;'
    '  font-family:"Avenir Next",Avenir,"Segoe UI",sans-serif;'
    '  font-size:clamp(5rem,14vw,10rem);'
    '  font-weight:800;'
    '  letter-spacing:-0.11em;'
    '  line-height:0.9;'
    '  text-transform:uppercase;'
    '  color:var(--site-text);'
    '  will-change:transform,filter,opacity;'
    '}'
    '.home-title p { margin:0; font-size:inherit; font-weight:inherit; color:inherit; letter-spacing:inherit; }'
    ''
    '.home-content-layer {'
    '  position:relative; z-index:2;'
    '  width:100vw;'
    '  margin-left:calc(50% - 50vw);'
    '  margin-top:44vh;'
    '  padding:2rem 0 0;'
    '  background:linear-gradient(180deg,transparent 0%,var(--site-bg) 14%,var(--site-bg) 100%);'
    '  overflow-x:clip;'
    '}'
    'body.quarto-dark .home-content-layer {'
    '  background:linear-gradient(180deg,transparent 0%,#111213 14%,#111213 100%);'
    '}'
    '.home-sections-wrap {'
    '  max-width:1080px;'
    '  margin:0 auto;'
    '  padding:0 2rem;'
    '}'
    '.home-intro {'
    '  max-width:min(760px,100%);'
    '  margin:0 auto 6.8rem;'
    '  transform:translateY(-2.1rem);'
    '  text-align:center;'
    '}'
    '.home-intro p {'
    '  margin:0;'
    '  font-size:clamp(1.04rem,1.8vw,1.24rem);'
    '  line-height:1.72;'
    '  color:var(--site-text-soft);'
    '}'
    ''
    '.home-latest-section {'
    '  display:grid;'
    '  grid-template-columns:minmax(80px,110px) 1fr;'
    '  gap:2rem;'
    '  align-items:start;'
    '  margin-top:1.1rem;'
    '  margin-bottom:4rem;'
    '}'
    '.home-band-divider {'
    '  width:100vw;'
    '  height:2px;'
    '  margin:0 0 2.1rem calc(50% - 50vw);'
    '  background:color-mix(in srgb,var(--site-text) 26%,transparent);'
    '}'
    '.home-latest-label {'
    '  padding-top:0.25rem;'
    '  font-family:"Avenir Next",Avenir,"Segoe UI",sans-serif;'
    '  font-size:0.75rem;'
    '  font-weight:700;'
    '  letter-spacing:0.18em;'
    '  text-transform:uppercase;'
    '  color:var(--site-text-soft);'
    '}'
    '.home-latest-main .quarto-listing,'
    '.home-latest-main .quarto-listing-container,'
    '.home-latest-main .quarto-listing-container-default,'
    '.home-latest-main .list,'
    '.home-latest-main .listing-item,'
    '.home-latest-main .quarto-post {'
    '  border:0!important; box-shadow:none!important; background:transparent!important; outline:0!important;'
    '}'
    '.home-latest-main .quarto-listing { margin-top:0; }'
    '.home-latest-main .list { display:grid; gap:1.2rem; }'
    '.home-latest-main .quarto-post { padding:0; }'
    '.home-latest-main .listing-title { margin:0; font-size:clamp(1.3rem,2vw,1.75rem); line-height:1.1; letter-spacing:-0.03em; }'
    '.home-latest-main .listing-title a { color:var(--site-text); text-decoration:none; }'
    '.home-latest-main .listing-title a:hover { color:var(--site-accent); }'
    '.home-latest-main .listing-date { margin-top:0.1rem; font-size:0.75rem; letter-spacing:0.1em; text-transform:uppercase; color:var(--site-text-soft); }'
    '.home-latest-main .listing-description,.home-latest-main .description { display:none; }'
    '.home-latest-main .metadata { padding-top:0; }'
    ''
    '.home-band {'
    '  --band-peek:clamp(4rem,8vw,8rem);'
    '  position:relative;'
    '  margin-top:1rem;'
    '}'
    '.home-band-sticky {'
    '  position:sticky;'
    '  top:5rem;'
    '  overflow:hidden;'
    '  padding-right:var(--band-peek);'
    '}'
    '.home-band-track {'
    '  display:flex;'
    '  gap:clamp(1rem,2vw,2rem);'
    '  will-change:transform;'
    '}'
    '.home-band-panel {'
    '  flex:0 0 calc(100% - var(--band-peek));'
    '  width:calc(100% - var(--band-peek));'
    '  display:grid;'
    '  grid-template-columns:1fr;'
    '  align-content:start;'
    '  padding:0 0 2rem;'
    '}'
    '.hbp-label {'
    '  font-family:"Avenir Next",Avenir,"Segoe UI",sans-serif;'
    '  font-size:clamp(3rem,8vw,6.5rem);'
    '  font-weight:800;'
    '  letter-spacing:-0.09em;'
    '  line-height:0.88;'
    '  text-transform:uppercase;'
    '  color:color-mix(in srgb,var(--site-text) 10%,transparent);'
    '  margin-bottom:1.6rem;'
    '  pointer-events:none;'
    '  user-select:none;'
    '}'
    '.hbp-main .quarto-listing,'
    '.hbp-main .quarto-listing-container,'
    '.hbp-main .quarto-listing-container-default,'
    '.hbp-main .list,'
    '.hbp-main .listing-item,'
    '.hbp-main .quarto-post {'
    '  border:0!important; box-shadow:none!important; background:transparent!important; outline:0!important;'
    '}'
    '.hbp-main .quarto-listing { margin-top:0; }'
    '.hbp-main .list { display:grid; gap:1.4rem; }'
    '.hbp-main .quarto-post { padding:0; display:grid; grid-template-columns:minmax(100px,130px) 1fr; gap:1.2rem; align-items:start; }'
    '.hbp-main .metadata { grid-column:1; grid-row:1; }'
    '.hbp-main .body { grid-column:2; grid-row:1; margin-bottom:0; }'
    '.hbp-main .listing-title { margin:0; font-size:clamp(1.6rem,2.4vw,2.3rem); line-height:1.06; letter-spacing:-0.04em; }'
    '.hbp-main .listing-title a { color:var(--site-text); text-decoration:none; }'
    '.hbp-main .listing-title a:hover { color:var(--site-accent); }'
    '.hbp-main .listing-date { font-size:0.75rem; letter-spacing:0.1em; text-transform:uppercase; color:var(--site-text-soft); margin-top:0.1rem; }'
    ''
    '@media(max-width:640px){'
    '  .home-stage{padding:3.5rem 1rem 8rem;}'
    '  .home-content-layer{margin-top:42vh;padding-top:1.2rem;}'
    '  .home-intro{transform:none;margin:0 auto 3rem;}'
    '  .home-band-divider{margin:0 0 1.4rem calc(50% - 50vw);}'
    '  .home-latest-section{grid-template-columns:1fr;gap:0.6rem;}'
    '  .home-band-sticky{position:static;overflow:visible;}'
    '  .home-band-track{display:grid;transform:none!important;}'
    '  .home-band-panel{flex:none;width:100%;}'
    '  .hbp-main .quarto-post{grid-template-columns:1fr;gap:0.3rem;}'
    '  .hbp-main .metadata,.hbp-main .body{grid-column:auto;grid-row:auto;}'
    '}'
    '</style>'
    '<script>'
    '(function(){'
    '  const title = document.querySelector(".home-title");'
    '  const cl = document.querySelector(".home-content-layer");'
    '  const band = document.querySelector(".home-band");'
    '  const sticky = document.querySelector(".home-band-sticky");'
    '  const track = document.querySelector(".home-band-track");'
    '  const panels = Array.from(document.querySelectorAll(".home-band-panel"));'
    '  let ticking = false;'
    '  let cycleHeight = 1;'
    '  let ringCycles = 1;'
    ''
    '  function setGeometry(){'
    '    if(!band||!sticky||!track||!panels.length)return;'
    '    if(window.innerWidth<=640){'
    '      sticky.style.height="";'
    '      band.style.height="";'
    '      panels.forEach(p=>p.style.minHeight="");'
    '      return;'
    '    }'
    '    const ph = Math.max(...panels.map(p=>p.scrollHeight),300);'
    '    const vh = window.innerHeight;'
    '    const stickyH = Math.min(ph, Math.floor(vh*0.72));'
    '    sticky.style.height = stickyH+"px";'
    '    panels.forEach(p=>p.style.minHeight=stickyH+"px");'
    '    const dist = Math.max(track.scrollWidth - sticky.clientWidth, 0);'
    '    cycleHeight = dist>0 ? Math.max(vh*0.58, stickyH*0.52) : 1;'
    '    ringCycles = dist>0 ? Math.max(panels.length + 2, 5) : 1;'
    '    const scrollRange = cycleHeight * ringCycles;'
    '    band.style.height = (stickyH + scrollRange)+"px";'
    '  }'
    ''
    '  function draw(){'
    '    const y = window.scrollY;'
    '    const fade = Math.min(y/380,1);'
    '    if(title){'
    '      title.style.transform=`translate3d(0,${y*0.16}px,0)`;'
    '      title.style.filter=`blur(${fade*16}px) grayscale(${fade*100}%)`;'
    '      title.style.opacity=Math.max(1-fade*1.6,0);'
    '    }'
    '    if(!band||!sticky||!track||!panels.length||window.innerWidth<=640)return;'
    '    const stickyTop = parseFloat(getComputedStyle(sticky).top)||0;'
    '    const start = band.offsetTop - stickyTop;'
    '    const span = Math.max(cycleHeight * ringCycles, 1);'
    '    const local = Math.min(Math.max(window.scrollY - start,0),span);'
    '    const phase = ((local / Math.max(cycleHeight,1)) % 1 + 1) % 1;'
    '    const dist = Math.max(track.scrollWidth - sticky.clientWidth, 0);'
    '    track.style.transform=`translate3d(${-phase*dist}px,0,0)`;'
    '  }'
    ''
    '  window.addEventListener("scroll",function(){'
    '    if(!ticking){requestAnimationFrame(function(){draw();ticking=false;});ticking=true;}'
    '  },{passive:true});'
    ''
    '  window.addEventListener("resize",function(){setGeometry();draw();});'
    '  setGeometry(); draw();'
    '})()'
    '</script>'
    '```'
)

Write-Utf8File -Path (Join-Path $project 'index.qmd') -Lines $homePage

$aboutPage = @(
    '---'
    'title: "About"'
    'page-layout: full'
    '---'
    ''
    '<!-- AUTO-GENERATED-ABOUT-PAGE: edit the root About.md in Obsidian, not this file. -->'
    '<!-- BUILD-ID: ' + $buildId + ' -->'
)

if ($aboutContentLines.Count -gt 0) {
    $aboutPage += ''
    $aboutPage += $aboutContentLines
}

Write-Utf8File -Path (Join-Path $project 'about.qmd') -Lines $aboutPage

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
    '    left:'
    '      - href: about.qmd'
    '        text: About'
    '    right:'
)

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
    '    respect-user-color-scheme: false'
    '    css: styles.css'
    '    include-after-body: outline-sidebar.html'
    '    toc: false'
)

Write-Utf8File -Path (Join-Path $project '_quarto.yml') -Lines $config
Write-Host ('Generated categories: ' + (($items | ForEach-Object { $_.Name }) -join ', '))
