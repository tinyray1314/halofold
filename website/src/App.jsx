import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  AppleLogo, ArrowDown, ArrowRight, BellSimpleRinging, CheckCircle, Circle, Cpu,
  CaretDown, CaretRight, Check, DownloadSimple, FileAudio, GearSix, Globe,
  ListBullets, ListNumbers, LockKey, Microphone, NotePencil, PauseCircle, Play,
  Plus, Quotes, ShieldCheck, SpeakerHigh, TextB, TextH, Waveform,
} from "@phosphor-icons/react";
import { ProductPricingSection, productNavigation, productNavigationCopy } from "./ProductPricingSection.jsx";

const DOWNLOAD_URL = "/downloads/Halofold-1.1.0.dmg";

const productUiCopy = {
  zh: {
    runningShort: "运行中", completedShort: "完成", interruptedShort: "中断", taskStatus: "任务状态", taskNames: ["优化数据导入性能", "重构用户权限模块", "修复移动端布局问题", "设计系统组件更新", "API 接口稳定性提升"],
    taskTimes: ["1 分钟", "21 分钟", "42 分钟", "1 小时 4 分", "1 小时 25 分"], completedRecords: "完成记录 · 2", unread: "2 未查看", interrupted: "中断 · 1",
    usage: "使用情况", weekly: "本周剩余", reset: "8 月 17 日重置", localToday: "本机今日", updated: "更新于 12:28 · 官方周用量",
    settings: "设置", done: "完成", voice: "语音", general: "通用", display: "显示", completeAlert: "任务完成", pauseAlert: "任务中断",
    systemVoice: "系统语音", uploadAudio: "上传音频", reminderLine: "有 {count} 个 Codex 任务已完成", countHint: "{count} 会替换为本批任务数量", preview: "预览",
    recordTitle: "直接录音", recordBody: "录下你熟悉的声音，完成时直接播放。", fileTitle: "导入提醒音频", fileBody: "使用已有音频作为任务完成提醒。", ready: "提醒已就绪",
    notes: "便签", activity: "活动", newNote: "新建", noteTabs: ["灵动岛便签功能", "产品思路", "发布准备"],
    noteDocs: [
      { title: "灵动岛便签功能", body: "在不打断当前工作流的前提下，提供随时召唤的快速记录能力，让灵感和想法一次即记、轻松切换、随时可查。" },
      { title: "产品思路", body: "把 Codex 的活动状态、声音提醒和随手记录放进同一个轻量入口，让等待任务完成的时间重新变得可用。" },
      { title: "发布准备", body: "确认安装包版本、下载链接和中英文文案，在发布前完成一轮桌面端与移动端验收。" },
    ],
    principle: "核心原则：快速捕捉，专注思考，零干扰。", noteQuote: "真正的效率，来自于在正确的时刻，记录正确的想法。", noteBullets: ["快速召唤与记录", "横向切换多张便签", "自动保存于本机"], saving: "正在保存…", saved: "已本地保存", shortcut: "⌘⇧Space 快速召唤",
    notePathIsland: "从灵动岛打开", notePathActivity: "从活动切换", noteOpen: "打开便签", noteSwitch: "切换到便签", noteExpanded: "便签已展开",
  },
  en: {
    runningShort: "Running", completedShort: "Done", interruptedShort: "Stopped", taskStatus: "Task status", taskNames: ["Optimize data imports", "Rebuild permission module", "Fix mobile layout", "Update design system", "Improve API stability"],
    taskTimes: ["1 min", "21 min", "42 min", "1 hr 4 min", "1 hr 25 min"], completedRecords: "Completed · 2", unread: "2 unread", interrupted: "Interrupted · 1",
    usage: "Usage", weekly: "Weekly remaining", reset: "Resets Aug 17", localToday: "Local today", updated: "Updated 12:28 · Official weekly usage",
    settings: "Settings", done: "Done", voice: "Voice", general: "General", display: "Display", completeAlert: "Task completed", pauseAlert: "Task interrupted",
    systemVoice: "System voice", uploadAudio: "Upload audio", reminderLine: "{count} Codex tasks have finished", countHint: "{count} is replaced with the current batch size", preview: "Preview",
    recordTitle: "Record directly", recordBody: "Use your own familiar voice when work finishes.", fileTitle: "Import reminder audio", fileBody: "Use an existing file for completed-task alerts.", ready: "Reminder ready",
    notes: "Notes", activity: "Activity", newNote: "New", noteTabs: ["Quick notes", "Product ideas", "Launch prep"],
    noteDocs: [
      { title: "Quick notes without leaving the flow", body: "Capture a thought without interrupting the current workflow. Keep ideas close, move between notes quickly, and return whenever you need them." },
      { title: "Product ideas", body: "Bring Codex activity, voice reminders, and quick notes into one lightweight place so waiting time becomes useful again." },
      { title: "Launch prep", body: "Verify the package version, download link, and bilingual copy before the final desktop and mobile review." },
    ],
    principle: "Core principle: quick capture, focused thinking, zero interruption.", noteQuote: "Real efficiency comes from capturing the right thought at the right moment.", noteBullets: ["Open and capture quickly", "Move between notes", "Save automatically on this Mac"], saving: "Saving…", saved: "Saved locally", shortcut: "⌘⇧Space to open",
    notePathIsland: "Open from island", notePathActivity: "Switch from activity", noteOpen: "Open Notes", noteSwitch: "Switch to Notes", noteExpanded: "Notes expanded",
  },
};

