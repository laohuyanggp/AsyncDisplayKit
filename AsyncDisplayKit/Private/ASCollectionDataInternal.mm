//
//  ASCollectionDataInternal.m
//  AsyncDisplayKit
//
//  Created by Adlai Holler on 11/5/16.
//  Copyright © 2016 Facebook. All rights reserved.
//

#import "ASCollectionDataInternal.h"
#import "ASDimension.h"

std::vector<NSInteger> ASItemCountsFromData(ASCollectionData * data)
{
  std::vector<NSInteger> result;
  for (id<ASCollectionSection> s in data.mutableSections) {
    result.push_back(s.mutableItems.count);
  }
	return result;
}

@implementation ASCollectionItemImpl
@synthesize identifier = _identifier;
@synthesize constrainedSize = _constrainedSize;
@synthesize nodeBlock = _nodeBlock;

- (instancetype)initWithIdentifier:(ASItemIdentifier)identifier constrainedSize:(ASSizeRange)constrainedSize nodeBlock:(ASCellNodeBlock)nodeBlock
{
  self = [super init];
  if (self != nil) {
    _identifier = identifier;
    _constrainedSize = constrainedSize;
    _nodeBlock = nodeBlock;
  }
  return self;
}

- (ASCellNodeBlock)nodeBlock
{
  ASCellNodeBlock result = _nodeBlock;
  _nodeBlock = nil;
  return result;
}

- (BOOL)isEqual:(id)object
{
  if ([object isKindOfClass:[ASCollectionItemImpl class]] == NO) {
    return NO;
  }
  return [_identifier isEqualToString:[object identifier]];
}

- (NSUInteger)hash
{
  return _identifier.hash;
}

- (NSString *)description
{
  return ASObjectDescriptionMake(self, [self propertiesForDescription]);
}

- (NSMutableArray <NSDictionary *> *)propertiesForDescription
{
  NSMutableArray *array = [NSMutableArray array];
  [array addObject:@{ @"identifier" : _identifier }];
  return array;
}

@end

@implementation ASCollectionSectionImpl
@synthesize mutableItems = _mutableItems;
@synthesize identifier = _identifier;

- (instancetype)initWithIdentifier:(ASSectionIdentifier)identifier
{
  self = [super init];
  if (self != nil) {
    _identifier = identifier;
    _mutableItems = [NSMutableArray array];
  }
  return self;
}

- (NSArray *)itemsInternal
{
  return _mutableItems;
}

- (BOOL)isEqual:(id)object
{
  if ([object isKindOfClass:[ASCollectionSectionImpl class]] == NO) {
    return NO;
  }
  return [_identifier isEqualToString:[object identifier]];
}

- (NSUInteger)hash
{
  return _identifier.hash;
}

- (id)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc] initWithIdentifier:_identifier];
}

- (NSString *)description
{
  return ASObjectDescriptionMake(self, [self propertiesForDescription]);
}

- (NSMutableArray <NSDictionary *> *)propertiesForDescription
{
  NSMutableArray *array = [NSMutableArray array];
  [array addObject:@{ @"identifier" : _identifier }];
  [array addObject:@{ @"items" : _mutableItems }];
  return array;
}

@end

@implementation ASCollectionData {
  ASCollectionSectionImpl *_currentSection;
  NSMutableDictionary<ASItemIdentifier, ASCollectionItemImpl *> *_itemsDict;
  NSMutableDictionary<ASSectionIdentifier, ASCollectionSectionImpl *> *_sectionsDict;

  // We could have used NSMutableSet for these, but copying the dictionary is probably faster than
  // creating an array of all keys, then creating a set of those, and then creating an array from the set
  // during the trim.
  NSMutableDictionary<ASItemIdentifier, ASCollectionItemImpl *> *_usedItems;
  NSMutableDictionary<ASSectionIdentifier, ASCollectionSectionImpl *> *_usedSections;

  BOOL _completed;
}

