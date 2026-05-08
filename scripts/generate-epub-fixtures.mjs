// Generate small public-domain EPUB fixtures using fflate.
// Run via: bun run fixtures:epub  (or: node scripts/generate-epub-fixtures.mjs)
//
// Sources are short excerpts from clearly public-domain works:
//   - Pride and Prejudice by Jane Austen (1813)
//   - 道德經 (Tao Te Ching, Laozi, 6th century BCE) — zh-Hant
//
// Lives outside test/ on purpose: `node --test` discovers any *.mjs under
// test/ and used to re-run this generator on every test invocation, which
// rewrote the binary fixtures and dirtied the working tree.
import { zipSync, strToU8 } from "fflate";
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = join(dirname(fileURLToPath(import.meta.url)), "..", "test", "fixtures", "epub");
mkdirSync(here, { recursive: true });

function makeEpub(spec) {
  const files = {
    // mimetype must be the first entry and stored uncompressed in real readers,
    // but for parsing tests fflate's unzipSync handles it either way.
    mimetype: [strToU8("application/epub+zip"), { level: 0 }],
    "META-INF/container.xml": strToU8(
      `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
`,
    ),
    "OEBPS/content.opf": strToU8(spec.opf),
    "OEBPS/nav.xhtml": strToU8(spec.nav),
  };
  for (const [name, body] of Object.entries(spec.chapters)) {
    files[`OEBPS/${name}`] = strToU8(body);
  }
  return zipSync(files);
}

function chapterXhtml(title, body) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>${title}</title></head>
<body>
<h1>${title}</h1>
<p>${body}</p>
</body>
</html>
`;
}

// Fixture 1: Pride and Prejudice excerpt
{
  const opf = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:fixture:pride-and-prejudice</dc:identifier>
    <dc:title>Pride and Prejudice</dc:title>
    <dc:creator>Jane Austen</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
`;
  const nav = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head>
<body>
<nav epub:type="toc">
<ol>
<li><a href="chapter1.xhtml">Chapter 1</a></li>
<li><a href="chapter2.xhtml">Chapter 2</a></li>
</ol>
</nav>
</body>
</html>
`;
  const chapters = {
    "chapter1.xhtml": chapterXhtml(
      "Chapter 1",
      "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
    ),
    "chapter2.xhtml": chapterXhtml(
      "Chapter 2",
      "Mr. Bennet was among the earliest of those who waited on Mr. Bingley.",
    ),
  };
  const buf = makeEpub({ opf, nav, chapters });
  writeFileSync(join(here, "pride-and-prejudice.epub"), buf);
}

// Fixture 2: 道德經 (zh-Hant) using NCX (epub2-style) instead of nav.xhtml
{
  const opf = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:fixture:tao-te-ching</dc:identifier>
    <dc:title>道德經</dc:title>
    <dc:creator>老子</dc:creator>
    <dc:language>zh-Hant</dc:language>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch3" href="chapter3.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
    <itemref idref="ch3"/>
  </spine>
</package>
`;
  const ncx = `<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="urn:fixture:tao-te-ching"/></head>
  <docTitle><text>道德經</text></docTitle>
  <navMap>
    <navPoint id="np1" playOrder="1">
      <navLabel><text>第一章</text></navLabel>
      <content src="chapter1.xhtml"/>
    </navPoint>
    <navPoint id="np2" playOrder="2">
      <navLabel><text>第二章</text></navLabel>
      <content src="chapter2.xhtml"/>
    </navPoint>
    <navPoint id="np3" playOrder="3">
      <navLabel><text>第三章</text></navLabel>
      <content src="chapter3.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
`;
  const chapters = {
    "chapter1.xhtml": chapterXhtml("第一章", "道可道，非常道。名可名，非常名。"),
    "chapter2.xhtml": chapterXhtml(
      "第二章",
      "天下皆知美之為美，斯惡已；皆知善之為善，斯不善已。",
    ),
    "chapter3.xhtml": chapterXhtml(
      "第三章",
      "不尚賢，使民不爭；不貴難得之貨，使民不為盜。",
    ),
    "toc.ncx": ncx,
  };
  // We want toc.ncx to be a regular file too, so add it as such:
  const filesSpec = {
    opf,
    nav: ncx, // unused; placeholder
    chapters,
  };
  // The makeEpub helper writes nav as OEBPS/nav.xhtml; here we don't want a nav.xhtml,
  // so use a custom build instead:
  const files = {
    mimetype: [strToU8("application/epub+zip"), { level: 0 }],
    "META-INF/container.xml": strToU8(
      `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
`,
    ),
    "OEBPS/content.opf": strToU8(opf),
  };
  for (const [name, body] of Object.entries(filesSpec.chapters)) {
    files[`OEBPS/${name}`] = strToU8(body);
  }
  const buf = zipSync(files);
  writeFileSync(join(here, "tao-te-ching.epub"), buf);
}

console.log("Wrote EPUB fixtures to", here);
