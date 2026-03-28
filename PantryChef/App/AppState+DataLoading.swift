import Foundation

// MARK: - Data Loading

extension AppState {
    func loadAllData() async {
        isLoading = true
        defer {
            isLoading = false
        }

        await Task.yield()

        var failures: [String] = []

        if let storageService = storageService as? StorageService {
            do {
                let snapshot = try await storageService.fetchStartupSnapshot()
                setPantryItems(snapshot.pantryItems)
                setPreparedDishes(snapshot.preparedDishes)
                setPreparedDishHistoryItems(snapshot.preparedDishHistory)
                setRecipes(snapshot.recipes.filter { $0.source.isUserRecipe })
                let persistedDiscover = snapshot.recipes.filter { !$0.source.isUserRecipe }
                setDiscoverRecipes(mergedDiscoverRecipes(withPersisted: persistedDiscover))

                let sanitizedPlan = sanitizeMealPlanEntries(snapshot.mealPlan)
                setMealPlanEntries(sanitizedPlan.visibleEntries)
                await purgeMealPlanEntries(sanitizedPlan.removedEntries)

                setShoppingItemsValue(snapshot.shoppingItems)
                setCookQueueValue(snapshot.cookQueue)
                clearError()
                return
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        do {
            let fetchedItems = try await storageService.fetchPantryItems()
            setPantryItems(fetchedItems)
        } catch {
            failures.append(error.localizedDescription)
        }
        await Task.yield()

        do {
            let fetchedPreparedDishes = try await storageService.fetchPreparedDishes()
            setPreparedDishes(fetchedPreparedDishes)
        } catch {
            failures.append(error.localizedDescription)
        }
        await Task.yield()

        do {
            let fetchedPreparedDishHistory = try await storageService.fetchPreparedDishHistory()
            setPreparedDishHistoryItems(fetchedPreparedDishHistory)
        } catch {
            failures.append(error.localizedDescription)
        }
        await Task.yield()

        do {
            let fetchedRecipes = try await storageService.fetchRecipes()
            setRecipes(fetchedRecipes.filter { $0.source.isUserRecipe })
            let persistedDiscover = fetchedRecipes.filter { !$0.source.isUserRecipe }
            setDiscoverRecipes(mergedDiscoverRecipes(withPersisted: persistedDiscover))
        } catch {
            failures.append(error.localizedDescription)
        }
        await Task.yield()

        do {
            let fetchedPlan = try await storageService.fetchMealPlan()
            let sanitizedPlan = sanitizeMealPlanEntries(fetchedPlan)
            setMealPlanEntries(sanitizedPlan.visibleEntries)
            await purgeMealPlanEntries(sanitizedPlan.removedEntries)
        } catch {
            failures.append(error.localizedDescription)
        }
        await Task.yield()

        do {
            let fetchedShopping = try await storageService.fetchShoppingItems()
            setShoppingItemsValue(fetchedShopping)
        } catch {
            failures.append(error.localizedDescription)
        }

        await Task.yield()

        do {
            let fetchedCookQueue = try await storageService.fetchCookQueue()
            setCookQueueValue(fetchedCookQueue)
        } catch {
            failures.append(error.localizedDescription)
        }

        if failures.isEmpty {
            clearError()
        } else {
            pushError(.loadFailure(failures))
        }
    }
}
