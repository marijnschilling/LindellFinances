//
//  Item.swift
//  LindellFinances
//
//  Created by Marijn Work on 2026-03-28.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