const copy = {
  zh: {
    nav: { voice: "语音提示", activity: "活动", notes: "便签", privacy: "隐私", download: "下载" },
    eyebrow: "专为 Codex 用户设计 · macOS 14+",
    heroTitleA: "不盯进度。", heroTitleB: "听见完成。",
    heroBody: "Halofold 把 Codex 关键提醒、随手便签和个人计划收进 Mac 顶部：需要你时会提醒，完成时会播报，到点时帮你真正开始。",
    downloadMac: "下载 macOS 版", seeHow: "看看它如何工作", scenes: "任务场景", settings: "提醒设置",
    running: "运行中", runningDesc: "持续跟进后台活动", completed: "任务完成", completedDesc: "完成后立即发声",
    interrupted: "任务中断", interruptedDesc: "需要处理时提醒", systemVoice: "文案朗读", recording: "直接录音", audioFile: "导入音频",
    voiceLine: "有 1 个 Codex 任务已完成", speaking: "正在播放提醒", detail: "活动详情已展开",
    voiceKicker: "不用把提醒交给默认提示音", voiceTitle: "让 Codex 用你熟悉的声音叫你回来。",
    voiceBody: "为完成和中断分别设置提醒。朗读一句文案、录下自己的声音，或直接导入常用音频。",
    voiceModes: {
      speech: { title: "文案朗读", body: "使用 macOS 系统语音朗读自定义文案，也可以选择趣味音色效果。" },
      record: { title: "直接录音", body: "在 Halofold 里录下自己的提醒，不需要额外的录音软件。" },
      file: { title: "导入音频", body: "使用已有的 m4a、mp3、wav、aiff 或 caf 音频作为提醒。" },
    },
    preview: "试听提醒", stopPreview: "停止试听", previewHint: "声音只会在你点击后播放",
    arrivalBlocked: "浏览器阻止了自动播放 · 点击听提醒", arrivalPlayed: "你有一个 Codex 任务已完成",
    activityKicker: "活动中心", activityTitle: "Codex 的进度，一眼就知道。",
    activityBody: "运行中、待你处理、已完成与已中断集中在 Mac 顶部；本周用量和本机今日 Token 也在同一处，不用反复切换窗口。",
    activityPoints: ["需要登录、确认或补充信息时及时提醒", "点击活动即可回到对应 Codex 任务", "官方周用量与本地 Token 分开显示"],
    notesKicker: "便签", notesTitle: "灵感出现时，不必离开当前工作。",
    notesBody: "从任何界面快速打开便签，记录、整理并自动保存在本机。它和活动并列存在，但不会打断你正在做的事。",
    notesPoints: ["标题、粗体、引用与列表格式", "多张便签横向切换", "内容仅保存在本机"],
    privacyKicker: "本地优先", privacyTitle: "看到工作状态，不等于交出工作内容。",
    privacyItems: [
      { title: "只读访问", body: "仅以只读方式访问你授权的本机 .codex 文件夹。" },
      { title: "不碰凭据", body: "不读取、复制或保存 Codex 登录凭据。" },
      { title: "不会上传", body: "对话内容、便签与提醒音频都留在这台 Mac。" },
    ],
    downloadKicker: "Halofold 1.1.0", downloadTitle: "把等待、灵感与下一步，放回同一个节奏。",
    downloadBody: "Codex 跟进、快速便签与我的日程均为本地优先。适用于 macOS 14 及以上版本，同时支持 Apple Silicon 与 Intel Mac。",
    directDownload: "下载 Halofold 1.1.0", installTitle: "安装很简单",
    installSteps: ["下载并打开 DMG", "将 Halofold 拖入“应用程序”", "首次打开时按系统提示确认"],
    localZip: "通用 DMG · Apple Silicon + Intel", footerTitle: "做完时，Halofold 会叫你回来。", creatorPrefix: "作者", backTop: "返回顶部",
    downloadStarted: "下载已开始",
  },
  en: {
    nav: { voice: "Voice", activity: "Activity", notes: "Notes", privacy: "Privacy", download: "Download" },
    eyebrow: "Built for Codex users · macOS 14+",
    heroTitleA: "Stop watching progress.", heroTitleB: "Hear when it’s done.",
    heroBody: "Halofold brings Codex alerts, quick notes, and personal plans to the top of your Mac—calling you back when attention is needed and helping you start what comes next.",
    downloadMac: "Download for macOS", seeHow: "See how it works", scenes: "Task scenes", settings: "Reminder",
    running: "Running", runningDesc: "Following background work", completed: "Completed", completedDesc: "Hear it the moment it ends",
    interrupted: "Interrupted", interruptedDesc: "Know when attention is needed", systemVoice: "Text to speech", recording: "Your recording", audioFile: "Audio file",
    voiceLine: "1 Codex task has finished", speaking: "Playing reminder", detail: "Activity details expanded",
    voiceKicker: "More personal than a default chime", voiceTitle: "Let Codex call you back in a voice you know.",
    voiceBody: "Set separate reminders for completed and interrupted work. Read a line, record yourself, or import an audio file you already use.",
    voiceModes: {
      speech: { title: "Text to speech", body: "Read custom copy with macOS system voices, with optional playful voice effects." },
      record: { title: "Record directly", body: "Capture your own reminder inside Halofold—no extra recording app needed." },
      file: { title: "Import audio", body: "Use an existing m4a, mp3, wav, aiff, or caf file as your alert." },
    },
    preview: "Preview reminder", stopPreview: "Stop preview", previewHint: "Audio only plays after you click",
    arrivalBlocked: "Browser blocked autoplay · Click to hear it", arrivalPlayed: "One Codex task has finished",
    activityKicker: "Activity center", activityTitle: "Know where Codex stands at a glance.",
    activityBody: "Running, action-needed, completed, and interrupted work stays together at the top of your Mac. Weekly usage and today's local tokens are there too—without another window.",
    activityPoints: ["Know when Codex needs a login, confirmation, or more context", "Open the matching Codex task in one click", "Keep official weekly usage separate from local tokens"],
    notesKicker: "Notes", notesTitle: "Capture the thought without leaving the work.",
    notesBody: "Open notes from anywhere, shape the idea, and keep it saved locally. Notes sit beside Activity without pulling you out of flow.",
    notesPoints: ["Headings, bold, quotes, and lists", "Move quickly between notes", "Everything stays on this Mac"],
    privacyKicker: "Local first", privacyTitle: "Seeing work status should not mean giving up your work.",
    privacyItems: [
      { title: "Read only", body: "Halofold only reads the local .codex folder you authorize." },
      { title: "No credentials", body: "It never reads, copies, or stores your Codex login credentials." },
      { title: "No uploads", body: "Conversations, notes, and reminder audio stay on this Mac." },
    ],
    downloadKicker: "Halofold 1.1.0", downloadTitle: "Bring waiting, ideas, and the next step into one rhythm.",
    downloadBody: "Codex follow-up, quick notes, and personal schedules are local first. For macOS 14 and later, with one universal build for Apple silicon and Intel Macs.",
    directDownload: "Download Halofold 1.1.0", installTitle: "Three quick steps",
    installSteps: ["Download and open the DMG", "Move Halofold to Applications", "Confirm the first launch when macOS asks"],
    localZip: "Universal DMG · Apple silicon + Intel", footerTitle: "When it’s done, Halofold calls you back.", creatorPrefix: "Author", backTop: "Back to top",
    downloadStarted: "Download started",
  },
};

