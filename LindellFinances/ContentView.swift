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

private func sortedCategories(_ categories: [Category]) -> [Category] {
    categories.sorted { lhs, rhs in
        if lhs.kind != rhs.kind {
            return lhs.kind == .income
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
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section as AppSection?)
            }
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
                            onCreate: { openCategoryEditor(nil) },
                            onEdit: openCategoryEditor
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

                Button("New Category", systemImage: "tag.badge.plus") {
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
                onSave: { categoryID, moneyPotID, note, ruleField in
                    saveAssignments(
                        for: transaction,
                        categoryID: categoryID,
                        moneyPotID: moneyPotID,
                        note: note,
                        createRuleFrom: ruleField
                    )
                }
            )
        }
        .sheet(isPresented: $showingCategoryEditor) {
            CategoryEditorView(category: categoryEditorSeed) { name, kind, targetCents in
                saveCategory(name: name, kind: kind, targetCents: targetCents)
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
        .onAppear(perform: presentReviewIfNeeded)
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

    private func openCategoryEditor(_ category: Category?) {
        categoryEditorSeed = category
        showingCategoryEditor = true
    }

    private func openMoneyPotEditor(_ moneyPot: MoneyPot?) {
        moneyPotEditorSeed = moneyPot
        showingMoneyPotEditor = true
    }

    private func saveCategory(name: String, kind: CategoryKind, targetCents: Int) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            errorMessage = "Category name cannot be empty."
            return
        }

        do {
            if let category = categoryEditorSeed {
                category.name = trimmedName
                category.kind = kind
                category.monthlyBudgetCents = targetCents
            } else {
                modelContext.insert(Category(name: trimmedName, kind: kind, monthlyBudgetCents: targetCents))
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
        createRuleFrom field: MatchingField?
    ) {
        do {
            transaction.category = categories.first(where: { $0.id == categoryID })
            transaction.moneyPot = moneyPots.first(where: { $0.id == moneyPotID })
            transaction.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            transaction.needsCategoryReview = transaction.category == nil

            if let field, let pattern = rulePattern(for: transaction, field: field) {
                try upsertRule(
                    field: field,
                    pattern: pattern,
                    category: transaction.category,
                    moneyPot: transaction.moneyPot
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

    private var incomeCategories: [Category] {
        categoriesOfKind(.income, from: categories)
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

                if incomeCategories.isEmpty == false {
                    GlassSection(title: "Expected income", actionTitle: "New Category", action: {
                        onEditCategory(nil)
                    }) {
                        VStack(spacing: 14) {
                            ForEach(incomeCategories) { category in
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
    let onCreate: () -> Void
    let onEdit: (Category) -> Void

    private var incomeCategories: [Category] {
        categoriesOfKind(.income, from: categories)
    }

    private var expenseCategories: [Category] {
        categoriesOfKind(.expense, from: categories)
    }

    var body: some View {
        GlassSection(title: "Categories", actionTitle: "New Category", action: onCreate) {
            if categories.isEmpty {
                EmptyStateView(
                    title: "No categories configured",
                    message: "Create income categories with an expected amount or expense categories with a monthly budget.",
                    buttonTitle: "Create Category",
                    action: onCreate
                )
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    if incomeCategories.isEmpty == false {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Income")
                                .font(.headline)

                            ForEach(incomeCategories) { category in
                                BudgetRowView(
                                    category: category,
                                    actual: FinanceMath.budgetSpent(for: category, transactions: transactions)
                                ) {
                                    onEdit(category)
                                }
                            }
                        }
                    }

                    if expenseCategories.isEmpty == false {
                        VStack(alignment: .leading, spacing: 12) {
                            if incomeCategories.isEmpty == false {
                                Divider()
                            }

                            Text("Expenses")
                                .font(.headline)

                            ForEach(expenseCategories) { category in
                                BudgetRowView(
                                    category: category,
                                    actual: FinanceMath.budgetSpent(for: category, transactions: transactions)
                                ) {
                                    onEdit(category)
                                }
                            }
                        }
                    }
                }
            }
        }
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
        switch category.kind {
        case .expense:
            return target - actual
        case .income:
            return actual - target
        }
    }

    private var statusColor: Color {
        if target == 0 {
            return .secondary
        }

        switch category.kind {
        case .expense:
            return variance >= 0 ? .green : .red
        case .income:
            return variance >= 0 ? .green : .orange
        }
    }

    private var statusText: String {
        if target == 0 {
            return category.kind.emptyTargetLabel
        }

        switch category.kind {
        case .expense:
            return variance >= 0
                ? "\(FinanceDisplay.currency(cents: variance)) left"
                : "\(FinanceDisplay.currency(cents: abs(variance))) over"
        case .income:
            return variance >= 0
                ? "\(FinanceDisplay.currency(cents: variance)) above expected"
                : "\(FinanceDisplay.currency(cents: abs(variance))) below expected"
        }
    }

    private var amountLabel: String {
        switch category.kind {
        case .expense:
            return "Spent"
        case .income:
            return "Received"
        }
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
    let onSave: (UUID?, UUID?, String, MatchingField?) -> Void

    @State private var selectedCategoryID: UUID?
    @State private var selectedMoneyPotID: UUID?
    @State private var note: String

    init(
        transaction: Transaction,
        categories: [Category],
        moneyPots: [MoneyPot],
        onSave: @escaping (UUID?, UUID?, String, MatchingField?) -> Void
    ) {
        self.transaction = transaction
        self.categories = categories
        self.moneyPots = moneyPots
        self.onSave = onSave
        _selectedCategoryID = State(initialValue: transaction.category?.id)
        _selectedMoneyPotID = State(initialValue: transaction.moneyPot?.id)
        _note = State(initialValue: transaction.note)
    }

    private var orderedCategories: [Category] {
        sortedCategories(categories)
    }

    private var canSaveAccountRule: Bool {
        FinanceNormalizer.accountKey(transaction.counterpartyAccount).isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(transaction.displayTitle)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                DetailLine(label: "Amount", value: transaction.signedAmountText)
                DetailLine(label: "Date", value: transaction.rawBookingDay)
                DetailLine(label: "Description key", value: transaction.merchantKey)
                DetailLine(label: "Counterparty account", value: transaction.counterpartyAccount.isEmpty ? "None detected" : transaction.counterpartyAccount)
            }

            Picker("Category", selection: $selectedCategoryID) {
                Text("Needs category")
                    .tag(Optional<UUID>.none)
                ForEach(orderedCategories) { category in
                    Text(category.kind == .income ? "\(category.name) (Income)" : category.name)
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

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Save") {
                    onSave(selectedCategoryID, selectedMoneyPotID, note, nil)
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save + Description Rule") {
                    onSave(selectedCategoryID, selectedMoneyPotID, note, .merchantKey)
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save + Account Rule") {
                    onSave(selectedCategoryID, selectedMoneyPotID, note, .counterpartyAccount)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(canSaveAccountRule == false)
            }
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
    let onSave: (String, CategoryKind, Int) -> Void

    @State private var name: String
    @State private var selectedKind: CategoryKind
    @State private var targetAmount: String

    init(category: Category?, onSave: @escaping (String, CategoryKind, Int) -> Void) {
        self.category = category
        self.onSave = onSave
        _name = State(initialValue: category?.name ?? "")
        _selectedKind = State(initialValue: category?.kind ?? .expense)
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

            Picker("Type", selection: $selectedKind) {
                ForEach(CategoryKind.allCases) { kind in
                    Text(kind.title)
                        .tag(kind)
                }
            }

            TextField(selectedKind == .income ? "Expected This Month" : "Monthly Budget", text: $targetAmount)

            Text(selectedKind == .income
                 ? "Income categories are shown above expense budgets and compare received income with your expected amount."
                 : "Expense categories compare this month’s spending with your budget.")
                .foregroundStyle(.secondary)
                .font(.caption)

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Save") {
                    onSave(name, selectedKind, parsedTarget ?? 0)
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
