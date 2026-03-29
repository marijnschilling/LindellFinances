//
//  FinanceModels.swift
//  LindellFinances
//
//  Created by Codex on 2026-03-28.
//

import Foundation
import SwiftData

enum MatchingField: String, CaseIterable, Identifiable {
    case counterpartyAccount
    case merchantKey

    var id: String { rawValue }

    var label: String {
        switch self {
        case .counterpartyAccount:
            return "Counterparty Account"
        case .merchantKey:
            return "Description"
        }
    }
}

enum CategoryKind: String, CaseIterable, Identifiable {
    case income
    case expense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .income:
            return "Income"
        case .expense:
            return "Expense"
        }
    }

    var targetLabel: String {
        switch self {
        case .income:
            return "Expected"
        case .expense:
            return "Budget"
        }
    }

    var emptyTargetLabel: String {
        switch self {
        case .income:
            return "No expected amount set"
        case .expense:
            return "No budget set"
        }
    }
}

struct TitleWordToken: Identifiable, Hashable {
    let normalizedWord: String
    let displayWord: String

    var id: String { normalizedWord }
}

@Model
final class Transaction {
    @Attribute(.unique) var externalID: String
    var importedAt: Date
    var sourceFileName: String
    var sourceAccountNumber: String
    var rawBookingDay: String
    var bookingDate: Date?
    var effectiveDate: Date
    var isPending: Bool
    var amountCents: Int
    var balanceCents: Int?
    var currencyCode: String
    var senderAccount: String
    var recipientAccount: String
    var counterpartyAccount: String
    var counterpartyName: String
    var title: String
    var rawDescription: String
    var normalizedDescription: String
    var merchantKey: String
    var note: String
    var needsCategoryReview: Bool
    var category: Category?
    var moneyPot: MoneyPot?

    init(
        externalID: String,
        importedAt: Date,
        sourceFileName: String,
        sourceAccountNumber: String,
        rawBookingDay: String,
        bookingDate: Date?,
        effectiveDate: Date,
        isPending: Bool,
        amountCents: Int,
        balanceCents: Int?,
        currencyCode: String,
        senderAccount: String,
        recipientAccount: String,
        counterpartyAccount: String,
        counterpartyName: String,
        title: String,
        rawDescription: String,
        normalizedDescription: String,
        merchantKey: String,
        note: String = "",
        needsCategoryReview: Bool = true,
        category: Category? = nil,
        moneyPot: MoneyPot? = nil
    ) {
        self.externalID = externalID
        self.importedAt = importedAt
        self.sourceFileName = sourceFileName
        self.sourceAccountNumber = sourceAccountNumber
        self.rawBookingDay = rawBookingDay
        self.bookingDate = bookingDate
        self.effectiveDate = effectiveDate
        self.isPending = isPending
        self.amountCents = amountCents
        self.balanceCents = balanceCents
        self.currencyCode = currencyCode
        self.senderAccount = senderAccount
        self.recipientAccount = recipientAccount
        self.counterpartyAccount = counterpartyAccount
        self.counterpartyName = counterpartyName
        self.title = title
        self.rawDescription = rawDescription
        self.normalizedDescription = normalizedDescription
        self.merchantKey = merchantKey
        self.note = note
        self.needsCategoryReview = needsCategoryReview
        self.category = category
        self.moneyPot = moneyPot
    }

    var isExpense: Bool {
        amountCents < 0
    }

    var displayTitle: String {
        let candidates = [title, counterpartyName, rawDescription]
        return candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? "Transaction"
    }

    var signedAmountText: String {
        FinanceDisplay.currency(cents: amountCents, code: currencyCode)
    }
}

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRawValue: String
    var monthlyBudgetCents: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        kind: CategoryKind = .expense,
        monthlyBudgetCents: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kindRawValue = kind.rawValue
        self.monthlyBudgetCents = monthlyBudgetCents
        self.createdAt = createdAt
    }

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRawValue) ?? .expense }
        set { kindRawValue = newValue.rawValue }
    }
}