const sceneIcons = { running: Circle, completed: CheckCircle, interrupted: PauseCircle };
const modeIcons = { speech: SpeakerHigh, record: Microphone, file: FileAudio };

function usePreferredLanguage() {
  const [locale, setLocale] = useState(() => {
    const saved = window.localStorage.getItem("halofold-locale");
    if (saved === "zh" || saved === "en") return saved;
    return navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en";
  });
  const update = (next) => { window.localStorage.setItem("halofold-locale", next); setLocale(next); };
  return [locale, update];
}

function Header({ locale, setLocale, t }) {
  return (
    <header className="site-header">
      <a className="brand-pill" href="#top" aria-label="Halofold home"><img src="/assets/halofold-icon.png" alt="" /><span>Halofold</span></a>
      <nav className="nav-pill" aria-label="Primary navigation">
        {productNavigation[locale].map((item) => item.key === "download" ? <a className="nav-download" href={DOWNLOAD_URL} download key={item.key}>{item.label}</a> : <a href={item.href} key={item.key}>{item.label}</a>)}
        <button className="locale-button" type="button" onClick={() => setLocale(locale === "zh" ? "en" : "zh")} aria-label={productNavigationCopy[locale].language}><Globe size={17} /><span>{productNavigationCopy[locale].language}</span>{locale === "zh" ? "EN" : "中文"}</button>
      </nav>
    </header>
  );
}

