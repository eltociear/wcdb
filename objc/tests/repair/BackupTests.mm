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

#import "BackupTestCase.h"

@interface BackupTests : BackupTestCase

@end

@implementation BackupTests

- (void)test_backup
{
    TestCaseAssertTrue([self.database backup]);
}

- (void)test_dual_backup
{
    TestCaseAssertFalse([self.fileManager fileExistsAtPath:self.firstMaterial]);
    TestCaseAssertFalse([self.fileManager fileExistsAtPath:self.lastMaterial]);

    TestCaseAssertTrue([self.database backup]);
    TestCaseAssertTrue([self.fileManager fileExistsAtPath:self.firstMaterial]);
    TestCaseAssertFalse([self.fileManager fileExistsAtPath:self.lastMaterial]);

    [NSThread sleepForTimeInterval:1];
    TestCaseAssertTrue([self.database backup]);
    TestCaseAssertTrue([self.fileManager fileExistsAtPath:self.firstMaterial]);
    TestCaseAssertTrue([self.fileManager fileExistsAtPath:self.lastMaterial]);

    {
        // old one will be replaced
        NSDate *firstBackupModifiedDate = [self.fileManager attributesOfItemAtPath:self.firstMaterial error:nil][NSFileModificationDate];
        TestCaseAssertTrue(firstBackupModifiedDate != nil);
        NSDate *lastBackupModifiedDate = [self.fileManager attributesOfItemAtPath:self.lastMaterial error:nil][NSFileModificationDate];
        TestCaseAssertTrue(lastBackupModifiedDate != nil);
        TestCaseAssertTrue([firstBackupModifiedDate compare:lastBackupModifiedDate] == NSOrderedAscending);
    }

    [NSThread sleepForTimeInterval:1];
    TestCaseAssertTrue([self.database backup]);

    {
        // old one will be replaced
        NSDate *firstBackupModifiedDate = [self.fileManager attributesOfItemAtPath:self.firstMaterial error:nil][NSFileModificationDate];
        TestCaseAssertTrue(firstBackupModifiedDate != nil);
        NSDate *lastBackupModifiedDate = [self.fileManager attributesOfItemAtPath:self.lastMaterial error:nil][NSFileModificationDate];
        TestCaseAssertTrue(lastBackupModifiedDate != nil);
        TestCaseAssertTrue([firstBackupModifiedDate compare:lastBackupModifiedDate] == NSOrderedDescending);
    }
}

- (void)test_empty_backup
{
    TestCaseAssertTrue([self.database removeFiles]);
    TestCaseAssertTrue([self.database backup]);
    TestCaseAssertTrue([self.fileManager fileExistsAtPath:self.firstMaterial]);
}

- (void)test_wal
{
    TestCaseAssertTrue([[self.fileManager attributesOfItemAtPath:self.walPath error:nil] fileSize] > 0);

    TestCaseAssertTrue([self.database backup]);
}

- (void)test_empty_wal
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    TestCaseAssertTrue([[fileManager attributesOfItemAtPath:self.walPath error:nil] fileSize] > 0);
    TestCaseAssertTrue([self.database execute:WCDB::StatementPragma().pragma(WCDB::Pragma::walCheckpoint()).to("TRUNCATE")]);
    TestCaseAssertTrue([[fileManager attributesOfItemAtPath:self.walPath error:nil] fileSize] == 0);
    TestCaseAssertTrue([self.database backup]);
}

- (void)test_filter
{
    TestCaseAssertTrue([self.database backup]);
    TestCaseAssertTrue([self.fileManager fileExistsAtPath:self.firstMaterial]);
    TestCaseAssertFalse([self.fileManager fileExistsAtPath:self.lastMaterial]);

    [self.database filterBackup:^BOOL(NSString *tableName) {
        return NO;
    }];
    [NSThread sleepForTimeInterval:1];
    TestCaseAssertTrue([self.database backup]);
    TestCaseAssertTrue([self.fileManager fileExistsAtPath:self.firstMaterial]);
    TestCaseAssertTrue([self.fileManager fileExistsAtPath:self.lastMaterial]);

    NSInteger firstMaterialSize = [self getFileSize:self.firstMaterial].integerValue;
    NSInteger lastMaterialSize = [self getFileSize:self.lastMaterial].integerValue;
    TestCaseAssertTrue(firstMaterialSize > lastMaterialSize);
}

