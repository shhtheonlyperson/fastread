import AsyncStorage from "@react-native-async-storage/async-storage";
import Constants from "expo-constants";
import { StatusBar } from "expo-status-bar";
import * as ScreenOrientation from "expo-screen-orientation";
import { useFonts } from "expo-font";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Keyboard,
  Pressable,
  ScrollView,
  Switch,
  Text,
  TextInput,
  View,
  useWindowDimensions,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { extractArticle } from "../src/article-extract.js";
import { clamp, containsCjk, durationForToken, estimateMinutes, joinTokensForDisplay, splitForFocus, tokenSeparator, tokenize } from "../src/reader-core.js";

const STORAGE_KEY = "justread.expo.state.v2";
const APP_VERSION = Constants.expoConfig?.version || Constants.manifest?.version || "0.2.0";
const MAX_HTML_BYTES = 6 * 1024 * 1024;

const color = {
  paper: "#f5efe2",
  paperStrong: "#faf6ec",
  paperDeep: "#ece4d2",
  ink: "#1f1a17",
  inkMid: "#4a3f37",
  inkQuiet: "#8a7a6a",
  rule: "rgba(31,26,23,0.08)",
  ruleStrong: "rgba(31,26,23,0.18)",
  terracotta: "#c96442",
  focusDark: "#1c1714",
};

const localeData = {
  en: {
    label: "English",
    ui: {
      todayPrefix: "Today you've read",
      todaySuffix: "words.",
      todayMeta: ({ minutes, articles, streak }) => `${minutes} minutes across ${articles} articles. Streak: ${streak} days.`,
      continueReading: "Continue reading",
      ofWords: ({ read, total }) => `${read} of ${total}`,
      resume: "Resume",
      library: "Library",
      items: (count) => `${count} items`,
      readingNow: "Reading now",
      saved: "Saved",
      finished: "Finished",
    },
  },
  "zh-Hant": {
    label: "繁體中文",
    ui: {
      todayPrefix: "今天你已閱讀",
      todaySuffix: "個字",
      todayMeta: ({ minutes, articles, streak }) => `${minutes} 分鐘,共 ${articles} 篇文章。連續 ${streak} 天。`,
      continueReading: "繼續閱讀",
      ofWords: ({ read, total }) => `${read} / ${total}`,
      resume: "繼續",
      library: "書架",
      items: (count) => `${count} 項`,
      readingNow: "閱讀中",
      saved: "已儲存",
      finished: "已讀完",
    },
  },
};

const tabs = [
  { id: "home", label: "Library" },
  { id: "source", label: "Add" },
  { id: "reader", label: "Read" },
  { id: "stats", label: "Stats" },
  { id: "settings", label: "Settings" },
];

export default function FastReadScreen() {
  const { width, height } = useWindowDimensions();
  const [fontsLoaded] = useFonts({
    Fraunces: require("../FastReadApp/Resources/Fonts/Fraunces.ttf"),
    Inter: require("../FastReadApp/Resources/Fonts/Inter.ttf"),
    JetBrainsMono: require("../FastReadApp/Resources/Fonts/JetBrainsMono.ttf"),
  });
  const insets = useSafeAreaInsets();
  const [hasHydrated, setHasHydrated] = useState(false);
  const [locale, setLocale] = useState("en");
  const localePack = localeData[locale] || localeData.en;
  const ui = localePack.ui;
  const [activeTab, setActiveTab] = useState("home");
  const [library, setLibrary] = useState([]);
  const [articleId, setArticleId] = useState(null);
  const [wordIndex, setWordIndex] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [hasFinished, setHasFinished] = useState(false);
  const [focusMode, setFocusMode] = useState(false);
  const [wpm, setWpm] = useState(540);
  const [punctuationPause, setPunctuationPause] = useState(true);
  const [focusStyle, setFocusStyle] = useState("dot");
  const [wordFont, setWordFont] = useState("serif");
  const [readingStats, setReadingStats] = useState(() => createEmptyStats());

  const article = useMemo(() => library.find((item) => item.id === articleId) || library[0] || null, [articleId, library]);
  const tokens = useMemo(() => tokenize(article?.text || ""), [article?.text]);
  const token = tokens[wordIndex] || "";
  const progress = tokens.length ? (wordIndex + 1) / tokens.length : 0;
  const stats = useMemo(() => normalizeStatsForToday(readingStats, wpm), [readingStats, wpm]);
  const recentSources = useMemo(() => getRecentSources(library), [library]);
  const physicalIsLandscape = width > height;
  const appIsLandscape = physicalIsLandscape;
  const focusIsLandscape = focusMode || physicalIsLandscape;
  const isWide = width >= 700;

  useEffect(() => {
    let cancelled = false;

    async function hydrate() {
      try {
        const raw = await AsyncStorage.getItem(STORAGE_KEY);
        if (!raw || cancelled) {
          return;
        }

        const saved = JSON.parse(raw);
        const savedLibrary = Array.isArray(saved.library) ? saved.library.filter((item) => item?.text) : [];
        setLibrary(savedLibrary);
        setArticleId(savedLibrary.some((item) => item.id === saved.articleId) ? saved.articleId : savedLibrary[0]?.id || null);
        setWordIndex(Number.isFinite(saved.wordIndex) ? saved.wordIndex : 0);
        setLocale(localeData[saved.locale] ? saved.locale : "en");
        setWpm(clamp(Number(saved.wpm) || 540, 150, 1000));
        setPunctuationPause(saved.punctuationPause ?? true);
        setFocusStyle(["dot", "line", "crosshair"].includes(saved.focusStyle) ? saved.focusStyle : "dot");
        setWordFont(["serif", "sans", "mono"].includes(saved.wordFont) ? saved.wordFont : "serif");
        setReadingStats(normalizeStatsForToday(saved.stats || createEmptyStats(), Number(saved.wpm) || 540));
      } catch (error) {
        console.warn("Unable to restore JustRead state.", error);
      } finally {
        if (!cancelled) setHasHydrated(true);
      }
    }

    hydrate();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!hasHydrated) return;

    const payload = {
      locale,
      library,
      articleId: article?.id || null,
      wordIndex,
      wpm,
      punctuationPause,
      focusStyle,
      wordFont,
      stats,
    };
    AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(payload)).catch((error) => {
      console.warn("Unable to persist JustRead state.", error);
    });
  }, [article?.id, focusStyle, hasHydrated, library, locale, punctuationPause, stats, wordFont, wordIndex, wpm]);

  useEffect(() => {
    setWordIndex((current) => clamp(current, 0, Math.max(tokens.length - 1, 0)));
  }, [tokens.length]);

  const recordWords = useCallback(
    (count) => {
      setReadingStats((current) => recordReadWords(current, count, wpm));
    },
    [wpm],
  );

  const recordArticleFinished = useCallback(() => {
    setReadingStats((current) => recordFinishedArticle(current, wpm));
  }, [wpm]);

  useEffect(() => {
    if (!isPlaying || !tokens.length || !article) return undefined;

    const timeout = setTimeout(() => {
      setWordIndex((current) => {
        if (current >= tokens.length - 1) {
          setIsPlaying(false);
          setHasFinished(true);
          return current;
        }
        recordWords(1);
        return current + 1;
      });
    }, durationForToken(token, wpm, punctuationPause));

    return () => clearTimeout(timeout);
  }, [article, isPlaying, punctuationPause, recordWords, token, tokens.length, wpm]);

  useEffect(() => {
    ScreenOrientation.unlockAsync().catch((error) => {
      console.warn("Unable to unlock screen orientation.", error);
    });
  }, []);

  useEffect(() => {
    if (!article || !tokens.length) return;
    const shouldRecordFinish = progress >= 1 && !article.finishedAt;
    setLibrary((items) =>
      items.map((item) =>
        item.id === article.id
          ? {
              ...item,
              progress,
              tagKey: progress >= 1 ? "finished" : progress > 0 ? "readingNow" : item.tagKey,
              finishedAt: progress >= 1 ? item.finishedAt || new Date().toISOString() : null,
            }
          : item,
      ),
    );
    if (shouldRecordFinish) {
      recordArticleFinished();
    }
  }, [article, progress, recordArticleFinished, tokens.length]);

  const openArticle = useCallback((item, resume = item.progress > 0) => {
    if (!item) return;
    const articleTokens = tokenize(item.text);
    setIsPlaying(false);
    setHasFinished(resume && item.progress >= 1);
    setArticleId(item.id);
    setWordIndex(resume ? clamp(Math.floor(articleTokens.length * item.progress), 0, Math.max(articleTokens.length - 1, 0)) : 0);
    setLibrary((items) =>
      items.map((articleItem) =>
        articleItem.id === item.id
          ? {
              ...articleItem,
              lastOpenedAt: new Date().toISOString(),
              timesOpened: (articleItem.timesOpened || 0) + 1,
            }
          : articleItem,
      ),
    );
    setActiveTab("reader");
  }, []);

  const addArticle = useCallback(
    (text, title = "Pasted text", source = "Clipboard", sourceURL = null) => {
      const trimmed = text.trim();
      if (!trimmed) return;
      const readingUnits = tokenize(trimmed);
      const now = new Date().toISOString();
      const item = {
        id: `article-${Date.now()}`,
        title,
        source,
        sourceURL,
        author: "You",
        date: formatDisplayDate(now),
        createdAt: now,
        lastOpenedAt: now,
        finishedAt: null,
        readTime: `${Math.max(1, Math.ceil(estimateMinutes(readingUnits.length, wpm)))} min`,
        progress: 0,
        lede: makeLede(trimmed, readingUnits),
        tagKey: "readingNow",
        text: trimmed,
        timesOpened: 1,
      };
      setLibrary((items) => [item, ...items]);
      setArticleId(item.id);
      setWordIndex(0);
      setHasFinished(false);
      setActiveTab("reader");
    },
    [wpm],
  );

  const move = useCallback(
    (delta) => {
      setIsPlaying(false);
      setHasFinished(false);
      setWordIndex((current) => clamp(current + delta, 0, Math.max(tokens.length - 1, 0)));
    },
    [tokens.length],
  );

  const setProgress = useCallback(
    (value) => {
      setIsPlaying(false);
      setHasFinished(false);
      setWordIndex(clamp(Math.floor(value * Math.max(tokens.length - 1, 0)), 0, Math.max(tokens.length - 1, 0)));
    },
    [tokens.length],
  );

  const togglePlayback = useCallback(() => {
    if (!article || !tokens.length) return;

    if (isPlaying) {
      setIsPlaying(false);
      return;
    }

    if (hasFinished) {
      setWordIndex(0);
      setHasFinished(false);
    }
    setIsPlaying(true);
  }, [article, hasFinished, isPlaying, tokens.length]);

  if (!fontsLoaded || !hasHydrated) {
    return (
      <View style={[s.app, { alignItems: "center", justifyContent: "center" }]}>
        <ActivityIndicator color={color.terracotta} />
      </View>
    );
  }

  return (
    <View style={s.app}>
      <StatusBar style="dark" />
      <View style={[s.contentFrame, isWide && s.contentFrameWide, appIsLandscape && s.contentFrameLandscape]}>
        {activeTab === "home" ? (
          <LibraryScreen
            insets={insets}
            isLandscape={appIsLandscape}
            ui={ui}
            stats={stats}
            library={library}
            onResume={() => (article ? openArticle(article, true) : setActiveTab("source"))}
            onOpen={openArticle}
          />
        ) : null}
        {activeTab === "source" ? <SourceScreen insets={insets} isLandscape={appIsLandscape} recentSources={recentSources} onAddArticle={addArticle} /> : null}
        {activeTab === "reader" && article ? (
          <ReaderScreen
            insets={insets}
            isLandscape={appIsLandscape}
            article={article}
            token={token}
            tokens={tokens}
            wordIndex={wordIndex}
            progress={progress}
            isPlaying={isPlaying}
            wpm={wpm}
            setWpm={setWpm}
            focusStyle={focusStyle}
            wordFont={wordFont}
            onBack={() => setActiveTab("home")}
            onMove={move}
            onScrub={setProgress}
            onPlayPause={togglePlayback}
            onFocus={() => setFocusMode(true)}
          />
        ) : null}
        {activeTab === "reader" && !article ? <ReaderEmptyScreen insets={insets} isLandscape={appIsLandscape} onAdd={() => setActiveTab("source")} /> : null}
        {activeTab === "stats" ? <StatsScreen insets={insets} isLandscape={appIsLandscape} library={library} stats={stats} ui={ui} /> : null}
        {activeTab === "settings" ? (
          <SettingsScreen
            insets={insets}
            isLandscape={appIsLandscape}
            wpm={wpm}
            setWpm={setWpm}
            punctuationPause={punctuationPause}
            setPunctuationPause={setPunctuationPause}
            focusStyle={focusStyle}
            setFocusStyle={setFocusStyle}
            wordFont={wordFont}
            setWordFont={setWordFont}
            locale={locale}
            setLocale={setLocale}
          />
        ) : null}

        <TabBar activeTab={activeTab} onChange={setActiveTab} bottomInset={Math.max(insets.bottom, appIsLandscape ? 16 : 28)} />
      </View>

      <FocusMode
        visible={focusMode && !!article}
        isLandscape={focusIsLandscape}
        token={token}
        article={article}
        progress={progress}
        wordIndex={wordIndex}
        total={tokens.length}
        isPlaying={isPlaying}
        wpm={wpm}
        focusStyle={focusStyle}
        wordFont={wordFont}
        onClose={() => setFocusMode(false)}
        onMove={move}
        onPlayPause={togglePlayback}
      />
    </View>
  );
}