function ArrivalVoicePrompt({ locale, t, onComplete }) {
  const audioRef = useRef(null);
  const hideTimerRef = useRef(null);
  const [status, setStatus] = useState("idle");

  const playAudio = async (audio) => {
    await new Promise((resolve, reject) => {
      let settled = false;
      const finish = (callback, value) => {
        if (settled) return;
        settled = true;
        window.clearTimeout(startTimeout);
        audio.removeEventListener("playing", handlePlaying);
        audio.removeEventListener("error", handleError);
        callback(value);
      };
      const handlePlaying = () => finish(resolve);
      const handleError = () => finish(reject, audio.error || new Error("audio-playback-error"));
      const startTimeout = window.setTimeout(() => finish(reject, new Error("audio-start-timeout")), 2200);

      audio.addEventListener("playing", handlePlaying, { once: true });
      audio.addEventListener("error", handleError, { once: true });
      audio.play().catch((error) => finish(reject, error));
    });
  };

  const markPlayed = () => {
    onComplete();
    setStatus("played");
    window.clearTimeout(hideTimerRef.current);
    hideTimerRef.current = window.setTimeout(() => setStatus("idle"), 3600);
  };

  const playReminder = async () => {
    const audio = audioRef.current;
    if (!audio) return;
    audio.currentTime = 0;
    try {
      await playAudio(audio);
      markPlayed();
    } catch {
      if (!("speechSynthesis" in window)) { setStatus("blocked"); return; }
      try {
        await new Promise((resolve, reject) => {
          const utterance = new SpeechSynthesisUtterance(t.arrivalPlayed);
          const startTimeout = window.setTimeout(() => reject(new Error("speech-start-timeout")), 1400);
          utterance.lang = locale === "zh" ? "zh-CN" : "en-US";
          utterance.rate = .96;
          utterance.onstart = () => { window.clearTimeout(startTimeout); resolve(); };
          utterance.onerror = () => { window.clearTimeout(startTimeout); reject(new Error("speech-blocked")); };
          window.speechSynthesis.cancel();
          window.speechSynthesis.speak(utterance);
        });
        markPlayed();
      } catch {
        setStatus("blocked");
      }
    }
  };

  useEffect(() => {
    setStatus("pending");
    const timer = window.setTimeout(playReminder, 1500);
    return () => window.clearTimeout(timer);
  }, []);

  useEffect(() => () => window.clearTimeout(hideTimerRef.current), []);

  return (
    <>
      <audio
        ref={audioRef}
        src={locale === "zh" ? "/assets/codex-task-completed-zh.wav" : "/assets/codex-task-completed-en.wav"}
        preload="auto"
      />
      {status === "blocked" && (
        <button className="arrival-audio-prompt" type="button" onClick={() => playReminder()} aria-label={t.arrivalBlocked}>
          <SpeakerHigh size={18} weight="fill" /><span>{t.arrivalBlocked}</span>
        </button>
      )}
      {status === "played" && (
        <div className="arrival-audio-prompt is-played" role="status" aria-live="polite">
          <Waveform size={18} /><span>{t.arrivalPlayed}</span>
        </div>
      )}
    </>
  );
}

function ProductActivityUI({ ui, demoCompleted = true }) {
  const [selectedTask, setSelectedTask] = useState(0);
  const runningCount = demoCompleted ? 0 : 1;
  const completedCount = demoCompleted ? 4 : 3;
  return (
    <div className="product-ui activity-ui" aria-label={ui.taskStatus}>
      <div className={`activity-menubar ${demoCompleted ? "is-complete" : ""}`} aria-live="polite">
        <span><Circle size={17} weight="fill" />{ui.runningShort}<b>{runningCount}</b></span>
        <span className={demoCompleted ? "count-updated" : ""}><CheckCircle size={17} weight="fill" />{ui.completedShort}<b>{completedCount}</b></span>
        <span><PauseCircle size={17} weight="fill" />{ui.interruptedShort}<b>1</b></span>
        <span className="menu-weekly"><i>94%</i><em>{ui.weekly}</em></span>
        <GearSix className="activity-gear" size={19} />
      </div>
      <div className="activity-task-list">
        {ui.taskNames.map((name, index) => <button type="button" aria-pressed={selectedTask === index} className={`activity-task-row ${selectedTask === index ? "is-active" : ""}`} onClick={() => setSelectedTask(index)} key={name}><span className="ui-status-dot" /><strong>{name}</strong><small>{ui.taskTimes[index]}</small><CaretRight size={17} /></button>)}
      </div>
      <div className="activity-summary-row"><CheckCircle size={22} weight="fill" /><strong>{ui.completedRecords}</strong><span>{ui.unread}</span><CaretDown size={16} /></div>
      <div className="activity-summary-row interrupted-row"><PauseCircle size={22} weight="fill" /><strong>{ui.interrupted}</strong><CaretDown size={16} /></div>
      <div className="usage-block"><small>{ui.usage}</small><div className="usage-grid"><span className="usage-ring">64%</span><div><strong>{ui.weekly}</strong><small>{ui.reset}</small></div><div className="token-line"><strong>{ui.localToday}</strong><b>182K</b><span>tokens</span></div></div><small>{ui.updated}</small></div>
    </div>
  );
}

