//
//  ASTRuntimeBootstrap.m
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/28.
//

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_IOS
extern void AstrolabeRuntimeInstallAutomaticBootstrap(void);

@interface ASTRuntimeBootstrap : NSObject
@end

@implementation ASTRuntimeBootstrap

+ (void)load {
    AstrolabeRuntimeInstallAutomaticBootstrap();
}

@end
#endif
