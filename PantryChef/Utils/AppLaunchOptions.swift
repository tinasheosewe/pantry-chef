import Foundation

struct AppLaunchOptions {
    let useInMemoryStorage: Bool
    let shouldBootstrapStorage: Bool
    let resetPersistentStore: Bool
    let seedPantryItems: Bool
    let seedRecipes: Bool
    let seedDiscoverRecipes: Bool
    let openSeededRecipeDetail: Bool

    static var current: AppLaunchOptions {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("UITEST_MODE") else {
            return AppLaunchOptions(
                useInMemoryStorage: false,
                shouldBootstrapStorage: true,
                resetPersistentStore: args.contains("RESET_PERSISTENT_STORE"),
                seedPantryItems: true,
                seedRecipes: true,
                seedDiscoverRecipes: true,
                openSeededRecipeDetail: false
            )
        }

        let emptyState = args.contains("UITEST_EMPTY_STATE")
        return AppLaunchOptions(
            useInMemoryStorage: true,
            shouldBootstrapStorage: !emptyState,
            resetPersistentStore: args.contains("RESET_PERSISTENT_STORE"),
            seedPantryItems: !emptyState,
            seedRecipes: !emptyState,
            seedDiscoverRecipes: !emptyState,
            openSeededRecipeDetail: args.contains("UITEST_RECIPE_DETAIL")
        )
    }
}
