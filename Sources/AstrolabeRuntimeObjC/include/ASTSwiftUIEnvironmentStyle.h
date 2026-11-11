#ifndef AST_SWIFT_UI_ENVIRONMENT_STYLE_H
#define AST_SWIFT_UI_ENVIRONMENT_STYLE_H

/// Calls the checked Swift getter with its environment in swiftself. Result must be initialized nil Optional<AnyShapeStyle> storage.
void ASTCopySwiftUIForegroundStyle(const void * _Nonnull environment,
                                  const void * _Nonnull getter,
                                  void * _Nonnull result);

#endif