function LibraryScreen({ insets, isLandscape, ui, stats, library, onResume, onOpen }) {
  const current = library.find((item) => item.progress > 0 && item.progress < 1) || library[0] || null;
  const currentCount = current ? tokenize(current.text).length : 0;
  const topPad = topPadding(insets, isLandscape);
  const bottomPad = bottomPadding(isLandscape);

  return (
    <ScrollView style={s.screen} contentContainerStyle={{ paddingBottom: bottomPad }} showsVerticalScrollIndicator={false}>
      <View style={[s.masthead, { paddingTop: topPad }, isLandscape && s.mastheadLandscape]}>
        <View style={s.mastheadRow}>
          <View style={s.brandRow}>
            <BrandMark size={28} />
            <Text style={s.wordmark}>JustRead</Text>
          </View>
          <SectionLabel>{formatShortDate(new Date())}</SectionLabel>
        </View>
        <Text style={[s.heroLine, isLandscape && s.heroLineLandscape]}>{ui.todayPrefix}</Text>
        <Text style={[s.heroLine, isLandscape && s.heroLineLandscape]}>
          <Text style={{ color: color.terracotta }}>{stats.today.words.toLocaleString()}</Text> {ui.todaySuffix}
        </Text>
        <Text style={s.heroMeta}>{ui.todayMeta({ minutes: stats.today.minutes, articles: stats.today.articles, streak: stats.streak })}</Text>
      </View>

      <View style={[s.libraryBody, isLandscape && s.libraryBodyLandscape]}>
        <Pressable onPress={onResume} style={[s.continueWrap, isLandscape && s.continueWrapLandscape]}>
          {current ? (
            <Card>
              <View style={s.rowBetween}>
                <SectionLabel>{ui.continueReading}</SectionLabel>
                <SectionLabel tone="accent">{ui.ofWords({ read: Math.round(currentCount * current.progress), total: currentCount })}</SectionLabel>
              </View>
              <Text style={s.continueTitle}>{current.title}</Text>
              <View style={s.progressRow}>
                <ProgressBar progress={current.progress} />
                <Text style={s.percent}>{Math.round(current.progress * 100)}%</Text>
              </View>
              <View style={s.rowBetween}>
                <Text style={s.metaText}>
                  {current.source} / {current.readTime}
                </Text>
                <View style={s.resumePill}>
                  <Text style={s.resumeText}>{ui.resume}</Text>
                </View>
              </View>
            </Card>
          ) : (
            <Card>
              <SectionLabel>Start reading</SectionLabel>
              <Text style={s.continueTitle}>Add your first article.</Text>
              <Text style={s.metaText}>Paste text or fetch a URL to build a real library. Nothing is preloaded.</Text>
            </Card>
          )}
        </Pressable>

        <View style={[s.libraryListWrap, isLandscape && s.libraryListWrapLandscape]}>
          <View style={[s.rowBetween, { paddingHorizontal: 8, paddingBottom: 12 }]}>
            <SectionLabel>{ui.library}</SectionLabel>
            <SectionLabel faded>{ui.items(library.length)}</SectionLabel>
          </View>
          <View style={s.listCard}>
            {library.length ? (
              library.map((item, index) => (
                <Pressable key={item.id} onPress={() => onOpen(item)} style={[s.articleRow, index > 0 && s.topRule]}>
                  <View style={s.articleRowMain}>
                    <View style={s.articleTitleBlock}>
                      <Text numberOfLines={1} style={s.articleTitle}>
                        {item.title}
                      </Text>
                      <Text style={s.articleSubline}>
                        {item.source} · {item.readTime}
                      </Text>
                    </View>
                    <TagPill item={item} ui={ui} />
                  </View>
                </Pressable>
              ))
            ) : (
              <View style={s.articleRow}>
                <Text style={s.articleTitle}>No saved articles yet.</Text>
                <Text style={s.articleSubline}>Use Add to paste text or fetch a webpage.</Text>
              </View>
            )}
          </View>
        </View>
      </View>
    </ScrollView>
  );
}

