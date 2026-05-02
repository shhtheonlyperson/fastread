import { Image } from "expo-image";
import { StatusBar } from "expo-status-bar";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Keyboard,
  Modal,
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
import {
  DEFAULT_TEXT,
  clamp,
  durationForToken,
  estimateMinutes,
  getProgress,
  splitForFocus,
  tokenize,
} from "../src/reader-core.js";

const palette = {
  bg: "#edf2f7",
  surface: "#ffffff",
  ink: "#101827",
  muted: "#607083",
  border: "#d7e0eb",
  stage: "#101827",
  accent: "#e11d48",
  accentSoft: "#fff1f4",
  teal: "#0f766e",
};

const WPM_STEP = 25;

export default function FastReadScreen() {
  const [text, setText] = useState(DEFAULT_TEXT);
  const [url, setUrl] = useState("https://stratechery.com/2026/long-term-peripheral-myopic-visions/");
  const [status, setStatus] = useState("");
  const [statusTone, setStatusTone] = useState("muted");
  const [isLoadingUrl, setIsLoadingUrl] = useState(false);
  const [wpm, setWpm] = useState(650);
  const [punctuationPause, setPunctuationPause] = useState(true);
  const [index, setIndex] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [isFocusMode, setIsFocusMode] = useState(false);

  const tokens = useMemo(() => tokenize(text), [text]);
  const currentToken = tokens[index] || "";
  const progress = tokens.length ? getProgress(index, tokens.length) : 0;
  const minutes = estimateMinutes(tokens.length, wpm);
  const eta = minutes < 1 ? `${Math.ceil(minutes * 60)}s` : `${minutes.toFixed(1)}m`;

  useEffect(() => {
    setIndex((current) => clamp(current, 0, Math.max(tokens.length - 1, 0)));
  }, [tokens.length]);

  useEffect(() => {
    if (!isPlaying || !tokens.length) {
      return undefined;
    }

    const timeout = setTimeout(() => {
      setIndex((current) => {
        if (current >= tokens.length - 1) {
          setIsPlaying(false);
          return current;
        }

        return current + 1;
      });
    }, durationForToken(currentToken, wpm, punctuationPause));

    return () => clearTimeout(timeout);
  }, [currentToken, index, isPlaying, punctuationPause, tokens.length, wpm]);

  const resetReader = useCallback(() => {
    setIsPlaying(false);
    setIndex(0);
  }, []);

  const move = useCallback(
    (delta) => {
      setIsPlaying(false);
      setIndex((current) => clamp(current + delta, 0, Math.max(tokens.length - 1, 0)));
    },
    [tokens.length],
  );

  const updateText = useCallback((value) => {
    setIsPlaying(false);
    setText(value);
    setIndex(0);
  }, []);

  const loadUrl = useCallback(async () => {
    Keyboard.dismiss();
    setIsPlaying(false);

    const trimmed = url.trim();
    if (!trimmed) {
      setStatusTone("error");
      setStatus("Enter a URL first.");
      return;
    }

    try {
      const parsed = new URL(trimmed);
      if (!["http:", "https:"].includes(parsed.protocol)) {
        throw new Error("Only http and https URLs are supported.");
      }
    } catch (error) {
      setStatusTone("error");
      setStatus(error.message || "Enter a valid URL.");
      return;
    }

    setIsLoadingUrl(true);
    setStatusTone("muted");
    setStatus("Loading...");

    try {
      const response = await fetch(trimmed, {
        headers: {
          accept: "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.2",
        },
      });

      if (!response.ok) {
        throw new Error(`Fetch failed with HTTP ${response.status}.`);
      }

      const html = await response.text();
      const article = extractArticle(html, response.url || trimmed);
      if (!article.text || article.wordCount < 20) {
        throw new Error("Could not find enough readable text on that page.");
      }

      setText(article.text);
      setIndex(0);
      setStatusTone("ok");
      setStatus(`${article.title ? `${article.title} | ` : ""}${article.wordCount} words loaded.`);
    } catch (error) {
      setStatusTone("error");
      setStatus(error.message || "Could not load that URL.");
    } finally {
      setIsLoadingUrl(false);
    }
  }, [url]);

  return (
    <>
      <StatusBar style="dark" />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        keyboardShouldPersistTaps="handled"
        style={{ flex: 1, backgroundColor: palette.bg }}
        contentContainerStyle={{ padding: 16, gap: 16, paddingBottom: 32 }}
      >
        <View style={{ gap: 4 }}>
          <Text selectable style={{ color: palette.muted, fontSize: 16 }}>
            {tokens.length} words · {eta} at {wpm} WPM · {progress}%
          </Text>
        </View>

        <View style={styles.card}>
          <SectionTitle title="Source" />
          <Text selectable style={styles.label}>
            URL
          </Text>
          <View style={{ flexDirection: "row", gap: 10 }}>
            <TextInput
              value={url}
              onChangeText={setUrl}
              autoCapitalize="none"
              autoCorrect={false}
              keyboardType="url"
              returnKeyType="go"
              onSubmitEditing={loadUrl}
              placeholder="https://example.com/article"
              placeholderTextColor="#94a3b8"
              style={[styles.input, { flex: 1 }]}
            />
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Load URL"
              onPress={loadUrl}
              disabled={isLoadingUrl}
              style={({ pressed }) => [
                styles.smallButton,
                isLoadingUrl && { opacity: 0.55 },
                pressed && !isLoadingUrl && { transform: [{ translateY: 1 }] },
              ]}
            >
              {isLoadingUrl ? <ActivityIndicator color={palette.ink} /> : <Text style={styles.smallButtonText}>Load</Text>}
            </Pressable>
          </View>
          {!!status && (
            <Text
              selectable
              numberOfLines={2}
              style={{
                color: statusTone === "error" ? palette.accent : statusTone === "ok" ? palette.teal : palette.muted,
                fontSize: 13,
                lineHeight: 18,
              }}
            >
              {status}
            </Text>
          )}
          <TextInput
            value={text}
            onChangeText={updateText}
            multiline
            textAlignVertical="top"
            placeholder="Paste text here"
            placeholderTextColor="#94a3b8"
            style={[styles.input, { minHeight: 190, lineHeight: 22 }]}
          />
        </View>

        <View style={styles.card}>
          <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
            <SectionTitle title="Speed" />
            <Text selectable style={{ color: palette.ink, fontSize: 16, fontWeight: "800", fontVariant: ["tabular-nums"] }}>
              {wpm} WPM
            </Text>
          </View>
          <View style={{ flexDirection: "row", gap: 10 }}>
            <StepButton label="-25" onPress={() => setWpm((value) => clamp(value - WPM_STEP, 100, 1200))} />
            <StepButton label="+25" onPress={() => setWpm((value) => clamp(value + WPM_STEP, 100, 1200))} />
          </View>
          <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 14 }}>
            <Text selectable style={{ color: palette.muted, fontSize: 15 }}>
              Pause on punctuation
            </Text>
            <Switch value={punctuationPause} onValueChange={setPunctuationPause} trackColor={{ true: palette.teal }} />
          </View>
        </View>

        <View style={styles.card}>
          <SectionTitle title="Reader" />
          <ReaderStage token={currentToken} />
          <Transport
            isPlaying={isPlaying}
            canPrevious={index > 0}
            canNext={index < tokens.length - 1}
            onPrevious={() => move(-1)}
            onPlayPause={() => tokens.length && setIsPlaying((value) => !value)}
            onNext={() => move(1)}
            onReset={resetReader}
            onFocus={() => setIsFocusMode(true)}
          />
          <ProgressBar index={index} total={tokens.length} />
        </View>

        <View style={styles.card}>
          <SectionTitle title="Focus Text" />
          <FocusPreview tokens={tokens} />
        </View>
      </ScrollView>

      <FocusModal
        visible={isFocusMode}
        token={currentToken}
        index={index}
        total={tokens.length}
        isPlaying={isPlaying}
        canPrevious={index > 0}
        canNext={index < tokens.length - 1}
        onClose={() => setIsFocusMode(false)}
        onPrevious={() => move(-1)}
        onPlayPause={() => tokens.length && setIsPlaying((value) => !value)}
        onNext={() => move(1)}
        onReset={resetReader}
      />
    </>
  );
}

