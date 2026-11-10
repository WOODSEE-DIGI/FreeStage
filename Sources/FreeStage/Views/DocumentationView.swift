//
//  DocumentationView.swift
//  FreeStage
//
//  Local help documentation rendered in a WKWebView.
//

import SwiftUI
@preconcurrency import WebKit

struct DocumentationView: View {
    var body: some View {
        WebView(url: docsURL)
            .frame(minWidth: 600, minHeight: 500)
    }

    private var docsURL: URL? {
        Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Docs")
    }
}

private struct WebView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let url else { return }
        if webView.url != url {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }
}

#Preview {
    DocumentationView()
}