@Model
final class MoneyPot {
    @Attribute(.unique) var id: UUID
    var name: String
    var monthlyContributionCents: Int
    var openingBalanceCents: Int
    var startsOn: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        monthlyContributionCents: Int = 0,
        openingBalanceCents: Int = 0,
        startsOn: Date = .now,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.monthlyContributionCents = monthlyContributionCents
        self.openingBalanceCents = openingBalanceCents
        self.startsOn = startsOn
        self.createdAt = createdAt
    }
}

@Model
final class MatchingRule {
    @Attribute(.unique) var id: UUID
    var fieldRawValue: String
    var pattern: String
    var createdAt: Date
    var updatedAt: Date
    var category: Category?
    var moneyPot: MoneyPot?

    init(
        id: UUID = UUID(),
        field: MatchingField,
        pattern: String,
        category: Category? = nil,
        moneyPot: MoneyPot? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.fieldRawValue = field.rawValue
        self.pattern = pattern
        self.category = category
        self.moneyPot = moneyPot
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var field: MatchingField {
        get { MatchingField(rawValue: fieldRawValue) ?? .merchantKey }
        set { fieldRawValue = newValue.rawValue }
    }
}

@Model
final class CategoryWordTag {
    @Attribute(.unique) var normalizedWord: String
    var displayWord: String
    var createdAt: Date
    var category: Category?

    init(
        normalizedWord: String,
        displayWord: String,
        category: Category? = nil,
        createdAt: Date = .now
    ) {
        self.normalizedWord = normalizedWord
        self.displayWord = displayWord
        self.category = category
        self.createdAt = createdAt
    }
}

@Model
final class IgnoredTitleWord {
    @Attribute(.unique) var normalizedWord: String
    var displayWord: String
    var createdAt: Date

    init(
        normalizedWord: String,
        displayWord: String,
        createdAt: Date = .now
    ) {
        self.normalizedWord = normalizedWord
        self.displayWord = displayWord
        self.createdAt = createdAt
    }
}

enum FinanceNormalizer {
    nonisolated static func comparableText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "sv_SE"))
            .replacingOccurrences(
                of: "[^a-z0-9]+",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func accountKey(_ text: String) -> String {
        text.filter { $0.isNumber }
    }

    nonisolated static func normalizedTitleWord(_ text: String) -> String {
        comparableText(text).replacingOccurrences(of: " ", with: "")
    }

    nonisolated static func titleWords(
        from text: String,
        ignoring ignoredWords: Set<String> = []
    ) -> [TitleWordToken] {
        guard text.isEmpty == false,
              // Keep common in-word punctuation so merchants like E.ON stay as one token.
              let expression = try? NSRegularExpression(pattern: "\\p{L}+(?:[.'’\\-]\\p{L}+)*", options: [])
        else {
            return []
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var seenWords: Set<String> = []

        return expression.matches(in: text, options: [], range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }

            let rawWord = String(text[range])
            let normalizedWord = normalizedTitleWord(rawWord)
            guard normalizedWord.isEmpty == false,
                  ignoredWords.contains(normalizedWord) == false,
                  seenWords.insert(normalizedWord).inserted
            else {
                return nil
            }

            return TitleWordToken(
                normalizedWord: normalizedWord,
                displayWord: rawWord.uppercased(with: Locale(identifier: "sv_SE"))
            )
        }
    }

    nonisolated static var defaultIgnoredTitleWords: [String] {
        [
            "Kortköp",
            "Reservation",
            "Autogiro",
            "Överföring",
            "Swish"
        ]
    }

    nonisolated static func merchantKey(title: String, fallbackName: String) -> String {
        var value = comparableText(firstNonEmpty(title, fallbackName))
        let prefixes = [
            "reservation kortkop",
            "reservation",
            "kortkop",
            "autogiro",
            "overforing",
            "swish"
        ]

        for prefix in prefixes {
            if value.hasPrefix(prefix + " ") {
                value.removeFirst(prefix.count + 1)
                break
            }
        }

        value = value.replacingOccurrences(
            of: "\\b\\d{6}\\b",
            with: " ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.isEmpty {
            return comparableText(firstNonEmpty(title, fallbackName))
        }

        return value
    }

    nonisolated static func firstNonEmpty(_ values: String...) -> String {
        firstNonEmpty(values)
    }

    nonisolated static func firstNonEmpty(_ values: [String]) -> String {
        values.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
    }
}

