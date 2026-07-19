//
//  ASTRuntimeMetadataAdapter.h
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Provides the narrow Objective-C Runtime operations used by the Swift SDK.
NS_SWIFT_NAME(RuntimeMetadataAdapter)
@interface ASTRuntimeMetadataAdapter : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Returns the runtime class name for an Objective-C object.
+ (NSString *)classNameForObject:(id)object NS_SWIFT_NAME(className(for:));

/// Returns runtime class names ordered from the most-derived class to NSObject.
+ (NSArray<NSString *> *)classChainForObject:(id)object NS_SWIFT_NAME(classChain(for:));

@end

NS_ASSUME_NONNULL_END
