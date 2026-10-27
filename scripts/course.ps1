# course.ps1 - the required 5-8 minute CET-4 paper-structure micro-course.

$script:CourseCtx = $null

$script:CourseSlides = @(
    [pscustomobject]@{
        Title = '1. 四级一张卷，分数怎么分？'
        Body = @'
总分 710。听力和阅读各占 35%，加起来就是 70%。
先记住一句话：听力和阅读是大头，写作和翻译是稳分区。

部分        | 分值  | 占比 | 时间    | 题量
------------+-------+------+---------+------
写作        | 106.5 | 15%  | 30 分钟 | 1 篇
听力        | 248.5 | 35%  | 25 分钟 | 25 题
阅读        | 248.5 | 35%  | 40 分钟 | 30 题
翻译        | 106.5 | 15%  | 30 分钟 | 1 段

分值色块（每一格大约 1%）：

写作  ███████████████  15%
听力  ███████████████████████████████████  35%
阅读  ███████████████████████████████████  35%
翻译  ███████████████  15%

普通同学想稳稳过线，先把听力和阅读抓住，再拿写作、翻译的框架分。
'@
    }
    [pscustomobject]@{
        Title = '2. 听力内部：一道篇章题顶两道新闻题'
        Body = @'
听力 25 题，内部并不是「每题一样值钱」。

短篇新闻：7 题 × 7.1 分 = 49.7 分
长对话：  8 题 × 7.1 分 = 56.8 分
听力篇章：10 题 × 14.2 分 = 142 分

用柱子看更直观（每题分值）：

新闻      ███████ 7.1
长对话    ███████ 7.1
听力篇章  ██████████████ 14.2

所以：听力篇章一道题，等于新闻/长对话两道题。
听篇章时更要集中，尤其是 but / however / because / so 后面的句子。
'@
    }
    [pscustomobject]@{
        Title = '3. 阅读内部：先做最值钱的仔细阅读'
        Body = @'
阅读 30 题，三种题型的分值差得很大：

选词填空：10 题 × 3.55 分 = 35.5 分（性价比最低）
长篇匹配：10 题 × 7.1 分 = 71 分
仔细阅读：10 题 × 14.2 分 = 142 分

每题分值柱状图：

选词填空  ███ 3.55
长篇匹配  ███████ 7.1
仔细阅读  ██████████████ 14.2

记住：一道仔细阅读 = 四道选词填空。

建议答题顺序：
仔细阅读（先拿大头） → 长篇匹配（找关键词） → 选词填空（时间不够可放弃）

这不是「偷懒」，是把有限时间放在最值钱的地方。
'@
    }
    [pscustomobject]@{
        Title = '4. 写作和翻译：各 106.5 分，靠框架稳分'
        Body = @'
写作 106.5 分，翻译 106.5 分。它们不要求你写得花哨，先要求：
切题、结构清楚、少语法错误。

写作的三段框架：
1. 开头：用自己的话复述题目，给出观点。
2. 中间：两个简单理由 + 一个例子。
3. 结尾：再说一次观点，提一个建议。

翻译的保命动作：
1. 先找句子主干（谁 + 做什么 + 什么）。
2. 不会的词，用简单词绕过去，比如「促进」不会写 promote，可以写 help。
3. 不要空着。空着一定是 0 分；写简单句还有分。

这两部分靠固定练习，不靠临时背大词。
'@
    }
    [pscustomobject]@{
        Title = '5. 整场 130 分钟，时间要这样分'
        Body = @'
建议时间轴（考试总时长约 130 分钟）：

写作 30 分钟
  ↓
听力 25 分钟（跟着录音走，不能暂停）
  ↓
仔细阅读 25—30 分钟（最值钱，先做）
  ↓
翻译 20—25 分钟（先写主干，不空着）
  ↓
长篇匹配 8—10 分钟（找关键词）
  ↓
选词填空 5—7 分钟（不够就猜，不纠结）

时间轴：

写作        ██████████████ 30
听力        ███████████ 25
仔细阅读    █████████████ 28
翻译        ██████████ 22
长篇匹配    ████ 9
选词填空    ███ 6

如果只剩 5 分钟，先保仔细阅读和翻译，不要回头死磕选词填空。
'@
    }
)

$script:CourseQuestions = @(
    [pscustomobject]@{
        Q = '听力篇章一道题多少分？'
        Options = @('7.1 分', '14.2 分', '3.55 分', '106.5 分')
        Answer = '14.2 分'
        Explain = '听力篇章每题 14.2 分，是新闻/长对话的两倍。一道篇章题等于两道新闻题。'
        Slide = 1
    },
    [pscustomobject]@{
        Q = '阅读里应该先做哪种题型？'
        Options = @('选词填空', '仔细阅读', '长篇匹配', '按试卷顺序做')
        Answer = '仔细阅读'
        Explain = '仔细阅读每题 14.2 分，是选词填空的 4 倍。先做仔细阅读，再做长篇匹配，最后选词填空。'
        Slide = 2
    },
    [pscustomobject]@{
        Q = '选词填空的性价比怎么样？'
        Options = @('最高，必须死磕', '中等，慢慢做', '最低，时间不够可放弃', '和仔细阅读一样')
        Answer = '最低，时间不够可放弃'
        Explain = '选词填空每题只有 3.55 分，10 题才 35.5 分。时间不够时，先保仔细阅读和翻译。'
        Slide = 2
    }
)

