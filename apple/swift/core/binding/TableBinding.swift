/*
 * Tencent is pleased to support the open source community by making
 * WCDB available.
 *
 * Copyright (C) 2017 THL A29 Limited, a Tencent company.
 * All rights reserved.
 *
 * Licensed under the BSD 3-Clause License (the "License"); you may not use
 * this file except in compliance with the License. You may obtain a copy of
 * the License at
 *
 *       https://opensource.org/licenses/BSD-3-Clause
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation
import WCDB_Private

public class TableBindingBase {
    internal var columnConstraints: [String: [ColumnConstraint]] = [:]
    internal var tableConstraints: [TableConstraint] = []
    internal var indexes: [String: StatementCreateIndex] = [:]
    internal var virtualTableBinding: VirtualTableConfig?
}

public final class TableBinding<CodingTableKeyType: CodingTableKey>: TableBindingBase {
    private let properties: [CodingTableKeyType: Property]

    public init(_ type: CodingTableKeyType.Type) {
        var allProperties: [Property] = []
        var properties: [CodingTableKeyType: Property] = [:]
        var allKeys: [CodingTableKeyType] = []
        var i = 0
        while true {
            guard let key = (withUnsafePointer(to: &i) {
                return $0.withMemoryRebound(to: CodingTableKeyType?.self, capacity: 1, { return $0.pointee })
            }) else {
                break
            }
            allKeys.append(key)
            i += 1
        }

        for key in allKeys {
            let property = Property(with: key)
            properties[key] = property
            allProperties.append(property)
        }

        self.allKeys = allKeys
        self.properties = properties
        self.allProperties = allProperties

        #if DEBUG
        if let tableDecodableType = CodingTableKeyType.Root.self as? TableDecodableBase.Type {
            let types = ColumnTypeDecoder.types(of: tableDecodableType)
            let keys = allKeys.filter({ (key) -> Bool in
                return types.index(forKey: key.stringValue) == nil
            })
            assert(keys.count == 0,
                   """
                   The following keys: \(keys) can't be decoded. \
                   1. Try to change their definition from `let` to `var` or report an issue to us. \
                   2. Try to rename the `static` variable with same name.
                   """)
        }
        #endif
    }

    @resultBuilder
    public struct TableConfigurationBuilder {
        public static func buildBlock(_ configs: TableConfiguration...) -> [TableConfiguration] {
            return configs
        }
        public static func buildBlock() -> [TableConfiguration] {
            return []
        }
    }

    public convenience init(_ type: CodingTableKeyType.Type, @TableConfigurationBuilder _ configBuildler: () -> [TableConfiguration]) {
        self.init(type)
        let configs = configBuildler()
        for config in configs {
            config.config(with: self)
        }
    }

    let allProperties: [Property]
    let allKeys: [CodingTableKeyType]

    private lazy var columnTypes: [String: ColumnType] = {
        // CodingTableKeyType.Root must conform to TableEncodable protocol.
        let tableDecodableType = CodingTableKeyType.Root.self as! TableDecodableBase.Type
        return ColumnTypeDecoder.types(of: tableDecodableType)
    }()

    private lazy var allColumnDef: [ColumnDef] = allKeys.map { (key) -> ColumnDef in
        return generateColumnDef(with: key)
    }

    private lazy var primaryKey: CodingTableKeyType? = {
        let filtered = allKeys.filter({ key in
            if let constraints = columnConstraints[key.rawValue], constraints.contains(where: { WCDBColumnConstraintIsPrimaryKey($0.cppObj)
            }) {
                return true
            }
            return false
        })
        guard filtered.count == 1 else {
            assert(filtered.count == 0, "Only one primary key is supported. Use MultiPrimaryBinding instead")
            return nil
        }
        return filtered.first!
    }()

    typealias TypedCodingTableKeyType = CodingTableKeyType
    func property<CodingTableKeyType: CodingTableKey>(from codingTableKey: CodingTableKeyType) -> Property {
        let typedCodingTableKey = codingTableKey as? TypedCodingTableKeyType
        assert(typedCodingTableKey != nil, "[\(codingTableKey)] must conform to CodingTableKey protocol.")
        let typedProperty = properties[typedCodingTableKey!]
        assert(typedProperty != nil, "It should not be failed. If you think it's a bug, please report an issue to us.")
        return typedProperty!
    }

    func generateColumnDef(with key: CodingTableKeyBase) -> ColumnDef {
        let codingTableKey = key as? CodingTableKeyType
        assert(codingTableKey != nil, "[\(key)] must conform to CodingTableKey protocol.")
        let columnType = columnTypes[codingTableKey!.stringValue]
        assert(columnType != nil, "It should not be failed. If you think it's a bug, please report an issue to us.")
        let columnDef = ColumnDef(with: codingTableKey!, and: columnType!)
        if let index = columnConstraints.index(forKey: codingTableKey!.rawValue) {
            for constraint in columnConstraints[index].value {
                columnDef.addConstraint(constraint)
            }
        }
        return columnDef
    }

    public func generateCreateVirtualTableStatement(named table: String) -> StatementCreateVirtualTable {
        assert(virtualTableBinding != nil, "Virtual table binding is not defined")
        let statement = StatementCreateVirtualTable().create(virtualTable: table).ifNotExists()
        guard let virtualTableBinding = virtualTableBinding else {
            return statement
        }
        var arguments: [String] = []
        arguments.append(contentsOf: virtualTableBinding.parameters)
        let isFTS5 = virtualTableBinding.module == FTSVersion.FTS5.description
        for columnDef in allColumnDef {
            if isFTS5 {
                let columnName = String(cString: WCDBColumnDefGetColumnName(columnDef.cppObj))
                if WCDBColumnDefIsNotIndexed(columnDef.cppObj) {
                    arguments.append("\(columnName) UNINDEXED")
                } else {
                    arguments.append(columnName)
                }
            } else {
                arguments.append(columnDef.description)
            }
        }
        statement.using(module: virtualTableBinding.module)
        statement.arguments(arguments)
        return statement
    }

    public func generateCreateTableStatement(named table: String) -> StatementCreateTable {
        return StatementCreateTable().create(table: table).ifNotExists().with(columns: allColumnDef).constraint(tableConstraints)
    }

    public func generateCreateIndexStatements(onTable table: String) -> [StatementCreateIndex]? {

        return indexes.map { $0.value.create(index: table + $0.key).on(table: table) }
    }

    func getPrimaryKey() -> CodingTableKeyBase? {
        return primaryKey
    }
}