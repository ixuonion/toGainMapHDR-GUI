import Foundation

actor WorkQueue<Element> {
    private var items: [Element]

    init(_ items: [Element]) {
        self.items = items
    }

    func next() -> Element? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }
}
