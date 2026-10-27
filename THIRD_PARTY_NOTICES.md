# 第三方来源与使用边界

本目录是个人备考工具，不是官方产品。以下来源的知识产权归各自权利人；请仅用于个人学习，不要二次分发题库/音频的原始内容。

## 题库

- **o-Sakurajimamai-o/cet-practice**  
  <https://github.com/o-Sakurajimamai-o/cet-practice>  
  Windows Release v1.1.0 的 `seed/cet6.db`（含 CET4 行）。本系统读取其中题目、解析、文章与听力原文。该仓库 LICENSE 为 “Other”；使用前请自行阅读上游许可与第三方声明。
- 四级真题版权归全国大学英语四、六级考试委员会。题目/解析仅用于个人学习研究，不用于商业分发。

## 单词释义

- **懒笔记 英语四级高频词**  
  <https://english-exam.lazynote.cn/cet4/words/stats/frequency/>  
  用作 CET4 高频词释义与 CEFR 标签的来源之一。
- **KyleBing/english-vocabulary**  
  <https://github.com/KyleBing/english-vocabulary>  
  CET4 词表释义补充。

## 句子的中文翻译

- 部分真题例句的机器翻译来自 **MyMemory** 免费接口（<https://mymemory.translated.net/>）。机器翻译可能有误，程序把未翻译的句子标为“中文提示”而不是逐句翻译。
- 趣味句的离线种子由本系统生成；可用 DeepSeek 重新预生成。

## 技巧库

`data/techniques.json` 的 `basis` 仅使用“官方大纲要求 / 历年真题统计规律 / 公开备考教材常见方法 / 经验性技巧”，未编造论文或具体统计。

## 工具

- **ffmpeg / ffprobe**：<https://ffmpeg.org/>，用于整卷听力切分与时长读取。请遵守其 LGPL/GPL 许可。
- **PotPlayer**：由 Kakao/DAUM 提供；本系统只调用本机已安装的程序，不附带其安装包。
- **eSpeak NG**：<https://github.com/espeak-ng/espeak-ng>，GPL-3.0-or-later；`tools/espeak/` 内附精简 Windows 可执行文件与英语语音数据，仅用于本地生成听力 WAV。许可证全文见 `tools/espeak/COPYING.txt`。

## 个人数据

`data/` 下的错题、打卡、会话和缓存属于学习者自己的学习记录。程序不会上传音频或整个题库；DeepSeek 只接收当前题/词所需的短文本。
