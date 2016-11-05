//
//  ASChangeSetDataController.m
//  AsyncDisplayKit
//
//  Created by Huy Nguyen on 19/10/15.
//
//  Copyright (c) 2014-present, Facebook, Inc.  All rights reserved.
//  This source code is licensed under the BSD-style license found in the
//  LICENSE file in the root directory of this source tree. An additional grant
//  of patent rights can be found in the PATENTS file in the same directory.
//

#import "ASChangeSetDataController.h"
#import "_ASHierarchyChangeSet.h"
#import "ASAssert.h"
#import "ASDataController+Subclasses.h"
#import "NSArray+Diffing.h"
#import "ASCollectionData.h"

@implementation ASChangeSetDataController {
  NSInteger _changeSetBatchUpdateCounter;
  _ASHierarchyChangeSet *_changeSet;
}

- (void)dealloc
{
  ASDisplayNodeCAssert(_changeSetBatchUpdateCounter == 0, @"ASChangeSetDataController deallocated in the middle of a batch update.");
}

#pragma mark - Batching (External API)

- (void)beginUpdates
{
  ASDisplayNodeAssertMainThread();
  if (_changeSetBatchUpdateCounter <= 0) {
    _changeSetBatchUpdateCounter = 0;
    _changeSet = [[_ASHierarchyChangeSet alloc] initWithOldData:[self itemCountsFromDataSource]];
  }
  _changeSetBatchUpdateCounter++;
}

- (void)endUpdatesAnimated:(BOOL)animated completion:(void (^)(BOOL))completion
{
  ASDisplayNodeAssertMainThread();
  _changeSetBatchUpdateCounter--;
  
  // Prevent calling endUpdatesAnimated:completion: in an unbalanced way
  NSAssert(_changeSetBatchUpdateCounter >= 0, @"endUpdatesAnimated:completion: called without having a balanced beginUpdates call");
  
  [_changeSet addCompletionHandler:completion];
  if (_changeSetBatchUpdateCounter == 0) {
    void (^batchCompletion)(BOOL finished) = _changeSet.completionHandler;
    
    /**
     * If the initial reloadData has not been called, just bail because we don't have
     * our old data source counts.
     * See ASUICollectionViewTests.testThatIssuingAnUpdateBeforeInitialReloadIsUnacceptable
     * For the issue that UICollectionView has that we're choosing to workaround.
     */
    if (!self.initialReloadDataHasBeenCalled) {
      if (batchCompletion != nil) {
        batchCompletion(YES);
      }
      _changeSet = nil;
      return;
    }

    // If they do functional data sourcing, we ignored the imperative updates
    // so now let's do the diff and compute the changeset ourselves.
    if (self.supportsDeclarativeData) {
      [self _applyFunctionalDataSourceUpdate];
    } else {
      [self invalidateDataSourceData];
    }

    [_changeSet markCompletedWithNewItemCounts:[self itemCountsFromDataSource]];

    
    [super beginUpdates];
    
    for (_ASHierarchyItemChange *change in [_changeSet itemChangesOfType:_ASHierarchyChangeTypeDelete]) {
      [super deleteRowsAtIndexPaths:change.indexPaths withAnimationOptions:change.animationOptions];
    }
    
    for (_ASHierarchySectionChange *change in [_changeSet sectionChangesOfType:_ASHierarchyChangeTypeDelete]) {
      [super deleteSections:change.indexSet withAnimationOptions:change.animationOptions];
    }
    
    for (_ASHierarchySectionChange *change in [_changeSet sectionChangesOfType:_ASHierarchyChangeTypeInsert]) {
      [super insertSections:change.indexSet withAnimationOptions:change.animationOptions];
    }
    
    for (_ASHierarchyItemChange *change in [_changeSet itemChangesOfType:_ASHierarchyChangeTypeInsert]) {
      [super insertRowsAtIndexPaths:change.indexPaths withAnimationOptions:change.animationOptions];
    }

    [super endUpdatesAnimated:animated completion:batchCompletion];
    
    _changeSet = nil;
  }
}

/**
 * Updates _changeSet by reading the new data and diffing from the old data.
 */
- (void)_applyFunctionalDataSourceUpdate
{
  ASDisplayNodeAssertNotNil(_changeSet, nil);

  ASCollectionData * oldData = self.currentData;
  [self invalidateDataSourceData];
  ASCollectionData * data = self.currentData;
  NSIndexSet *insertedSections = nil, *deletedSections = nil;
  NSArray<NSIndexPath *> *insertedItems = nil, *deletedItems = nil;
  [oldData.mutableSections asdk_nestedDiffWithArray:data.mutableSections
                                insertedSections:&insertedSections
                                 deletedSections:&deletedSections
                                   insertedItems:&insertedItems
                                    deletedItems:&deletedItems
                                    nestingBlock:^NSArray *(id<ASCollectionSection> object) {
                                      return object.mutableItems;
                                    }];

  // Currently we assume automatic animation for all updates.
  if (insertedSections.count > 0) {
    [_changeSet insertSections:insertedSections animationOptions:UITableViewRowAnimationAutomatic];
  }
  if (deletedSections.count > 0) {
    [_changeSet deleteSections:deletedSections animationOptions:UITableViewRowAnimationAutomatic];
  }
  if (insertedItems.count > 0) {
    [_changeSet insertItems:insertedItems animationOptions:UITableViewRowAnimationAutomatic];
  }
  if (deletedItems.count > 0) {
    [_changeSet deleteItems:deletedItems animationOptions:UITableViewRowAnimationAutomatic];
  }
}

