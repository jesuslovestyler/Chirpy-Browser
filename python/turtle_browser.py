#!/usr/bin/env python3
"""
Turtle Browser — prototype 0.1
================================
A small browser with OUR OWN engine, written from scratch on the
Python standard library alone. No Chromium, no WebKit, no borrowed
rendering engine. The engine does the three things every browser
engine has done since 1993:

    1. FETCH   — get the page over the network        (fetch_url)
    2. PARSE   — turn HTML into a document tree       (TreeBuilder)
    3. RENDER  — lay the tree out as readable page    (render_document)

What it does not do yet (the honest roadmap):
    * JavaScript execution      — the mountain; every engine team
                                  spends most of its life here.
    * Full CSS layout           — v0.2: a small CSS subset.
    * Images                    — shown as labelled placeholders.
    * Forms, cookies, tabs      — later.

Public domain (Unlicense) — a gift, free for anyone.
Run the window:   python3 turtle_browser.py
Test the engine:  python3 turtle_browser.py --dump https://example.com
"""

import sys
import urllib.request
import urllib.error
from html.parser import HTMLParser
from urllib.parse import urljoin, urlparse

USER_AGENT = "TurtleBrowser/0.1 (public domain; our own engine)"

HOME_HTML = """<!DOCTYPE html>
<html>
<head><title>Turtle Home</title></head>
<body>
<h1>Turtle Browser</h1>
<p>A browser for Catholics, by Catholics. Private, simple, and ours.</p>
<h2>Your word is a lamp to my feet</h2>
<p>"Your word is a lamp to my feet, and a light for my path."
&mdash; Psalm 119:105 (World English Bible)</p>
<h2>Doors</h2>
<ul>
<li><a href="https://jesuslovestyler.github.io/Catholic-Bible/">Catholic Bible</a></li>
<li><a href="https://jesuslovestyler.github.io/Catholic-Study-Bible/">Catholic Study Bible</a></li>
<li><a href="https://jesuslovestyler.github.io/Library-of-Faith/">Library of Faith</a></li>
<li><a href="https://jesuslovestyler.github.io/Vigil/">Vigil</a></li>
<li><a href="https://jesuslovestyler.com/">Jesus Loves Tyler &mdash; the hub</a></li>
</ul>
<h2>Our promises</h2>
<p>No tracking. No ads. No selling data. A family filter that is on
on purpose, not buried in a settings page.</p>
</body>
</html>"""


# ------------------------------------------------------------------
# 1. FETCH
# ------------------------------------------------------------------
def fetch_url(url):
    """Return (final_url, html_text). Raises on network failure."""
    if url == "turtle://home":
        return url, HOME_HTML
    req = urllib.request.Request(url, headers={
        "User-Agent": USER_AGENT,
        "Accept-Encoding": "identity",
        "Accept": "text/html,application/xhtml+xml",
    })
    with urllib.request.urlopen(req, timeout=20) as resp:
        raw = resp.read()
        charset = resp.headers.get_content_charset() or "utf-8"
        final = resp.geturl()
    try:
        return final, raw.decode(charset, errors="replace")
    except (LookupError, UnicodeDecodeError):
        return final, raw.decode("utf-8", errors="replace")


# ------------------------------------------------------------------
# 2. PARSE — HTML into a tiny document tree
# ------------------------------------------------------------------
VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input",
             "link", "meta", "param", "source", "track", "wbr"}
SKIP_TAGS = {"script", "style", "noscript", "template", "svg", "iframe"}


class Node:
    __slots__ = ("tag", "attrs", "children", "text")

    def __init__(self, tag, attrs=None, text=""):
        self.tag = tag
        self.attrs = attrs or {}
        self.children = []
        self.text = text


