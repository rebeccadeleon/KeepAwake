import SwiftUI
import AppKit
import PDFKit
import WebKit

struct ReportPDFPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(
        context: Context
    ) -> PDFView {
        let view = PDFView()

        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical

        view.document = PDFDocument(
            data: data
        )

        return view
    }

    func updateNSView(
        _ view: PDFView,
        context: Context
    ) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(
                data: data
            )
        }
    }
}

struct ReportHTMLPreview: NSViewRepresentable {
    let html: String

    func makeNSView(
        context: Context
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        configuration.defaultWebpagePreferences
            .allowsContentJavaScript = false

        let view = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        view.loadHTMLString(
            html,
            baseURL: nil
        )

        return view
    }

    func updateNSView(
        _ view: WKWebView,
        context: Context
    ) {}
}

struct ReportPreviewView: View {
    @ObservedObject var manager: ReportManager

    @Environment(\.dismiss)
    private var dismiss

    @State private var data: Data?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                if let error {
                    Text(error)
                        .foregroundStyle(.red)

                } else if let data {
                    preview(data)

                } else {
                    ProgressView()
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )

            Divider()

            footer
        }
        .frame(
            minWidth: 720,
            minHeight: 600
        )
        .task {
            preparePreview()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "doc.richtext")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading) {
                Text("Report Preview")
                    .font(.headline)

                Text(manager.options.format.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    @ViewBuilder
    private func preview(
        _ data: Data
    ) -> some View {
        switch manager.options.format {
        case .pdf:
            ReportPDFPreview(data: data)

        case .html:
            ReportHTMLPreview(
                html: String(
                    decoding: data,
                    as: UTF8.self
                )
            )

        case .json, .text:
            ScrollView([.horizontal, .vertical]) {
                Text(
                    String(
                        decoding: data,
                        as: UTF8.self
                    )
                )
                .font(.system(
                    size: 11,
                    design: .monospaced
                ))
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .topLeading
                )
                .padding(16)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let data {
                Text(
                    ByteCountFormatter.string(
                        fromByteCount: Int64(data.count),
                        countStyle: .file
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }

            Button("Save Report") {
                Task {
                    await manager.save()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(data == nil)
        }
        .padding(14)
    }

    private func preparePreview() {
        guard let report = manager.report else {
            error = "No report is available."
            return
        }

        do {
            data = try ReportRenderer.render(
                report,
                format: manager.options.format
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}