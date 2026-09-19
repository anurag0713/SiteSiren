import Foundation
import Combine

@MainActor
public final class ActivityStore: ObservableObject {
    @Published public private(set) var events: [BlockEvent] = []
    
    public init() {
        refresh()
    }
    
    public func refresh() {
        self.events = SharedStore.shared.loadBlockEvents()
    }
    
    public func clearHistory() {
        SharedStore.shared.clearBlockEvents()
        self.events = []
    }
}