function SourceScreen({ insets, isLandscape, recentSources, onAddArticle }) {
  const [input, setInput] = useState("");
  const [status, setStatus] = useState("");
  const [loading, setLoading] = useState(false);
  const bottomPad = bottomPadding(isLandscape);
  const trimmed = input.trim();
  const isUrl = looksLikeUrl(trimmed);
  const hasInput = trimmed.length > 0;
  const wordCount = hasInput && !isUrl ? tokenize(trimmed).length : 0;
  const actionLabel = loading
    ? "Fetching article..."
    : isUrl
      ? "Fetch & open in reader"
      : hasInput
        ? `Open ${wordCount.toLocaleString()} words in reader`
        : "Paste or type to begin";

  const handleAction = useCallback(async () => {
    Keyboard.dismiss();
    if (!hasInput || loading) return;

    if (!isUrl) {
      onAddArticle(trimmed);
      return;
    }

    setLoading(true);
    setStatus("Loading...");
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const parsed = new URL(trimmed.startsWith("http") ? trimmed : `https://${trimmed}`);
      if (!["http:", "https:"].includes(parsed.protocol)) throw new Error("Only http and https URLs are supported.");
      const response = await fetch(parsed.toString(), {
        headers: { accept: "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.2" },
        signal: controller.signal,
      });
      if (!response.ok) throw new Error(`Fetch failed with HTTP ${response.status}.`);
      const length = Number(response.headers.get("content-length") || 0);
      if (length > MAX_HTML_BYTES) throw new Error("Page is too large to extract.");
      const contentType = response.headers.get("content-type") || "";
      if (contentType && !/text\/html|application\/xhtml\+xml|text\/plain/i.test(contentType)) {
        throw new Error(`Unsupported content type: ${contentType}.`);
      }
      const html = await response.text();
      if (html.length > MAX_HTML_BYTES) throw new Error("Page is too large to extract.");
      const article = extractArticle(html, response.url || parsed.toString());
      if (!article.text || article.wordCount < 20) throw new Error("Could not find enough readable text on that page.");
      onAddArticle(article.text, article.title || parsed.host, parsed.host, response.url || parsed.toString());
    } catch (error) {
      setStatus(error.name === "AbortError" ? "Fetch timed out." : error.message || "Could not load that URL.");
    } finally {
      clearTimeout(timeout);
      setLoading(false);
    }
  }, [hasInput, input, isUrl, loading, onAddArticle, trimmed]);

  return (
    <ScrollView style={s.screen} keyboardShouldPersistTaps="handled" contentContainerStyle={{ paddingBottom: bottomPad }} showsVerticalScrollIndicator={false}>
      <PageTitle insets={insets} isLandscape={isLandscape} label="New reading" title={"Add something\nto read."} sub={"Paste a link or any text. We'll figure out which it is."} />
      <View style={{ paddingHorizontal: 24, gap: 28 }}>
        <View style={s.smartInputWrap}>
          <TextInput
            value={input}
            onChangeText={(value) => {
              setInput(value);
              setStatus("");
            }}
            multiline={!isUrl}
            numberOfLines={isUrl ? 1 : 6}
            textAlignVertical="top"
            placeholder="https://example.com/article  -  or paste an article, memo, or transcript..."
            placeholderTextColor="rgba(138,122,106,0.68)"
            autoCapitalize="none"
            autoCorrect={!isUrl}
            keyboardType={isUrl ? "url" : "default"}
            onSubmitEditing={isUrl ? handleAction : undefined}
            style={[s.smartInput, isUrl && s.smartInputUrl]}
          />
          {hasInput ? (
            <View style={[s.modeBadge, { backgroundColor: isUrl ? color.terracotta : color.ink }]}>
              <Text style={s.modeBadgeText}>{isUrl ? "Link" : "Text"}</Text>
            </View>
          ) : null}
        </View>

        {status ? <Text style={[s.status, { color: color.terracotta }]}>{status.toUpperCase()}</Text> : null}

        <Pressable onPress={handleAction} disabled={!hasInput || loading} style={[s.primaryButton, (!hasInput || loading) && s.primaryButtonDisabled]}>
          {loading ? <ActivityIndicator color="#fff" size="small" /> : null}
          <Text style={[s.primaryButtonText, !hasInput && { color: color.inkQuiet }]}>{actionLabel}</Text>
          {!loading && hasInput ? <Text style={s.primaryArrow}>{"->"}</Text> : null}
        </Pressable>

        <View>
          <SectionLabel>Recent sources</SectionLabel>
          {recentSources.length ? (
            recentSources.map((item, index) => (
              <Pressable key={item.id} onPress={() => setInput(item.url || item.label)} style={[s.recentRow, index === 0 && { marginTop: 12 }]}>
                <Text style={s.recentLabel}>{item.label}</Text>
                <Text style={s.recentDate}>{item.date}</Text>
              </Pressable>
            ))
          ) : (
            <View style={[s.recentRow, { marginTop: 12 }]}>
              <Text style={s.recentLabel}>No web sources yet</Text>
              <Text style={s.recentDate}>Fetch a URL</Text>
            </View>
          )}
        </View>
      </View>
    </ScrollView>
  );
}

function ReaderScreen({
  insets,
  isLandscape,
  article,
  token,
  tokens,
  wordIndex,
  progress,
  isPlaying,
  wpm,
  setWpm,
  focusStyle,
  wordFont,
  onBack,
  onMove,
  onScrub,
  onPlayPause,
  onFocus,
}) {
  const minutesLeft = estimateMinutes(Math.max(tokens.length - wordIndex, 0), wpm);
  const topPad = topPadding(insets, isLandscape);
  const bottomPad = bottomPadding(isLandscape);

  return (
    <ScrollView style={s.screen} contentContainerStyle={{ paddingBottom: bottomPad }} showsVerticalScrollIndicator={false}>
      <View style={[s.readerHeader, { paddingTop: topPad }, isLandscape && s.readerHeaderLandscape]}>
        <Pressable onPress={onBack}>
          <SectionLabel>{"< Library"}</SectionLabel>
        </Pressable>
        <Text style={s.readerTitle}>{article.title}</Text>
        <Text style={s.readerMeta}>
          {article.source} / {article.author} / {article.date}
        </Text>
      </View>

      <View style={[s.readerBody, isLandscape && s.readerBodyLandscape]}>
        <View style={[s.readerControls, isLandscape && s.readerControlsLandscape]}>
          <Card padding={0}>
            <View style={{ paddingHorizontal: 16, paddingTop: isLandscape ? 12 : 20, paddingBottom: 8 }}>
              <RSVPStage token={token} focusStyle={focusStyle} wordFont={wordFont} compact={isLandscape} />
            </View>
            <View style={{ paddingHorizontal: 16, paddingBottom: isLandscape ? 14 : 20, gap: 8 }}>
              <Scrubber value={progress} onChange={onScrub} />
              <View style={s.rowBetween}>
                <Text style={s.percent}>
                  {wordIndex + 1} / {tokens.length}
                </Text>
                <Text style={s.percent}>{minutesLeft < 1 ? `${Math.ceil(minutesLeft * 60)}s left` : `${minutesLeft.toFixed(1)}m left`}</Text>
              </View>
            </View>
          </Card>

          <Transport isPlaying={isPlaying} onPlayPause={onPlayPause} onMove={onMove} onFocus={onFocus} compact={isLandscape} />

          <PaceControl wpm={wpm} setWpm={setWpm} compact={isLandscape} />
        </View>

        <View style={[s.fullTextWrap, isLandscape && s.fullTextWrapLandscape]}>
          <SectionLabel>The full text</SectionLabel>
          <Text style={s.fullText}>
            {tokens.map((item, index) => {
              const parts = splitForFocus(item);
              const baseColor = index < wordIndex ? color.inkQuiet : index === wordIndex ? color.ink : color.inkMid;
              return (
                <Text key={`${item}-${index}`} style={{ color: baseColor, fontWeight: index === wordIndex ? "600" : "400" }}>
                  {parts.before}
                  <Text style={{ color: color.terracotta, fontWeight: "700" }}>{parts.focus}</Text>
                  {parts.after}
                  {tokenSeparator(item, tokens[index + 1])}
                </Text>
              );
            })}
          </Text>
        </View>
      </View>
    </ScrollView>
  );
}