- (instancetype)initWithReusableContentFromCompletedData:(ASCollectionData *)data
{
  self = [super init];
  if (self != nil) {
    _usedItems = [NSMutableDictionary dictionary];
    _usedSections = [NSMutableDictionary dictionary];
    _mutableSections = [NSMutableArray array];
    
    if (data != nil) {
      ASDisplayNodeAssert(data->_completed, @"You must pass a completed collection data.");
      _itemsDict = data->_usedItems;
      _sectionsDict = [[NSMutableDictionary alloc] initWithDictionary:data->_usedSections copyItems:YES];
    } else {
      _itemsDict = [NSMutableDictionary dictionary];
      _sectionsDict = [NSMutableDictionary dictionary];
    }
  }
  return self;
}

- (instancetype)init
{
  return [self initWithReusableContentFromCompletedData:nil];
}

#pragma mark - Convenience Builders (Public)

- (void)addSectionWithIdentifier:(ASSectionIdentifier)identifier block:(void (^)(ASCollectionData * _Nonnull))block
{
  if (_currentSection != nil) {
    ASDisplayNodeFailAssert(@"Call to %@ must not be inside an addSection: block.", NSStringFromSelector(_cmd));
    return;
  }

  _currentSection = (ASCollectionSectionImpl *)[self sectionWithIdentifier:identifier];
  [_mutableSections addObject:_currentSection];
  block(self);
  _currentSection = nil;
}

- (void)addItemWithIdentifier:(ASItemIdentifier)identifier constrainedSize:(ASSizeRange)constrainedSize nodeBlock:(ASCellNodeBlock)nodeBlock
{
  if (_currentSection == nil) {
    ASDisplayNodeFailAssert(@"Call to %@ must be inside an addSection: block.", NSStringFromSelector(_cmd));
    return;
  }

  id<ASCollectionItem> item = [self itemWithIdentifier:identifier constrainedSize:constrainedSize nodeBlock:nodeBlock];
  [_currentSection.mutableItems addObject:item];
}

#pragma mark - Item / Section Access (Public)

- (id<ASCollectionItem>)itemWithIdentifier:(ASItemIdentifier)identifier constrainedSize:(ASSizeRange)constrainedSize nodeBlock:(nonnull ASCellNodeBlock)nodeBlock
{
  ASCollectionItemImpl *item = _itemsDict[identifier];
  if (item == nil) {

    void (^postNodeBlock)(ASCellNode *) = _postNodeBlock;
    item = [[ASCollectionItemImpl alloc] initWithIdentifier:identifier constrainedSize:constrainedSize nodeBlock:^{
      ASCellNode *node = nodeBlock();
      if (postNodeBlock != nil) {
        postNodeBlock(node);
      }
      return node;
    }];
  }
  ASDisplayNodeAssertNil(_usedItems[identifier], @"Attempt to use the same item twice. Identifier: %@", identifier);
  _usedItems[identifier] = item;
  return item;
}

- (id<ASCollectionSection>)sectionWithIdentifier:(ASSectionIdentifier)identifier
{
  ASCollectionSectionImpl *section = _sectionsDict[identifier];
  if (section == nil) {
    section = [[ASCollectionSectionImpl alloc] initWithIdentifier:identifier];
  }
  ASDisplayNodeAssertNil(_usedSections[identifier], @"Attempt to use the same section twice. Identifier: %@", identifier);
  _usedSections[identifier] = section;
  return section;
}

#pragma mark - Framework Accessors

- (NSArray *)sectionsInternal
{
  return _mutableSections;
}

- (ASCollectionItemImpl *)itemAtIndexPath:(NSIndexPath *)indexPath
{
  return self.sectionsInternal[indexPath.section].itemsInternal[indexPath.item];
}

- (void)markCompleted
{
  _completed = YES;
}

- (std::vector<NSInteger>)itemCounts
{
  std::vector<NSInteger> result;
  for (ASCollectionSectionImpl *section in self.sectionsInternal) {
    result.push_back(section.itemsInternal.count);
  }
  return result;
}

- (NSString *)description
{
  return ASObjectDescriptionMake(self, [self propertiesForDescription]);
}

- (NSMutableArray <NSDictionary *> *)propertiesForDescription
{
  NSMutableArray *array = [NSMutableArray array];
  [array addObject:@{ @"sections" : _mutableSections }];
  return array;
}

@end
