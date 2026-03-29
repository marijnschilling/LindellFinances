//
//  CSVImportService.swift
//  LindellFinances
//
//  Created by Codex on 2026-03-28.
//

import Foundation
import SwiftData

struct ImportSummary: Identifiable {
    let id = UUID()
    var inserted = 0
    var updated = 0
    var skipped = 0
    var needsReview = 0

    var message: String {
        """
        Imported \(inserted) new transactions, updated \(updated), skipped \(skipped).
        \(needsReview) transactions still need a category.
        """
    }

    mutating func merge(_ other: ImportSummary) {
        inserted += other.inserted
        updated += other.updated
        skipped += other.skipped
        needsReview += other.needsReview
    }
}

enum CSVImportError: LocalizedError {
    case invalidHeader(URL)
    case unreadableFile(URL)

    var errorDescription: String? {
        switch self {
        case .invalidHeader(let url):
            return "The CSV header in \(url.lastPathComponent) was not recognized."
        case .unreadableFile(let url):
            return "The CSV file \(url.lastPathComponent) could not be read."
        }
    }
}

enum CSVImportService {
    @MainActor
    static func importFiles(_ urls: [URL], into modelContext: ModelContext) throws -> ImportSummary {
        let rules = try modelContext.fetch(FetchDescriptor<MatchingRule>())
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.updatedAt > rhs.updatedAt
            }
        let titleTagCategories: [String: Category] = Dictionary(
            uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<CategoryWordTag>()).compactMap { tag in
                guard let category = tag.category else {
                    return nil
                }

                return (tag.normalizedWord, category)
            }
        )
        let ignoredTitleWords = Set(
            try modelContext.fetch(FetchDescriptor<IgnoredTitleWord>()).map(\.normalizedWord)
        )

        var summary = ImportSummary()

        for url in urls {
            let fileSummary = try importFile(
                url,
                into: modelContext,
                rules: rules,
                titleTagCategories: titleTagCategories,
                ignoredTitleWords: ignoredTitleWords
            )
            summary.merge(fileSummary)
        }

        try modelContext.save()
        return summary
    }

    @MainActor
    private static func importFile(
        _ url: URL,
        into modelContext: ModelContext,
        rules: [MatchingRule],
        titleTagCategories: [String: Category],
        ignoredTitleWords: Set<String>
    ) throws -> ImportSummary {
        let records = try parseTransactions(from: url)
        var summary = ImportSummary()

        for record in records {
            if let existing = try existingTransaction(for: record, in: modelContext) {
                update(
                    existing,
                    from: record,
                    applying: rules,
                    titleTagCategories: titleTagCategories,
                    ignoredTitleWords: ignoredTitleWords
                )
                summary.updated += 1
                if existing.needsCategoryReview {
                    summary.needsReview += 1
                }
                continue
            }

            if let pending = try matchingPendingTransaction(for: record, in: modelContext) {
                update(
                    pending,
                    from: record,
                    applying: rules,
                    titleTagCategories: titleTagCategories,
                    ignoredTitleWords: ignoredTitleWords
                )
                summary.updated += 1
                if pending.needsCategoryReview {
                    summary.needsReview += 1
                }
                continue
            }

            let transaction = Transaction(
                externalID: record.externalID,
                importedAt: .now,
                sourceFileName: record.sourceFileName,
                sourceAccountNumber: record.sourceAccountNumber,
                rawBookingDay: record.rawBookingDay,
                bookingDate: record.bookingDate,
                effectiveDate: record.effectiveDate,
                isPending: record.isPending,
                amountCents: record.amountCents,
                balanceCents: record.balanceCents,
                currencyCode: record.currencyCode,
                senderAccount: record.senderAccount,
                recipientAccount: record.recipientAccount,
                counterpartyAccount: record.counterpartyAccount,
                counterpartyName: record.counterpartyName,
                title: record.title,
                rawDescription: record.rawDescription,
                normalizedDescription: record.normalizedDescription,
                merchantKey: record.merchantKey
            )
            applyRules(
                to: transaction,
                using: rules,
                titleTagCategories: titleTagCategories,
                ignoredTitleWords: ignoredTitleWords
            )
            modelContext.insert(transaction)
            summary.inserted += 1
            if transaction.needsCategoryReview {
                summary.needsReview += 1
            }
        }

        return summary
    }

    @MainActor
    private static func existingTransaction(
        for record: ImportedTransactionRecord,
        in modelContext: ModelContext
    ) throws -> Transaction? {
        let externalID = record.externalID
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { transaction in
                transaction.externalID == externalID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    @MainActor
    private static func matchingPendingTransaction(
        for record: ImportedTransactionRecord,
        in modelContext: ModelContext
    ) throws -> Transaction? {
        guard record.isPending == false else {
            return nil
        }

        let sourceAccountNumber = record.sourceAccountNumber
        let amountCents = record.amountCents
        let merchantKey = record.merchantKey

        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { transaction in
                transaction.isPending == true &&
                transaction.sourceAccountNumber == sourceAccountNumber &&
                transaction.amountCents == amountCents &&
                transaction.merchantKey == merchantKey
            }
        )
        descriptor.fetchLimit = 1
        descriptor.sortBy = [SortDescriptor(\Transaction.importedAt, order: .reverse)]
        return try modelContext.fetch(descriptor).first
    }

    private static func update(
        _ transaction: Transaction,
        from record: ImportedTransactionRecord,
        applying rules: [MatchingRule],
        titleTagCategories: [String: Category],
        ignoredTitleWords: Set<String>
    ) {
        transaction.externalID = record.externalID
        transaction.importedAt = .now
        transaction.sourceFileName = record.sourceFileName
        transaction.sourceAccountNumber = record.sourceAccountNumber
        transaction.rawBookingDay = record.rawBookingDay
        transaction.bookingDate = record.bookingDate
        transaction.effectiveDate = record.effectiveDate
        transaction.isPending = record.isPending
        transaction.amountCents = record.amountCents
        transaction.balanceCents = record.balanceCents
        transaction.currencyCode = record.currencyCode
        transaction.senderAccount = record.senderAccount
        transaction.recipientAccount = record.recipientAccount
        transaction.counterpartyAccount = record.counterpartyAccount
        transaction.counterpartyName = record.counterpartyName
        transaction.title = record.title
        transaction.rawDescription = record.rawDescription
        transaction.normalizedDescription = record.normalizedDescription
        transaction.merchantKey = record.merchantKey
        applyRules(
            to: transaction,
            using: rules,
            titleTagCategories: titleTagCategories,
            ignoredTitleWords: ignoredTitleWords
        )
    }

    private static func applyRules(
        to transaction: Transaction,
        using rules: [MatchingRule],
        titleTagCategories: [String: Category],
        ignoredTitleWords: Set<String>
    ) {
        if let accountRule = rules.first(where: {
            $0.field == .counterpartyAccount &&
            $0.pattern == FinanceNormalizer.accountKey(transaction.counterpartyAccount) &&
            !$0.pattern.isEmpty
        }) {
            if transaction.category == nil {
                transaction.category = accountRule.category
            }
            if transaction.moneyPot == nil {
                transaction.moneyPot = accountRule.moneyPot
            }
        }

        if let merchantRule = rules.first(where: {
            $0.field == .merchantKey &&
            $0.pattern == transaction.merchantKey &&
            !$0.pattern.isEmpty
        }) {
            if transaction.category == nil {
                transaction.category = merchantRule.category
            }
            if transaction.moneyPot == nil {
                transaction.moneyPot = merchantRule.moneyPot
            }
        }

        if transaction.category == nil,
           let titleWordCategory = matchedCategory(
               for: transaction.title,
               titleTagCategories: titleTagCategories,
               ignoredTitleWords: ignoredTitleWords
           ) {
            transaction.category = titleWordCategory
        }

        transaction.needsCategoryReview = transaction.category == nil
    }

    private static func matchedCategory(
        for title: String,
        titleTagCategories: [String: Category],
        ignoredTitleWords: Set<String>
    ) -> Category? {
        let matchedCategories = FinanceNormalizer.titleWords(from: title, ignoring: ignoredTitleWords)
            .compactMap { titleTagCategories[$0.normalizedWord] }

        guard let firstCategory = matchedCategories.first else {
            return nil
        }

        let uniqueCategoryIDs = Set(matchedCategories.map(\.id))
        return uniqueCategoryIDs.count == 1 ? firstCategory : nil
    }

    nonisolated private static func parseTransactions(from url: URL) throws -> [ImportedTransactionRecord] {
        let content = try decodeFile(at: url)
        let cleanedContent = content.replacingOccurrences(of: "\u{feff}", with: "")
        let rawLines = cleanedContent.components(separatedBy: .newlines)
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }

        guard let headerLine = lines.first else {
            throw CSVImportError.unreadableFile(url)
        }

        let header = parseDelimitedRow(headerLine).map(FinanceNormalizer.comparableText)
        let expectedColumns = [
            "bokforingsdag",
            "belopp",
            "avsandare",
            "mottagare",
            "namn",
            "rubrik",
            "saldo",
            "valuta"
        ]
        let indexByHeader = Dictionary(uniqueKeysWithValues: zip(header, header.indices))

        guard expectedColumns.allSatisfy({ indexByHeader[$0] != nil }) else {
            throw CSVImportError.invalidHeader(url)
        }

        let rows = lines.dropFirst().map(parseDelimitedRow)
        let sourceAccountNumber = extractSourceAccountNumber(from: url.lastPathComponent, rows: rows, indexByHeader: indexByHeader)
        let importReferenceDate = Date()

        return rows.compactMap { row in
            guard let amount = value("belopp", in: row, indexByHeader: indexByHeader),
                  let amountCents = FinanceInput.cents(from: amount)
            else {
                return nil
            }

            let rawBookingDay = value("bokforingsdag", in: row, indexByHeader: indexByHeader) ?? ""
            let bookingDate = parseDate(rawBookingDay)
            let title = value("rubrik", in: row, indexByHeader: indexByHeader) ?? ""
            let counterpartyName = value("namn", in: row, indexByHeader: indexByHeader) ?? ""
            let senderAccount = value("avsandare", in: row, indexByHeader: indexByHeader) ?? ""
            let recipientAccount = value("mottagare", in: row, indexByHeader: indexByHeader) ?? ""
            let rawBalance = value("saldo", in: row, indexByHeader: indexByHeader) ?? ""
            let balanceCents = rawBalance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : FinanceInput.cents(from: rawBalance)
            let currencyCode = value("valuta", in: row, indexByHeader: indexByHeader) ?? "SEK"
            let rawDescription = FinanceNormalizer.firstNonEmpty(title, counterpartyName, rawBookingDay)
            let merchantKey = FinanceNormalizer.merchantKey(title: title, fallbackName: counterpartyName)
            let normalizedDescription = FinanceNormalizer.comparableText(rawDescription)
            let counterpartyAccount = inferCounterpartyAccount(
                senderAccount: senderAccount,
                recipientAccount: recipientAccount,
                sourceAccountNumber: sourceAccountNumber
            )

            return ImportedTransactionRecord(
                sourceFileName: url.lastPathComponent,
                sourceAccountNumber: sourceAccountNumber,
                rawBookingDay: rawBookingDay,
                bookingDate: bookingDate,
                effectiveDate: bookingDate ?? importReferenceDate,
                isPending: bookingDate == nil,
                amountCents: amountCents,
                balanceCents: balanceCents,
                currencyCode: currencyCode,
                senderAccount: senderAccount,
                recipientAccount: recipientAccount,
                counterpartyAccount: counterpartyAccount,
                counterpartyName: counterpartyName,
                title: title,
                rawDescription: rawDescription,
                normalizedDescription: normalizedDescription,
                merchantKey: merchantKey
            )
        }
    }

    nonisolated private static func decodeFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let encodings: [String.Encoding] = [.utf8, .windowsCP1252, .isoLatin1]

        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }

        throw CSVImportError.unreadableFile(url)
    }

    nonisolated private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.date(from: value)
    }

    nonisolated private static func parseDelimitedRow(_ line: String) -> [String] {
        var values: [String] = []
        var current = ""
        var insideQuotes = false
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                if insideQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    current.append("\"")
                    index += 1
                } else {
                    insideQuotes.toggle()
                }
            } else if character == ";" && insideQuotes == false {
                values.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }

            index += 1
        }

        values.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return values
    }

    nonisolated private static func value(
        _ header: String,
        in row: [String],
        indexByHeader: [String: Int]
    ) -> String? {
        guard let index = indexByHeader[header], index < row.count else {
            return nil
        }

        return row[index]
    }

    nonisolated private static func extractSourceAccountNumber(
        from fileName: String,
        rows: [[String]],
        indexByHeader: [String: Int]
    ) -> String {
        if let match = fileName.range(
            of: "\\d{4} \\d{2} \\d{5}",
            options: .regularExpression
        ) {
            return String(fileName[match])
        }

        var counts: [String: Int] = [:]
        for row in rows {
            let sender = value("avsandare", in: row, indexByHeader: indexByHeader) ?? ""
            let recipient = value("mottagare", in: row, indexByHeader: indexByHeader) ?? ""

            for account in [sender, recipient] where account.isEmpty == false {
                counts[account, default: 0] += 1
            }
        }

        return counts.max(by: { $0.value < $1.value })?.key ?? ""
    }

    nonisolated private static func inferCounterpartyAccount(
        senderAccount: String,
        recipientAccount: String,
        sourceAccountNumber: String
    ) -> String {
        let sourceKey = FinanceNormalizer.accountKey(sourceAccountNumber)
        let senderKey = FinanceNormalizer.accountKey(senderAccount)
        let recipientKey = FinanceNormalizer.accountKey(recipientAccount)

        if senderKey.isEmpty == false, senderKey != sourceKey, recipientKey == sourceKey {
            return senderAccount
        }

        if recipientKey.isEmpty == false, recipientKey != sourceKey, senderKey == sourceKey {
            return recipientAccount
        }

        if senderKey.isEmpty == false, senderKey != sourceKey {
            return senderAccount
        }

        if recipientKey.isEmpty == false, recipientKey != sourceKey {
            return recipientAccount
        }

        return ""
    }
}

private struct ImportedTransactionRecord {
    let sourceFileName: String
    let sourceAccountNumber: String
    let rawBookingDay: String
    let bookingDate: Date?
    let effectiveDate: Date
    let isPending: Bool
    let amountCents: Int
    let balanceCents: Int?
    let currencyCode: String
    let senderAccount: String
    let recipientAccount: String
    let counterpartyAccount: String
    let counterpartyName: String
    let title: String
    let rawDescription: String
    let normalizedDescription: String
    let merchantKey: String

    var externalID: String {
        [
            sourceAccountNumber,
            rawBookingDay,
            String(amountCents),
            senderAccount,
            recipientAccount,
            counterpartyName,
            title,
            balanceCents.map(String.init) ?? "",
            currencyCode
        ].joined(separator: "|")
    }
}
