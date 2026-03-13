import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {
    let pdfData: Data
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        if let document = PDFDocument(data: pdfData) {
            pdfView.document = document
        }
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil || uiView.document?.documentURL == nil { // quick check if we actually need to reload but for now it's static
            if let document = PDFDocument(data: pdfData) {
                uiView.document = document
            }
        }
    }
}