function ReaderEmptyScreen({ insets, isLandscape, onAdd }) {
  return (
    <ScrollView style={s.screen} contentContainerStyle={{ paddingBottom: bottomPadding(isLandscape) }} showsVerticalScrollIndicator={false}>
      <PageTitle insets={insets} isLandscape={isLandscape} label="Reader" title={"Nothing\nqueued."} sub={"Add text or fetch a URL first. JustRead will preserve your real library and progress locally."} />
      <View style={{ paddingHorizontal: 24 }}>
        <Pressable onPress={onAdd} style={s.primaryButton}>
          <Text style={s.primaryButtonText}>Add something to read</Text>
          <Text style={s.primaryArrow}>{"->"}</Text>
        </Pressable>
      </View>
    </ScrollView>
  );
}

function FocusMode({ visible, isLandscape, token, article, progress, wordIndex, total, isPlaying, wpm, focusStyle, wordFont, onClose, onMove, onPlayPause }) {
  const insets = useSafeAreaInsets();

  if (!visible) return null;

  return (
    <View style={[s.focusScreen, s.focusOverlay, { paddingTop: Math.max(insets.top + 10, isLandscape ? 28 : 56), paddingBottom: Math.max(insets.bottom, isLandscape ? 18 : 40) }]}>
      <StatusBar hidden />
      <View style={s.focusTop}>
        <View style={{ flex: 1 }}>
          <Text style={s.focusLabel}>Focus / {wpm} wpm</Text>
          <Text numberOfLines={1} style={s.focusTitle}>
            {article.title}
          </Text>
        </View>
        <Pressable onPress={onClose} style={s.closeButton}>
          <Text style={s.closeText}>x</Text>
        </Pressable>
      </View>
      <View style={{ flex: 1, justifyContent: "center" }}>
        <RSVPStage token={token} focusStyle={focusStyle} wordFont={wordFont} dark big compact={isLandscape} />
      </View>
      <View style={{ paddingHorizontal: 24, gap: 18 }}>
        <View style={{ gap: 6 }}>
          <ProgressBar progress={progress} track="rgba(245,239,226,0.15)" />
          <View style={s.rowBetween}>
            <Text style={s.focusProgress}>
              {wordIndex + 1} / {total}
            </Text>
            <Text style={s.focusProgress}>{Math.round(progress * 100)}%</Text>
          </View>
        </View>
        <Transport dark compact={isLandscape} isPlaying={isPlaying} onPlayPause={onPlayPause} onMove={onMove} />
      </View>
    </View>
  );
}

function StatsScreen({ insets, isLandscape, library, stats, ui }) {
  const maxWords = Math.max(1, ...stats.week.map((item) => item.words));
  const weekTotal = stats.week.reduce((sum, item) => sum + item.words, 0);
  const finishedArticles = library.filter((item) => item.progress >= 1);
  const bottomPad = bottomPadding(isLandscape);
  const pace = stats.avgWpm || 0;

  return (
    <ScrollView style={s.screen} contentContainerStyle={{ paddingBottom: bottomPad }} showsVerticalScrollIndicator={false}>
      <PageTitle insets={insets} isLandscape={isLandscape} label="Stats" title={`${weekTotal.toLocaleString()} words`} sub={weekTotal ? `That's roughly ${(weekTotal / 60000).toFixed(2)} novellas at ${pace || 540} wpm.` : "Start reading to build a real weekly trend."} />
      <View style={{ paddingHorizontal: 16, gap: 8 }}>
        <View style={s.statCards}>
          <SmallStat label="Streak" value={stats.streak} unit="days" />
          <SmallStat label="Avg pace" value={stats.avgWpm || "-"} unit="wpm" />
          <SmallStat label="Best pace" value={stats.bestWpm || "-"} unit="wpm" />
          <SmallStat label="Articles read" value={stats.totalArticles} unit="total" />
        </View>
        <Card>
          <SectionLabel>This week</SectionLabel>
          <View style={s.chart}>
            {stats.week.map((item, index) => {
              const today = index === stats.week.length - 1;
              return (
                <View key={item.day} style={s.barColumn}>
                  <View style={[s.bar, { height: Math.max(4, (item.words / maxWords) * 112), backgroundColor: today ? color.terracotta : color.ink }]} />
                  <Text style={[s.barLabel, today && { color: color.terracotta, fontWeight: "700" }]}>{item.day}</Text>
                </View>
              );
            })}
          </View>
        </Card>
        <View style={{ paddingTop: 16 }}>
          <SectionLabel>Recently finished</SectionLabel>
          <View style={[s.listCard, { marginTop: 12 }]}>
            {finishedArticles.length ? (
              finishedArticles.map((item, index) => (
                <View key={item.id} style={[s.articleRow, index > 0 && s.topRule]}>
                  <View style={s.articleRowMain}>
                    <View style={s.articleTitleBlock}>
                      <Text numberOfLines={1} style={s.articleTitle}>
                        {item.title}
                      </Text>
                      <Text style={s.articleSubline}>
                        {item.source} · {item.readTime}
                      </Text>
                    </View>
                    <TagPill item={item} ui={ui} />
                  </View>
                </View>
              ))
            ) : (
              <View style={s.articleRow}>
                <Text style={s.articleTitle}>No completed articles yet.</Text>
                <Text style={s.articleSubline}>Finished articles will appear here after real reading sessions.</Text>
              </View>
            )}
          </View>
        </View>
        <View style={s.noteCard}>
          <SectionLabel>This week's note</SectionLabel>
          <Text style={s.noteText}>{buildWeeklyNote(stats)}</Text>
        </View>
      </View>
    </ScrollView>
  );
}

function SettingsScreen({ insets, isLandscape, wpm, setWpm, punctuationPause, setPunctuationPause, focusStyle, setFocusStyle, wordFont, setWordFont, locale, setLocale }) {
  const bottomPad = bottomPadding(isLandscape);

  return (
    <ScrollView style={s.screen} contentContainerStyle={{ paddingBottom: bottomPad }} showsVerticalScrollIndicator={false}>
      <PageTitle insets={insets} isLandscape={isLandscape} label="Settings" title={"The shape\nof your read."} />
      <View style={{ paddingHorizontal: 16, gap: 22 }}>
        <SettingsGroup label="Pace">
          <SettingsRow label="Words per minute" value={wpm} />
          <View style={{ paddingHorizontal: 16, paddingBottom: 14, gap: 4 }}>
            <Scrubber value={(wpm - 150) / 850} onChange={(value) => setWpm(Math.round((150 + value * 850) / 25) * 25)} />
            <View style={s.rowBetween}>
              <Text style={s.tinyMono}>Slow / 150</Text>
              <Text style={s.tinyMono}>Comfortable / 500</Text>
              <Text style={s.tinyMono}>Sprint / 1000</Text>
            </View>
          </View>
          <View style={s.settingsRow}>
            <View style={{ flex: 1 }}>
              <Text style={s.settingsLabel}>Pause on punctuation</Text>
              <Text style={s.settingsHint}>Slows down at periods, commas, and semicolons.</Text>
            </View>
            <Switch value={punctuationPause} onValueChange={setPunctuationPause} trackColor={{ true: color.terracotta, false: color.ruleStrong }} thumbColor="#fff" />
          </View>
        </SettingsGroup>
        <SettingsGroup label="Focus indicator">
          <Segmented value={focusStyle} onChange={setFocusStyle} options={[["dot", "Dots"], ["line", "Line"], ["crosshair", "Crosshair"]]} />
        </SettingsGroup>
        <SettingsGroup label="Word typeface">
          <Segmented value={wordFont} onChange={setWordFont} options={[["serif", "Serif"], ["sans", "Sans"], ["mono", "Mono"]]} />
        </SettingsGroup>
        <SettingsGroup label="Language">
          <Segmented value={locale} onChange={setLocale} options={[["en", "English"], ["zh-Hant", "繁體"]]} />
        </SettingsGroup>
        <SettingsGroup label="About">
          <SettingsRow label="Version" value={APP_VERSION} />
          <SettingsRow label="Privacy" value="Local only" />
          <SettingsRow label="Send feedback" value="shh@theonlyperson.com" last />
        </SettingsGroup>
      </View>
    </ScrollView>
  );
}

