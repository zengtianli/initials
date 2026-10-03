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


def performance_reuse(raw, release):
    """Allow explicitly reviewed historical display, never relabel a measurement."""
    if raw["version"].split(" ")[0] == release["version"]:
        return None
    key = f"{release['version']} ({release.get('build', '')})"
    reuse = (raw.get("reused_for") or {}).get(key) or {}
    artifact = raw.get("measured_artifact") or {}
    sources = sorted(ROOT.glob("Sources/**/*.swift")) + sorted(ROOT.glob("Resources/*"))
    actual = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sources if p.is_file()}
    # raw["version"] is "1.1.2 (4)" since measurements carry the build; measured_artifact splits it.
    short, _, build = raw["version"].partition(" ")
    valid = (reuse.get("display") == "historical_only"
             and reuse.get("measured_version") == raw["version"]
             and short == artifact.get("version") and build.strip("()") in ("", str(artifact.get("build")))
             and reuse.get("measured_executable_sha256") == artifact.get("executable_sha256")
             and re.fullmatch(r"[0-9a-f]{64}", str(artifact.get("executable_sha256", "")))
             and reuse.get("reviewed_at") and reuse.get("reason") and reuse.get("reason_en")
             and reuse.get("reviewed_sources_sha256") == actual)
    if not valid:
        raise SystemExit("Historical performance needs an explicit, source-matched review for this release/build")
    return reuse


def lightweight_section(raw, release, reuse, lang):
    # The shared renderer still receives the measurement's true version. The
    # repository gate above separately validates the offered release and review.
    measured = raw["version"].split(" ")[0]
    block = standalone_section(ROOT / "perf/lightweight.json", measured, accent="#1d7a78", lang=lang)
    if not reuse:
        return block
    zh = lang == "zh"
    note = (f"以下为 v{measured} 的历史实测，供 v{release['version']} 参考；不是本版本新测。"
            if zh else f"Historical measurements from v{measured}, shown for reference with v{release['version']}; this release has not been re-measured. ")
    note += reuse["reason" if zh else "reason_en"]
    block = block.replace("数字来自所列设备实测，版本更新后重新测量。" if zh else
                          "Measured on the listed device; re-measured for each version.", escape(note))
    heading = "资源占用与响应速度。" if zh else "Resource use and response time."
    return block.replace(heading, f"{heading} (v{escape(measured)})")


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
    if not perf:
        raise SystemExit("perf/lightweight.json is required")
    raw_perf = json.loads((ROOT / "perf/lightweight.json").read_text())
    reuse = performance_reuse(raw_perf, release)
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
    updates = {"bundle_id": "cyou.tianli.initials", "version": release["version"],
               "build": str(release["build"]), "channel": "public", "sha256": release["sha256"],
               "size_bytes": release["size_bytes"], "installation": "bundle",
               "download_url": f"{ORIGIN}/downloads/{dmg.name}",
               "release_url": f"https://github.com/zengtianli/initials/releases/tag/v{release['version']}"}
    (out / "updates.json").write_text(json.dumps(updates, ensure_ascii=False, indent=2) + "\n")
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
                  "LIGHTWEIGHT": lightweight_section(raw_perf, release, reuse, "zh" if lang == "zh-CN" else "en")}
        if reuse:
            label = f"（v{raw_perf['version']} 实测）" if lang == "zh-CN" else f" (measured on v{raw_perf['version']})"
            page = page.replace("{{LW_MEMORY}} MB", "{{LW_MEMORY}} MB" + label)
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
    # Portal/Chapter read this product's published numbers from facts.json, deployed with the page.
    import product_facts
    facts = product_facts.from_repo(ROOT, product_id="initials-mac", icon="assets/icon.png")
    if facts["version"] != release["version"]:
        raise SystemExit(f"facts.json version {facts['version']} (project.yaml sop.release) != release {release['version']}")
    if reuse:
        # Keep current artifact sizes separate from the explicitly labelled old runtime measurements.
        bundle = ROOT / "build/Initials.app"
        facts.update(download_bytes=release["size_bytes"],
                     installed_bytes=sum(p.stat().st_size for p in bundle.rglob("*") if p.is_file()),
                     measured_version=raw_perf["version"], historical_reference=True,
                     download_source="release.json", installed_source="notarized bundle file lengths")
        facts["card_line"] = (f"当前下载 {release['size_bytes'] / 1_000_000:.1f} MB · 历史实测 "
                              f"{escape(raw_perf['version'])}（{escape(raw_perf['measured_at'])}）：" + facts["card_line"])
        facts["card_text"] = product_facts.card_text(facts["card_line"])
        print(f"warning: facts.json v{release['version']} carries historical v{raw_perf['version']} measurements "
              f"(reviewed reuse); measured_at={facts['measured_at']}", file=sys.stderr)
    product_facts.write(out, facts)
    print(f"Built {out}: Chinese + English, v{release['version']}, {dmg.name}")


if __name__ == "__main__":
    main()
