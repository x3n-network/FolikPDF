import Foundation

extension Task where Failure == Error {
    /// Propagate the waiting screen's cancellation into its detached worker.
    nonisolated var cancellableValue: Success {
        get async throws {
            try await withTaskCancellationHandler {
                let result = try await value
                try Task<Never, Never>.checkCancellation()
                return result
            } onCancel: { cancel() }
        }
    }
}
