import Foundation

struct AppLaunchOptions {
    let useInMemoryStorage: Bool
    let shouldBootstrapStorage: Bool
    let seedPantryItems: Bool
    let seedRecipes: Bool
    let seedDiscoverRecipes: Bool

    static var current: AppLaunchOptions {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("UITEST_MODE") else {
            return AppLaunchOptions(
                useInMemoryStorage: false,
                shouldBootstrapStorage: true,
                seedPantryItems: true,
                seedRecipes: true,
                seedDiscoverRecipes: true
            )
        }

        let emptyState = args.contains("UITEST_EMPTY_STATE")
        return AppLaunchOptions(
            useInMemoryStorage: true,
            shouldBootstrapStorage: !emptyState,
            seedPantryItems: !emptyState,
            seedRecipes: !emptyState,
            seedDiscoverRecipes: !emptyState
        )
    }
}