function Set-CourseSlide {
    param([int]$Index)
    $ctx = $script:CourseCtx
    if ($null -eq $ctx) { return }
    if ($Index -lt 0 -or $Index -ge $script:CourseSlides.Count) { return }
    $ctx.Index = $Index
    $slide = $script:CourseSlides[$Index]
    $ctx.Title.Text = $slide.Title
    $ctx.Body.Text = $slide.Body
    $ctx.Progress.Text = ('第 {0}/{1} 页 · 大约 6 分钟' -f ($Index + 1), $script:CourseSlides.Count)
    $ctx.Prev.Enabled = ($Index -gt 0)
    $ctx.Next.Text = if ($Index -eq $script:CourseSlides.Count - 1) { '开始 3 题小测' } else { '下一页' }
}

function Show-CourseQuiz {
    $ctx = $script:CourseCtx
    $ctx.BodyHost.Visible = $false
    $ctx.QuizPanel.Visible = $true
    $ctx.QuizPanel.Controls.Clear()
    $ctx.Title.Text = '6. 三题小测：全对才进主菜单'
    $ctx.Progress.Text = '答错没关系，会带你回对应那页再讲一遍。'
    $ctx.Prev.Visible = $false
    $ctx.Next.Visible = $false
    $script:CourseQuizState = [ordered]@{ Index = 0; Wrong = @(); Attempts = 0 }

    $render = {
        $panel = $script:CourseCtx.QuizPanel
        $panel.Controls.Clear()
        $state = $script:CourseQuizState
        if ($state.Index -ge $script:CourseQuestions.Count) {
            $allCorrect = ($state.Wrong.Count -eq 0)
            if ($allCorrect) {
                $l = New-UiLabel -Text '三题全对。你已抓住四级的分值重点，可以开始学习了。' -Size 22 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiGood
                $l.Location = New-Object System.Drawing.Point(10, 20)
                $panel.Controls.Add($l)
                $b = New-UiButton -Text '进入主菜单' -Width 220 -OnClick {
                    $st = Get-AppState
                    Set-ObjectPropertyValue $st 'onboardingComplete' $true
                    Set-ObjectPropertyValue $st 'tutorialPassed' $true
                    Set-ObjectPropertyValue $st 'tutorialCompletedAt' (Get-Date).ToString('o')
                    Save-AppState $st
                    Show-HomePage
                }
                $b.Location = New-Object System.Drawing.Point(10, 90)
                $panel.Controls.Add($b)
            } else {
                $l = New-UiLabel -Text '还有题没全对。我们回去把对应那一页再看一遍，不扣分。' -Size 18 -Color $script:UiTextColor -MaxWidth 850
                $l.Location = New-Object System.Drawing.Point(10, 20)
                $panel.Controls.Add($l)
                $b = New-UiButton -Text '回到对应那一页' -Width 220 -OnClick {
                    $target = 1
                    if ($script:CourseQuizState.Wrong.Count -gt 0) { $target = [int]$script:CourseQuizState.Wrong[0] }
                    $script:CourseQuizState = [ordered]@{ Index = 0; Wrong = @(); Attempts = 0 }
                    $script:CourseCtx.BodyHost.Visible = $true
                    $script:CourseCtx.QuizPanel.Visible = $false
                    $script:CourseCtx.Prev.Visible = $true
                    $script:CourseCtx.Next.Visible = $true
                    Set-CourseSlide $target
                }
                $b.Location = New-Object System.Drawing.Point(10, 90)
                $panel.Controls.Add($b)
            }
            return
        }
        $q = $script:CourseQuestions[$state.Index]
        $title = New-UiLabel -Text ('第 {0} 题：{1}' -f ($state.Index + 1), $q.Q) -Size 19 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark -MaxWidth 880
        $title.Location = New-Object System.Drawing.Point(10, 12)
        $panel.Controls.Add($title)
        $y = 62
        $script:CourseQuizChoice = $null
        foreach ($opt in $q.Options) {
            $rb = New-Object System.Windows.Forms.RadioButton
            $rb.Text = $opt
            $rb.Font = New-Object System.Drawing.Font($script:UiFontName, 16)
            $rb.AutoSize = $true
            $rb.Location = New-Object System.Drawing.Point(15, $y)
            $rb.Tag = $opt
            $panel.Controls.Add($rb)
            $script:CourseQuizChoice = $rb
            $y += 44
        }
        $feedback = New-UiLabel -Text '' -Size 15 -Color $script:UiDanger -MaxWidth 860
        $feedback.Location = New-Object System.Drawing.Point(10, ($y + 8))
        $panel.Controls.Add($feedback)
        $btn = New-UiButton -Text '提交这一题' -Width 190 -OnClick {
            $state = $script:CourseQuizState
            $q = $script:CourseQuestions[$state.Index]
            $checked = @($script:CourseCtx.QuizPanel.Controls | Where-Object { $_ -is [System.Windows.Forms.RadioButton] -and $_.Checked })
            if ($checked.Count -eq 0) { return }
            $choice = [string]$checked[0].Tag
            $fb = @($script:CourseCtx.QuizPanel.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Text -eq '' })[0]
            if ($choice -eq $q.Answer) {
                if ($fb) { $fb.Text = '对了。' + $q.Explain; $fb.ForeColor = $script:UiGood }
                Start-Sleep -Milliseconds 450
                $state.Index++
                & $script:CourseQuizRender
            } else {
                if ($fb) { $fb.Text = '不对。' + $q.Explain; $fb.ForeColor = $script:UiDanger }
                if ($state.Wrong -notcontains [int]$q.Slide) { $state.Wrong += [int]$q.Slide }
                $retry = New-UiButton -Text '看懂了，重答这题' -Width 210 -OnClick {
                    $st = $script:CourseQuizState
                    & $script:CourseQuizRender
                }
                $retry.Location = New-Object System.Drawing.Point(220, ($y + 40))
                $script:CourseCtx.QuizPanel.Controls.Add($retry)
            }
        }
        $btn.Location = New-Object System.Drawing.Point(10, ($y + 42))
        $panel.Controls.Add($btn)
    }
    $script:CourseQuizRender = $render
    & $render
}