- (BOOL)batchUpdating
{
  BOOL batchUpdating = (_changeSetBatchUpdateCounter != 0);
  // _changeSet must be available during batch update
  ASDisplayNodeAssertTrue(batchUpdating == (_changeSet != nil));
  return batchUpdating;
}

- (void)waitUntilAllUpdatesAreCommitted
{
  ASDisplayNodeAssertMainThread();
  if (self.batchUpdating) {
    // This assertion will be enabled soon.
//    ASDisplayNodeFailAssert(@"Should not call %@ during batch update", NSStringFromSelector(_cmd));
    return;
  }

  [super waitUntilAllUpdatesAreCommitted];
}

#pragma mark - Section Editing (External API)

- (void)insertSections:(NSIndexSet *)sections withAnimationOptions:(ASDataControllerAnimationOptions)animationOptions
{
  ASDisplayNodeAssertMainThread();
  [self beginUpdates];
  if (self.supportsDeclarativeData == NO) {
  	[_changeSet insertSections:sections animationOptions:animationOptions];
  }
  [self endUpdates];
}

- (void)deleteSections:(NSIndexSet *)sections withAnimationOptions:(ASDataControllerAnimationOptions)animationOptions
{
  ASDisplayNodeAssertMainThread();
  [self beginUpdates];
  if (self.supportsDeclarativeData == NO) {
  	[_changeSet deleteSections:sections animationOptions:animationOptions];
  }
  [self endUpdates];
}

- (void)reloadSections:(NSIndexSet *)sections withAnimationOptions:(ASDataControllerAnimationOptions)animationOptions
{
  ASDisplayNodeAssertMainThread();
  [self beginUpdates];
  if (self.supportsDeclarativeData == NO) {
  	[_changeSet reloadSections:sections animationOptions:animationOptions];
  }
  [self endUpdates];
}

- (void)moveSection:(NSInteger)section toSection:(NSInteger)newSection withAnimationOptions:(ASDataControllerAnimationOptions)animationOptions
{
  ASDisplayNodeAssertMainThread();
  [self beginUpdates];
  if (self.supportsDeclarativeData == NO) {
    [_changeSet deleteSections:[NSIndexSet indexSetWithIndex:section] animationOptions:animationOptions];
    [_changeSet insertSections:[NSIndexSet indexSetWithIndex:newSection] animationOptions:animationOptions];
  }
  [self endUpdates];
}

#pragma mark - Row Editing (External API)

- (void)insertRowsAtIndexPaths:(NSArray *)indexPaths withAnimationOptions:(ASDataControllerAnimationOptions)animationOptions
{
  ASDisplayNodeAssertMainThread();
  [self beginUpdates];
  if (self.supportsDeclarativeData == NO) {
    [_changeSet insertItems:indexPaths animationOptions:animationOptions];
  }
  [self endUpdates];
}

- (void)deleteRowsAtIndexPaths:(NSArray *)indexPaths withAnimationOptions:(ASDataControllerAnimationOptions)animationOptions
{
  ASDisplayNodeAssertMainThread();
  [self beginUpdates];
  if (self.supportsDeclarativeData == NO) {
    [_changeSet deleteItems:indexPaths animationOptions:animationOptions];
  }
  [self endUpdates];
}

- (void)reloadRowsAtIndexPaths:(NSArray *)indexPaths withAnimationOptions:(ASDataControllerAnimationOptions)animationOptions
{
  ASDisplayNodeAssertMainThread();
  [self beginUpdates];
  if (self.supportsDeclarativeData == NO) {
    [_changeSet reloadItems:indexPaths animationOptions:animationOptions];
  }
  [self endUpdates];
}

- (void)moveRowAtIndexPath:(NSIndexPath *)indexPath toIndexPath:(NSIndexPath *)newIndexPath withAnimationOptions:(ASDataControllerAnimationOptions)animationOptions
{
  ASDisplayNodeAssertMainThread();
  [self beginUpdates];
  if (self.supportsDeclarativeData == NO) {
    [_changeSet deleteItems:@[indexPath] animationOptions:animationOptions];
    [_changeSet insertItems:@[newIndexPath] animationOptions:animationOptions];
  }
  [self endUpdates];
}

@end
