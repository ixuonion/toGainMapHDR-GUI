import SwiftUI

struct ContentView: View {
    @Bindable var store: ConversionStore

    var body: some View {
        NavigationSplitView {
            InputSidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
        } detail: {
            DetailView(store: store)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.removeSelectedInput()
                } label: {
                    Label(L10n.text("remove"), systemImage: "minus.circle")
                }
                .disabled(store.selectedInputID == nil || store.isConverting)
                .help(L10n.text("remove"))
            }

            ToolbarItemGroup(placement: .confirmationAction) {
                Button {
                    store.revealOutputFolder()
                } label: {
                    Label(L10n.text("reveal_output"), systemImage: "folder")
                }
                .disabled(store.outputURL == nil)
                .help(L10n.text("reveal_output"))

                Button {
                    store.isConverting ? store.cancelConversion() : store.startConversion()
                } label: {
                    Label(store.isConverting ? L10n.text("cancel") : L10n.text("convert"), systemImage: store.isConverting ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canConvert && !store.isConverting)
                .help(store.isConverting ? L10n.text("cancel") : L10n.text("convert"))
            }
        }
    }
}
