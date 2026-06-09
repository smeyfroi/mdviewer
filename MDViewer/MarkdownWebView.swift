import AppKit
import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    var html: String
    var baseURL: URL?
    var zoomScale: Double
    var findQuery: String
    var scrollRequest: MarkdownScrollRequest?
    var onFindResult: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFindResult: onFindResult)
    }

    func makeNSView(context: Context) -> MarkdownPreviewView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = .textBackgroundColor

        let view = MarkdownPreviewView(webView: webView)
        return view
    }

    func updateNSView(_ view: MarkdownPreviewView, context: Context) {
        let webView = view.webView

        if context.coordinator.lastHTML != html || context.coordinator.lastBaseURL != baseURL {
            context.coordinator.lastHTML = html
            context.coordinator.lastBaseURL = baseURL
            context.coordinator.lastFindQuery = nil
            context.coordinator.pendingFindQuery = findQuery
            context.coordinator.pendingScrollRequest = scrollRequest
            webView.load(
                Data(html.utf8),
                mimeType: "text/html",
                characterEncodingName: "utf-8",
                baseURL: baseURL ?? Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")
            )
        } else {
            context.coordinator.applyFind(findQuery, in: webView)
            context.coordinator.applyScroll(scrollRequest, in: webView)
        }

        webView.pageZoom = CGFloat(zoomScale)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var lastBaseURL: URL?
        var lastFindQuery: String?
        var lastScrollRequestID: UUID?
        var pendingFindQuery: String?
        var pendingScrollRequest: MarkdownScrollRequest?

        private let onFindResult: (Int) -> Void

        init(onFindResult: @escaping (Int) -> Void) {
            self.onFindResult = onFindResult
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            if url.isFileURL {
                decisionHandler(.allow)
            } else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyFind(pendingFindQuery ?? "", in: webView, force: true)
            pendingFindQuery = nil

            applyScroll(pendingScrollRequest, in: webView)
            pendingScrollRequest = nil
        }

        func applyFind(_ query: String, in webView: WKWebView, force: Bool = false) {
            guard force || lastFindQuery != query else { return }
            lastFindQuery = query

            webView.evaluateJavaScript(findScript(for: query)) { [weak self] result, _ in
                let count: Int
                if let number = result as? NSNumber {
                    count = number.intValue
                } else if let int = result as? Int {
                    count = int
                } else {
                    count = 0
                }
                self?.onFindResult(count)
            }
        }

        func applyScroll(_ request: MarkdownScrollRequest?, in webView: WKWebView) {
            guard let request, lastScrollRequestID != request.id else { return }
            lastScrollRequestID = request.id
            webView.evaluateJavaScript(scrollScript(for: request.anchorID))
        }

        private func findScript(for query: String) -> String {
            let queryLiteral = javaScriptString(query)
            return """
            (() => {
              const query = \(queryLiteral);
              const root = document.querySelector('.markdown-body');
              if (!root) { return 0; }

              document.querySelectorAll('mark.mdviewer-find-highlight').forEach((mark) => {
                mark.replaceWith(document.createTextNode(mark.textContent));
              });
              root.normalize();

              if (!query.trim()) { return 0; }

              const needle = query.toLocaleLowerCase();
              const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
                acceptNode(node) {
                  if (!node.nodeValue || !node.nodeValue.trim()) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  const parent = node.parentElement;
                  if (parent && parent.closest('script, style')) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  return NodeFilter.FILTER_ACCEPT;
                }
              });

              const nodes = [];
              let node;
              while ((node = walker.nextNode())) {
                nodes.push(node);
              }

              const marks = [];
              for (const textNode of nodes) {
                const text = textNode.nodeValue;
                const lower = text.toLocaleLowerCase();
                let index = lower.indexOf(needle);
                if (index === -1) { continue; }

                const fragment = document.createDocumentFragment();
                let cursor = 0;
                while (index !== -1) {
                  if (index > cursor) {
                    fragment.appendChild(document.createTextNode(text.slice(cursor, index)));
                  }
                  const mark = document.createElement('mark');
                  mark.className = 'mdviewer-find-highlight';
                  mark.textContent = text.slice(index, index + query.length);
                  fragment.appendChild(mark);
                  marks.push(mark);
                  cursor = index + query.length;
                  index = lower.indexOf(needle, cursor);
                }
                if (cursor < text.length) {
                  fragment.appendChild(document.createTextNode(text.slice(cursor)));
                }
                textNode.parentNode.replaceChild(fragment, textNode);
              }

              if (marks[0]) {
                marks[0].scrollIntoView({ block: 'center', inline: 'nearest' });
              }

              return marks.length;
            })();
            """
        }

        private func scrollScript(for anchorID: String) -> String {
            let anchorLiteral = javaScriptString(anchorID)
            return """
            (() => {
              const element = document.getElementById(\(anchorLiteral));
              if (element) {
                element.scrollIntoView({ block: 'start', inline: 'nearest' });
              }
            })();
            """
        }

        private func javaScriptString(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let string = String(data: data, encoding: .utf8)
            else { return "\"\"" }

            return string
        }
    }
}

final class MarkdownPreviewView: NSView {
    let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