class TreeBuilder(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("document")
        self.stack = [self.root]
        self.skip_depth = 0

    def handle_starttag(self, tag, attrs):
        if tag in SKIP_TAGS:
            self.skip_depth += 1
            return
        if self.skip_depth:
            return
        node = Node(tag, dict(attrs))
        self.stack[-1].children.append(node)
        if tag not in VOID_TAGS:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        if self.skip_depth or tag in SKIP_TAGS:
            return
        self.stack[-1].children.append(Node(tag, dict(attrs)))

    def handle_endtag(self, tag):
        if tag in SKIP_TAGS:
            if self.skip_depth:
                self.skip_depth -= 1
            return
        if self.skip_depth:
            return
        # Pop back to the matching open tag; forgive bad nesting.
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                break

    def handle_data(self, data):
        if self.skip_depth:
            return
        if data:
            self.stack[-1].children.append(Node("#text", text=data))


def parse_html(html):
    builder = TreeBuilder()
    builder.feed(html)
    builder.close()
    return builder.root


def find_title(node):
    if node.tag == "title":
        return "".join(c.text for c in node.children if c.tag == "#text").strip()
    for child in node.children:
        found = find_title(child)
        if found:
            return found
    return ""


# ------------------------------------------------------------------
# 3. RENDER — the tree becomes blocks of readable page
# ------------------------------------------------------------------
BLOCK_TAGS = {"p", "div", "section", "article", "main", "header",
              "footer", "li", "blockquote", "pre", "tr", "figure",
              "figcaption", "h1", "h2", "h3", "h4", "h5", "h6"}
HEADING_TAGS = {"h1", "h2", "h3", "h4", "h5", "h6"}


def style_for(tag):
    if tag in HEADING_TAGS:
        return tag
    if tag == "blockquote":
        return "quote"
    if tag == "li":
        return "li"
    return "p"


class Renderer:
    def __init__(self, base_url):
        self.base_url = base_url
        self.blocks = []   # (style, text)
        self.links = []    # (link_text, absolute_url)

    def render(self, root):
        self._block_walk(root, "p")
        return self.blocks, self.links

    def _has_block(self, node):
        return any(c.tag in BLOCK_TAGS or self._has_block(c)
                   for c in node.children if c.tag != "#text")

    def _block_walk(self, node, style):
        buffer = []

        def flush():
            text = " ".join("".join(buffer).split())
            if text:
                self.blocks.append((style, text))
            buffer.clear()

        for child in node.children:
            if child.tag == "head" or child.tag == "title":
                continue
            if child.tag in BLOCK_TAGS:
                flush()
                self._block_walk(child, style_for(child.tag))
            elif child.tag in ("html", "body", "document") or self._has_block(child):
                flush()
                self._block_walk(child, style)
            else:
                buffer.append(self._inline(child))
        flush()

    def _inline(self, node):
        if node.tag == "#text":
            return node.text
        if node.tag == "br":
            return " "
        if node.tag == "img":
            return f" [Image: {node.attrs.get('alt') or 'image'}] "
        if node.tag == "a":
            text = " ".join("".join(self._inline(c) for c in node.children).split())
            href = node.attrs.get("href", "")
            if href:
                absolute = urljoin(self.base_url, href)
                self.links.append((text or absolute, absolute))
                return f" {text} [{len(self.links)}] "
            return f" {text} "
        return "".join(self._inline(c) for c in node.children)


def render_document(html, base_url):
    tree = parse_html(html)
    title = find_title(tree) or base_url
    renderer = Renderer(base_url)
    blocks, links = renderer.render(tree)
    return title, blocks, links


# ------------------------------------------------------------------
# Command-line test harness — this is how the engine is verified.
# ------------------------------------------------------------------
def normalize_url(raw):
    raw = raw.strip()
    if raw.startswith("turtle://"):
        return raw
    parsed = urlparse(raw)
    if not parsed.scheme:
        raw = "https://" + raw
    return raw


def dump(url):
    url = normalize_url(url)
    final_url, html = fetch_url(url)
    title, blocks, links = render_document(html, final_url)
    print(f"URL:   {final_url}")
    print(f"TITLE: {title}")
    print(f"BLOCKS: {len(blocks)}   LINKS: {len(links)}")
    print("-" * 60)
    for style, text in blocks:
        prefix = {"h1": "# ", "h2": "## ", "h3": "### ",
                  "quote": "> ", "li": "- "}.get(style, "")
        print(f"{prefix}{text}")
    print("-" * 60)
    for i, (text, href) in enumerate(links, 1):
        print(f"[{i}] {text} -> {href}")


# ------------------------------------------------------------------
# The window (Tkinter — ships with Python, no Xcode, no installs)
# ------------------------------------------------------------------
def run_gui():
    import tkinter as tk
    from tkinter import font as tkfont

    class TurtleBrowser:
        def __init__(self, root):
            self.root = root
            self.current_url = ""
            self.back_stack = []
            self.forward_stack = []
            self.links = []

            root.title("Turtle Browser — prototype 0.1")

            bar = tk.Frame(root)
            bar.pack(side="top", fill="x")
            tk.Button(bar, text="◀", width=3,
                      command=self.go_back).pack(side="left")
            tk.Button(bar, text="▶", width=3,
                      command=self.go_forward).pack(side="left")
            tk.Button(bar, text="⟳", width=3,
                      command=self.reload).pack(side="left")
            tk.Button(bar, text="⌂", width=3,
                      command=lambda: self.navigate("turtle://home")
                      ).pack(side="left")
            self.address = tk.Entry(bar)
            self.address.pack(side="left", fill="x", expand=True)
            self.address.bind("<Return>", lambda e: self.go())
            tk.Button(bar, text="Go", width=4,
                      command=self.go).pack(side="left")

            self.view = tk.Text(root, wrap="word", state="disabled",
                                font=tkfont.Font(family="Helvetica", size=12))
            self.view.pack(side="top", fill="both", expand=True)
            self.view.tag_configure(
                "h1", font=tkfont.Font(family="Helvetica", size=22, weight="bold"))
            self.view.tag_configure(
                "h2", font=tkfont.Font(family="Helvetica", size=17, weight="bold"))
            self.view.tag_configure(
                "h3", font=tkfont.Font(family="Helvetica", size=14, weight="bold"))
            self.view.tag_configure(
                "quote", font=tkfont.Font(family="Helvetica", size=12, style="italic"),
                lmargin1=24, lmargin2=24)
            self.view.tag_configure(
                "li", lmargin1=18, lmargin2=30)
            self.view.tag_configure(
                "link", foreground="#0b5394", underline=True)

            self.status = tk.Label(root, anchor="w", relief="sunken")
            self.status.pack(side="bottom", fill="x")

            self.navigate("turtle://home")

        def go(self):
            self.navigate(self.address.get())

        def reload(self):
            if self.current_url:
                self.navigate(self.current_url, push=False)

        def go_back(self):
            if self.back_stack:
                self.forward_stack.append(self.current_url)
                self.navigate(self.back_stack.pop(), push=False)

        def go_forward(self):
            if self.forward_stack:
                self.back_stack.append(self.current_url)
                self.navigate(self.forward_stack.pop(), push=False)

        def navigate(self, url, push=True):
            url = normalize_url(url)
            if push and self.current_url:
                self.back_stack.append(self.current_url)
                self.forward_stack.clear()
            self.status.config(text=f"Loading {url} …")
            self.root.update_idletasks()
            try:
                final_url, html = fetch_url(url)
                title, blocks, links = render_document(html, final_url)
            except Exception as exc:  # show the failure honestly, in-page
                final_url, title = url, "Could not load page"
                blocks = [("h1", "This page could not be loaded"),
                          ("p", f"{url}"),
                          ("p", f"Reason: {exc}")]
                links = []
            self.current_url = final_url
            self.links = links
            self.address.delete(0, "end")
            self.address.insert(0, final_url)
            self.root.title(f"{title} — Turtle Browser (prototype)")
            self._paint(blocks)
            self.status.config(
                text=f"{final_url}   ·   {len(blocks)} blocks · {len(links)} links"
                     "   ·   Turtle Engine 0.1 (no JavaScript yet)")

        def _paint(self, blocks):
            self.view.config(state="normal")
            self.view.delete("1.0", "end")
            for style, text in blocks:
                tag = style if style in ("h1", "h2", "h3", "quote", "li") else ""
                start = self.view.index("end-1c")
                self.view.insert("end", text + "\n\n", tag)
                end = self.view.index("end-1c")
                # Make every [n] marker in this block a clickable link.
                pos = start
                while True:
                    found = self.view.search(r"\[\d+\]", pos, end, regexp=True)
                    if not found:
                        break
                    close = self.view.search("]", found, end)
                    if not close:
                        break
                    marker_end = f"{close} + 1 chars"
                    digits = self.view.get(f"{found} + 1 chars", close)
                    if digits.isdigit() and 1 <= int(digits) <= len(self.links):
                        num = int(digits)
                        tag_name = f"link{num}_{found.replace('.', '_')}"
                        self.view.tag_add(tag_name, found, marker_end)
                        self.view.tag_add("link", found, marker_end)
                        target = self.links[num - 1][1]
                        self.view.tag_bind(
                            tag_name, "<Button-1>",
                            lambda e, u=target: self.navigate(u))
                        self.view.tag_config(tag_name, cursor="hand2")
                    pos = marker_end
            self.view.config(state="disabled")

    root = tk.Tk()
    TurtleBrowser(root)
    root.mainloop()


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--dump":
        dump(sys.argv[2])
    elif len(sys.argv) == 2 and sys.argv[1] == "--dump":
        print("usage: turtle_browser.py --dump <url>")
    else:
        run_gui()


if __name__ == "__main__":
    main()
