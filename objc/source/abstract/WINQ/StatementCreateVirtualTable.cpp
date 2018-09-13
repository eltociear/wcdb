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

#include <WCDB/Assertion.hpp>
#include <WCDB/WINQ.h>

namespace WCDB {

StatementCreateVirtualTable::StatementCreateVirtualTable()
{
    getMutableLang().ifNotExists = true;
}

StatementCreateVirtualTable &
StatementCreateVirtualTable::createVirtualTable(const std::string &tableName)
{
    Lang::CreateVirtualTableSTMT &lang = getMutableLang();
    lang.tableName.assign(tableName);
    return *this;
}

StatementCreateVirtualTable &StatementCreateVirtualTable::ifNotExists(bool ifNotExists)
{
    Lang::CreateVirtualTableSTMT &lang = getMutableLang();
    lang.ifNotExists = ifNotExists;
    return *this;
}

StatementCreateVirtualTable &
StatementCreateVirtualTable::withSchema(const std::string &schemaName)
{
    Lang::CreateVirtualTableSTMT &lang = getMutableLang();
    lang.schemaName.assign(schemaName);
    return *this;
}

StatementCreateVirtualTable &
StatementCreateVirtualTable::usingModule(const std::string &moduleName)
{
    Lang::CreateVirtualTableSTMT &lang = getMutableLang();
    lang.moduleName.assign(moduleName);
    return *this;
}

StatementCreateVirtualTable &
StatementCreateVirtualTable::on(const ModuleArgument &moduleArgument)
{
    Lang::CreateVirtualTableSTMT &lang = getMutableLang();
    lang.moduleArguments.append(moduleArgument.getCOWLang());
    return *this;
}

StatementCreateVirtualTable &
StatementCreateVirtualTable::on(const std::list<ModuleArgument> &moduleArguments)
{
    Lang::CreateVirtualTableSTMT &lang = getMutableLang();
    for (const ModuleArgument &moduleArgument : moduleArguments) {
        lang.moduleArguments.append(moduleArgument.getCOWLang());
    }
    return *this;
}

} // namespace WCDB