import Foundation
import SwiftData

/// Creates the app's model container (current schema with migration plan).
public enum PodlistStore {
    /// `url` is for tests; the app uses the default store location.
    public static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV6.self)
        // CloudKit sync comes later (concept §5); the schema is already compatible.
        let configuration = if let url {
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        return try ModelContainer(
            for: schema, migrationPlan: PodlistMigrationPlan.self, configurations: [configuration])
    }
}