function SectionTitle({ title }) {
  return (
    <Text selectable style={{ color: palette.muted, fontSize: 12, fontWeight: "800", textTransform: "uppercase" }}>
      {title}
    </Text>
  );
}

function ReaderStage({ token, fullscreen = false }) {
  const { width } = useWindowDimensions();
  const parts = splitForFocus(token);
  const fontSize = Math.round(Math.min(fullscreen ? width * 0.19 : width * 0.145, fullscreen ? 142 : 76));

  return (
    <View
      style={{
        minHeight: fullscreen ? 280 : 190,
        flex: fullscreen ? 1 : undefined,
        justifyContent: "center",
        borderRadius: fullscreen ? 0 : 8,
        borderCurve: "continuous",
        backgroundColor: palette.stage,
        overflow: "hidden",
        paddingHorizontal: fullscreen ? 20 : 16,
      }}
    >
      <View
        pointerEvents="none"
        style={{
          position: "absolute",
          top: fullscreen ? 36 : 0,
          bottom: fullscreen ? 36 : 0,
          left: "50%",
          width: 1,
          backgroundColor: "rgba(225, 29, 72, 0.35)",
        }}
      />
      <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "center" }}>
        <Text numberOfLines={1} style={[styles.stageText, { flex: 1, textAlign: "right", fontSize }]}>
          {parts.before}
        </Text>
        <Text numberOfLines={1} style={[styles.stageText, { color: "#ff2f62", fontSize }]}>
          {parts.focus}
        </Text>
        <Text numberOfLines={1} style={[styles.stageText, { flex: 1, textAlign: "left", fontSize }]}>
          {parts.after}
        </Text>
      </View>
    </View>
  );
}

