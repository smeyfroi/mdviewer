import Cocoa
import Quartz
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let markdown = try String(contentsOf: request.fileURL, encoding: .utf8)
        let stylesheet = Self.loadStylesheet()
        let html = MarkdownRenderer.htmlDocument(
            markdown: markdown,
            title: request.fileURL.lastPathComponent,
            stylesheet: stylesheet
        )
        let htmlData = Data(html.utf8)

        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 860, height: 1000)) { replyToUpdate in
            replyToUpdate.stringEncoding = .utf8
            replyToUpdate.title = request.fileURL.lastPathComponent
            return htmlData
        }

        return reply
    }

    private static func loadStylesheet() -> String {
        guard let url = Bundle.main.url(forResource: "native", withExtension: "css", subdirectory: "Styles"),
              let stylesheet = try? String(contentsOf: url, encoding: .utf8)
        else {
            return """
            :root {
              --page-bg: Canvas;
              --content-bg: Canvas;
              --text: CanvasText;
              --muted: color-mix(in srgb, CanvasText 62%, transparent);
              --body-font: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
              --content-width: 860px;
              --content-padding: 44px 56px 64px;
            }

            a { color: LinkText; }
            code, pre { font-family: "SF Mono", ui-monospace, monospace; }
            pre {
              overflow-x: auto;
              padding: 14px 16px;
              border-radius: 8px;
              background: color-mix(in srgb, CanvasText 7%, transparent);
            }
            blockquote {
              margin-left: 0;
              padding-left: 16px;
              border-left: 3px solid AccentColor;
              color: var(--muted);
            }
            """
        }

        return stylesheet
    }
}
