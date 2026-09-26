#!/usr/bin/env python3
"""Build both languages from one HTML source and the verified release record.

site/index.html is the readable Chinese template. locales/en.json translates its
text nodes and labelled attributes; new untranslated Chinese fails the build.
"""
import hashlib
from html import escape
from html.parser import HTMLParser
import json
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / "apps-portal/site"))
from perf_block import load as load_perf, standalone_section
ORIGIN = "https://initials.tianli.cyou"
CJK = re.compile(r"[\u4e00-\u9fff]")


class EnglishPage(HTMLParser):
    def __init__(self, strings):
        super().__init__(convert_charrefs=False)
        self.strings = strings
        self.output = []

    def translate(self, value):
        stripped = value.strip()
        if stripped in self.strings:
            return value.replace(stripped, self.strings[stripped], 1)
        if CJK.search(value):
            raise ValueError(f"Missing English translation: {value!r}")
        return value

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "img" and values.get("data-locale") == "zh":
            # English retains the three real native views, not the Chinese diagram.
            return
        translated = []
        for key, value in attrs:
            if value is not None:
                if key in ("alt", "aria-label", "content", "title", "label"):
                    value = self.translate(value)
                if key in ("src", "href", "poster"):
                    value = value.replace("/media/", "/media/en/")
                    value = value.replace("/assets/picker-zh.png", "/assets/picker-en.png")
                    value = value.replace("/assets/scene-settings-right-zh.png", "/assets/settings-right-en.png")
                    value = value.replace("/assets/scene-settings-left-zh.png", "/assets/settings-left-en.png")
                    value = value.replace("/assets/scene-picker-dark-zh.png", "/assets/picker-dark-en.png")
                if key == "srclang":
                    value = "en"
                if key == "href" and values.get("class") == "language-switch":
                    value = "/"
                if key == "lang" and values.get("class") == "language-switch":
                    value = "zh-CN"
            translated.append((key, value))
        # Native English screenshots have different aspect ratios from scenes.
        src = dict(translated).get("src", "")
        if tag == "img" and src.startswith("/assets/") and src.endswith("-en.png"):
            raw = (ROOT / "site" / src.lstrip("/")).read_bytes()
            sizes = {"width": str(int.from_bytes(raw[16:20], "big")),
                     "height": str(int.from_bytes(raw[20:24], "big"))}
            translated = [(key, sizes.get(key, value)) for key, value in translated]
        self.output.append("<" + tag + "".join(
            f" {key}" if value is None else f' {key}="{escape(value, quote=True)}"'
            for key, value in translated) + ">")

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        self.output.append(f"</{tag}>")

    def handle_data(self, data):
        self.output.append(self.translate(data))

    def handle_entityref(self, name):
        self.output.append(f"&{name};")

    def handle_charref(self, name):
        self.output.append(f"&#{name};")

    def handle_comment(self, data):
        self.output.append(f"<!--{data}-->")

    def handle_decl(self, data):
        self.output.append(f"<!{data}>")


def main():
    release = json.loads((ROOT / "build/release.json").read_text())
    perf = load_perf({"repo": str(ROOT)})
    if not perf or perf["version"].split(" ")[0] != release["version"]:
        raise SystemExit("perf/lightweight.json must measure the current release")
    dmg = ROOT / release["artifact_path"]
    if hashlib.sha256(dmg.read_bytes()).hexdigest() != release["sha256"]:
        raise SystemExit("DMG does not match build/release.json; rerun scripts/release.py")
    out = ROOT / "build/site"
    if out.is_symlink():
        raise SystemExit("Refusing to replace a symlinked build/site")
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(ROOT / "site", out, ignore=shutil.ignore_patterns("locales"))
    (out / "downloads").mkdir()
    shutil.copy2(dmg, out / "downloads" / dmg.name)
    (out / "downloads/SHA256SUMS.txt").write_text(f"{release['sha256']}  {dmg.name}\n")
    source = (ROOT / "site/index.html").read_text()
    source = re.sub(r'(src|href|poster)="(assets|media|downloads)/', r'\1="/\2/', source)
    parser = EnglishPage(json.loads((ROOT / "site/locales/en.json").read_text()))
    parser.feed(source)
    parser.close()
    pages = {"index.html": (source, "zh-CN", f"{ORIGIN}/", "zh_CN"),
             "en/index.html": ("".join(parser.output), "en", f"{ORIGIN}/en/", "en_US")}
    for filename, (page, lang, canonical, og_locale) in pages.items():
        destination = out / filename
        destination.parent.mkdir(parents=True, exist_ok=True)
        values = {"VERSION": release["version"], "SIZE": f"{release['size_bytes'] / 1_000_000:.1f}",
                  "SHA256": release["sha256"], "LANG": lang, "CANONICAL": canonical,
                  "OG_LOCALE": og_locale,
                  "LW_MEMORY": perf["memory"] or ("未测" if lang == "zh-CN" else "Unmeasured"),
                  "LIGHTWEIGHT": standalone_section(ROOT / "perf/lightweight.json", release["version"],
                                                    accent="#1d7a78", lang="zh" if lang == "zh-CN" else "en")}
        for key, value in values.items():
            page = page.replace("{{" + key + "}}", value)
        destination.write_text(page)
    # Future HTML files share release substitution and the completeness gate.
    for destination in out.rglob("*.html"):
        page = destination.read_text()
        for key in ("VERSION", "SIZE", "SHA256"):
            page = page.replace("{{" + key + "}}", values[key])
        if "{{" in page:
            raise SystemExit(f"Unfilled placeholder in {destination.relative_to(out)}")
        destination.write_text(page)
    alternates = ''.join(f'<xhtml:link rel="alternate" hreflang="{lang}" href="{url}"/>'
                         for lang, url in (("zh-CN", f"{ORIGIN}/"), ("en", f"{ORIGIN}/en/"),
                                           ("x-default", f"{ORIGIN}/")))
    (out / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" '
        'xmlns:xhtml="http://www.w3.org/1999/xhtml">\n' + ''.join(
            f'<url><loc>{url}</loc>{alternates}</url>\n' for url in (f"{ORIGIN}/", f"{ORIGIN}/en/"))
        + '</urlset>\n')
    (out / "robots.txt").write_text(f"User-agent: *\nAllow: /\nSitemap: {ORIGIN}/sitemap.xml\n")
    print(f"Built {out}: Chinese + English, v{release['version']}, {dmg.name}")


if __name__ == "__main__":
    main()
