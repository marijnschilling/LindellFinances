//
//  ContentView.swift
//  LindellFinances
//
//  Created by Marijn Work on 2026-03-28.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case transactions
    case categories
    case moneyPots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .transactions:
            return "Transactions"
        case .categories:
            return "Categories"
        case .moneyPots:
            return "Money Pots"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:
            return "rectangle.grid.2x2"
        case .transactions:
            return "list.bullet.rectangle"
        case .categories:
            return "tag"
        case .moneyPots:
            return "shippingbox"
        }
    }
}

private struct DefaultCategorySeed {
    let name: String
    let kind: CategoryKind
    let monthlyBudgetCents: Int
}

private let defaultCategorySeeds = [
    DefaultCategorySeed(name: "🏡 House", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "🛒 Groceries", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "☕️ Fika/Luch/Dinner", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "👶 Kids", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "💳 Subscriptions", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "🛋️ Home", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "🚗 Car", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "🐈‍⬛ Cat", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "💊 Health", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "🎡 Fun", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "🛍️ Shopping", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "🥡 Take-Out", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "🏦 Bank", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "🎁 Gifts", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "🏝️ Vacation", kind: .expense, monthlyBudgetCents: 0),
    DefaultCategorySeed(name: "💰Savings", kind: .expense, monthlyBudgetCents: 0),
]

private let defaultCategoriesSeedKey = "default-categories-seeded-v3"
private let ignoredTitleWordsSeedKey = "ignored-title-words-seeded"

private let defaultCategoryOrder = Dictionary(
    uniqueKeysWithValues: defaultCategorySeeds.enumerated().map { offset, seed in
        (FinanceNormalizer.comparableText(seed.name), offset)
    }
)