function ProductVoiceUI({ ui, mode }) {
  const modeContent = mode === "record" ? { icon: Microphone, title: ui.recordTitle, body: ui.recordBody } : mode === "file" ? { icon: FileAudio, title: ui.fileTitle, body: ui.fileBody } : null;
  if (modeContent) {
    const ModeIcon = modeContent.icon;
    return <div className="product-ui voice-ui voice-mode-state"><div className="product-ui-top"><span /><strong>{ui.settings}</strong><span>{ui.done}</span></div><div className="voice-mode-hero"><span className="voice-mode-icon"><ModeIcon size={38} weight="fill" /></span><h3>{modeContent.title}</h3><p>{modeContent.body}</p><span className="ready-pill"><Check size={16} weight="bold" />{ui.ready}</span></div></div>;
  }
  return (
    <div className="product-ui voice-ui">
      <div className="product-ui-top"><span /><strong>{ui.settings}</strong><span>{ui.done}</span></div>
      <div className="settings-tabs"><span>{ui.display}</span><strong><Waveform size={18} />{ui.voice}</strong><span><GearSix size={18} />{ui.general}</span></div>
      {[ui.completeAlert, ui.pauseAlert].map((title, index) => <div className={`voice-setting-card ${index ? "is-pause" : ""}`} key={title}><div className="voice-setting-title"><CheckCircle size={20} weight="fill" /><strong>{title}</strong><span className="ui-switch" /></div><div className="ui-segmented"><strong>{ui.systemVoice}</strong><span>{ui.uploadAudio}</span></div><div className="ui-input">{index ? ui.reminderLine.replace("已完成", "已中断").replace("finished", "stopped") : ui.reminderLine}</div><small>{ui.countHint}</small><button type="button"><Play size={14} weight="fill" />{ui.preview}</button></div>)}
    </div>
  );
}

function ProductNotesUI({ ui }) {
  const [activeNote, setActiveNote] = useState(0);
  const [typedBody, setTypedBody] = useState("");
  const [saved, setSaved] = useState(false);
  const activeDocument = ui.noteDocs[activeNote];

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) { setTypedBody(activeDocument.body); setSaved(true); return undefined; }
    let character = 0; let typingTimer; let restartTimer;
    const startTyping = () => {
      character = 0; setTypedBody(""); setSaved(false);
      typingTimer = window.setInterval(() => {
        character += 1; setTypedBody(activeDocument.body.slice(0, character));
        if (character >= activeDocument.body.length) { window.clearInterval(typingTimer); setSaved(true); restartTimer = window.setTimeout(startTyping, 4200); }
      }, 45);
    };
    startTyping();
    return () => { window.clearInterval(typingTimer); window.clearTimeout(restartTimer); };
  }, [activeDocument.body]);

  return (
    <div className="product-ui notes-ui" aria-label={ui.notes}>
      <div className="notes-ui-top"><strong>{ui.notes}</strong><span><b>{ui.activity}</b><i>11</i></span></div>
      <div className="note-tabs">{ui.noteTabs.map((tab, index) => <button type="button" className={index === activeNote ? "is-active" : ""} aria-pressed={index === activeNote} onClick={() => setActiveNote(index)} key={tab}>{tab}</button>)}<button className="new-note-button" type="button"><Plus size={17} weight="bold" />{ui.newNote}</button></div>
      <div className="note-document"><h3>{activeDocument.title}</h3><p>{typedBody}<span className="typing-caret" aria-hidden="true" /></p><strong>{ui.principle}</strong><blockquote>{ui.noteQuote}</blockquote><ul>{ui.noteBullets.map((item) => <li key={item}>{item}</li>)}</ul></div>
      <div className="note-toolbar"><span>{ui.shortcut}</span><div><TextH size={18} /><TextB size={18} weight="bold" /><Quotes size={18} /><ListBullets size={18} /><ListNumbers size={18} /></div><span className={saved ? "is-saved" : "is-saving"}>{saved ? <Check size={17} /> : <Waveform size={17} />}{saved ? ui.saved : ui.saving}</span></div>
    </div>
  );
}