function RSVPStage({ token, focusStyle, wordFont, dark = false, big = false, compact = false }) {
  const parts = splitForFocus(token);
  const size = big ? (compact ? 58 : 76) : compact ? 44 : 54;
  const family = wordFont === "mono" ? "JetBrainsMono" : wordFont === "sans" ? "Inter" : "Fraunces";
  const fontStyle = containsCjk(token) ? null : { fontFamily: family };
  const ink = dark ? color.paper : color.ink;

  return (
    <View style={[s.stage, { minHeight: big ? (compact ? 142 : 220) : compact ? 122 : 180 }]}>
      <FocusGuide type={focusStyle} dark={dark} />
      <View style={s.stageWord}>
        <Text numberOfLines={1} adjustsFontSizeToFit style={[s.stageText, { color: ink, fontSize: size, textAlign: "right" }, fontStyle]}>
          {parts.before}
        </Text>
        <Text numberOfLines={1} style={[s.stageFocus, { fontSize: size }, fontStyle]}>
          {parts.focus}
        </Text>
        <Text numberOfLines={1} adjustsFontSizeToFit style={[s.stageText, { color: ink, fontSize: size, textAlign: "left" }, fontStyle]}>
          {parts.after}
        </Text>
      </View>
    </View>
  );
}

function FocusGuide({ type, dark }) {
  const guide = dark ? "rgba(245,239,226,0.18)" : "rgba(31,26,23,0.15)";
  if (type === "line") return <View pointerEvents="none" style={[s.centerLine, { backgroundColor: dark ? "rgba(201,100,66,0.55)" : "rgba(201,100,66,0.4)" }]} />;
  if (type === "crosshair") {
    return (
      <>
        <View pointerEvents="none" style={[s.centerLine, { backgroundColor: guide }]} />
        <View pointerEvents="none" style={[s.centerCross, { backgroundColor: dark ? "rgba(245,239,226,0.08)" : color.rule }]} />
      </>
    );
  }
  return (
    <>
      <View pointerEvents="none" style={[s.guideDot, { top: 22 }]} />
      <View pointerEvents="none" style={[s.guideDot, { bottom: 22 }]} />
    </>
  );
}

function Transport({ isPlaying, onPlayPause, onMove, onFocus, dark = false, compact = false }) {
  return (
    <View style={[s.transport, compact && s.transportCompact, dark ? { paddingTop: 0 } : null]}>
      <RoundButton label="-10" dark={dark} compact={compact} onPress={() => onMove(-10)} />
      <RoundButton label="<" dark={dark} small compact={compact} onPress={() => onMove(-1)} />
      <Pressable onPress={onPlayPause} style={[s.playButton, compact && s.playButtonCompact, dark && { width: compact ? 58 : 72, height: compact ? 58 : 72 }]}>
        <Text style={s.playText}>{isPlaying ? "II" : "▶"}</Text>
      </Pressable>
      <RoundButton label=">" dark={dark} small compact={compact} onPress={() => onMove(1)} />
      {onFocus ? <RoundButton label="[]" dark={dark} compact={compact} onPress={onFocus} /> : <RoundButton label="+10" dark={dark} compact={compact} onPress={() => onMove(10)} />}
    </View>
  );
}

function PaceControl({ wpm, setWpm, compact = false }) {
  return (
    <View style={[s.pace, compact && s.paceCompact]}>
      <View style={s.rowBetween}>
        <SectionLabel>Pace</SectionLabel>
        <Text style={s.paceValue}>
          {wpm} <Text style={s.paceUnit}>wpm</Text>
        </Text>
      </View>
      <Scrubber value={(wpm - 150) / 850} onChange={(value) => setWpm(Math.round((150 + value * 850) / 25) * 25)} />
      <View style={s.rowBetween}>
        <Text style={s.tinyMono}>150</Text>
        <Text style={s.tinyMono}>500</Text>
        <Text style={s.tinyMono}>1000</Text>
      </View>
    </View>
  );
}

function Scrubber({ value, onChange }) {
  const [width, setWidth] = useState(1);
  const apply = (event) => {
    const next = clamp(event.nativeEvent.locationX / width, 0, 1);
    onChange(next);
  };
  return (
    <Pressable onPress={apply} onLayout={(event) => setWidth(event.nativeEvent.layout.width)} style={s.scrubber}>
      <View style={[s.scrubberFill, { width: `${clamp(value, 0, 1) * 100}%` }]} />
      <View style={[s.scrubberThumb, { left: `${clamp(value, 0, 1) * 100}%` }]} />
    </Pressable>
  );
}

