import test from "node:test";
import assert from "node:assert/strict";

import { decodeHtml, extractArticle, htmlToText } from "../src/article-extract.js";

test("extractArticle prefers entry-content text over navigation and footer chrome", () => {
  const html = `
    <html>
      <head><meta property="og:title" content="Readable &amp; Fast"></head>
      <body>
        <nav>Home Pricing Login</nav>
        <div class="entry-content wp-block-post-content">
          <p>First paragraph has enough useful article words to be selected by the extractor.</p>
          <p>Second paragraph keeps the reader input clean, readable, and focused on the actual page body.</p>
        </div>
        <footer>Copyright and links</footer>
      </body>
    </html>`;

  const result = extractArticle(html, "https://example.com/post");

  assert.equal(result.title, "Readable & Fast");
  assert.equal(result.source, "entry-content");
  assert.match(result.text, /First paragraph/);
  assert.doesNotMatch(result.text, /Pricing Login/);
  assert.doesNotMatch(result.text, /Copyright/);
});

test("extractArticle can use JSON-LD articleBody when available", () => {
  const articleBody = "This JSON LD article body has enough words to act as the clean readable source for the speed reader input without scraping page chrome.";
  const html = `
    <script type="application/ld+json">
      {"@type":"Article","headline":"Example","articleBody":"${articleBody}"}
    </script>
    <body><main>Short shell</main></body>`;

  const result = extractArticle(html);

  assert.equal(result.source, "json-ld");
  assert.equal(result.text, articleBody);
});

test("htmlToText decodes entities and inserts paragraph breaks", () => {
  assert.equal(htmlToText("<p>Fast&nbsp;readers</p><p>focus &amp; move.</p>"), "Fast readers\n\nfocus & move.");
});

test("htmlToText removes common sharing and related-post chrome", () => {
  const html = `
    <div>
      <p>Actual article paragraph remains available for reading.</p>
      <div class="sharedaddy sd-sharing-enabled"><h3>Share</h3><span>Facebook</span></div>
      <nav class="jp-relatedposts-i2"><h3>Related</h3><a>Old article</a></nav>
    </div>`;

  const text = htmlToText(html);

  assert.match(text, /Actual article paragraph/);
  assert.doesNotMatch(text, /Share/);
  assert.doesNotMatch(text, /Related/);
});

test("decodeHtml handles numeric entities", () => {
  assert.equal(decodeHtml("A &#8217; B &#x2014; C"), "A ' B - C");
});
