//
//  ASTRuntimeMetadataAdapter.m
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#import "ASTRuntimeMetadataAdapter.h"
#import <objc/runtime.h>

@implementation ASTRuntimeMetadataAdapter

+ (NSString *)classNameForObject:(id)object {
    return NSStringFromClass([object class]);
}

+ (NSArray<NSString *> *)classChainForObject:(id)object {
    NSMutableArray<NSString *> *classNames = [NSMutableArray array];
    Class currentClass = [object class];
    while (currentClass != Nil) {
        [classNames addObject:NSStringFromClass(currentClass)];
        currentClass = class_getSuperclass(currentClass);
    }
    return [classNames copy];
}

@end