- (void)test_backup_fail
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *firstBackupPath = [self.database.path stringByAppendingString:@"-first.material"];
    NSString *lastBackupPath = [self.database.path stringByAppendingString:@"-last.material"];
    TestCaseAssertTrue([fileManager createDirectoryAtPath:firstBackupPath withIntermediateDirectories:YES attributes:nil error:nil]);
    TestCaseAssertTrue([fileManager createDirectoryAtPath:lastBackupPath withIntermediateDirectories:YES attributes:nil error:nil]);

    TestCaseAssertFalse([self.database backup]);
}

- (void)test_auto_backup_when_checkpointed
{
    [self.database removeConfigForName:WCTConfigNameCheckpoint];
    self.database.autoBackup = YES;

    TestCaseObject *object = [[TestCaseObject alloc] init];
    object.isAutoIncrement = YES;
    object.content = [NSString randomString];
    TestCaseAssertTrue([self.table insertObject:object]);

    TestCaseAssertFalse([self.fileManager fileExistsAtPath:self.firstMaterial]);
    TestCaseAssertTrue([self.database execute:WCDB::StatementPragma().pragma(WCDB::Pragma::walCheckpoint())]);

    [NSThread sleepForTimeInterval:self.delayForTolerance];
    TestCaseAssertTrue([self.fileManager fileExistsAtPath:self.firstMaterial]);
}

- (void)test_auto_backup_when_meet_non_critical_frames_interval
{
    [self.database removeConfigForName:WCTConfigNameCheckpoint];
    self.database.autoBackup = YES;

    TestCaseObject *object = [[TestCaseObject alloc] init];
    object.isAutoIncrement = YES;
    object.content = [NSString randomString];

    while ([self getWalFrameCount] < self.backupFramesIntervalForNonCritical - self.framesForTolerance) {
        TestCaseAssertTrue([self.table insertObject:object]);
    }
    [NSThread sleepForTimeInterval:self.backupDelayForNonCritical + self.delayForTolerance];
    TestCaseAssertFalse([self.fileManager fileExistsAtPath:self.firstMaterial]);

    while ([self getWalFrameCount] < self.backupFramesIntervalForNonCritical) {
        TestCaseAssertTrue([self.table insertObject:object]);
    }
    [NSThread sleepForTimeInterval:self.backupDelayForNonCritical + self.delayForTolerance];
    TestCaseAssertTrue([self.fileManager fileExistsAtPath:self.firstMaterial]);
}

- (void)test_auto_backup_when_meet_critical_frames_interval
{
    [self.database removeConfigForName:WCTConfigNameCheckpoint];
    self.database.autoBackup = YES;

    TestCaseObject *object = [[TestCaseObject alloc] init];
    object.isAutoIncrement = YES;
    object.content = [NSString randomString];

    while ([self getWalFrameCount] < self.backupFramesIntervalForCritical - self.framesForTolerance) {
        TestCaseAssertTrue([self.table insertObject:object]);
    }

    [NSThread sleepForTimeInterval:self.backupDelayForCritical + self.delayForTolerance];
    TestCaseAssertFalse([self.fileManager fileExistsAtPath:self.firstMaterial]);

    while ([self getWalFrameCount] < self.backupFramesIntervalForCritical) {
        TestCaseAssertTrue([self.table insertObject:object]);
    }
    [NSThread sleepForTimeInterval:self.backupDelayForCritical + self.delayForTolerance];
    TestCaseAssertTrue([self.fileManager fileExistsAtPath:self.firstMaterial]);
}

@end