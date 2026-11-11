#include "ASTSwiftUIEnvironmentStyle.h"
#include <stdint.h>

typedef uintptr_t __attribute__((swiftcall)) (*ASTForegroundStyleGetter)(const void * __attribute__((swift_context)));

void ASTCopySwiftUIForegroundStyle(const void *environment, const void *getter, void *result) {
    // Transfer the getter's owned optional into the caller's typed nil slot without an extra retain.
    *(uintptr_t *)result = ((ASTForegroundStyleGetter)getter)(environment);
}
