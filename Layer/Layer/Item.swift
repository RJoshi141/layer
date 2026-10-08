//
//  Item.swift
//  Layer
//
//  Created by Ritika Joshi on 10/8/26.
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