function Transport({ isPlaying, canPrevious, canNext, onPrevious, onPlayPause, onNext, onReset, onFocus, onClose }) {
  return (
    <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 10 }}>
      <IconButton label="Previous word" symbol="backward.end.fill" onPress={onPrevious} disabled={!canPrevious} />
      <IconButton primary label={isPlaying ? "Pause" : "Play"} symbol={isPlaying ? "pause.fill" : "play.fill"} onPress={onPlayPause} />
      <IconButton label="Next word" symbol="forward.end.fill" onPress={onNext} disabled={!canNext} />
      <IconButton label="Reset" symbol="arrow.counterclockwise" onPress={onReset} />
      {onFocus ? <IconButton label="Focus" symbol="arrow.up.left.and.arrow.down.right" onPress={onFocus} /> : null}
      {onClose ? <IconButton label="Close focus" symbol="xmark" onPress={onClose} /> : null}
    </View>
  );
}

function IconButton({ label, symbol, onPress, primary = false, disabled = false }) {
  const bg = primary ? palette.accent : "#eef2f7";
  const color = primary ? "#ffffff" : palette.ink;

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        {
          width: primary ? 58 : 46,
          height: primary ? 58 : 46,
          alignItems: "center",
          justifyContent: "center",
          borderRadius: 8,
          borderCurve: "continuous",
          backgroundColor: bg,
          boxShadow: primary ? "0 14px 28px rgba(225, 29, 72, 0.24)" : "0 8px 18px rgba(15, 23, 42, 0.08)",
        },
        disabled && { opacity: 0.4 },
        pressed && !disabled && { transform: [{ translateY: 1 }] },
      ]}
    >
      <Image source={`sf:${symbol}`} style={{ width: primary ? 24 : 19, height: primary ? 24 : 19, tintColor: color }} />
    </Pressable>
  );
}

