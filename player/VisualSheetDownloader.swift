// Import Foundation for JSON transport and URL errors.
import Foundation
// Import WebKit so the app can run Sky Music's public sheet-export logic against its own page DOM.
import WebKit

// Fetch one public visual sheet and return its official JSON-export shape.
final class VisualSheetDownloader: NSObject, WKNavigationDelegate {
    // Keep the hidden web view alive while the current public sheet loads.
    private var webView: WKWebView?
    // Retain exactly one completion because Community Collection downloads one sheet at a time.
    private var completion: ((Result<Data, Error>) -> Void)?

    // Load a public sheet page and export the same timed key JSON the site offers in its Download button.
    func download(from url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        // Reject concurrent requests rather than mixing one score's DOM with another callback.
        guard self.completion == nil else { completion(.failure(VisualSheetDownloadError.busy)); return }
        // Keep the caller completion until page navigation and JavaScript export finish.
        self.completion = completion
        // Construct a non-persistent hidden renderer so no browsing state or cookies are retained.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // Retain the renderer without placing it in the app's visible UI hierarchy.
        let renderer = WKWebView(frame: .zero, configuration: configuration)
        renderer.navigationDelegate = self
        webView = renderer
        // Let WebKit parse the source page exactly as Safari would.
        renderer.load(URLRequest(url: url))
    }

    // Run export logic only after the public sheet's static notation DOM has loaded.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Mirror Sky Music's public downloader: V3 `.line` notation first, legacy tables otherwise.
        let script = #"""
        (() => {
          const songNotes = [];
          let timestamp = { value: 200 };
          const bump = () => { timestamp.value += 500; };
          const v3 = document.querySelectorAll('d1').length > 0;
          if (v3) {
            const containers = Array.from(document.querySelectorAll('.line')).flatMap(line => Array.from(line.children));
            for (const container of containers) {
              if (container.children.length > 10) {
                bump();
                if (!container.classList.contains('silent')) {
                  Array.from(container.children).forEach((note, index) => {
                    if (!['D1', 'D2', 'D3'].includes(note.tagName)) songNotes.push({ key: '1Key' + index, time: timestamp.value });
                  });
                }
              }
            }
          } else {
            const tables = Array.from(document.getElementsByTagName('table'));
            for (const table of tables.slice(1)) {
              const cell = table.children[0]?.children[0];
              if (!cell) continue;
              if (cell.children.length > 2) bump();
              let noteNumber = 0;
              for (let rowIndex = 0; rowIndex < 3; rowIndex++) {
                const row = cell.children[rowIndex];
                if (!row) break;
                for (let column = 0; column < 5; column++) {
                  const note = row.children[column];
                  if (note?.children[0] && !note.children[0].classList.contains('OFF') && note.children[0].querySelector('[class*=ON]')) songNotes.push({ key: '1Key' + noteNumber, time: timestamp.value });
                  noteNumber += 1;
                }
              }
            }
          }
          return JSON.stringify([{ name: document.title, songNotes }]);
        })()
        """#
        // Evaluate only this local extraction script against the already-loaded source page.
        webView.evaluateJavaScript(script) { [weak self] result, error in
            // Return a typed failure when the page could not expose a usable export.
            guard let self else { return }
            if let error { self.finish(.failure(error)); return }
            guard let json = result as? String, let data = json.data(using: .utf8) else {
                self.finish(.failure(VisualSheetDownloadError.invalidExport))
                return
            }
            // Hand the normal Sky Music array-wrapper bytes to the existing strict converter.
            self.finish(.success(data))
        }
    }

    // Surface navigation failures rather than leaving the card in an endless downloading state.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }

    // Complete exactly once and release the hidden renderer plus callback.
    private func finish(_ result: Result<Data, Error>) {
        // Capture then clear retained transient navigation state before callback code runs.
        let callback = completion
        completion = nil
        webView?.navigationDelegate = nil
        webView = nil
        // Return success or failure to the AppKit main queue caller.
        callback?(result)
    }
}

// Keep concise actionable failures at the public web-sheet boundary.
enum VisualSheetDownloadError: LocalizedError {
    // Prevent concurrent extraction work inside one tiny renderer.
    case busy
    // Reject a page whose notation could not become JSON data.
    case invalidExport
    // Explain each failure without exposing internal web view details.
    var errorDescription: String? {
        switch self {
        case .busy: return "Another visual sheet is still downloading."
        case .invalidExport: return "This sheet could not be exported as Sky Music JSON."
        }
    }
}
