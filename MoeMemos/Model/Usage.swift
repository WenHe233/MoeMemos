//
//  Usage.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/9/4.
//

import Foundation
import Models

struct DailyUsageStat: Identifiable {
    let date: Date
    var count: Int
    
    var id: String {
        date.formatted(date: .numeric, time: .omitted)
    }
    
    static let initialMatrix: [DailyUsageStat] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let days = calendar.range(of: .day, in: .year, for: today) else {
            return []
        }

        return days.compactMap { day in
            calendar.date(byAdding: .day, value: 1 - day, to: today).map {
                Self(date: $0, count: 0)
            }
        }.reversed()
    }()
    
    static func calculateMatrix<M: MemoPresentable>(memoList: [M]) -> [DailyUsageStat] {
        var result = DailyUsageStat.initialMatrix
        var countDict = [String: Int]()
        
        for memo in memoList {
            let key = memo.createdAt.formatted(date: .numeric, time: .omitted)
            countDict[key] = (countDict[key] ?? 0) + 1
        }
        
        for (i, day) in result.enumerated() {
            result[i].count = countDict[day.id] ?? 0
        }
        
        return result
    }
}