function Show-CoursePage {
    param([switch]$FromMenu)
    Clear-ContentPanel
    $head = New-PageHeader '四级入门微课' '先花 5—8 分钟弄懂「分在哪里」，后面每天练什么就不再糊里糊涂。'
    $script:ContentPanel.Controls.Add($head)
    $card = New-UiCard -Width 1060 -Height 640
    $card.Location = New-Object System.Drawing.Point(0, 100)
    $script:ContentPanel.Controls.Add($card)
    $title = New-UiLabel -Text '' -Size 22 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark -MaxWidth 920
    $title.Location = New-Object System.Drawing.Point(20, 16)
    $card.Controls.Add($title)
    $progress = New-UiLabel -Text '' -Size 13 -Color $script:UiMutedColor
    $progress.Location = New-Object System.Drawing.Point(700, 24)
    $card.Controls.Add($progress)
    $bodyHost = New-Object System.Windows.Forms.Panel
    $bodyHost.Location = New-Object System.Drawing.Point(18, 64)
    $bodyHost.Size = New-Object System.Drawing.Size(1040, 480)
    $bodyHost.BackColor = [System.Drawing.Color]::FromArgb(252, 250, 244)
    $card.Controls.Add($bodyHost)
    $body = New-Object System.Windows.Forms.RichTextBox
    $body.Dock = [System.Windows.Forms.DockStyle]::Fill
    $body.ReadOnly = $true; $body.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $body.BackColor = [System.Drawing.Color]::FromArgb(252, 250, 244)
    $body.Font = New-Object System.Drawing.Font('NSimSun', 15.5)
    $body.ForeColor = $script:UiTextColor
    $bodyHost.Controls.Add($body)
    $quizPanel = New-Object System.Windows.Forms.Panel
    $quizPanel.Location = New-Object System.Drawing.Point(18, 64)
    $quizPanel.Size = New-Object System.Drawing.Size(1040, 500)
    $quizPanel.BackColor = [System.Drawing.Color]::FromArgb(252, 250, 244)
    $quizPanel.Visible = $false
    $quizPanel.AutoScroll = $true
    $card.Controls.Add($quizPanel)
    $prev = New-UiButton -Text '上一页' -Width 150 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor -OnClick {
        Set-CourseSlide ($script:CourseCtx.Index - 1)
    }
    $prev.Location = New-Object System.Drawing.Point(20, 560)
    $card.Controls.Add($prev)
    $next = New-UiButton -Text '下一页' -Width 190 -OnClick {
        $idx = $script:CourseCtx.Index
        if ($idx -ge $script:CourseSlides.Count - 1) { Show-CourseQuiz } else { Set-CourseSlide ($idx + 1) }
    }
    $next.Location = New-Object System.Drawing.Point(185, 560)
    $card.Controls.Add($next)
    if ($FromMenu) {
        $skip = New-UiButton -Text '返回主菜单' -Width 160 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor -OnClick { Show-HomePage }
        $skip.Location = New-Object System.Drawing.Point(760, 560)
        $card.Controls.Add($skip)
    }
    $script:CourseCtx = [pscustomobject]@{
        Index = 0; Title = $title; Body = $body; Progress = $progress;
        Prev = $prev; Next = $next; BodyHost = $bodyHost; QuizPanel = $quizPanel
    }
    Set-CourseSlide 0
    Set-StatusBar '完成 3 题小测后进入主菜单。'
    Reset-ContentScroll
}