function NotesJourneyDemo({ ui }) {
  const [path, setPath] = useState("island");
  const [phase, setPhase] = useState("source");
  const [cycle, setCycle] = useState(0);

  useEffect(() => {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reducedMotion) { setPhase("notes"); return undefined; }
    setPhase("source");
    const revealTimer = window.setTimeout(() => setPhase("notes"), path === "island" ? 1250 : 1650);
    const nextTimer = window.setTimeout(() => { setPath((current) => current === "island" ? "activity" : "island"); setCycle((current) => current + 1); }, 8200);
    return () => { window.clearTimeout(revealTimer); window.clearTimeout(nextTimer); };
  }, [path, cycle]);

  const replayPath = (nextPath) => { setPath(nextPath); setCycle((current) => current + 1); };
  const caption = phase === "notes" ? ui.noteExpanded : path === "island" ? ui.noteOpen : ui.noteSwitch;

  return (
    <div className={`notes-journey path-${path} phase-${phase}`}>
      <div className="notes-path-controls" aria-label={ui.notes}>
        <button type="button" className={path === "island" ? "is-active" : ""} onClick={() => replayPath("island")}><NotePencil size={16} />{ui.notePathIsland}</button>
        <button type="button" className={path === "activity" ? "is-active" : ""} onClick={() => replayPath("activity")}><ArrowRight size={16} />{ui.notePathActivity}</button>
      </div>
      <div className="notes-transition-stage">
        <div className="notes-source-layer" aria-hidden={phase === "notes"}>
          {path === "island" ? (
            <button type="button" className="notes-island-source" onClick={() => setPhase("notes")}><img src="/assets/halofold-icon.png" alt="" /><NotePencil size={20} weight="fill" /><strong>{ui.notes}</strong><small>{ui.shortcut.replace("快速召唤", "").replace("to open", "")}</small></button>
          ) : (
            <div className="activity-to-notes-source"><ProductActivityUI ui={ui} /><button type="button" className="activity-note-switch" onClick={() => setPhase("notes")}><NotePencil size={17} weight="fill" />{ui.noteSwitch}<ArrowRight size={15} /></button></div>
          )}
        </div>
        <div className="notes-target-layer"><ProductNotesUI key={`${path}-${cycle}`} ui={ui} /></div>
      </div>
      <div className="notes-journey-caption" aria-live="polite"><span /><strong>{caption}</strong></div>
    </div>
  );
}

function HeroShowcase({ t, ui, arrivalCompleted }) {
  const states = useMemo(() => ["running", "completed", "speaking", "detail"], []);
  const [step, setStep] = useState(0);
  const [manualUntil, setManualUntil] = useState(0);
  useEffect(() => {
    const id = window.setInterval(() => { if (Date.now() >= manualUntil) setStep((current) => (current + 1) % states.length); }, 2600);
    return () => window.clearInterval(id);
  }, [manualUntil, states.length]);
  useEffect(() => { if (arrivalCompleted) { setStep(2); setManualUntil(Date.now() + 4500); } }, [arrivalCompleted]);
  const state = states[step];
  const selectedScene = state === "running" ? "running" : state === "detail" || state === "speaking" ? "completed" : state;
  const chooseScene = (scene) => { setStep(scene === "running" ? 0 : scene === "completed" ? 1 : 2); setManualUntil(Date.now() + 7200); };
  return (
    <div className="showcase-grid" aria-label="Halofold activity and voice reminder demo">
      <div className="showcase-side scene-column">
        <p className="micro-label">{t.scenes}</p>
        {["running", "completed", "interrupted"].map((scene) => {
          const Icon = sceneIcons[scene]; const selected = selectedScene === scene;
          return <button key={scene} type="button" className={`scene-button ${selected ? "is-selected" : ""}`} onClick={() => chooseScene(scene)}><Icon size={22} weight={selected ? "fill" : "regular"} /><span><strong>{t[scene]}</strong><small>{t[`${scene}Desc`]}</small></span></button>;
        })}
        <div className="side-note"><BellSimpleRinging size={20} /><span>{t.voiceLine}</span></div>
      </div>
      <div className={`product-stage state-${state}`}>
        <div className="stage-bezel">
          <div className="macbook-screen">
            <ProductActivityUI ui={ui} demoCompleted={arrivalCompleted} />
            <div className="activity-shade" aria-hidden="true" />
            <div className="voice-toast" role="status" aria-live="polite">
              <img src="/assets/halofold-icon.png" alt="" /><div><strong>{state === "detail" ? t.detail : t.speaking}</strong><span>{t.voiceLine}</span></div>
              <div className="wave-bars" aria-hidden="true"><i /><i /><i /><i /><i /></div>
            </div>
          </div>
          <img className="macbook-frame" src="/assets/macbook-display-frame-alpha.png" alt="" aria-hidden="true" />
        </div>
        <div className="stage-caption"><span className={`status-dot status-${selectedScene}`} /><strong>{t[selectedScene]}</strong><span>{state === "speaking" ? t.speaking : state === "detail" ? t.detail : t[`${selectedScene}Desc`]}</span></div>
      </div>
      <div className="showcase-side settings-column">
        <p className="micro-label">{t.settings}</p>
        <div className="settings-card">
          <div className="setting-block"><span>{t.systemVoice}</span><div className="segmented"><b>{t.systemVoice}</b><span>{t.audioFile}</span></div></div>
          <div className="setting-block"><span>{t.voiceLine}</span><div className="voice-line">{t.voiceLine}</div></div>
          <div className="setting-block accent-row"><span>Accent</span><div><i className="accent blue" /><i className="accent green" /><i className="accent amber" /></div></div>
          <div className="appearance-row"><Waveform size={18} /><span>{t.speaking}</span></div>
        </div>
      </div>
    </div>
  );
}