private func sortedCategories(_ categories: [Category]) -> [Category] {
    categories.sorted { lhs, rhs in
        let lhsDefaultOrder = defaultCategoryOrder[FinanceNormalizer.comparableText(lhs.name)] ?? Int.max
        let rhsDefaultOrder = defaultCategoryOrder[FinanceNormalizer.comparableText(rhs.name)] ?? Int.max

        if lhsDefaultOrder != rhsDefaultOrder {
            return lhsDefaultOrder < rhsDefaultOrder
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

private func categoriesOfKind(_ kind: CategoryKind, from categories: [Category]) -> [Category] {
    sortedCategories(categories.filter { $0.kind == kind })
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Transaction.effectiveDate, order: .reverse) private var transactions: [Transaction]
    @Query(
        filter: #Predicate<Transaction> { transaction in
            transaction.needsCategoryReview == true
        },
        sort: \Transaction.effectiveDate,
        order: .reverse
    ) private var transactionsNeedingReview: [Transaction]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \MoneyPot.name) private var moneyPots: [MoneyPot]
    @Query(sort: \CategoryWordTag.displayWord) private var categoryWordTags: [CategoryWordTag]
    @Query(sort: \IgnoredTitleWord.displayWord) private var ignoredTitleWords: [IgnoredTitleWord]

    @State private var selectedSection: AppSection? = .dashboard
    @State private var showingImporter = false
    @State private var importSummary: ImportSummary?
    @State private var errorMessage: String?
    @State private var editingTransaction: Transaction?
    @State private var showingCategoryEditor = false
    @State private var categoryEditorSeed: Category?
    @State private var showingMoneyPotEditor = false
    @State private var moneyPotEditorSeed: MoneyPot?

    private var showingImportSummaryBinding: Binding<Bool> {
        Binding(
            get: { importSummary != nil },
            set: { isPresented in
                if isPresented == false {
                    importSummary = nil
                }
            }
        )
    }

    private var showingErrorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    errorMessage = nil
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(AppSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.icon)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if transactionsNeedingReview.isEmpty == false {
                        Button {
                            editingTransaction = transactionsNeedingReview.first
                        } label: {
                            HStack {
                                Label(
                                    "\(transactionsNeedingReview.count) Need Review",
                                    systemImage: "exclamationmark.circle.fill"
                                )
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        HStack {
                            Label("Import Nordea CSV", systemImage: "square.and.arrow.down")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                .background(.bar)
            }
        } detail: {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.98, blue: 0.96),
                        Color(red: 0.97, green: 0.97, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Group {
                    switch selectedSection ?? .dashboard {
                    case .dashboard:
                        DashboardView(
                            transactions: transactions,
                            categories: categories,
                            moneyPots: moneyPots,
                            transactionsNeedingReview: transactionsNeedingReview,
                            onImport: { showingImporter = true },
                            onReview: { editingTransaction = $0 },
                            onEditCategory: openCategoryEditor,
                            onEditMoneyPot: openMoneyPotEditor
                        )
                    case .transactions:
                        TransactionsView(
                            transactions: transactions,
                            onImport: { showingImporter = true },
                            onEdit: { editingTransaction = $0 }
                        )
                    case .categories:
                        CategoriesView(
                            categories: categories,
                            transactions: transactions,
                            categoryWordTags: categoryWordTags,
                            ignoredTitleWords: ignoredTitleWords,
                            onCreate: { openCategoryEditor(nil) },
                            onEdit: openCategoryEditor,
                            onDeleteTag: deleteCategoryWordTag,
                            onAddIgnoredWords: addIgnoredTitleWords,
                            onDeleteIgnoredWord: deleteIgnoredTitleWord
                        )
                    case .moneyPots:
                        MoneyPotsView(
                            moneyPots: moneyPots,
                            transactions: transactions,
                            onCreate: { openMoneyPotEditor(nil) },
                            onEdit: openMoneyPotEditor
                        )
                    }
                }
                .padding(24)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Import CSV", systemImage: "square.and.arrow.down") {
                    showingImporter = true
                }

                Button("New Category", systemImage: "tag") {
                    openCategoryEditor(nil)
                }

                Button("New Money Pot", systemImage: "shippingbox.and.arrow.backward") {
                    openMoneyPotEditor(nil)
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: true,
            onCompletion: handleImportResult
        )
        .sheet(item: $editingTransaction) { transaction in
            TransactionAssignmentView(
                transaction: transaction,
                categories: categories,
                moneyPots: moneyPots,
                categoryWordTags: categoryWordTags,
                ignoredTitleWords: ignoredTitleWords,
                onSave: { categoryID, moneyPotID, note, selectedTitleTags in
                    saveAssignments(
                        for: transaction,
                        categoryID: categoryID,
                        moneyPotID: moneyPotID,
                        note: note,
                        selectedTitleTags: selectedTitleTags
                    )
                }
            )
        }
        .sheet(isPresented: $showingCategoryEditor) {
            CategoryEditorView(category: categoryEditorSeed) { name, targetCents in
                saveCategory(name: name, targetCents: targetCents)
            }
        }
        .sheet(isPresented: $showingMoneyPotEditor) {
            MoneyPotEditorView(moneyPot: moneyPotEditorSeed) { name, monthlyContributionCents, openingBalanceCents, startsOn in
                saveMoneyPot(
                    name: name,
                    monthlyContributionCents: monthlyContributionCents,
                    openingBalanceCents: openingBalanceCents,
                    startsOn: startsOn
                )
            }
        }
        .alert("Import Complete", isPresented: showingImportSummaryBinding, presenting: importSummary) { _ in
            Button("OK") {
                importSummary = nil
            }
        } message: { summary in
            Text(summary.message)
        }
        .alert("Something Went Wrong", isPresented: showingErrorBinding, presenting: errorMessage) { _ in
            Button("OK") {
                errorMessage = nil
            }
        } message: { message in
            Text(message)
        }
        .onAppear(perform: handleAppear)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                presentReviewIfNeeded()
            }
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            importTransactions(from: urls)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func importTransactions(from urls: [URL]) {
        let accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        let fallbackURLs = urls.filter { accessedURLs.contains($0) == false }
        let readableURLs = accessedURLs + fallbackURLs

        defer {
            accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        }

        do {
            importSummary = try CSVImportService.importFiles(readableURLs, into: modelContext)
            presentReviewIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleAppear() {
        removeIncomeDataIfNeeded()
        seedDefaultCategoriesIfNeeded()
        seedDefaultIgnoredTitleWordsIfNeeded()
        presentReviewIfNeeded()
    }

    private func openCategoryEditor(_ category: Category?) {
        categoryEditorSeed = category
        showingCategoryEditor = true
    }

    private func openMoneyPotEditor(_ moneyPot: MoneyPot?) {
        moneyPotEditorSeed = moneyPot
        showingMoneyPotEditor = true
    }

    private func saveCategory(name: String, targetCents: Int) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            errorMessage = "Category name cannot be empty."
            return
        }

        do {
            if let category = categoryEditorSeed {
                category.name = trimmedName
                category.kind = .expense
                category.monthlyBudgetCents = targetCents
            } else {
                modelContext.insert(Category(name: trimmedName, kind: .expense, monthlyBudgetCents: targetCents))
            }

            try modelContext.save()
            categoryEditorSeed = nil
            showingCategoryEditor = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveMoneyPot(
        name: String,
        monthlyContributionCents: Int,
        openingBalanceCents: Int,
        startsOn: Date
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            errorMessage = "Money pot name cannot be empty."
            return
        }

        do {
            if let moneyPot = moneyPotEditorSeed {
                moneyPot.name = trimmedName
                moneyPot.monthlyContributionCents = monthlyContributionCents
                moneyPot.openingBalanceCents = openingBalanceCents
                moneyPot.startsOn = startsOn
            } else {
                modelContext.insert(
                    MoneyPot(
                        name: trimmedName,
                        monthlyContributionCents: monthlyContributionCents,
                        openingBalanceCents: openingBalanceCents,
                        startsOn: startsOn
                    )
                )
            }

            try modelContext.save()
            moneyPotEditorSeed = nil
            showingMoneyPotEditor = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAssignments(
        for transaction: Transaction,
        categoryID: UUID?,
        moneyPotID: UUID?,
        note: String,
        selectedTitleTags: [TitleWordToken]
    ) {
        do {
            transaction.category = categories.first(where: { $0.id == categoryID })
            transaction.moneyPot = moneyPots.first(where: { $0.id == moneyPotID })
            transaction.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            transaction.needsCategoryReview = transaction.category == nil

            if let category = transaction.category {
                try updateTitleTags(
                    selectedWords: selectedTitleTags,
                    from: transaction.title,
                    for: category
                )
            }

            try modelContext.save()
            editingTransaction = nil

            DispatchQueue.main.async {
                presentReviewIfNeeded()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upsertRule(
        field: MatchingField,
        pattern: String,
        category: Category?,
        moneyPot: MoneyPot?
    ) throws {
        let fieldRawValue = field.rawValue
        var descriptor = FetchDescriptor<MatchingRule>(
            predicate: #Predicate<MatchingRule> { rule in
                rule.fieldRawValue == fieldRawValue && rule.pattern == pattern
            }
        )
        descriptor.fetchLimit = 1

        let existingRule = try modelContext.fetch(descriptor).first
        let rule = existingRule ?? MatchingRule(field: field, pattern: pattern)
        if existingRule == nil {
            modelContext.insert(rule)
        }

        rule.category = category
        rule.moneyPot = moneyPot
        rule.updatedAt = .now

        for transaction in transactions where transactionMatches(transaction, field: field, pattern: pattern) {
            transaction.category = category
            transaction.moneyPot = moneyPot
            transaction.needsCategoryReview = transaction.category == nil
        }
    }

    private func transactionMatches(_ transaction: Transaction, field: MatchingField, pattern: String) -> Bool {
        switch field {
        case .counterpartyAccount:
            return FinanceNormalizer.accountKey(transaction.counterpartyAccount) == pattern
        case .merchantKey:
            return transaction.merchantKey == pattern
        }
    }

    private func rulePattern(for transaction: Transaction, field: MatchingField) -> String? {
        switch field {
        case .counterpartyAccount:
            let pattern = FinanceNormalizer.accountKey(transaction.counterpartyAccount)
            return pattern.isEmpty ? nil : pattern
        case .merchantKey:
            return transaction.merchantKey.isEmpty ? nil : transaction.merchantKey
        }
    }

    private func seedDefaultIgnoredTitleWordsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: ignoredTitleWordsSeedKey) == false else {
            return
        }

        do {
            for defaultWord in FinanceNormalizer.defaultIgnoredTitleWords {
                let normalizedWord = FinanceNormalizer.normalizedTitleWord(defaultWord)
                guard normalizedWord.isEmpty == false else {
                    continue
                }

                if try existingIgnoredTitleWord(normalizedWord: normalizedWord) == nil {
                    modelContext.insert(
                        IgnoredTitleWord(
                            normalizedWord: normalizedWord,
                            displayWord: defaultWord.uppercased(with: Locale(identifier: "sv_SE"))
                        )
                    )
                }
            }

            try modelContext.save()
            defaults.set(true, forKey: ignoredTitleWordsSeedKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func seedDefaultCategoriesIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: defaultCategoriesSeedKey) == false || categories.isEmpty else {
            return
        }

        do {
            let existingCategoryKeys = Set(categories.map { category in
                FinanceNormalizer.comparableText(category.name)
            })

            for seed in defaultCategorySeeds {
                let comparableName = FinanceNormalizer.comparableText(seed.name)
                guard existingCategoryKeys.contains(comparableName) == false else {
                    continue
                }

                modelContext.insert(
                    Category(
                        name: seed.name,
                        kind: seed.kind,
                        monthlyBudgetCents: seed.monthlyBudgetCents
                    )
                )
            }

            try modelContext.save()
            defaults.set(true, forKey: defaultCategoriesSeedKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeIncomeDataIfNeeded() {
        let incomeCategories = categories.filter { $0.kind == .income }
        guard incomeCategories.isEmpty == false else {
            return
        }

        let incomeCategoryIDs = Set(incomeCategories.map(\.id))

        do {
            let matchingRules = try modelContext.fetch(FetchDescriptor<MatchingRule>())

            for transaction in transactions {
                guard let category = transaction.category,
                      incomeCategoryIDs.contains(category.id)
                else {
                    continue
                }

                transaction.category = nil
                transaction.needsCategoryReview = true
            }

            for tag in categoryWordTags {
                guard let category = tag.category,
                      incomeCategoryIDs.contains(category.id)
                else {
                    continue
                }

                modelContext.delete(tag)
            }

            for rule in matchingRules {
                guard let category = rule.category,
                      incomeCategoryIDs.contains(category.id)
                else {
                    continue
                }

                modelContext.delete(rule)
            }

            for category in incomeCategories {
                modelContext.delete(category)
            }

            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateTitleTags(
        selectedWords: [TitleWordToken],
        from title: String,
        for category: Category
    ) throws {
        let ignoredWords = Set(ignoredTitleWords.map(\.normalizedWord))
        let candidateWords = FinanceNormalizer.titleWords(from: title, ignoring: ignoredWords)
        let selectedWordIDs = Set(selectedWords.map(\.normalizedWord))
        let candidateWordIDs = Set(candidateWords.map(\.normalizedWord))
        let selectedCandidateWords = candidateWords.filter { selectedWordIDs.contains($0.normalizedWord) }

        for candidateWord in candidateWords where selectedWordIDs.contains(candidateWord.normalizedWord) == false {
            if let existingTag = try existingCategoryWordTag(normalizedWord: candidateWord.normalizedWord),
               existingTag.category?.id == category.id {
                modelContext.delete(existingTag)
            }
        }

        for word in selectedCandidateWords {
            let existingTag = try existingCategoryWordTag(normalizedWord: word.normalizedWord)
            let tag = existingTag ?? CategoryWordTag(
                normalizedWord: word.normalizedWord,
                displayWord: word.displayWord,
                category: category
            )

            if existingTag == nil {
                modelContext.insert(tag)
            }

            tag.displayWord = word.displayWord
            tag.category = category
        }

        let learnedMappings: [String: Category] = Dictionary(
            uniqueKeysWithValues: selectedCandidateWords.map { ($0.normalizedWord, category) }
        )
        applyCategoryWordTagsToUncategorisedTransactions(
            additionalMappings: learnedMappings,
            removingWords: candidateWordIDs.subtracting(selectedWordIDs)
        )
    }

    private func applyCategoryWordTagsToUncategorisedTransactions(
        additionalMappings: [String: Category] = [:],
        removingWords: Set<String> = []
    ) {
        let ignoredWords = Set(ignoredTitleWords.map(\.normalizedWord))
        var tagCategories: [String: Category] = Dictionary(uniqueKeysWithValues: categoryWordTags.compactMap { tag in
            guard let category = tag.category else {
                return nil
            }

            return (tag.normalizedWord, category)
        })

        for word in removingWords {
            tagCategories.removeValue(forKey: word)
        }

        for (word, category) in additionalMappings {
            tagCategories[word] = category
        }

        for transaction in transactions where transaction.category == nil {
            if let category = matchedCategory(
                for: transaction.title,
                titleTagCategories: tagCategories,
                ignoredTitleWords: ignoredWords
            ) {
                transaction.category = category
                transaction.needsCategoryReview = false
            } else {
                transaction.needsCategoryReview = true
            }
        }
    }

    private func matchedCategory(
        for title: String,
        titleTagCategories: [String: Category],
        ignoredTitleWords: Set<String>
    ) -> Category? {
        let matches = FinanceNormalizer.titleWords(from: title, ignoring: ignoredTitleWords)
            .compactMap { titleTagCategories[$0.normalizedWord] }

        guard let firstCategory = matches.first else {
            return nil
        }

        let uniqueCategoryIDs = Set(matches.map(\.id))
        return uniqueCategoryIDs.count == 1 ? firstCategory : nil
    }

    private func addIgnoredTitleWords(_ input: String) {
        do {
            let words = FinanceNormalizer.titleWords(from: input)
            guard words.isEmpty == false else {
                errorMessage = "Ignored words must contain letters."
                return
            }

            for word in words {
                if try existingIgnoredTitleWord(normalizedWord: word.normalizedWord) == nil {
                    modelContext.insert(
                        IgnoredTitleWord(
                            normalizedWord: word.normalizedWord,
                            displayWord: word.displayWord
                        )
                    )
                }

                if let existingTag = try existingCategoryWordTag(normalizedWord: word.normalizedWord) {
                    modelContext.delete(existingTag)
                }
            }

            applyCategoryWordTagsToUncategorisedTransactions(
                removingWords: Set(words.map(\.normalizedWord))
            )
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteIgnoredTitleWord(_ ignoredWord: IgnoredTitleWord) {
        do {
            modelContext.delete(ignoredWord)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCategoryWordTag(_ tag: CategoryWordTag) {
        do {
            applyCategoryWordTagsToUncategorisedTransactions(
                removingWords: [tag.normalizedWord]
            )
            modelContext.delete(tag)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func existingCategoryWordTag(normalizedWord: String) throws -> CategoryWordTag? {
        var descriptor = FetchDescriptor<CategoryWordTag>(
            predicate: #Predicate<CategoryWordTag> { tag in
                tag.normalizedWord == normalizedWord
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func existingIgnoredTitleWord(normalizedWord: String) throws -> IgnoredTitleWord? {
        var descriptor = FetchDescriptor<IgnoredTitleWord>(
            predicate: #Predicate<IgnoredTitleWord> { ignoredWord in
                ignoredWord.normalizedWord == normalizedWord
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func presentReviewIfNeeded() {
        guard editingTransaction == nil else {
            return
        }

        editingTransaction = transactionsNeedingReview.first
    }
}

private struct DashboardView: View {
    let transactions: [Transaction]
    let categories: [Category]
    let moneyPots: [MoneyPot]
    let transactionsNeedingReview: [Transaction]
    let onImport: () -> Void
    let onReview: (Transaction) -> Void
    let onEditCategory: (Category?) -> Void
    let onEditMoneyPot: (MoneyPot?) -> Void

    private var actualBalance: Int {
        FinanceMath.actualBalance(from: transactions)
    }

    private var currentSaldo: Int {
        FinanceMath.currentSaldo(from: transactions, moneyPots: moneyPots)
    }

    private var reservedInPots: Int {
        moneyPots.reduce(0) { total, moneyPot in
            total + FinanceMath.moneyPotBalance(for: moneyPot, transactions: transactions)
        }
    }

    private var pendingExpenses: Int {
        transactions.reduce(into: 0) { total, transaction in
            if transaction.isPending && transaction.amountCents < 0 {
                total += abs(transaction.amountCents)
            }
        }
    }

    private var expenseCategories: [Category] {
        categoriesOfKind(.expense, from: categories)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Family finances")
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text("Import Nordea exports, review unknown transactions, and keep budgets and money pots aligned with your actual balance.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    MetricCardView(
                        title: "Actual balance",
                        value: FinanceDisplay.currency(cents: actualBalance),
                        subtitle: "Latest booked balance across imported accounts",
                        accent: .blue
                    )
                    MetricCardView(
                        title: "Current saldo",
                        value: FinanceDisplay.currency(cents: currentSaldo),
                        subtitle: "Actual balance minus reserved money pots",
                        accent: .green
                    )
                    MetricCardView(
                        title: "Reserved in pots",
                        value: FinanceDisplay.currency(cents: reservedInPots),
                        subtitle: "Money currently set aside",
                        accent: .teal
                    )
                    MetricCardView(
                        title: "Pending expenses",
                        value: FinanceDisplay.currency(cents: pendingExpenses),
                        subtitle: "Transactions still reserved at the bank",
                        accent: .orange
                    )
                }

                GlassSection(title: "Budget status", actionTitle: "New Category", action: {
                    onEditCategory(nil)
                }) {
                    if expenseCategories.isEmpty {
                        EmptyStateView(
                            title: "No expense categories yet",
                            message: "Create expense categories with monthly budgets so imported spending can be tracked against each budget.",
                            buttonTitle: "Create Category",
                            action: { onEditCategory(nil) }
                        )
                    } else {
                        VStack(spacing: 14) {
                            ForEach(expenseCategories) { category in
                                BudgetRowView(
                                    category: category,
                                    actual: FinanceMath.budgetSpent(for: category, transactions: transactions)
                                ) {
                                    onEditCategory(category)
                                }
                            }
                        }
                    }
                }

                GlassSection(title: "Money pots", actionTitle: "New Pot", action: {
                    onEditMoneyPot(nil)
                }) {
                    if moneyPots.isEmpty {
                        EmptyStateView(
                            title: "No money pots yet",
                            message: "Use money pots for planned expenses like mortgage or quarterly bills so your current saldo stays realistic.",
                            buttonTitle: "Create Money Pot",
                            action: { onEditMoneyPot(nil) }
                        )
                    } else {
                        VStack(spacing: 14) {
                            ForEach(moneyPots) { moneyPot in
                                MoneyPotRowView(
                                    moneyPot: moneyPot,
                                    currentBalance: FinanceMath.moneyPotBalance(for: moneyPot, transactions: transactions)
                                ) {
                                    onEditMoneyPot(moneyPot)
                                }
                            }
                        }
                    }
                }

                GlassSection(title: "Needs categorisation", actionTitle: "Import CSV", action: onImport) {
                    if transactionsNeedingReview.isEmpty {
                        Text("All imported transactions have a category.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(Array(transactionsNeedingReview.prefix(5))) { transaction in
                                ReviewRowView(transaction: transaction) {
                                    onReview(transaction)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TransactionsView: View {
    let transactions: [Transaction]
    let onImport: () -> Void
    let onEdit: (Transaction) -> Void

    var body: some View {
        GlassSection(title: "Transactions", actionTitle: "Import CSV", action: onImport) {
            if transactions.isEmpty {
                EmptyStateView(
                    title: "No transactions imported",
                    message: "Start by importing a Nordea CSV export. The importer deduplicates entries and keeps pending transactions up to date.",
                    buttonTitle: "Import Nordea CSV",
                    action: onImport
                )
            } else {
                List(transactions) { transaction in
                    TransactionRowView(transaction: transaction) {
                        onEdit(transaction)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .frame(minHeight: 500)
            }
        }
    }
}

private struct CategoriesView: View {
    let categories: [Category]
    let transactions: [Transaction]
    let categoryWordTags: [CategoryWordTag]
    let ignoredTitleWords: [IgnoredTitleWord]
    let onCreate: () -> Void
    let onEdit: (Category) -> Void
    let onDeleteTag: (CategoryWordTag) -> Void
    let onAddIgnoredWords: (String) -> Void
    let onDeleteIgnoredWord: (IgnoredTitleWord) -> Void

    @State private var ignoredWordInput = ""

    private var expenseCategories: [Category] {
        categoriesOfKind(.expense, from: categories)
    }

    private var wordChipColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .leading)]
    }

    private func tags(for category: Category) -> [CategoryWordTag] {
        categoryWordTags.filter { $0.category?.id == category.id }
    }

    private func addIgnoredWords() {
        let input = ignoredWordInput
        ignoredWordInput = ""
        onAddIgnoredWords(input)
    }

    var body: some View {
        ScrollView {
            GlassSection(title: "Categories", actionTitle: "New Category", action: onCreate) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ignored Title Words")
                            .font(.headline)

                        Text("Words in the title that should never become automatic category tags. You can add more at any time.")
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            TextField("Add ignored word", text: $ignoredWordInput)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addIgnoredWords)

                            Button("Add", action: addIgnoredWords)
                                .buttonStyle(.borderedProminent)
                                .disabled(FinanceNormalizer.titleWords(from: ignoredWordInput).isEmpty)
                        }

                        if ignoredTitleWords.isEmpty {
                            Text("No ignored words yet.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            LazyVGrid(columns: wordChipColumns, alignment: .leading, spacing: 8) {
                                ForEach(ignoredTitleWords) { ignoredWord in
                                    RemovableWordChip(
                                        text: ignoredWord.displayWord,
                                        tint: .secondary
                                    ) {
                                        onDeleteIgnoredWord(ignoredWord)
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    if categories.isEmpty {
                        EmptyStateView(
                            title: "No categories configured",
                            message: "Create expense categories with a monthly budget.",
                            buttonTitle: "Create Category",
                            action: onCreate
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(expenseCategories) { category in
                                CategoryTagCard(
                                    category: category,
                                    actual: FinanceMath.budgetSpent(for: category, transactions: transactions),
                                    tags: tags(for: category),
                                    onEdit: { onEdit(category) },
                                    onDeleteTag: onDeleteTag
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct CategoryTagCard: View {
    let category: Category
    let actual: Int
    let tags: [CategoryWordTag]
    let onEdit: () -> Void
    let onDeleteTag: (CategoryWordTag) -> Void

    private var wordChipColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .leading)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BudgetRowView(category: category, actual: actual, onEdit: onEdit)

            VStack(alignment: .leading, spacing: 8) {
                Text("Title Tags")
                    .font(.subheadline.weight(.semibold))

                if tags.isEmpty {
                    Text("No learned tags yet. Saving a categorised transaction will add the selected title words here.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    LazyVGrid(columns: wordChipColumns, alignment: .leading, spacing: 8) {
                        ForEach(tags) { tag in
                            RemovableWordChip(text: tag.displayWord, tint: .blue) {
                                onDeleteTag(tag)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }
}

private struct RemovableWordChip: View {
    let text: String
    let tint: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
        .foregroundStyle(tint)
    }
}

private struct SelectableWordChip: View {
    let text: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    private var tint: Color {
        isSelected ? .blue : .secondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(text)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(isEnabled ? 0.12 : 0.06))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(isEnabled ? 0.25 : 0.12), lineWidth: 1)
            )
            .foregroundStyle(isEnabled ? tint : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
    }
}

private struct MoneyPotsView: View {
    let moneyPots: [MoneyPot]
    let transactions: [Transaction]
    let onCreate: () -> Void
    let onEdit: (MoneyPot) -> Void

    var body: some View {
        GlassSection(title: "Money Pots", actionTitle: "New Pot", action: onCreate) {
            if moneyPots.isEmpty {
                EmptyStateView(
                    title: "No money pots configured",
                    message: "Reserve money monthly for larger recurring expenses and deduct matched expenses from the pot balance.",
                    buttonTitle: "Create Money Pot",
                    action: onCreate
                )
            } else {
                VStack(spacing: 14) {
                    ForEach(moneyPots) { moneyPot in
                        MoneyPotRowView(
                            moneyPot: moneyPot,
                            currentBalance: FinanceMath.moneyPotBalance(for: moneyPot, transactions: transactions)
                        ) {
                            onEdit(moneyPot)
                        }
                    }
                }
            }
        }
    }
}

private struct MetricCardView: View {
    let title: String
    let value: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(subtitle)
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct GlassSection<Content: View>: View {
    let title: String
    let actionTitle: String
    let action: () -> Void
    let content: Content

    init(
        title: String,
        actionTitle: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title)
                    .font(.title2.weight(.semibold))

                Spacer()

                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }

            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.regularMaterial)
        )
    }
}

private struct BudgetRowView: View {
    let category: Category
    let actual: Int
    let onEdit: () -> Void

    private var target: Int {
        category.monthlyBudgetCents
    }

    private var variance: Int {
        target - actual
    }

    private var statusColor: Color {
        if target == 0 {
            return .secondary
        }

        return variance >= 0 ? .green : .red
    }

    private var statusText: String {
        if target == 0 {
            return CategoryKind.expense.emptyTargetLabel
        }

        return variance >= 0
            ? "\(FinanceDisplay.currency(cents: variance)) left"
            : "\(FinanceDisplay.currency(cents: abs(variance))) over"
    }

    private var amountLabel: String {
        "Spent"
    }

    private var progress: Double {
        guard target > 0 else {
            return 0
        }
        return min(Double(actual) / Double(target), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name)
                        .font(.headline)

                    if target > 0 {
                        Text("\(category.kind.targetLabel) \(FinanceDisplay.currency(cents: target))")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(category.kind.emptyTargetLabel)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(FinanceDisplay.currency(cents: actual))
                        .font(.headline)
                    Text(amountLabel)
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    Text(statusText)
                        .foregroundStyle(statusColor)
                        .font(.subheadline.weight(.medium))
                }

                Button("Edit", action: onEdit)
                    .buttonStyle(.bordered)
            }

            ProgressView(value: progress)
                .tint(statusColor)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
    }
}

private struct MoneyPotRowView: View {
    let moneyPot: MoneyPot
    let currentBalance: Int
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(moneyPot.name)
                    .font(.headline)

                Text("Adds \(FinanceDisplay.currency(cents: moneyPot.monthlyContributionCents)) each month from \(moneyPot.startsOn.formatted(date: .abbreviated, time: .omitted))")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(FinanceDisplay.currency(cents: currentBalance))
                    .font(.headline)
                Text("Reserved now")
                    .foregroundStyle(.secondary)
            }

            Button("Edit", action: onEdit)
                .buttonStyle(.bordered)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
    }
}

private struct ReviewRowView: View {
    let transaction: Transaction
    let onReview: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(transaction.displayTitle)
                    .font(.headline)
                Text("\(transaction.rawBookingDay) • \(transaction.signedAmountText)")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Review", action: onReview)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }
}

private struct TransactionRowView: View {
    let transaction: Transaction
    let onEdit: () -> Void

    private var statusText: String {
        if transaction.isPending {
            return "Pending"
        }
        return transaction.bookingDate?.formatted(date: .abbreviated, time: .omitted) ?? transaction.rawBookingDay
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(transaction.displayTitle)
                    .font(.headline)

                Text(statusText)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    StatusCapsule(
                        text: transaction.category?.name ?? "Needs category",
                        tint: transaction.category == nil ? .orange : .blue
                    )

                    if let moneyPot = transaction.moneyPot {
                        StatusCapsule(text: moneyPot.name, tint: .teal)
                    }

                    if transaction.counterpartyAccount.isEmpty == false {
                        StatusCapsule(text: transaction.counterpartyAccount, tint: .gray)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(transaction.signedAmountText)
                    .font(.headline)
                    .foregroundStyle(transaction.amountCents < 0 ? Color.primary : Color.green)

                Button(transaction.needsCategoryReview ? "Review" : "Edit", action: onEdit)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct StatusCapsule: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .foregroundStyle(tint)
    }
}

private struct EmptyStateView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
    }
}

private struct TransactionAssignmentView: View {
    @Environment(\.dismiss) private var dismiss

    let transaction: Transaction
    let categories: [Category]
    let moneyPots: [MoneyPot]
    let categoryWordTags: [CategoryWordTag]
    let ignoredTitleWords: [IgnoredTitleWord]
    let onSave: (UUID?, UUID?, String, [TitleWordToken]) -> Void

    @State private var selectedCategoryID: UUID?
    @State private var selectedMoneyPotID: UUID?
    @State private var note: String
    @State private var selectedTitleTagWords: Set<String> = []

    init(
        transaction: Transaction,
        categories: [Category],
        moneyPots: [MoneyPot],
        categoryWordTags: [CategoryWordTag],
        ignoredTitleWords: [IgnoredTitleWord],
        onSave: @escaping (UUID?, UUID?, String, [TitleWordToken]) -> Void
    ) {
        self.transaction = transaction
        self.categories = categories
        self.moneyPots = moneyPots
        self.categoryWordTags = categoryWordTags
        self.ignoredTitleWords = ignoredTitleWords
        self.onSave = onSave
        _selectedCategoryID = State(initialValue: transaction.category?.id)
        _selectedMoneyPotID = State(initialValue: transaction.moneyPot?.id)
        _note = State(initialValue: transaction.note)
    }

    private var orderedCategories: [Category] {
        sortedCategories(categories.filter { $0.kind == .expense })
    }

    private var wordChipColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .leading)]
    }

    private var candidateTitleTagWords: [TitleWordToken] {
        FinanceNormalizer.titleWords(
            from: transaction.title,
            ignoring: Set(ignoredTitleWords.map(\.normalizedWord))
        )
    }

    private var selectedCategoryTagWordIDs: Set<String> {
        guard let selectedCategoryID else {
            return []
        }

        return Set(
            categoryWordTags.compactMap { tag in
                guard tag.category?.id == selectedCategoryID else {
                    return nil
                }
                return tag.normalizedWord
            }
        )
    }

    private var selectedTitleTagCandidates: [TitleWordToken] {
        candidateTitleTagWords.filter { selectedTitleTagWords.contains($0.normalizedWord) }
    }

    private var canEditTitleTags: Bool {
        selectedCategoryID != nil && candidateTitleTagWords.isEmpty == false
    }

    private var titleTagHelperText: String {
        if candidateTitleTagWords.isEmpty {
            return "No title words available for future category matching."
        }

        if selectedCategoryID == nil {
            return "Choose a category first, then select the title words you want to save for future matches."
        }

        return "Only the selected title words will be saved as tags for this category."
    }

    private func syncSelectedTitleTagWords() {
        let candidateIDs = Set(candidateTitleTagWords.map(\.normalizedWord))
        selectedTitleTagWords = selectedCategoryTagWordIDs.intersection(candidateIDs)
    }

    private func toggleTitleTag(_ word: TitleWordToken) {
        guard selectedCategoryID != nil else {
            return
        }

        if selectedTitleTagWords.contains(word.normalizedWord) {
            selectedTitleTagWords.remove(word.normalizedWord)
        } else {
            selectedTitleTagWords.insert(word.normalizedWord)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(transaction.displayTitle)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                DetailLine(label: "Amount", value: transaction.signedAmountText)
                DetailLine(label: "Date", value: transaction.rawBookingDay)
                DetailLine(label: "Title", value: transaction.title.isEmpty ? "None detected" : transaction.title)
                DetailLine(label: "Description key", value: transaction.merchantKey)
                DetailLine(label: "Counterparty account", value: transaction.counterpartyAccount.isEmpty ? "None detected" : transaction.counterpartyAccount)
            }

            Picker("Category", selection: $selectedCategoryID) {
                Text("Needs category")
                    .tag(Optional<UUID>.none)
                ForEach(orderedCategories) { category in
                    Text(category.name)
                        .tag(Optional(category.id))
                }
            }

            Picker("Money Pot", selection: $selectedMoneyPotID) {
                Text("None")
                    .tag(Optional<UUID>.none)
                ForEach(moneyPots) { moneyPot in
                    Text(moneyPot.name)
                        .tag(Optional(moneyPot.id))
                }
            }

            TextField("Note", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Title Match Words")
                    .font(.headline)

                if candidateTitleTagWords.isEmpty {
                    Text("No word candidates found in the title.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    LazyVGrid(columns: wordChipColumns, alignment: .leading, spacing: 8) {
                        ForEach(candidateTitleTagWords) { word in
                            SelectableWordChip(
                                text: word.displayWord,
                                isSelected: selectedTitleTagWords.contains(word.normalizedWord),
                                isEnabled: canEditTitleTags
                            ) {
                                toggleTitleTag(word)
                            }
                        }
                    }
                }

                Text(titleTagHelperText)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Save") {
                    onSave(
                        selectedCategoryID,
                        selectedMoneyPotID,
                        note,
                        selectedTitleTagCandidates
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear(perform: syncSelectedTitleTagWords)
        .onChange(of: selectedCategoryID) { _, _ in
            syncSelectedTitleTagWords()
        }
        .padding(28)
        .frame(minWidth: 540)
    }
}

private struct DetailLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
        }
    }
}

private struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let category: Category?
    let onSave: (String, Int) -> Void

    @State private var name: String
    @State private var targetAmount: String

    init(category: Category?, onSave: @escaping (String, Int) -> Void) {
        self.category = category
        self.onSave = onSave
        _name = State(initialValue: category?.name ?? "")
        _targetAmount = State(initialValue: FinanceDisplay.editableAmount(cents: category?.monthlyBudgetCents ?? 0))
    }

    private var parsedTarget: Int? {
        FinanceInput.cents(from: targetAmount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(category == nil ? "New Category" : "Edit Category")
                .font(.title2.weight(.semibold))

            TextField("Name", text: $name)

            TextField("Monthly Budget", text: $targetAmount)

            Text("Expense categories compare this month’s spending with your budget.")
                .foregroundStyle(.secondary)
                .font(.caption)

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Save") {
                    onSave(name, parsedTarget ?? 0)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsedTarget == nil)
            }
        }
        .padding(28)
        .frame(minWidth: 360)
    }
}

private struct MoneyPotEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let moneyPot: MoneyPot?
    let onSave: (String, Int, Int, Date) -> Void

    @State private var name: String
    @State private var monthlyContribution: String
    @State private var openingBalance: String
    @State private var startsOn: Date

    init(
        moneyPot: MoneyPot?,
        onSave: @escaping (String, Int, Int, Date) -> Void
    ) {
        self.moneyPot = moneyPot
        self.onSave = onSave
        _name = State(initialValue: moneyPot?.name ?? "")
        _monthlyContribution = State(initialValue: FinanceDisplay.editableAmount(cents: moneyPot?.monthlyContributionCents ?? 0))
        _openingBalance = State(initialValue: FinanceDisplay.editableAmount(cents: moneyPot?.openingBalanceCents ?? 0))
        _startsOn = State(initialValue: moneyPot?.startsOn ?? .now)
    }

    private var parsedMonthlyContribution: Int? {
        FinanceInput.cents(from: monthlyContribution)
    }

    private var parsedOpeningBalance: Int? {
        FinanceInput.cents(from: openingBalance)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(moneyPot == nil ? "New Money Pot" : "Edit Money Pot")
                .font(.title2.weight(.semibold))

            TextField("Name", text: $name)
            TextField("Monthly Contribution", text: $monthlyContribution)
            TextField("Opening Balance", text: $openingBalance)
            DatePicker("Start month", selection: $startsOn, displayedComponents: .date)

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Save") {
                    onSave(
                        name,
                        parsedMonthlyContribution ?? 0,
                        parsedOpeningBalance ?? 0,
                        startsOn
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsedMonthlyContribution == nil || parsedOpeningBalance == nil)
            }
        }
        .padding(28)
        .frame(minWidth: 380)
    }
}
