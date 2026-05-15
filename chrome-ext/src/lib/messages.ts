export type Msg =
  | { type: 'ping' }
  | { type: 'toggle-reader'; force?: boolean }
  | { type: 'toggle-fastread'; force?: boolean }
  | { type: 'get-article-meta' };

export type MsgResponse =
  | {
      ok: true;
      readerable: boolean;
      title?: string;
      byline?: string;
      source?: string;
      readingTimeMin?: number;
    }
  | { ok: false; error: string };