function VoiceSection({ t, locale, ui }) {
  const [mode, setMode] = useState("speech"); const [speaking, setSpeaking] = useState(false);
  const previewVoice = () => {
    if (!("speechSynthesis" in window)) return;
    if (speaking) { window.speechSynthesis.cancel(); setSpeaking(false); return; }
    const utterance = new SpeechSynthesisUtterance(locale === "zh" ? "有一个 Codex 任务已完成" : "One Codex task has finished");
    utterance.lang = locale === "zh" ? "zh-CN" : "en-US"; utterance.rate = .96; utterance.onend = () => setSpeaking(false); utterance.onerror = () => setSpeaking(false);
    setSpeaking(true); window.speechSynthesis.cancel(); window.speechSynthesis.speak(utterance);
  };
  return (
    <section id="voice" className="section voice-section">
      <div className="section-heading centered-heading reveal"><span className="kicker">{t.voiceKicker}</span><h2>{t.voiceTitle}</h2><p>{t.voiceBody}</p></div>
      <div className="voice-workbench reveal">
        <div className="voice-image-frame"><ProductVoiceUI key={mode} ui={ui} mode={mode} /></div>
        <div className="voice-controls"><p className="micro-label">{t.settings}</p>
          {Object.keys(t.voiceModes).map((key) => { const Icon = modeIcons[key]; return <button key={key} className={`mode-button ${mode === key ? "is-selected" : ""}`} type="button" onClick={() => setMode(key)}><Icon size={22} weight={mode === key ? "fill" : "regular"} /><span><strong>{t.voiceModes[key].title}</strong><small>{t.voiceModes[key].body}</small></span></button>; })}
          <button className={`preview-button ${speaking ? "is-playing" : ""}`} type="button" onClick={previewVoice}>{speaking ? <Waveform size={20} /> : <Play size={20} weight="fill" />}{speaking ? t.stopPreview : t.preview}</button>
          <small className="preview-hint">{t.previewHint}</small>
        </div>
      </div>
    </section>
  );
}

function CheckList({ items }) { return <ul className="check-list">{items.map((item) => <li key={item}><CheckCircle size={20} weight="fill" /><span>{item}</span></li>)}</ul>; }

function DownloadButton({ className = "", label, startedLabel, icon: Icon = AppleLogo, iconWeight = "fill" }) {
  const [started, setStarted] = useState(false);
  const resetTimerRef = useRef(null);
  useEffect(() => () => window.clearTimeout(resetTimerRef.current), []);
  const handleClick = () => { setStarted(true); window.clearTimeout(resetTimerRef.current); resetTimerRef.current = window.setTimeout(() => setStarted(false), 2200); };
  return <a className={`download-button ${className}`} href={DOWNLOAD_URL} download onClick={handleClick} aria-live="polite">{started ? <CheckCircle size={20} weight="fill" /> : <Icon size={20} weight={iconWeight} />}{started ? startedLabel : label}</a>;
}

function ActivitySection({ t, ui }) { return <section id="activity" className="section split-section activity-section"><div className="split-copy reveal"><span className="kicker">{t.activityKicker}</span><h2>{t.activityTitle}</h2><p>{t.activityBody}</p><CheckList items={t.activityPoints} /></div><div className="screenshot-stage activity-screenshot reveal"><ProductActivityUI ui={ui} /></div></section>; }
function NotesSection({ t, ui }) { return <section id="notes" className="section split-section notes-section"><div className="screenshot-stage notes-screenshot reveal"><NotesJourneyDemo ui={ui} /></div><div className="split-copy reveal"><span className="kicker">{t.notesKicker}</span><h2>{t.notesTitle}</h2><p>{t.notesBody}</p><CheckList items={t.notesPoints} /></div></section>; }