function TabBar({ activeTab, onChange, bottomInset }) {
  return (
    <View style={[s.tabBar, { paddingBottom: bottomInset }]}>
      {tabs.map((tab) => {
        const active = activeTab === tab.id;
        return (
          <Pressable key={tab.id} onPress={() => onChange(tab.id)} style={s.tabButton}>
            <TabIcon id={tab.id} active={active} />
            <Text style={[s.tabLabel, active && { color: color.terracotta }]}>{tab.label.toUpperCase()}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

function TabIcon({ id, active }) {
  const tint = active ? color.terracotta : color.inkQuiet;
  let icon;

  if (id === "stats") {
    icon = (
      <View style={s.statsIcon}>
        {[8, 14, 10, 16].map((height, index) => (
          <View key={index} style={{ width: 2, height, borderRadius: 1, backgroundColor: tint }} />
        ))}
      </View>
    );
  } else if (id === "source") {
    icon = (
      <View style={[s.circleIcon, { borderColor: tint }]}>
        <Text style={[s.iconGlyph, { color: tint }]}>+</Text>
      </View>
    );
  } else if (id === "reader") {
    icon = (
      <View style={[s.squareIcon, { borderColor: tint }]}>
        <View style={{ width: 4, height: 4, borderRadius: 2, backgroundColor: tint }} />
      </View>
    );
  } else if (id === "settings") {
    icon = (
      <View style={[s.settingsIcon, { borderColor: tint }]}>
        <View style={[s.settingsIconDot, { backgroundColor: tint }]} />
      </View>
    );
  } else {
    icon = (
      <View style={s.bookIcon}>
        <View style={[s.bookPage, { borderColor: tint }]} />
        <View style={[s.bookPage, { borderColor: tint }]} />
      </View>
    );
  }

  return <View style={s.tabIconSlot}>{icon}</View>;
}

function BrandMark({ size = 56 }) {
  return (
    <View style={[s.brandMark, { width: size, height: size, borderRadius: size * 0.225 }]}>
      <View style={s.grain} />
      <View style={s.brandLetters}>
        <Text style={[s.brandJ, { fontSize: size * 0.46 }]}>J</Text>
        <Text style={[s.brandR, { fontSize: size * 0.5 }]}>R</Text>
      </View>
      <View style={[s.brandDot, { width: size * 0.11, height: size * 0.11, borderRadius: size * 0.055, right: size * 0.16, top: size * 0.19 }]} />
    </View>
  );
}

function PageTitle({ insets, isLandscape, label, title, sub }) {
  return (
    <View style={[s.pageTitle, { paddingTop: topPadding(insets, isLandscape) }, isLandscape && s.pageTitleLandscape]}>
      <SectionLabel>{label}</SectionLabel>
      <Text style={[s.pageHeading, isLandscape && s.pageHeadingLandscape]}>{title}</Text>
      {sub ? <Text style={s.pageSub}>{sub}</Text> : null}
    </View>
  );
}

function Card({ children, padding = 18 }) {
  return <View style={[s.card, { padding }]}>{children}</View>;
}

function SectionLabel({ children, tone, faded }) {
  return <Text style={[s.sectionLabel, tone === "accent" && { color: color.terracotta }, faded && { opacity: 0.5 }]}>{String(children).toUpperCase()}</Text>;
}

function ProgressBar({ progress, track = color.rule }) {
  return (
    <View style={[s.progressTrack, { backgroundColor: track }]}>
      <View style={[s.progressFill, { width: `${clamp(progress, 0, 1) * 100}%` }]} />
    </View>
  );
}

function RoundButton({ label, onPress, small = false, dark = false, compact = false }) {
  return (
    <Pressable onPress={onPress} style={[s.roundButton, compact && s.roundButtonCompact, small && { width: compact ? 36 : 40, height: compact ? 36 : 40 }, dark && { backgroundColor: "rgba(245,239,226,0.08)", borderWidth: 0 }]}>
      <Text style={[s.roundText, dark && { color: color.paper }]}>{label}</Text>
    </Pressable>
  );
}

function SettingsGroup({ label, children }) {
  return (
    <View style={{ gap: 8 }}>
      <SectionLabel>{label}</SectionLabel>
      <View style={s.settingsGroup}>{children}</View>
    </View>
  );
}

function SettingsRow({ label, value, last }) {
  return (
    <View style={[s.settingsRow, !last && s.bottomRule]}>
      <Text style={s.settingsLabel}>{label}</Text>
      <Text style={s.settingsValue}>{value}</Text>
    </View>
  );
}

function Segmented({ value, onChange, options }) {
  return (
    <View style={s.segmented}>
      {options.map(([id, label]) => {
        const active = value === id;
        return (
          <Pressable key={id} onPress={() => onChange(id)} style={[s.segment, active && { backgroundColor: color.ink }]}>
            <Text style={[s.segmentText, active && { color: color.paper, fontWeight: "700" }]}>{label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

function StatMetric({ value, label }) {
  return (
    <View style={s.statMetric}>
      <Text style={s.statMetricValue}>{value}</Text>
      <Text style={s.statMetricLabel}>{label}</Text>
    </View>
  );
}

function SmallStat({ label, value, unit }) {
  return (
    <View style={s.smallStat}>
      <SectionLabel>{label}</SectionLabel>
      <Text style={s.smallStatValue}>{value}</Text>
      <Text style={s.smallStatUnit}>{unit}</Text>
    </View>
  );
}

function createEmptyStats(referenceDate = new Date()) {
  return {
    today: { words: 0, minutes: 0, articles: 0 },
    week: buildWeek(referenceDate),
    streak: 0,
    avgWpm: 0,
    bestWpm: 0,
    totalArticles: 0,
    lastActiveDay: null,
  };
}

function normalizeStatsForToday(input, wpm) {
  const base = input && typeof input === "object" ? input : createEmptyStats();
  const todayKey = dayKey(new Date());
  const datedWeek = Array.isArray(base.week) ? base.week.filter((item) => item?.date) : [];

  if (!datedWeek.length && Array.isArray(base.week) && base.week.some((item) => item?.words > 0)) {
    return createEmptyStats();
  }

  const wordsByDay = new Map(datedWeek.map((item) => [item.date, Number(item.words) || 0]));
  const week = buildWeek(new Date()).map((item) => ({ ...item, words: wordsByDay.get(item.date) || 0 }));
  const todayWords = week.find((item) => item.date === todayKey)?.words || 0;
  const sameActiveDay = base.lastActiveDay === todayKey;
  const today = {
    words: sameActiveDay ? todayWords : 0,
    minutes: sameActiveDay ? estimateStatMinutes(todayWords, wpm) : 0,
    articles: sameActiveDay ? Number(base.today?.articles) || 0 : 0,
  };

  return {
    today,
    week,
    streak: Number(base.streak) || 0,
    avgWpm: Number(base.avgWpm) || 0,
    bestWpm: Number(base.bestWpm) || 0,
    totalArticles: Number(base.totalArticles) || 0,
    lastActiveDay: base.lastActiveDay || null,
  };
}

function recordReadWords(current, count, wpm) {
  if (!count) return normalizeStatsForToday(current, wpm);
  const stats = startActivity(normalizeStatsForToday(current, wpm), wpm);
  const today = dayKey(new Date());
  const week = stats.week.map((item) => (item.date === today ? { ...item, words: item.words + count } : item));
  const words = stats.today.words + count;
  return {
    ...stats,
    week,
    today: { ...stats.today, words, minutes: estimateStatMinutes(words, wpm) },
    avgWpm: Math.round(wpm),
    bestWpm: Math.max(stats.bestWpm || 0, Math.round(wpm)),
  };
}

function recordFinishedArticle(current, wpm) {
  const stats = startActivity(normalizeStatsForToday(current, wpm), wpm);
  return {
    ...stats,
    today: { ...stats.today, articles: stats.today.articles + 1, minutes: estimateStatMinutes(stats.today.words, wpm) },
    totalArticles: stats.totalArticles + 1,
    avgWpm: Math.round(wpm),
    bestWpm: Math.max(stats.bestWpm || 0, Math.round(wpm)),
  };
}

function startActivity(stats) {
  const today = dayKey(new Date());
  const alreadyActive = stats.lastActiveDay === today && (stats.today.words > 0 || stats.today.articles > 0);
  if (alreadyActive) return stats;

  const yesterday = dayKey(addDays(new Date(), -1));
  return {
    ...stats,
    streak: stats.lastActiveDay === yesterday ? (stats.streak || 0) + 1 : 1,
    lastActiveDay: today,
  };
}

function buildWeek(referenceDate) {
  return Array.from({ length: 7 }, (_, index) => {
    const date = addDays(referenceDate, index - 6);
    return { date: dayKey(date), day: weekdayLabel(date), words: 0 };
  });
}

function getRecentSources(library) {
  const seen = new Set();
  return library
    .filter((item) => item.source && item.source !== "Clipboard")
    .map((item) => ({
      id: String(item.sourceURL || item.source).toLowerCase(),
      label: item.source,
      date: relativeDateLabel(item.createdAt || item.lastOpenedAt),
      url: item.sourceURL || null,
    }))
    .filter((item) => {
      if (seen.has(item.id)) return false;
      seen.add(item.id);
      return true;
    })
    .slice(0, 5);
}

function buildWeeklyNote(stats) {
  const weekTotal = stats.week.reduce((sum, item) => sum + item.words, 0);
  if (!weekTotal) {
    return "No reading activity yet this week. Paste an article or fetch a URL and JustRead will fill this with real pace, streak, and completion data.";
  }

  const activeDays = stats.week.filter((item) => item.words > 0).length;
  const bestDay = [...stats.week].sort((a, b) => b.words - a.words)[0];
  return `You read on ${activeDays} day${activeDays === 1 ? "" : "s"} this week. Your strongest day was ${bestDay.day} with ${bestDay.words.toLocaleString()} words.`;
}

function dayKey(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function addDays(date, days) {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

function weekdayLabel(date) {
  return date.toLocaleDateString(undefined, { weekday: "short" });
}

function formatShortDate(date) {
  return date.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
}

function formatDisplayDate(value) {
  return new Date(value).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
}

function relativeDateLabel(value) {
  if (!value) return "Recent";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Recent";
  const today = startOfLocalDay(new Date());
  const then = startOfLocalDay(date);
  const days = Math.round((today - then) / 86400000);
  if (days <= 0) return "Today";
  if (days === 1) return "Yesterday";
  if (days < 7) return `${days}d ago`;
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function startOfLocalDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function estimateStatMinutes(words, wpm) {
  if (!words) return 0;
  return Math.max(1, Math.ceil(estimateMinutes(words, wpm || 540)));
}

function tagLabel(item, ui) {
  return ui[item.tagKey] || item.tagKey;
}

function TagPill({ item, ui }) {
  const finished = item.tagKey === "finished";
  const text = `${finished ? "✓ " : ""}${tagLabel(item, ui)}`;
  return (
    <View style={[s.tagPill, item.tagKey === "readingNow" && s.tagPillReading, item.tagKey === "saved" && s.tagPillSaved, finished && s.tagPillFinished]}>
      <Text style={[s.tagText, item.tagKey === "readingNow" && s.tagTextReading, item.tagKey === "saved" && s.tagTextSaved, finished && s.tagTextFinished]}>{text}</Text>
    </View>
  );
}

function makeLede(text, tokens) {
  const limit = containsCjk(text) ? 42 : 18;
  return joinTokensForDisplay(tokens.slice(0, limit));
}

const URL_RE = /^(https?:\/\/\S+|(?:[a-z0-9-]+\.)+[a-z]{2,}(?:\/\S*)?)$/i;

function looksLikeUrl(text) {
  const value = (text || "").trim();
  if (!value || /\s/.test(value)) return false;
  return URL_RE.test(value);
}

function topPadding(insets, isLandscape) {
  return Math.max(insets.top + (isLandscape ? 8 : 22), isLandscape ? 28 : 60);
}

function bottomPadding(isLandscape) {
  return isLandscape ? 92 : 118;
}

const s = {
  app: { flex: 1, backgroundColor: color.paper },
  contentFrame: { flex: 1, width: "100%", alignSelf: "center", position: "relative", backgroundColor: color.paper },
  contentFrameWide: { maxWidth: 980 },
  contentFrameLandscape: { borderLeftWidth: 0.5, borderRightWidth: 0.5, borderColor: color.rule },
  screen: { flex: 1, backgroundColor: color.paper },
  masthead: { paddingHorizontal: 24, paddingBottom: 18 },
  mastheadLandscape: { paddingBottom: 12 },
  mastheadRow: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", marginBottom: 18 },
  brandRow: { flexDirection: "row", alignItems: "center", gap: 10 },
  wordmark: { fontFamily: "Fraunces", fontSize: 19, fontWeight: "600", color: color.ink, letterSpacing: -0.3 },
  heroLine: { fontFamily: "Fraunces", fontSize: 38, lineHeight: 39, fontWeight: "500", letterSpacing: -1, color: color.ink },
  heroLineLandscape: { fontSize: 31, lineHeight: 32 },
  heroMeta: { marginTop: 10, fontFamily: "Inter", fontSize: 14, lineHeight: 21, color: color.inkQuiet },
  sectionLabel: { fontFamily: "JetBrainsMono", fontSize: 11, fontWeight: "500", letterSpacing: 1.54, color: color.inkQuiet },
  card: { backgroundColor: color.paperStrong, borderRadius: 4, borderWidth: 0.5, borderColor: color.rule, gap: 12 },
  rowBetween: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 8 },
  libraryBody: { gap: 28 },
  libraryBodyLandscape: { flexDirection: "row", alignItems: "flex-start", gap: 14, paddingHorizontal: 16 },
  continueWrap: { paddingHorizontal: 16 },
  continueWrapLandscape: { flex: 0.42, paddingHorizontal: 0 },
  continueTitle: { fontFamily: "Fraunces", fontSize: 22, lineHeight: 26, fontWeight: "500", letterSpacing: -0.3, color: color.ink },
  progressRow: { flexDirection: "row", alignItems: "center", gap: 8 },
  progressTrack: { flex: 1, height: 2, borderRadius: 2, overflow: "hidden" },
  progressFill: { height: 2, backgroundColor: color.terracotta },
  percent: { fontFamily: "JetBrainsMono", fontSize: 11, letterSpacing: 0.66, color: color.inkQuiet },
  metaText: { fontFamily: "Inter", fontSize: 13, color: color.inkMid },
  resumePill: { paddingHorizontal: 12, paddingVertical: 7, borderRadius: 999, backgroundColor: color.terracotta },
  resumeText: { fontFamily: "Inter", fontSize: 13, fontWeight: "700", color: "#fff" },
  listCard: { backgroundColor: color.paperStrong, borderRadius: 4, borderWidth: 0.5, borderColor: color.rule, overflow: "hidden" },
  libraryListWrap: { paddingHorizontal: 16 },
  libraryListWrapLandscape: { flex: 0.58, paddingHorizontal: 0 },
  articleRow: { paddingHorizontal: 16, paddingVertical: 14 },
  topRule: { borderTopWidth: 0.5, borderTopColor: color.rule },
  articleRowMain: { flexDirection: "row", alignItems: "center", gap: 12 },
  articleTitleBlock: { flex: 1, minWidth: 0, gap: 4 },
  articleTitle: { fontFamily: "Fraunces", fontSize: 16, lineHeight: 20, fontWeight: "500", color: color.ink, letterSpacing: -0.2 },
  articleSubline: { fontFamily: "Inter", fontSize: 12, lineHeight: 17, color: color.inkQuiet },
  tagPill: { alignSelf: "center", borderRadius: 4, paddingHorizontal: 8, paddingVertical: 3 },
  tagPillReading: { backgroundColor: "rgba(201,100,66,0.10)" },
  tagPillSaved: { backgroundColor: "rgba(31,26,23,0.05)" },
  tagPillFinished: { backgroundColor: "transparent", paddingHorizontal: 0 },
  tagText: { fontFamily: "Inter", fontSize: 10, fontWeight: "600", letterSpacing: 0.6, textTransform: "uppercase" },
  tagTextReading: { color: color.terracotta },
  tagTextSaved: { color: color.inkMid },
  tagTextFinished: { color: color.inkQuiet },
  pageTitle: { paddingHorizontal: 24, paddingBottom: 18, gap: 8 },
  pageTitleLandscape: { paddingBottom: 12 },
  pageHeading: { fontFamily: "Fraunces", fontSize: 36, lineHeight: 38, fontWeight: "500", letterSpacing: -0.9, color: color.ink },
  pageHeadingLandscape: { fontSize: 30, lineHeight: 32 },
  pageSub: { fontFamily: "Inter", fontSize: 14, lineHeight: 21, color: color.inkMid },
  smartInputWrap: { position: "relative" },
  smartInput: { minHeight: 180, paddingTop: 14, paddingRight: 78, paddingBottom: 14, paddingLeft: 16, borderRadius: 4, borderWidth: 0.5, borderColor: color.ruleStrong, backgroundColor: color.paperStrong, color: color.ink, fontFamily: "Fraunces", fontSize: 15, lineHeight: 23 },
  smartInputUrl: { minHeight: 52, height: 52, fontFamily: "JetBrainsMono", fontSize: 13, lineHeight: 18 },
  modeBadge: { position: "absolute", top: 12, right: 12, paddingHorizontal: 8, paddingVertical: 3, borderRadius: 999 },
  modeBadgeText: { fontFamily: "JetBrainsMono", fontSize: 10, fontWeight: "500", letterSpacing: 1.2, color: "#fff", textTransform: "uppercase" },
  status: { fontFamily: "JetBrainsMono", fontSize: 11, letterSpacing: 0.66, color: color.inkQuiet },
  primaryButton: { height: 52, flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 8, borderRadius: 4, backgroundColor: color.ink },
  primaryButtonDisabled: { backgroundColor: color.ruleStrong },
  primaryButtonText: { color: "#fff", fontFamily: "Inter", fontSize: 15, fontWeight: "700" },
  primaryArrow: { color: "rgba(255,255,255,0.6)", fontFamily: "JetBrainsMono", fontSize: 13 },
  recentRow: { flexDirection: "row", justifyContent: "space-between", paddingVertical: 12, borderTopWidth: 0.5, borderTopColor: color.rule },
  recentLabel: { fontFamily: "JetBrainsMono", fontSize: 13, color: color.ink },
  recentDate: { fontFamily: "Inter", fontSize: 12, color: color.inkQuiet },
  readerHeader: { paddingHorizontal: 24, paddingBottom: 16, gap: 8 },
  readerHeaderLandscape: { paddingBottom: 10 },
  readerTitle: { marginTop: 4, fontFamily: "Fraunces", fontSize: 22, lineHeight: 25, fontWeight: "500", letterSpacing: -0.4, color: color.ink },
  readerMeta: { fontFamily: "Inter", fontSize: 12, color: color.inkQuiet },
  readerBody: { gap: 0 },
  readerBodyLandscape: { flexDirection: "row", alignItems: "flex-start", gap: 14, paddingHorizontal: 16 },
  readerControls: { gap: 0 },
  readerControlsLandscape: { flex: 0.48 },
  fullTextWrap: { paddingHorizontal: 24, paddingTop: 24 },
  fullTextWrapLandscape: { flex: 0.52, paddingHorizontal: 0, paddingTop: 0 },
  stage: { position: "relative", width: "100%", justifyContent: "center" },
  stageWord: { flexDirection: "row", alignItems: "baseline", justifyContent: "center", width: "100%" },
  stageText: { flex: 1, fontWeight: "500", letterSpacing: -0.5 },
  stageFocus: { color: color.terracotta, fontWeight: "700", letterSpacing: -0.5 },
  centerLine: { position: "absolute", top: 12, bottom: 12, left: "50%", width: 0.5 },
  centerCross: { position: "absolute", top: "50%", left: 24, right: 24, height: 0.5 },
  guideDot: { position: "absolute", left: "50%", width: 4, height: 4, marginLeft: -2, borderRadius: 2, backgroundColor: color.terracotta },
  scrubber: { height: 22, justifyContent: "center" },
  scrubberFill: { height: 2, borderRadius: 2, backgroundColor: color.terracotta },
  scrubberThumb: { position: "absolute", width: 18, height: 18, marginLeft: -9, borderRadius: 9, backgroundColor: color.terracotta },
  transport: { flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 14, paddingHorizontal: 24, paddingTop: 18 },
  transportCompact: { gap: 10, paddingHorizontal: 0, paddingTop: 12 },
  playButton: { width: 64, height: 64, borderRadius: 32, alignItems: "center", justifyContent: "center", backgroundColor: color.terracotta },
  playButtonCompact: { width: 54, height: 54, borderRadius: 27 },
  playText: { color: "#fff", fontFamily: "Inter", fontSize: 20, fontWeight: "800" },
  roundButton: { width: 44, height: 44, borderRadius: 22, alignItems: "center", justifyContent: "center", borderWidth: 0.5, borderColor: color.ruleStrong },
  roundButtonCompact: { width: 40, height: 40, borderRadius: 20 },
  roundText: { color: color.ink, fontFamily: "JetBrainsMono", fontSize: 12, fontWeight: "700" },
  pace: { paddingHorizontal: 24, paddingTop: 22, gap: 8 },
  paceCompact: { paddingHorizontal: 0, paddingTop: 14 },
  paceValue: { fontFamily: "Fraunces", fontSize: 22, fontWeight: "700", color: color.ink },
  paceUnit: { fontFamily: "JetBrainsMono", fontSize: 11, color: color.inkQuiet, letterSpacing: 1.54 },
  tinyMono: { fontFamily: "JetBrainsMono", fontSize: 10, letterSpacing: 0.6, color: color.inkQuiet },
  fullText: { marginTop: 10, fontFamily: "Fraunces", fontSize: 15.5, lineHeight: 24, color: color.inkMid },
  focusScreen: { flex: 1, backgroundColor: color.focusDark },
  focusOverlay: { position: "absolute", top: 0, right: 0, bottom: 0, left: 0, zIndex: 20 },
  focusTop: { flexDirection: "row", alignItems: "center", paddingHorizontal: 24, gap: 12 },
  focusLabel: { fontFamily: "JetBrainsMono", fontSize: 10, letterSpacing: 1.4, color: "rgba(245,239,226,0.5)", textTransform: "uppercase" },
  focusTitle: { marginTop: 4, fontFamily: "Fraunces", fontSize: 14, color: "rgba(245,239,226,0.85)" },
  closeButton: { width: 40, height: 40, borderRadius: 20, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(245,239,226,0.1)" },
  closeText: { fontFamily: "Inter", color: color.paper, fontSize: 18, fontWeight: "700" },
  focusProgress: { fontFamily: "JetBrainsMono", fontSize: 10, letterSpacing: 0.6, color: "rgba(245,239,226,0.5)" },
  todayGrid: { flexDirection: "row" },
  statMetric: { flex: 1, alignItems: "center", gap: 6 },
  statMetricValue: { fontFamily: "Fraunces", fontSize: 26, color: color.ink, fontWeight: "500" },
  statMetricLabel: { fontFamily: "JetBrainsMono", fontSize: 10, letterSpacing: 1.4, color: color.inkQuiet, textTransform: "uppercase" },
  chart: { height: 130, flexDirection: "row", alignItems: "flex-end", gap: 10 },
  barColumn: { flex: 1, alignItems: "center", justifyContent: "flex-end", gap: 8 },
  bar: { width: "100%", borderRadius: 1, opacity: 0.78 },
  barLabel: { fontFamily: "JetBrainsMono", fontSize: 10, letterSpacing: 0.6, color: color.inkQuiet, textTransform: "uppercase" },
  statCards: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  smallStat: { width: "48.8%", padding: 14, paddingBottom: 16, borderRadius: 4, borderWidth: 0.5, borderColor: color.rule, backgroundColor: color.paperStrong },
  smallStatValue: { marginTop: 10, fontFamily: "Fraunces", fontSize: 30, fontWeight: "500", color: color.ink },
  smallStatUnit: { marginTop: 4, fontFamily: "JetBrainsMono", fontSize: 10, letterSpacing: 1.4, color: color.inkQuiet, textTransform: "uppercase" },
  noteCard: { marginTop: 16, padding: 18, borderLeftWidth: 3, borderLeftColor: color.terracotta, borderRadius: 4, borderWidth: 0.5, borderColor: color.rule, backgroundColor: color.paperStrong },
  noteText: { marginTop: 10, fontFamily: "Fraunces", fontSize: 16, lineHeight: 23, color: color.ink },
  settingsGroup: { borderRadius: 4, borderWidth: 0.5, borderColor: color.rule, backgroundColor: color.paperStrong, overflow: "hidden" },
  settingsRow: { minHeight: 52, paddingHorizontal: 16, paddingVertical: 14, flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 14 },
  bottomRule: { borderBottomWidth: 0.5, borderBottomColor: color.rule },
  settingsLabel: { fontFamily: "Inter", fontSize: 15, color: color.ink },
  settingsHint: { marginTop: 2, fontFamily: "Inter", fontSize: 12, color: color.inkQuiet },
  settingsValue: { fontFamily: "JetBrainsMono", fontSize: 13, color: color.inkQuiet },
  segmented: { flexDirection: "row", padding: 4, gap: 4 },
  segment: { flex: 1, paddingVertical: 10, borderRadius: 3, alignItems: "center" },
  segmentText: { fontFamily: "Inter", fontSize: 13, color: color.inkMid, fontWeight: "600" },
  tabBar: { position: "absolute", left: 16, right: 16, bottom: 0, paddingTop: 8, paddingHorizontal: 8, flexDirection: "row", backgroundColor: "rgba(250,246,236,0.88)", borderRadius: 22, borderWidth: 0.5, borderColor: "rgba(201,100,66,0.22)", overflow: "hidden" },
  tabButton: { flex: 1, minHeight: 44, alignItems: "center", justifyContent: "center", gap: 3, paddingVertical: 6 },
  tabLabel: { fontFamily: "JetBrainsMono", fontSize: 10, letterSpacing: 0.6, color: color.inkQuiet },
  tabIconSlot: { width: 24, height: 24, alignItems: "center", justifyContent: "center" },
  bookIcon: { width: 22, height: 22, flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 2 },
  bookPage: { width: 7, height: 14, borderWidth: 1.4, borderRadius: 1 },
  circleIcon: { width: 18, height: 18, borderWidth: 1.4, borderRadius: 9, alignItems: "center", justifyContent: "center" },
  squareIcon: { width: 14, height: 14, borderWidth: 1.4, alignItems: "center", justifyContent: "center" },
  iconGlyph: { fontFamily: "Inter", fontSize: 14, lineHeight: 16, fontWeight: "600" },
  statsIcon: { width: 22, height: 22, flexDirection: "row", alignItems: "flex-end", justifyContent: "center", gap: 3 },
  settingsIcon: { width: 18, height: 18, borderWidth: 1.4, borderRadius: 9, alignItems: "center", justifyContent: "center" },
  settingsIconDot: { width: 5, height: 5, borderRadius: 2.5 },
  brandMark: { position: "relative", overflow: "hidden", alignItems: "center", justifyContent: "center", backgroundColor: "#eadcc5", borderWidth: 0.5, borderColor: "rgba(0,0,0,0.08)" },
  grain: { position: "absolute", inset: 0, backgroundColor: "rgba(0,0,0,0.02)" },
  brandLetters: { flexDirection: "row", alignItems: "baseline" },
  brandJ: { fontFamily: "Inter", fontWeight: "500", color: "rgba(43,38,34,0.55)", marginRight: -4 },
  brandR: { fontFamily: "Fraunces", fontWeight: "700", color: color.terracotta },
  brandDot: { position: "absolute", backgroundColor: color.terracotta },
};