enum FinanceDisplay {
    nonisolated static func currency(cents: Int, code: String = "SEK") -> String {
        let amount = Double(cents) / 100
        return amount.formatted(
            .currency(code: code)
                .locale(Locale(identifier: "sv_SE"))
        )
    }

    nonisolated static func editableAmount(cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "0,00"
    }
}

enum FinanceInput {
    nonisolated static func cents(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }

        let normalized = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        let decimal = NSDecimalNumber(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
        if decimal == .notANumber {
            return nil
        }

        return decimal.multiplying(by: 100).intValue
    }
}

enum FinanceMath {
    nonisolated static func actualBalance(from transactions: [Transaction]) -> Int {
        var latestByAccount: [String: Int] = [:]

        for transaction in transactions {
            guard let balance = transaction.balanceCents else {
                continue
            }

            let key = transaction.sourceAccountNumber.isEmpty
                ? transaction.sourceFileName
                : transaction.sourceAccountNumber

            if latestByAccount[key] == nil {
                latestByAccount[key] = balance
            }
        }

        return latestByAccount.values.reduce(0, +)
    }

    nonisolated static func budgetSpent(
        for category: Category,
        transactions: [Transaction],
        monthAnchor: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let interval = calendar.dateInterval(of: .month, for: monthAnchor)

        return transactions.reduce(into: 0) { total, transaction in
            guard transaction.category?.id == category.id else {
                return
            }
            guard interval?.contains(transaction.effectiveDate) == true else {
                return
            }
            guard transaction.amountCents < 0 else {
                return
            }
            total += abs(transaction.amountCents)
        }
    }

    nonisolated static func moneyPotBalance(
        for moneyPot: MoneyPot,
        transactions: [Transaction],
        asOf date: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let contributionCount = monthlyContributionCount(
            startingAt: moneyPot.startsOn,
            endingAt: date,
            calendar: calendar
        )
        let contributions = contributionCount * moneyPot.monthlyContributionCents
        let movement = transactions.reduce(into: 0) { total, transaction in
            guard transaction.moneyPot?.id == moneyPot.id else {
                return
            }
            guard transaction.effectiveDate <= date else {
                return
            }

            total += transaction.amountCents
        }

        return max(0, moneyPot.openingBalanceCents + contributions + movement)
    }

    nonisolated static func currentSaldo(
        from transactions: [Transaction],
        moneyPots: [MoneyPot],
        asOf date: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let reservedInPots = moneyPots.reduce(into: 0) { total, moneyPot in
            total += moneyPotBalance(
                for: moneyPot,
                transactions: transactions,
                asOf: date,
                calendar: calendar
            )
        }

        return actualBalance(from: transactions) - reservedInPots
    }

    nonisolated static func monthlyContributionCount(
        startingAt startDate: Date,
        endingAt endDate: Date,
        calendar: Calendar = .current
    ) -> Int {
        let startMonth = calendar.startOfMonth(for: startDate)
        let endMonth = calendar.startOfMonth(for: endDate)

        if startMonth > endMonth {
            return 0
        }

        let months = calendar.dateComponents([.month], from: startMonth, to: endMonth).month ?? 0
        return months + 1
    }
}

extension Calendar {
    nonisolated func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