function StepButton({ label, onPress }) {
  return (
    <Pressable accessibilityRole="button" onPress={onPress} style={({ pressed }) => [styles.stepButton, pressed && { transform: [{ translateY: 1 }] }]}>
      <Text style={styles.stepText}>{label}</Text>
    </Pressable>
  );
}

function ProgressBar({ index, total }) {
  const progress = total ? (index + 1) / total : 0;

  return (
    <View style={{ gap: 8 }}>
      <View style={{ height: 6, borderRadius: 999, backgroundColor: "#e2e8f0", overflow: "hidden" }}>
        <View style={{ width: `${progress * 100}%`, height: 6, borderRadius: 999, backgroundColor: palette.accent }} />
      </View>
      <Text selectable style={{ alignSelf: "flex-end", color: palette.muted, fontSize: 13, fontVariant: ["tabular-nums"] }}>
        {total ? index + 1 : 0} / {total}
      </Text>
    </View>
  );
}

function FocusPreview({ tokens }) {
  return (
    <Text selectable style={{ color: palette.ink, fontSize: 16, lineHeight: 28 }}>
      {tokens.map((token, tokenIndex) => {
        const parts = splitForFocus(token);
        return (
          <Text key={`${token}-${tokenIndex}`}>
            {parts.before}
            <Text style={{ color: palette.accent, fontWeight: "900" }}>{parts.focus}</Text>
            {parts.after}{" "}
          </Text>
        );
      })}
    </Text>
  );
}

function FocusModal({ visible, token, index, total, isPlaying, canPrevious, canNext, onClose, onPrevious, onPlayPause, onNext, onReset }) {
  const insets = useSafeAreaInsets();

  return (
    <Modal visible={visible} animationType="fade" presentationStyle="fullScreen" onRequestClose={onClose}>
      <StatusBar hidden />
      <View
        style={{
          flex: 1,
          backgroundColor: palette.stage,
          paddingTop: Math.max(insets.top, 18),
          paddingBottom: Math.max(insets.bottom, 18),
          paddingHorizontal: 18,
          gap: 18,
        }}
      >
        <ReaderStage token={token} fullscreen />
        <Transport
          isPlaying={isPlaying}
          canPrevious={canPrevious}
          canNext={canNext}
          onPrevious={onPrevious}
          onPlayPause={onPlayPause}
          onNext={onNext}
          onReset={onReset}
          onClose={onClose}
        />
        <ProgressBar index={index} total={total} />
      </View>
    </Modal>
  );
}

const styles = {
  card: {
    gap: 14,
    padding: 16,
    borderWidth: 1,
    borderColor: palette.border,
    borderRadius: 8,
    borderCurve: "continuous",
    backgroundColor: palette.surface,
    boxShadow: "0 14px 32px rgba(15, 23, 42, 0.08)",
  },
  label: {
    color: palette.muted,
    fontSize: 12,
    fontWeight: "800",
    textTransform: "uppercase",
  },
  input: {
    minHeight: 44,
    borderWidth: 1,
    borderColor: palette.border,
    borderRadius: 8,
    borderCurve: "continuous",
    paddingHorizontal: 12,
    paddingVertical: 10,
    color: palette.ink,
    backgroundColor: "#fbfcfe",
    fontSize: 16,
  },
  smallButton: {
    minWidth: 64,
    height: 44,
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 8,
    borderCurve: "continuous",
    backgroundColor: "#eef2f7",
  },
  smallButtonText: {
    color: palette.ink,
    fontSize: 15,
    fontWeight: "800",
  },
  stageText: {
    color: "#f8fafc",
    fontWeight: "900",
    letterSpacing: 0,
  },
  stepButton: {
    flex: 1,
    minHeight: 44,
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 8,
    borderCurve: "continuous",
    backgroundColor: palette.accentSoft,
  },
  stepText: {
    color: palette.accent,
    fontSize: 16,
    fontWeight: "900",
    fontVariant: ["tabular-nums"],
  },
};
