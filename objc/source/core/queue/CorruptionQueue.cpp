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
#include <WCDB/CorruptionQueue.hpp>
#include <WCDB/FileManager.hpp>
#include <WCDB/Notifier.hpp>

namespace WCDB {

CorruptionEvent::~CorruptionEvent()
{
}

CorruptionQueue::CorruptionQueue(const String& name)
: AsyncQueue(name), m_event(nullptr)
{
    Notifier::shared()->setNotification(
    0, name, std::bind(&CorruptionQueue::handleError, this, std::placeholders::_1));
}

CorruptionQueue::~CorruptionQueue()
{
    Notifier::shared()->unsetNotification(name);
}

void CorruptionQueue::setEvent(CorruptionEvent* event)
{
    m_event = event;
}

bool CorruptionQueue::containsDatabase(const String& database) const
{
    std::lock_guard<std::mutex> lockGuard(m_mutex);
    return m_corrupted.find(database) != m_corrupted.end();
}

void CorruptionQueue::handleError(const Error& error)
{
    if (m_event == nullptr || !error.isCorruption()) {
        return;
    }
    const auto& infos = error.infos.getStrings();
    auto iter = infos.find("Path");
    if (iter == infos.end()) {
        return;
    }
    if (!m_event->onDatabaseCorrupted(iter->second)) {
        return;
    }
    bool succeed;
    uint32_t identifier;
    std::tie(succeed, identifier) = FileManager::getFileIdentifier(iter->second);
    if (!succeed) {
        return;
    }
    bool notify = false;
    {
        std::lock_guard<std::mutex> lockGuard(m_mutex);
        notify = m_corrupted.empty();
        m_corrupted[iter->second] = identifier;
    }
    lazyRun();
    if (notify) {
        m_cond.notify_all();
    }
}

void CorruptionQueue::loop()
{
    while (!exit()) {
        String path;
        uint32_t corruptedIdentifier;
        {
            std::unique_lock<std::mutex> lockGuard(m_mutex);
            if (m_corrupted.empty()) {
                m_cond.wait(lockGuard);
                continue;
            }
            auto iter = m_corrupted.begin();
            path = iter->first;
            corruptedIdentifier = iter->second;
        }
        m_event->databaseShouldRecover(path, corruptedIdentifier);
        std::lock_guard<std::mutex> lockGuard(m_mutex);
        m_corrupted.erase(path);
    }
}

} //namespace WCDB