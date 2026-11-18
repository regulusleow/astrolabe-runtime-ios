#pragma once

/// Returns an owned optional responder using the verified Swift class-generic calling convention.
void * _Nullable ASTCopySwiftUIVisibilityResponder(const void * _Nonnull geometry,
                                                  const void * _Nonnull getter,
                                                  const void * _Nonnull metadata);