function PrivacySection({ t }) {
  const icons = [ShieldCheck, LockKey, Cpu];
  return <section id="privacy" className="section privacy-section"><div className="section-heading centered-heading reveal"><span className="kicker">{t.privacyKicker}</span><h2>{t.privacyTitle}</h2></div><div className="privacy-grid reveal">{t.privacyItems.map((item, index) => { const Icon = icons[index]; return <div className="privacy-item" key={item.title}><Icon size={28} /><strong>{item.title}</strong><p>{item.body}</p></div>; })}</div></section>;
}

function SiteFooter({ t }) {
  const waveSegments = [44, 58, 76, 104, 68, 52, 122, 72, 56, 42];
  return (
    <footer id="download" className="site-footer">
      <div className="footer-signal" aria-hidden="true">
        <div className="footer-wave-track footer-wave-left">{waveSegments.map((size, index) => <Waveform key={`left-${size}-${index}`} size={size} weight="thin" />)}</div>
        <div className="footer-island"><img src="/assets/halofold-icon.png" alt="" /><Waveform size={86} weight="thin" /><CheckCircle size={27} weight="bold" /></div>
        <div className="footer-wave-track footer-wave-right">{waveSegments.slice().reverse().map((size, index) => <Waveform key={`right-${size}-${index}`} size={size} weight="thin" />)}</div>
      </div>
      <div className="footer-cta">
        <h2>{t.footerTitle}</h2>
        <DownloadButton className="footer-download" label={t.downloadMac} startedLabel={t.downloadStarted} icon={DownloadSimple} iconWeight="bold" />
      </div>
      <div className="footer-bottom">
        <a className="footer-brand" href="#top"><img src="/assets/halofold-icon.png" alt="" /><strong>Halofold</strong></a>
        <nav className="footer-nav" aria-label="Footer navigation"><a href="#voice">{t.nav.voice}</a><a href="#activity">{t.nav.activity}</a><a href="#notes">{t.nav.notes}</a><a href="#privacy">{t.nav.privacy}</a></nav>
        <div className="footer-meta"><span>Halofold 1.1.0</span><span>macOS 14+ · Apple Silicon + Intel</span></div>
        <a className="creator-link" href="https://aitiny.top" target="_blank" rel="noreferrer"><span>{t.creatorPrefix}</span>{" "}<strong>Tiny</strong><ArrowRight size={16} /></a>
      </div>
    </footer>
  );
}

function useReveal() {
  useEffect(() => {
    const elements = [...document.querySelectorAll(".reveal")];
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) { elements.forEach((el) => el.classList.add("is-visible")); return undefined; }
    const observer = new IntersectionObserver((entries) => entries.forEach((entry) => { if (entry.isIntersecting) { entry.target.classList.add("is-visible"); observer.unobserve(entry.target); } }), { threshold: .12 });
    elements.forEach((el) => observer.observe(el)); return () => observer.disconnect();
  }, []);
}

export function App() {
  const [locale, setLocale] = usePreferredLanguage(); const [arrivalCompleted, setArrivalCompleted] = useState(false); const t = copy[locale]; const ui = productUiCopy[locale]; useReveal();
  const handleArrivalComplete = useCallback(() => setArrivalCompleted(true), []);
  useEffect(() => { document.documentElement.lang = locale === "zh" ? "zh-CN" : "en"; document.title = locale === "zh" ? "Halofold — 不盯进度，听见完成" : "Halofold — Hear when Codex is done"; }, [locale]);
  return <div id="top" className="site-shell"><Header locale={locale} setLocale={setLocale} t={t} /><ArrivalVoicePrompt locale={locale} t={t} onComplete={handleArrivalComplete} /><main><section id="product" className="hero-section"><div className="hero-copy reveal is-visible"><span className="eyebrow"><span className="live-dot" />{t.eyebrow}</span><h1><span>{t.heroTitleA}</span>{" "}<span>{t.heroTitleB}</span></h1><p>{t.heroBody}</p><div className="hero-actions"><DownloadButton label={t.downloadMac} startedLabel={t.downloadStarted} /><a className="secondary-button" href="#voice">{t.seeHow}<ArrowDown size={18} /></a></div></div><HeroShowcase t={t} ui={ui} arrivalCompleted={arrivalCompleted} /></section><VoiceSection t={t} locale={locale} ui={ui} /><ActivitySection t={t} ui={ui} /><NotesSection t={t} ui={ui} /><PrivacySection t={t} /><ProductPricingSection locale={locale} downloadUrl={DOWNLOAD_URL} /></main><SiteFooter t={t} /></div>;
}
