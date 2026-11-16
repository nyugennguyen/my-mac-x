// MyMacX
// Copyright (C) 2026 NyugenNguyen
//
// This program is free software: you can redistribute it
// and/or modify it under the terms of the GNU General Public
// License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//
// See the LICENSE file for details.

import Foundation

enum StrictJSONValue {
    case object([String: StrictJSONValue])
    case array([StrictJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
}

struct StrictJSONParser {
    private let bytes: [UInt8]
    private let maximumDepth: Int
    private var index = 0

    init(data: Data, maximumDepth: Int) {
        bytes = Array(data)
        self.maximumDepth = maximumDepth
    }

    mutating func parse() throws -> StrictJSONValue {
        skipWhitespace()
        let value = try parseValue(depth: 1)
        skipWhitespace()
        guard index == bytes.count else { throw SettingsDecodingError.invalidShape }
        return value
    }

    private mutating func parseValue(depth: Int) throws -> StrictJSONValue {
        guard depth <= maximumDepth, let byte = bytes[safe: index] else { throw SettingsDecodingError.invalidShape }
        switch byte {
        case 123: return try parseObject(depth: depth)
        case 91: return try parseArray(depth: depth)
        case 34: return .string(try parseString())
        case 45, 48...57: return .number(try parseNumber())
        case 116: try consume("true"); return .bool(true)
        case 102: try consume("false"); return .bool(false)
        case 110: try consume("null"); return .null
        default: throw SettingsDecodingError.invalidShape
        }
    }

    private mutating func parseObject(depth: Int) throws -> StrictJSONValue {
        index += 1; skipWhitespace()
        var fields: [String: StrictJSONValue] = [:]
        if consumeIf(125) { return .object(fields) }
        while true {
            guard bytes[safe: index] == 34 else { throw SettingsDecodingError.invalidShape }
            let key = try parseString()
            guard fields[key] == nil else { throw SettingsDecodingError.invalidShape }
            skipWhitespace(); try expect(58); skipWhitespace()
            fields[key] = try parseValue(depth: depth + 1)
            skipWhitespace()
            if consumeIf(125) { return .object(fields) }
            try expect(44); skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws -> StrictJSONValue {
        index += 1; skipWhitespace()
        var values: [StrictJSONValue] = []
        if consumeIf(93) { return .array(values) }
        while true {
            values.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            if consumeIf(93) { return .array(values) }
            try expect(44); skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        try expect(34)
        var result = ""
        while let byte = bytes[safe: index] {
            index += 1
            if byte == 34 { return result }
            guard byte >= 32 else { throw SettingsDecodingError.invalidShape }
            if byte == 92 {
                guard let escaped = bytes[safe: index] else { throw SettingsDecodingError.invalidShape }
                index += 1
                switch escaped {
                case 34: result.append("\"")
                case 92: result.append("\\")
                case 47: result.append("/")
                case 98: result.append("\u{08}")
                case 102: result.append("\u{0C}")
                case 110: result.append("\n")
                case 114: result.append("\r")
                case 116: result.append("\t")
                default: throw SettingsDecodingError.invalidShape
                }
            } else {
                result.append(Character(UnicodeScalar(byte)))
            }
        }
        throw SettingsDecodingError.invalidShape
    }

    private mutating func parseNumber() throws -> Double {
        let start = index
        if consumeIf(45) {}
        guard consumeDigit() else { throw SettingsDecodingError.invalidShape }
        while consumeDigit() {}
        if consumeIf(46) { guard consumeDigit() else { throw SettingsDecodingError.invalidShape }; while consumeDigit() {} }
        if bytes[safe: index] == 101 || bytes[safe: index] == 69 {
            index += 1; _ = consumeIf(43) || consumeIf(45)
            guard consumeDigit() else { throw SettingsDecodingError.invalidShape }; while consumeDigit() {}
        }
        guard let number = Double(String(decoding: bytes[start..<index], as: UTF8.self)), number.isFinite else {
            throw SettingsDecodingError.invalidShape
        }
        return number
    }

    private mutating func skipWhitespace() { while let byte = bytes[safe: index], [9, 10, 13, 32].contains(byte) { index += 1 } }
    private mutating func expect(_ byte: UInt8) throws { guard consumeIf(byte) else { throw SettingsDecodingError.invalidShape } }
    private mutating func consumeIf(_ byte: UInt8) -> Bool { guard bytes[safe: index] == byte else { return false }; index += 1; return true }
    private mutating func consumeDigit() -> Bool { guard let byte = bytes[safe: index], (48...57).contains(byte) else { return false }; index += 1; return true }
    private mutating func consume(_ literal: String) throws { for byte in literal.utf8 { try expect(byte) } }
}

private extension Array where Element == UInt8 {
    subscript(safe index: Int) -> UInt8? { indices.contains(index) ? self[index] : nil }
}
