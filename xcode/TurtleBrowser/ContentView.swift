//
//  ContentView.swift
//  Turtle Browser — prototype 0.1 (Swift)
//
//  The browser window: back / forward / reload / home, an address
//  bar, and a page view painted by our own Turtle Engine.
//  Links in the page are clickable and load in the same window.
//

import SwiftUI
import AppKit

@MainActor
final class BrowserModel: ObservableObject {
    @Published var pageText = NSAttributedString(string: "")
    @Published var addressText = "turtle://home"
    @Published var pageTitle = "Turtle Browser"
    @Published var statusLine = "Turtle Engine 0.2 (Swift) — CSS step one, no JavaScript yet"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var pageID = 0

    private var currentURL = ""
    private var backStack: [String] = []
    private var forwardStack: [String] = []

    init() {
        load("turtle://home", push: false)
    }

    func normalize(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("turtle://") { return t }
        if t.contains("://") { return t }
        if t.contains(" ") || !t.contains(".") {
            let q = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
            return "https://html.duckduckgo.com/html/?q=\(q)"
        }
        return "https://" + t
    }

    func go() { load(addressText) }
    func reload() { if !currentURL.isEmpty { load(currentURL, push: false) } }
    func goHome() { load("turtle://home") }

    func goBack() {
        guard let target = backStack.popLast() else { return }
        forwardStack.append(currentURL)
        load(target, push: false)
    }

    func goForward() {
        guard let target = forwardStack.popLast() else { return }
        backStack.append(currentURL)
        load(target, push: false)
    }

    func load(_ raw: String, push: Bool = true) {
        let target = normalize(raw)
        if push && !currentURL.isEmpty {
            backStack.append(currentURL)
            forwardStack.removeAll()
        }
        statusLine = "Loading \(target) …"
        Task {
            do {
                let (finalURL, html) = try await tbFetch(urlString: target)
                let (title, body) = tbRenderPage(html: html, base: finalURL)
                self.currentURL = finalURL
                self.addressText = finalURL
                self.pageTitle = title
                self.pageText = body
                self.statusLine = "\(finalURL)  ·  Turtle Engine 0.2 (Swift) — CSS step one, no JavaScript yet"
            } catch {
                self.currentURL = target
                self.addressText = target
                self.pageTitle = "Could not load page"
                let msg = NSMutableAttributedString()
                msg.append(NSAttributedString(
                    string: "This page could not be loaded\n\n",
                    attributes: [.font: NSFont.boldSystemFont(ofSize: 20)]))
                msg.append(NSAttributedString(
                    string: "\(target)\n\nReason: \(error.localizedDescription)",
                    attributes: [.font: NSFont.systemFont(ofSize: 14)]))
                self.pageText = msg
                self.statusLine = "Load failed"
            }
            self.canGoBack = !self.backStack.isEmpty
            self.canGoForward = !self.forwardStack.isEmpty
            self.pageID += 1
        }
    }
}

struct PageTextView: NSViewRepresentable {
    @ObservedObject var model: BrowserModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isAutomaticLinkDetectionEnabled = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if context.coordinator.lastPageID != model.pageID {
            context.coordinator.lastPageID = model.pageID
            textView.textStorage?.setAttributedString(model.pageText)
            textView.scrollToBeginningOfDocument(nil)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: BrowserModel
        var lastPageID = -1

        init(model: BrowserModel) {
            self.model = model
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let s = link as? String {
                model.load(s)
                return true
            }
            if let u = link as? URL {
                model.load(u.absoluteString)
                return true
            }
            return false
        }
    }
}

struct ContentView: View {
    @StateObject private var model = BrowserModel()

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("\u{25C0}") { model.goBack() }
                    .disabled(!model.canGoBack)
                    .help("Back")
                Button("\u{25B6}") { model.goForward() }
                    .disabled(!model.canGoForward)
                    .help("Forward")
                Button("\u{27F3}") { model.reload() }
                    .help("Reload")
                Button("\u{2302}") { model.goHome() }
                    .help("Turtle Home")
                TextField("Address", text: $model.addressText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.go() }
                Button("Go") { model.go() }
            }
            PageTextView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(model.statusLine)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(minWidth: 720, minHeight: 520)
    }
}
